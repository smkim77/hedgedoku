-- 내 프로필(이모지 + 닉네임) 기능 추가
-- 이미 setup.sql 과 fix-security-definer-*.sql 을 실행한 프로젝트에서 SQL Editor에 붙여 넣고 한 번 실행하세요.
-- 여러 번 실행해도 안전하고, 기존 기록과 닉네임은 그대로 남아요.

-- 1) 플레이어 이모지 칸 (게임이 고를 수 있는 12가지만 허용)
alter table public.players add column if not exists avatar text;
alter table public.players drop constraint if exists players_avatar_check;
alter table public.players add constraint players_avatar_check
  check (avatar is null or avatar in ('🦔','🐰','🐻','🐼','🦊','🐸','🐧','🐹','🐨','🦉','🐢','🐙'));
grant select (avatar) on public.players to anon, authenticated;

-- 2) 순위표 뷰에 이모지 추가 (맨 끝 칸)
create or replace view public.leaderboard with (security_invoker = true) as
  select s.player_id, p.nickname, s.diff, s.levels, s.time_ms, s.updated_at, p.avatar
  from public.scores s
  join public.players p on p.id = s.player_id;
revoke all on public.leaderboard from anon, authenticated;
grant select on public.leaderboard to anon, authenticated;

-- 3) 프로필 저장: 처음이면 플레이어를 만들고, 아니면 비밀값을 확인한 뒤 닉네임과 이모지를 바꿔요.
create schema if not exists private;
create or replace function private.save_profile(p_player uuid, p_secret text, p_nickname text, p_avatar text)
returns jsonb
language plpgsql
security definer
set search_path = public, extensions
as $$
begin
  if p_avatar is not null and p_avatar not in ('🦔','🐰','🐻','🐼','🦊','🐸','🐧','🐹','🐨','🦉','🐢','🐙') then
    raise exception 'bad_avatar';
  end if;
  perform private.check_player(p_player, p_secret, p_nickname, true);
  update public.players set avatar = p_avatar where id = p_player and avatar is distinct from p_avatar;
  return jsonb_build_object('status', 'ok');
end;
$$;
revoke all on function private.save_profile(uuid, text, text, text) from public;
grant execute on function private.save_profile(uuid, text, text, text) to anon, authenticated;

create or replace function public.save_profile(p_player uuid, p_secret text, p_nickname text, p_avatar text)
returns jsonb
language sql
security invoker
set search_path = ''
as $$
  select private.save_profile(p_player, p_secret, p_nickname, p_avatar);
$$;
revoke all on function public.save_profile(uuid, text, text, text) from public;
grant execute on function public.save_profile(uuid, text, text, text) to anon, authenticated;

notify pgrst, 'reload schema';
