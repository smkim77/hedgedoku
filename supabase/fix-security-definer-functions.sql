-- Security Advisor 경고 해결: "Public Can Execute SECURITY DEFINER Function" (submit_score, set_nickname)
-- 이미 setup.sql을 실행한 프로젝트에서 SQL Editor에 붙여 넣고 한 번 실행하세요. 여러 번 실행해도 안전해요.
-- 기존 기록과 플레이어는 그대로 남고, 게임 코드도 바꿀 필요 없어요.

-- 쓰기 함수 구조
--   실제 검사·저장은 API로 공개되지 않는 private 스키마의 함수(security definer)가 맡고,
--   public 스키마에는 그 함수를 불러주기만 하는 얇은 창구(security invoker)만 둬요.
--   (Security Advisor의 "Public Can Execute SECURITY DEFINER Function" 경고가 나지 않는 구조예요.)
create schema if not exists private;
revoke all on schema private from public;
grant usage on schema private to anon, authenticated;

-- 공통 검증: 비밀값 확인, 닉네임 검사, 처음이면 플레이어 등록
create or replace function private.check_player(p_player uuid, p_secret text, p_nickname text, p_create boolean)
returns text
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_hash text;
  v_nick text := btrim(coalesce(p_nickname, ''));
  v_existing public.players%rowtype;
begin
  if p_player is null or p_secret is null or p_secret !~ '^[0-9a-f]{64}$' then
    raise exception 'bad_secret';
  end if;
  if char_length(v_nick) < 1 or char_length(v_nick) > 12 or v_nick ~ '[[:cntrl:]]' then
    raise exception 'bad_nickname';
  end if;
  v_hash := encode(digest(p_secret, 'sha256'), 'hex');

  select * into v_existing from public.players where id = p_player;
  if not found then
    if p_create then
      insert into public.players (id, secret_hash, nickname) values (p_player, v_hash, v_nick);
    end if;
  elsif v_existing.secret_hash <> v_hash then
    raise exception 'bad_secret';
  else
    update public.players set nickname = v_nick where id = p_player and nickname <> v_nick;
  end if;
  return v_nick;
end;
$$;
revoke all on function private.check_player(uuid, text, text, boolean) from public, anon, authenticated;

-- 기록 등록: 그 난이도의 개인 최고 기록보다 좋을 때만 바뀌어요.
create or replace function private.submit_score(
  p_player uuid, p_secret text, p_nickname text, p_diff text, p_levels integer, p_time_ms bigint
)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_prev public.scores%rowtype;
begin
  if p_diff is null or p_diff not in ('easy', 'normal', 'hard', 'expert') then
    raise exception 'bad_diff';
  end if;
  -- 한 레벨을 1초 안에 푸는 건 불가능하다고 보고 걸러요.
  if p_levels is null or p_time_ms is null or p_levels < 1 or p_levels > 100000
     or p_time_ms < p_levels * 1000::bigint or p_time_ms > 31536000000 then
    raise exception 'bad_score';
  end if;

  perform private.check_player(p_player, p_secret, p_nickname, true);

  select * into v_prev from public.scores where player_id = p_player and diff = p_diff for update;
  if found and not (p_levels > v_prev.levels or (p_levels = v_prev.levels and p_time_ms < v_prev.time_ms)) then
    return jsonb_build_object('status', 'not_better', 'levels', v_prev.levels, 'time_ms', v_prev.time_ms);
  end if;

  insert into public.scores (player_id, diff, levels, time_ms, updated_at)
  values (p_player, p_diff, p_levels, p_time_ms, now())
  on conflict (player_id, diff) do update
    set levels = excluded.levels, time_ms = excluded.time_ms, updated_at = now();
  return jsonb_build_object('status', 'new_best', 'levels', p_levels, 'time_ms', p_time_ms);
end;
$$;
revoke all on function private.submit_score(uuid, text, text, text, integer, bigint) from public;
grant execute on function private.submit_score(uuid, text, text, text, integer, bigint) to anon, authenticated;

-- 닉네임 변경: 이미 기록이 있는 플레이어만 바뀌어요. (기록이 없으면 아무 일도 없음)
create or replace function private.set_nickname(p_player uuid, p_secret text, p_nickname text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  perform private.check_player(p_player, p_secret, p_nickname, false);
  return jsonb_build_object('status', 'ok');
end;
$$;
revoke all on function private.set_nickname(uuid, text, text) from public;
grant execute on function private.set_nickname(uuid, text, text) to anon, authenticated;

-- 게임이 부르는 공개 창구 (/rest/v1/rpc/submit_score, /rest/v1/rpc/set_nickname)
create or replace function public.submit_score(
  p_player uuid, p_secret text, p_nickname text, p_diff text, p_levels integer, p_time_ms bigint
)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.submit_score(p_player, p_secret, p_nickname, p_diff, p_levels, p_time_ms);
$$;
revoke all on function public.submit_score(uuid, text, text, text, integer, bigint) from public;
grant execute on function public.submit_score(uuid, text, text, text, integer, bigint) to anon, authenticated;

create or replace function public.set_nickname(p_player uuid, p_secret text, p_nickname text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.set_nickname(p_player, p_secret, p_nickname);
$$;
revoke all on function public.set_nickname(uuid, text, text) from public;
grant execute on function public.set_nickname(uuid, text, text) to anon, authenticated;

-- 예전 구조에서 쓰던 공용 검증 함수는 정리해요.
drop function if exists public._hedgedoku_check_player(uuid, text, text, boolean);

notify pgrst, 'reload schema';
