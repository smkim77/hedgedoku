-- 주간 순위: 이번 주(한국 시간 월요일 0시부터)의 개인 최고 기록으로 따로 겨뤄요.
-- Supabase 대시보드 → SQL Editor 에서 한 번 실행하세요. 여러 번 실행해도 괜찮아요.
-- (setup.sql을 새로 실행하는 프로젝트에는 이미 들어 있어요.)

-- 주마다, 난이도마다, 플레이어마다 그 주의 최고 기록 하나
create table if not exists public.weekly_scores (
  player_id  uuid not null references public.players(id) on delete cascade,
  diff       text not null check (diff in ('easy', 'normal', 'hard', 'expert')),
  week       date not null,
  levels     integer not null check (levels between 1 and 100000),
  time_ms    bigint not null check (time_ms >= 0),
  updated_at timestamptz not null default now(),
  primary key (player_id, diff, week)
);
create index if not exists weekly_scores_rank_idx on public.weekly_scores (week, diff, levels desc, time_ms asc);

alter table public.weekly_scores enable row level security;
revoke all on public.weekly_scores from anon, authenticated;
grant select (player_id, diff, week, levels, time_ms, updated_at) on public.weekly_scores to anon, authenticated;
drop policy if exists "leaderboard read" on public.weekly_scores;
create policy "leaderboard read" on public.weekly_scores for select to anon, authenticated using (true);

-- 이번 주 리더보드 뷰 (조회하는 사람 권한으로 실행)
create or replace view public.leaderboard_week with (security_invoker = true) as
  select w.player_id, p.nickname, w.diff, w.levels, w.time_ms, w.updated_at, p.avatar
  from public.weekly_scores w
  join public.players p on p.id = w.player_id
  where w.week = (date_trunc('week', now() at time zone 'Asia/Seoul'))::date;
revoke all on public.leaderboard_week from anon, authenticated;
grant select on public.leaderboard_week to anon, authenticated;

-- 기록 등록: 전체 최고 기록과 이번 주 최고 기록을 각각 더 좋을 때만 바꿔요.
--   돌려주는 값: status(전체 기준 new_best / not_better), week_status(이번 주 기준)
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
  v_wprev public.weekly_scores%rowtype;
  v_week date := (date_trunc('week', now() at time zone 'Asia/Seoul'))::date;
  v_wstatus text;
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

  -- 이번 주
  select * into v_wprev from public.weekly_scores
    where player_id = p_player and diff = p_diff and week = v_week for update;
  if found and not (p_levels > v_wprev.levels or (p_levels = v_wprev.levels and p_time_ms < v_wprev.time_ms)) then
    v_wstatus := 'not_better';
  else
    insert into public.weekly_scores (player_id, diff, week, levels, time_ms, updated_at)
    values (p_player, p_diff, v_week, p_levels, p_time_ms, now())
    on conflict (player_id, diff, week) do update
      set levels = excluded.levels, time_ms = excluded.time_ms, updated_at = now();
    v_wstatus := 'new_best';
  end if;

  -- 전체
  select * into v_prev from public.scores where player_id = p_player and diff = p_diff for update;
  if found and not (p_levels > v_prev.levels or (p_levels = v_prev.levels and p_time_ms < v_prev.time_ms)) then
    return jsonb_build_object('status', 'not_better', 'levels', v_prev.levels, 'time_ms', v_prev.time_ms, 'week_status', v_wstatus);
  end if;

  insert into public.scores (player_id, diff, levels, time_ms, updated_at)
  values (p_player, p_diff, p_levels, p_time_ms, now())
  on conflict (player_id, diff) do update
    set levels = excluded.levels, time_ms = excluded.time_ms, updated_at = now();
  return jsonb_build_object('status', 'new_best', 'levels', p_levels, 'time_ms', p_time_ms, 'week_status', v_wstatus);
end;
$$;
revoke all on function private.submit_score(uuid, text, text, text, integer, bigint) from public;
grant execute on function private.submit_score(uuid, text, text, text, integer, bigint) to anon, authenticated;

-- 지금까지의 전체 최고 기록 중 이번 주에 세운 것은 이번 주 순위에도 넣어 줘요.
insert into public.weekly_scores (player_id, diff, week, levels, time_ms, updated_at)
select s.player_id, s.diff, (date_trunc('week', now() at time zone 'Asia/Seoul'))::date, s.levels, s.time_ms, s.updated_at
from public.scores s
where s.updated_at >= (date_trunc('week', now() at time zone 'Asia/Seoul')) at time zone 'Asia/Seoul'
on conflict (player_id, diff, week) do nothing;

notify pgrst, 'reload schema';
