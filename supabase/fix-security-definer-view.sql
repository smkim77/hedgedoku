-- Security Advisor 경고 해결: "View public.leaderboard is defined with the SECURITY DEFINER property"
-- 이미 setup.sql을 실행한 프로젝트에서 SQL Editor에 붙여 넣고 한 번 실행하세요. 여러 번 실행해도 안전해요.
--
-- 바뀌는 점
--   - leaderboard 뷰가 조회하는 사람 권한(security_invoker)으로 실행돼요.
--   - 그 대신 외부(anon)에는 순위표에 필요한 칸만 읽기 권한을 줘요.
--     players: id, nickname 만 (secret_hash 는 계속 못 읽어요)
--     scores : 기록 칸 전부
--   - 쓰기는 지금처럼 submit_score / set_nickname 함수로만 가능해요.

-- 1) 순위표에 필요한 칸만 읽기 허용
revoke all on public.players, public.scores from anon, authenticated;
grant select (id, nickname) on public.players to anon, authenticated;
-- 프로필 이모지 칸이 이미 있으면 그 칸도 다시 읽을 수 있게 해요. (위의 revoke가 지워버리기 때문)
do $$ begin
  if exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'players' and column_name = 'avatar') then
    grant select (avatar) on public.players to anon, authenticated;
  end if;
end $$;
grant select (player_id, diff, levels, time_ms, updated_at) on public.scores to anon, authenticated;

-- 2) RLS: 행은 누구나 읽을 수 있음 (위 칸 제한과 함께 적용)
drop policy if exists "leaderboard read" on public.players;
create policy "leaderboard read" on public.players for select to anon, authenticated using (true);
drop policy if exists "leaderboard read" on public.scores;
create policy "leaderboard read" on public.scores for select to anon, authenticated using (true);

-- 3) 뷰를 조회하는 사람 권한으로 실행
alter view public.leaderboard set (security_invoker = true);

notify pgrst, 'reload schema';
