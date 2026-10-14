-- 출처 확인: 내 게임 페이지(허용 목록에 있는 주소)에서 온 요청만 기록·프로필을 저장할 수 있게 해요.
-- Supabase 대시보드 → SQL Editor 에서 한 번 실행하세요. 여러 번 실행해도 괜찮아요.
--
-- ★ 실행 전에 아래 insert 줄의 주소를 내 GitHub Pages 주소로 바꾸세요.
--   - 주소 끝의 경로(/hedgedoku/)와 마지막 / 는 빼고 적어요.
--     예) 게임 주소가 https://abcd.github.io/hedgedoku/ 이면 → 'https://abcd.github.io'
--   - 시험용 localhost / 127.0.0.1 주소는 따로 적지 않아도 허용돼요.
--
-- 한계: 브라우저가 붙이는 Origin 값을 보는 것이라, 다른 사이트에서 몰래 부르는 것은 막지만
--       curl 같은 프로그램으로 Origin을 꾸며서 보내는 것까지 막지는 못해요.

create schema if not exists private;

create table if not exists private.allowed_origins (
  origin text primary key
);
alter table private.allowed_origins enable row level security;  -- 정책 없음: API로는 아무도 못 읽고 못 써요
revoke all on private.allowed_origins from public, anon, authenticated;
-- 일부러 아무도 통과 못 하는 정책을 하나 둬요. (Advisor의 "RLS enabled, no policies" 안내를 없애려는 것)
drop policy if exists "no api access" on private.allowed_origins;
create policy "no api access" on private.allowed_origins for all to anon, authenticated using (false) with check (false);

insert into private.allowed_origins (origin) values
  ('https://tempted.github.io')   -- ← 여기를 바꾸세요
on conflict do nothing;

-- 요청의 Origin 헤더가 허용 목록에 없으면 거부해요.
-- (SQL Editor처럼 API를 거치지 않는 관리자 실행에는 헤더가 없어서 검사하지 않아요.)
create or replace function private.check_origin()
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_headers text := current_setting('request.headers', true);
  v_origin text;
begin
  if v_headers is null or v_headers = '' then
    return;
  end if;
  v_origin := lower(rtrim(coalesce(v_headers::json ->> 'origin', ''), '/'));
  if v_origin ~ '^http://(localhost|127\.0\.0\.1)(:[0-9]+)?$' then
    return;
  end if;
  if v_origin = '' or not exists (select 1 from private.allowed_origins a where lower(a.origin) = v_origin) then
    raise exception 'bad_origin';
  end if;
end;
$$;
revoke all on function private.check_origin() from public, anon, authenticated;

-- 기록 등록·닉네임 변경·프로필 저장은 모두 check_player를 거치므로, 여기서 출처를 먼저 확인해요.
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
  perform private.check_origin();
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

-- 확인용: 허용된 주소 목록
select origin from private.allowed_origins;
