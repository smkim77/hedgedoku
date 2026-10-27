extends Control
## 고슴도쿠 (Godot port): game state and rules, the whole UI (built in code), the leaderboard window and
## the profile / rules / quit windows. Ported from the web version (index.html), keeping its behaviour.

# ---------- constants ----------
const DIFFS := [
	{"id": "normal", "label": "쉬움", "n": 7, "apples": 3},
	{"id": "hard", "label": "보통", "n": 9, "apples": 4},
	{"id": "expert", "label": "어려움", "n": 11, "apples": 5},
]
const MAX_LEVEL := 999
const DOUBLE_MS := 350
const FAIL_DELAY := 1.4
const AVATARS := ["🦔", "🐰", "🐻", "🐼", "🦊", "🐸", "🐧", "🐹", "🐨", "🦉", "🐢", "🐙"]
const AVATAR_FILES := ["1f994", "1f430", "1f43b", "1f43c", "1f98a", "1f438", "1f427", "1f439", "1f428", "1f989", "1f422", "1f419"]
const ANIMAL_NAMES := ["고슴도치", "토끼", "곰돌이", "판다", "여우", "개구리", "펭귄", "햄스터", "코알라", "부엉이", "거북이", "문어"]
const NICK_MAX := 12
const LB_TOP := 20
const LOCAL_KEEP := 100
const ROW_H := 40.0
const SAVE_PATH := "user://hedgedoku.cfg"
const WRITE_HOST := "smkim77.github.io"
const ERRORS := {
	"bad_secret": "이 기기의 플레이어 정보가 맞지 않아 기록을 저장하지 못했어요.",
	"bad_nickname": "닉네임은 1~12자로 정해 주세요.",
	"bad_diff": "알 수 없는 난이도라 기록을 저장하지 못했어요.",
	"bad_score": "기록 값이 올바르지 않아 저장하지 못했어요.",
	"bad_avatar": "고를 수 없는 이모지예요.",
	"bad_origin": "허용되지 않은 주소에서 열린 게임이라 기록을 저장하지 못했어요.",
}

const BG := Color("e9ece0")
const SURFACE := Color("f6f7ef")
const INK := Color("2e2a21")
const MUTED := Color("6a6656")
const ACCENT := Color("8a5a2b")
const ACCENT_INK := Color("fffaf2")
const ACCENT_SOFT := Color(0.541, 0.353, 0.169, 0.12)
const GRIDC := Color(0.231, 0.196, 0.149, 0.16)
const DANGER := Color("c0443b")
const RING := Color("e0a456")
const GOLD := Color("c9962a")
const SILVER := Color("8d96a0")
const BRONZE := Color("b0703c")

# ---------- state ----------
var mode := "run"
var diff := "normal"
var P: Puzzle
var cells := []
var history := []
var phase := "play"          # play | ready | between | over (run) · won | lost (practice)
var practice := {"level": 1, "hearts": 3, "hints": 0}
var run = null               # Dictionary while a challenge exists
var clock := {"acc": 0, "since": 0, "running": false}
var lb_diff := "normal"
var lb_period := "all"
var last_result = null
var cleared := {}
var auto_x := true
var last_tap := {"i": -1, "t": 0}
var pending_fx = null
var prev_lives := -1

# leaderboard
var sb: SupaClient
var lb_enabled := false
var player := {}
var nickname := ""
var avatar := ""
var lb_cache := {}
var lb_state := "loading"
var lb_token := 0
var lb_loaded_at := 0
var local_board := {}
var hold = null
var pending_anim = null

var cfg := ConfigFile.new()
var font_body: Font
var font_display: Font
var avatar_tex := {}

# ---------- UI refs ----------
var col: VBoxContainer
var title_hog: Control
var tagline: Label
var h1: Label
var pf_avatar: TextureRect
var pf_avatar_panel: PanelContainer
var pf_name: Label
var mode_btns := {}
var diff_btns := {}
var lock_note: Label
var lives_box: HBoxContainer
var info_box: HBoxContainer
var timer_lbl: Label
var board_area: Control
var board: BoardView
var overlay: Control
var overlay_card: PanelContainer
var overlay_peek := false
var undo_btn: Button
var hint_btn: Button
var hint_badge: Control
var restart_btn: Button
var restart_icon: Control
var quit_btn: Button
var autox_chk: CheckBox
var lb_text: Label
var lb_open_btn: Button
var toast_panel: PanelContainer
var toast_lbl: Label
var toast_tween: Tween
var narrow := false

var modal_layer: Control
var lb_modal: Control
var lb_panel: PanelContainer
var lb_result: PanelContainer
var res_head: Label
var res_stats: Label
var rank_move: VBoxContainer
var rank_line: HBoxContainer
var rank_from: Label
var rank_arrow: Label
var rank_to: Label
var rank_tag: Label
var save_area: VBoxContainer
var res_key := ""
var lb_seg_btns := {}
var lb_period_box: Control
var lb_period_btns := {}
var lb_scroll: ScrollContainer
var lb_list: Control
var lb_head_row: Control
var lb_empty: Label
var lb_status: Label
var lb_opener: Control

var pf_modal: Control
var pf_prev_avatar: TextureRect
var pf_prev_name: Label
var pf_grid_btns := []
var pf_nick: LineEdit
var pf_msg: Label
var pf_save: Button
var pf_draft := ""

var rules_modal: Control
var quit_modal: Control
var quit_body: Label
var quit_resume := false

var volley_at := 0.0
var test_mode := false       # local test against a mock server (?sb=… on localhost): F9 solves the level


# =====================================================================
# boot
# =====================================================================

func _ready() -> void:
	cfg.load(SAVE_PATH)
	_adopt_html_profile()
	font_body = load("res://fonts/GowunDodum-Regular.ttf")
	font_display = load("res://fonts/Jua-Regular.ttf")
	font_display.fallbacks = [font_body]   # Jua has no "·" and a few other symbols
	for k in AVATARS.size():
		avatar_tex[AVATARS[k]] = load("res://avatars/%s.png" % AVATAR_FILES[k])
	theme = _make_theme()
	sb = SupaClient.new()
	add_child(sb)
	_setup_lb_access()
	cleared = sget("cleared", {})
	auto_x = sget("autoX", true)
	_load_identity()
	_build_ui()
	get_viewport().size_changed.connect(_layout)
	if nickname == "":
		var av: String = AVATARS[randi() % AVATARS.size()]
		set_profile(auto_nick(av), av)
	render_profile_btn()
	_start()
	_layout.call_deferred()
	if not sget("seenRules", false):
		sset("seenRules", true)
		open_rules.call_deferred()
	volley_at = now_s() + 3.0 + randf() * 3.0


func _setup_lb_access() -> void:
	# Writes are accepted only from the game's web address; elsewhere the board is this device's own.
	if OS.has_feature("web"):
		var host := str(JavaScriptBridge.eval("location.hostname", true))
		lb_enabled = host == WRITE_HOST
		var mock := str(JavaScriptBridge.eval("new URLSearchParams(location.search).get('sb') || ''", true))
		if mock.begins_with("http://127.0.0.1:") and (host == "127.0.0.1" or host == "localhost"):
			sb.url = mock
			lb_enabled = true
			test_mode = true
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--sb="):   # testing against a local mock server
			sb.url = a.substr(5)
			lb_enabled = true
			test_mode = true


func _start() -> void:
	var saved = sget("run", null)
	if saved is Dictionary and saved.has("run") and _diff_of(str(saved.run.get("diff", ""))) != null:
		run = saved.run.duplicate(true)
		run.cells = saved.get("cells", [])
		run.levelMs = int(saved.get("levelMs", 0))
		run.apples = mini(int(run.apples), apples_of(run.diff))
		diff = run.diff
		lb_diff = run.diff
		enter_run_mode()
	else:
		new_run("normal")
	render_lb()


# =====================================================================
# storage
# =====================================================================

func sget(k: String, d):
	return cfg.get_value("data", k) if cfg.has_section_key("data", k) else d


func sset(k: String, v) -> void:
	cfg.set_value("data", k, v)
	cfg.save(SAVE_PATH)


## The HTML version (same address) kept the player id, profile and practice progress in localStorage.
## Take them over once, so this build keeps the same records on the leaderboard.
func _adopt_html_profile() -> void:
	if not OS.has_feature("web") or sget("adoptedHtml", false):
		return
	var raw = JavaScriptBridge.eval("""(() => { try {
		const out = {};
		for (const k of ['player', 'nick', 'avatar', 'cleared', 'autoX', 'seenRules', 'profileSynced', 'practice']) {
			const v = localStorage.getItem('hedgedoku.' + k);
			if (v !== null) out[k] = JSON.parse(v);
		}
		return JSON.stringify(out);
	} catch (e) { return '{}'; } })()""", true)
	var old = JSON.parse_string(str(raw)) if raw != null else null
	sset("adoptedHtml", true)
	if not (old is Dictionary):
		return
	var p = old.get("player")
	if p is Dictionary and str(p.get("id", "")).length() == 36 and str(p.get("secret", "")).length() == 64:
		sset("player", {"id": str(p.id), "secret": str(p.secret)})
		for k in ["nick", "avatar", "profileSynced"]:
			if old.has(k):
				sset(k, old[k])
	for k in ["cleared", "autoX", "seenRules", "practice"]:
		if old.has(k):
			sset(k, old[k])


func _load_identity() -> void:
	player = sget("player", {})
	if not (player is Dictionary) or str(player.get("id", "")).length() != 36 or str(player.get("secret", "")).length() != 64:
		var b := Crypto.new().generate_random_bytes(16)
		b[6] = (b[6] & 0x0f) | 0x40
		b[8] = (b[8] & 0x3f) | 0x80
		var h := b.hex_encode()
		player = {"id": "%s-%s-%s-%s-%s" % [h.substr(0, 8), h.substr(8, 4), h.substr(12, 4), h.substr(16, 4), h.substr(20, 12)],
			"secret": Crypto.new().generate_random_bytes(32).hex_encode()}
		sset("player", player)
	nickname = str(sget("nick", ""))
	avatar = valid_avatar(str(sget("avatar", "")))
	local_board = sget("localBoard", {})
	if not (local_board is Dictionary):
		local_board = {}


# =====================================================================
# helpers
# =====================================================================

static func now_s() -> float:
	return Time.get_ticks_msec() / 1000.0


func _diff_of(id: String):
	for d in DIFFS:
		if d.id == id:
			return d
	return null


func size_of(id: String) -> int:
	return _diff_of(id).n


func apples_of(id: String) -> int:
	return _diff_of(id).apples


static func fmt(ms: float) -> String:
	var s := int(floor(ms / 1000.0))
	return "%02d:%02d" % [s / 60, s % 60]


func valid_avatar(a: String) -> String:
	return a if a in AVATARS else ""


func auto_nick(av: String) -> String:
	var k := AVATARS.find(av)
	return "%s%d" % [ANIMAL_NAMES[k] if k >= 0 else "고슴도치", 1000 + randi() % 9000]


func clean_nick(s: String) -> String:
	var out := ""
	for ch in s:
		if ch.unicode_at(0) >= 32 and ch.unicode_at(0) != 127:
			out += ch
	return out.strip_edges().substr(0, NICK_MAX)


func clock_ms() -> int:
	return int(clock.acc) + (Time.get_ticks_msec() - int(clock.since) if clock.running else 0)


func clock_start() -> void:
	if not clock.running:
		clock.running = true
		clock.since = Time.get_ticks_msec()


func clock_pause() -> void:
	if clock.running:
		clock.acc = clock_ms()
		clock.running = false


func clock_reset(ms := 0) -> void:
	clock = {"acc": ms, "since": 0, "running": false}


func lives() -> int:
	return int(run.apples) if mode == "run" else int(practice.hearts)


func run_active() -> bool:
	return run != null and not run.get("finished", false)


func run_started() -> bool:
	return run_active() and (int(run.cleared) > 0 or int(run.level) > 1 or run.get("moved", false))


func playing() -> bool:
	return phase == "play"


func run_cells() -> Array:
	return cells.duplicate() if phase == "play" or phase == "ready" else []


func save_run() -> void:
	if run == null:
		return
	var here := mode == "run"
	var r: Dictionary = run.duplicate(true)
	r.erase("cells")
	sset("run", {"run": r, "cells": run_cells() if here else run.get("cells", []), "levelMs": clock_ms() if here else int(run.get("levelMs", 0))})


func save_if_run() -> void:
	if mode == "run" and run_active():
		save_run()


# =====================================================================
# loading boards
# =====================================================================

func set_board(p: Puzzle, c = null) -> void:
	prev_lives = -1
	P = p
	if c is Array and c.size() == P.N * P.N:
		cells = c.duplicate()
	else:
		cells = []
		cells.resize(P.N * P.N)
		cells.fill(0)
	history = []
	board.reset()
	_layout()


func load_practice(d: String, level: int) -> void:
	mode = "practice"
	diff = d
	practice = {"level": level, "hearts": apples_of(d), "hints": 0}
	set_board(Puzzle.for_key("%s:%d" % [d, level], size_of(d)))
	clock_reset()
	clock_start()
	phase = "play"
	sset("practice", {"diff": d, "level": level})
	hide_overlay()
	render()


func new_run(d: String) -> void:
	mode = "run"
	diff = d
	lb_diff = d
	run = {"diff": d, "seed": randi() % 2147483648, "level": 1, "cleared": 0, "totalMs": 0, "apples": apples_of(d),
		"hints": 0, "finished": false}
	load_run_level()
	phase = "ready"
	save_run()
	render()
	show_ready(false)


func load_run_level(c = null, level_ms := 0) -> void:
	set_board(Puzzle.for_key("run:%d:%d" % [int(run.seed), int(run.level)], size_of(run.diff)), c)
	clock_reset(level_ms)


func enter_run_mode() -> void:
	mode = "run"
	if run == null:
		new_run(diff)
		return
	diff = run.diff
	if run.get("finished", false):
		load_run_level()
		phase = "over"
		render()
		if run.get("endReason", "") != "quit":
			reveal_failure(-1, false)
		show_over()
		return
	load_run_level(run.get("cells", []), int(run.get("levelMs", 0)))
	var fresh: bool = int(run.level) == 1 and int(run.cleared) == 0 and clock_ms() == 0 and not (1 in cells or 2 in cells)
	phase = "ready"
	render()
	show_ready(not fresh)


func leave_run_mode() -> void:
	if mode != "run" or run == null:
		return
	clock_pause()
	run.cells = run_cells()
	run.levelMs = clock_ms()
	save_run()


func begin_level() -> void:
	phase = "play"
	clock_start()
	hide_overlay()
	render()
	save_run()
	board.grab_focus()


# =====================================================================
# moves
# =====================================================================

func push_history() -> void:
	if mode == "run" and run != null:
		run.moved = true
	history.append(cells.duplicate())
	if history.size() > 200:
		history.pop_front()


func auto_mark(i: int) -> void:
	if not auto_x:
		return
	var N := P.N
	var r := i / N
	var c := i % N
	for j in N * N:
		if cells[j] != 0:
			continue
		var rj := j / N
		var cj := j % N
		if rj == r or cj == c or P.reg[j] == P.reg[i] or (absi(rj - r) <= 1 and absi(cj - c) <= 1):
			cells[j] = 1


func mark_from(i: int) -> void:
	if not auto_x:
		return
	var before := cells.duplicate()
	auto_mark(i)
	var newly := []
	for j in cells.size():
		if before[j] == 0 and cells[j] == 1:
			newly.append(j)
	pending_fx = {"i": i, "newly": newly}


func lose_apple() -> void:
	if mode == "run":
		run.apples = int(run.apples) - 1
	else:
		practice.hearts = int(practice.hearts) - 1


func place(i: int) -> void:
	var N := P.N
	if P.sol[i / N] == i % N:
		push_history()
		cells[i] = 2
		mark_from(i)
		check_win()
		return
	lose_apple()
	cells[i] = 1
	board.mark_now(i)
	board.play_ouch(i)
	var left := lives()
	toast("따끔! 여긴 자리가 아니에요" if left > 0 else "따끔! 마지막 사과를 잃었어요")
	if left <= 0:
		if mode == "run":
			end_run("apples", i)
		else:
			clock_pause()
			phase = "lost"
			render()
			reveal_failure(i)
			await get_tree().create_timer(FAIL_DELAY).timeout
			if phase == "lost" and mode == "practice":
				show_practice_end(false)


## Single tap: empty → ×, × or hedgehog → empty. Double tap: place a hedgehog.
func tap(i: int) -> void:
	if not playing():
		return
	var t := Time.get_ticks_msec()
	if last_tap.i == i and t - int(last_tap.t) < DOUBLE_MS:
		last_tap = {"i": -1, "t": 0}
		if not history.is_empty():
			cells = history.pop_back()   # undo the first tap of the pair
		if cells[i] != 2:
			place(i)
		render()
		save_if_run()
		return
	last_tap = {"i": i, "t": t}
	push_history()
	cells[i] = 1 if cells[i] == 0 else 0
	render()
	save_if_run()


## Keyboard Enter: place a hedgehog on the cursor cell.
func place_direct(i: int) -> void:
	if not playing() or cells[i] == 2:
		return
	place(i)
	render()
	save_if_run()


func drag_done() -> void:
	last_tap = {"i": -1, "t": 0}
	save_if_run()


func check_win() -> void:
	if cells.count(2) != P.N:
		return
	clock_pause()
	if mode == "run":
		var level_ms := clock_ms()
		var cleared_level := int(run.level)
		run.totalMs = int(run.totalMs) + level_ms
		run.cleared = int(run.cleared) + 1
		run.level = int(run.level) + 1
		phase = "between"
		clock_reset()
		save_run()
		render()
		show_between(level_ms, cleared_level)
	else:
		phase = "won"
		var lst: Array = cleared.get(diff, [])
		if not (practice.level in lst):
			lst.append(practice.level)
			cleared[diff] = lst
			sset("cleared", cleared)
		render()
		show_practice_end(true)


func end_run(reason: String, fatal := -1) -> void:
	clock_pause()
	var r = run
	r.finished = true
	r.endReason = reason
	phase = "over"
	save_run()
	render()
	last_result = null if int(r.cleared) > 0 else {"ok": false, "msg": "클리어한 레벨이 없어서 기록은 남지 않아요."}
	if int(r.cleared) > 0:
		try_submit()
	if reason == "apples":
		reveal_failure(fatal)
		await get_tree().create_timer(FAIL_DELAY).timeout
		if run == r and mode == "run" and phase == "over":
			show_over()
			open_lb()
	else:
		show_over()
		open_lb()


func hint() -> void:
	if not playing():
		return
	if mode == "run":
		if int(run.apples) <= 1:
			return
		run.apples = int(run.apples) - 1
		run.hints = int(run.hints) + 1
	else:
		practice.hints = int(practice.hints) + 1
	var N := P.N
	var best := -1
	var best_open := 1 << 30
	for r in N:
		var i := r * N + P.sol[r]
		if cells[i] == 2:
			continue
		var open := 0
		for j in N * N:
			if P.reg[j] == P.reg[i] and cells[j] == 0:
				open += 1
		if open < best_open:
			best_open = open
			best = i
	if best < 0:
		return
	push_history()
	cells[best] = 2
	mark_from(best)
	render()
	board.play_glow(best)
	check_win()
	save_if_run()


func undo() -> void:
	if history.is_empty() or not playing():
		return
	cells = history.pop_back()
	render()
	save_if_run()


func restart() -> void:
	if mode == "run":
		if not playing():
			return
		# keep hedgehogs and the × marks they imply; clear only the player's own marks
		push_history()
		for i in cells.size():
			if cells[i] != 2:
				cells[i] = 0
		for i in cells.size():
			if cells[i] == 2:
				auto_mark(i)
		render()
		save_run()
	else:
		load_practice(diff, int(practice.level))


func reveal_failure(fatal: int, shake := true) -> void:
	board.revealed = true
	board.fatal = fatal
	if shake:
		board.shake()
	board.queue_redraw()


func start_new_run() -> void:
	last_result = null
	pending_anim = null
	hold = null
	new_run(diff)


# =====================================================================
# render
# =====================================================================

func render() -> void:
	if board == null or P == null:
		return
	var is_run := mode == "run"
	board.sync()
	if pending_fx != null:
		var fx = pending_fx
		pending_fx = null
		board.play_quills(fx.i, fx.newly)
	# lives
	var h := lives()
	var dropped := prev_lives >= 0 and h < prev_lives
	for c in lives_box.get_children():
		c.queue_free()
	for k in apples_of(diff):
		var a := DrawBox.new()
		a.custom_minimum_size = Vector2(20, 20) if narrow else Vector2(24, 24)
		a.kind = "apple"
		a.gray = k >= h
		a.drop = dropped and k >= h and k < prev_lives
		a.born = now_s()
		lives_box.add_child(a)
	if h <= 0:
		lives_box.add_child(_label("사과 없음", 15, DANGER, true))
	prev_lives = h
	_seg_set(mode_btns, mode)
	var lock := is_run and run_started()
	for id in diff_btns:
		diff_btns[id].disabled = lock and id != diff
	_seg_set(diff_btns, diff)
	lock_note.modulate.a = 1.0 if lock else 0.0
	_seg_set(lb_seg_btns, lb_diff)
	# info
	for c in info_box.get_children():
		c.queue_free()
	if is_run:
		info_box.add_child(_label("레벨 %d" % int(run.level), 18, INK, true))
	else:
		var lv := int(practice.level)
		var prev := _round_btn("‹", func(): load_practice(diff, lv - 1))
		prev.disabled = lv <= 1
		var nxt := _round_btn("›", func(): load_practice(diff, lv + 1))
		nxt.disabled = lv >= MAX_LEVEL
		info_box.add_child(prev)
		info_box.add_child(_label("레벨 %d" % lv, 18, INK, true))
		if lv in cleared.get(diff, []):
			info_box.add_child(_label("✓", 15, ACCENT, true))
		info_box.add_child(nxt)
	var pl := playing()
	undo_btn.disabled = history.is_empty() or not pl
	hint_btn.disabled = not pl or (is_run and int(run.apples) <= 1)
	hint_btn.tooltip_text = "힌트 (사과 1개 사용)" if is_run else "힌트"
	hint_badge.visible = is_run
	restart_icon.set("kind", "erase" if is_run else "restart")
	restart_icon.queue_redraw()
	restart_btn.tooltip_text = "보드 비우기 (고슴도치는 남겨요)" if is_run else "다시 시작"
	restart_btn.disabled = not pl if is_run else false
	quit_btn.visible = is_run
	quit_btn.disabled = not run_active() or not run_started()
	board.veiled = phase == "ready"
	tick_timer()


func tick_timer() -> void:
	var ms := clock_ms()
	if mode == "run" and run != null:
		ms = int(run.totalMs) + (0 if phase == "between" or phase == "over" else clock_ms())
	timer_lbl.text = fmt(ms)


func _process(_dt: float) -> void:
	if timer_lbl != null:
		tick_timer()
	# idle volleys: every few seconds a random hedgehog puffs up and shoots again (visual only)
	if now_s() >= volley_at:
		volley_at = now_s() + 3.0 + randf() * 3.0
		if phase == "play" and P != null:
			var hogs := []
			for j in cells.size():
				if cells[j] == 2:
					hogs.append(j)
			if not hogs.is_empty():
				board.play_puff(hogs[randi() % hogs.size()])


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		if mode == "run" and run_active():
			if run != null:
				run.levelMs = clock_ms()
			save_run()


# =====================================================================
# overlay cards on the board
# =====================================================================

func show_overlay(build: Callable) -> void:
	overlay_peek = false
	for c in overlay.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(BG, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	overlay_card = _card()
	overlay_card.custom_minimum_size.x = minf(board_area.size.x * 0.88, 340)
	center.add_child(overlay_card)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	overlay_card.add_child(box)
	build.call(box)
	overlay.visible = true


func hide_overlay() -> void:
	overlay.visible = false
	overlay_peek = false
	for c in overlay.get_children():
		c.queue_free()


func _card_row(box: VBoxContainer) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	row.name = "Row"
	box.add_child(row)
	return row


func _hog_box(sz := 60.0) -> Control:
	var h := DrawBox.new()
	h.kind = "hog"
	h.custom_minimum_size = Vector2(sz, sz)
	h.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return h


func _apples_row(box: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 4)
	for k in apples_of(diff):
		var a := DrawBox.new()
		a.kind = "apple"
		a.gray = true
		a.custom_minimum_size = Vector2(26, 26)
		row.add_child(a)
	box.add_child(row)


func show_ready(resume: bool) -> void:
	var d = _diff_of(run.diff)
	show_overlay(func(box: VBoxContainer):
		if resume:
			box.add_child(_title("이어서 도전하기"))
			box.add_child(_para("%s %d×%d · 레벨 %d · 사과 %d개" % [d.label, d.n, d.n, int(run.level), int(run.apples)]))
			var go := _button("계속하기", "primary", begin_level)
			_card_row(box).add_child(go)
			go.grab_focus.call_deferred()
		else:
			box.add_child(_hog_box())
			box.add_child(_title("%s 도전" % d.label))
			box.add_child(_para("사과 %d개로 몇 레벨까지 갈 수 있을까요? 시작하면 시간이 흘러요." % apples_of(diff)))
			var go := _button("시작", "primary", begin_level)
			_card_row(box).add_child(go)
			go.grab_focus.call_deferred())


func show_between(level_ms: int, cleared_level: int) -> void:
	show_overlay(func(box: VBoxContainer):
		box.add_child(_hog_box())
		box.add_child(_title("레벨 %d 클리어!" % cleared_level))
		box.add_child(_para("%s · 누적 %s · 사과 %d개" % [fmt(level_ms), fmt(run.totalMs), int(run.apples)]))
		var go := _button("다음 레벨", "primary", func():
			load_run_level()
			begin_level())
		_card_row(box).add_child(go)
		go.grab_focus.call_deferred())


func show_over() -> void:
	var d = _diff_of(run.diff)
	var failed: bool = run.get("endReason", "") != "quit"
	show_overlay(func(box: VBoxContainer):
		if failed:
			_apples_row(box)
		var t := _title("레벨 %d에서 사과를 다 썼어요" % int(run.level) if failed else "도전을 끝냈어요")
		if failed:
			t.add_theme_color_override("font_color", DANGER)
		box.add_child(t)
		box.add_child(_para("%s %d×%d 도전 결과" % [d.label, d.n, d.n]))
		box.add_child(_label("%d레벨 클리어 · %s" % [int(run.cleared), fmt(run.totalMs)], 21, INK, true, true))
		var row := _card_row(box)
		var nw := _button("새 도전", "primary", start_new_run)
		row.add_child(nw)
		row.add_child(_button("리더보드", "", open_lb))
		if failed:
			var peek: Button
			peek = _button("정답 보기", "", func(): _toggle_peek(peek))
			row.add_child(peek)
		nw.grab_focus.call_deferred())
	if int(run.cleared) > 0 and not run.get("submitted", false) and last_result == null:
		try_submit()


func show_practice_end(won: bool) -> void:
	show_overlay(func(box: VBoxContainer):
		var go: Button
		if won:
			box.add_child(_hog_box())
			box.add_child(_title("모두 자리를 찾았어요!"))
			var extra := " · 힌트 %d번" % int(practice.hints) if int(practice.hints) > 0 else ""
			box.add_child(_para("%s · 남은 사과 %d개%s" % [fmt(clock_ms()), int(practice.hearts), extra]))
			var lv := int(practice.level)
			go = _button("다음 레벨" if lv < MAX_LEVEL else "처음 레벨로", "primary", func(): load_practice(diff, lv + 1 if lv < MAX_LEVEL else 1))
			_card_row(box).add_child(go)
		else:
			_apples_row(box)
			var t := _title("사과를 다 썼어요")
			t.add_theme_color_override("font_color", DANGER)
			box.add_child(t)
			box.add_child(_para("흐린 고슴도치가 정답 자리예요."))
			var lv := int(practice.level)
			go = _button("다시 도전", "primary", func(): load_practice(diff, lv))
			var row := _card_row(box)
			row.add_child(go)
			var peek: Button
			peek = _button("정답 보기", "", func(): _toggle_peek(peek))
			row.add_child(peek)
		go.grab_focus.call_deferred())


## "정답 보기" shrinks the card so the revealed board can be seen; pressing again brings the card back.
func _toggle_peek(btn: Button) -> void:
	overlay_peek = not overlay_peek
	btn.text = "결과 보기" if overlay_peek else "정답 보기"
	var dim: ColorRect = overlay.get_child(0)
	dim.visible = not overlay_peek
	var box: VBoxContainer = overlay_card.get_child(0)
	for c in box.get_children():
		if c.name != "Row":
			c.visible = not overlay_peek
	var center: CenterContainer = overlay.get_child(1)
	if overlay_peek:
		overlay_card.custom_minimum_size.x = 0
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.offset_top = board_area.size.y - overlay_card.get_combined_minimum_size().y - 24
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		overlay_card.custom_minimum_size.x = minf(board_area.size.x * 0.88, 340)
		center.offset_top = 0


# =====================================================================
# UI construction
# =====================================================================

func _make_theme() -> Theme:
	var t := Theme.new()
	t.default_font = font_body
	t.default_font_size = 15
	t.set_color("font_color", "Label", INK)
	var mk := func(bg: Color, border: Color, radius: int, pad_h := 14, pad_v := 8) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = bg
		s.border_color = border
		s.set_border_width_all(1 if border.a > 0 else 0)
		s.set_corner_radius_all(radius)
		s.content_margin_left = pad_h
		s.content_margin_right = pad_h
		s.content_margin_top = pad_v
		s.content_margin_bottom = pad_v
		s.anti_aliasing = true
		return s
	var focus := StyleBoxFlat.new()
	focus.draw_center = false
	focus.border_color = RING
	focus.set_border_width_all(3)
	focus.set_corner_radius_all(12)
	focus.expand_margin_left = 2
	focus.expand_margin_right = 2
	focus.expand_margin_top = 2
	focus.expand_margin_bottom = 2
	for kind in [["Button", SURFACE, INK, GRIDC], ["Primary", ACCENT, ACCENT_INK, Color(0, 0, 0, 0)],
			["Danger", DANGER, Color.WHITE, Color(0, 0, 0, 0)], ["Warn", SURFACE, DANGER, GRIDC]]:
		var name: String = kind[0]
		if name != "Button":
			t.set_type_variation(name, "Button")
		var normal: StyleBoxFlat = mk.call(kind[1], kind[3], 10)
		var hover: StyleBoxFlat = normal.duplicate()
		hover.bg_color = kind[1].darkened(0.05) if name != "Button" else Color("eef0e4")
		var pressed: StyleBoxFlat = normal.duplicate()
		pressed.bg_color = kind[1].darkened(0.1)
		t.set_stylebox("normal", name, normal)
		t.set_stylebox("hover", name, hover)
		t.set_stylebox("pressed", name, pressed)
		t.set_stylebox("disabled", name, normal)
		t.set_stylebox("focus", name, focus)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(c, name, kind[2])
		t.set_color("font_disabled_color", name, Color(kind[2], 0.45))
		t.set_font_size("font_size", name, 15)
	# segmented buttons
	for kind in [["SegOn", ACCENT, ACCENT_INK], ["SegOff", Color(0, 0, 0, 0), MUTED]]:
		t.set_type_variation(kind[0], "Button")
		var s: StyleBoxFlat = mk.call(kind[1], Color(0, 0, 0, 0), 999, 12, 5)
		var hv: StyleBoxFlat = s.duplicate()
		if kind[0] == "SegOff":
			hv.bg_color = ACCENT_SOFT
		for st in ["normal", "pressed", "disabled"]:
			t.set_stylebox(st, kind[0], s)
		t.set_stylebox("hover", kind[0], hv)
		t.set_stylebox("focus", kind[0], focus)
		for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color", "font_hover_pressed_color"]:
			t.set_color(c, kind[0], kind[2])
		t.set_color("font_disabled_color", kind[0], Color(kind[2], 0.4))
	t.set_type_variation("Seg", "PanelContainer")
	var segbox: StyleBoxFlat = mk.call(SURFACE, GRIDC, 999, 4, 4)
	t.set_stylebox("panel", "Seg", segbox)
	t.set_type_variation("Card", "PanelContainer")
	var card: StyleBoxFlat = mk.call(SURFACE, GRIDC, 14, 24, 22)
	card.shadow_color = Color(0, 0, 0, 0.15)
	card.shadow_size = 14
	card.shadow_offset = Vector2(0, 8)
	t.set_stylebox("panel", "Card", card)
	t.set_type_variation("Soft", "PanelContainer")
	t.set_stylebox("panel", "Soft", mk.call(ACCENT_SOFT, Color(0, 0, 0, 0), 12, 14, 12))
	# line edit
	var le: StyleBoxFlat = mk.call(BG, GRIDC, 10, 10, 7)
	t.set_stylebox("normal", "LineEdit", le)
	var lef: StyleBoxFlat = le.duplicate()
	lef.border_color = RING
	lef.set_border_width_all(2)
	t.set_stylebox("focus", "LineEdit", lef)
	t.set_color("font_color", "LineEdit", INK)
	t.set_color("font_placeholder_color", "LineEdit", Color(MUTED, 0.7))
	t.set_color("caret_color", "LineEdit", INK)
	t.set_font_size("font_size", "LineEdit", 16)
	t.set_color("font_color", "CheckBox", MUTED)
	t.set_color("font_hover_color", "CheckBox", INK)
	t.set_color("font_pressed_color", "CheckBox", MUTED)
	t.set_color("font_hover_pressed_color", "CheckBox", INK)
	t.set_color("font_focus_color", "CheckBox", MUTED)
	t.set_stylebox("focus", "CheckBox", focus)
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		t.set_stylebox(st, "CheckBox", StyleBoxEmpty.new())
	var tip: StyleBoxFlat = mk.call(INK, Color(0, 0, 0, 0), 8, 8, 4)
	t.set_stylebox("panel", "TooltipPanel", tip)
	t.set_color("font_color", "TooltipLabel", BG)
	return t


func _label(text: String, sz := 15, color := INK, display := false, center := false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", color)
	if display:
		l.add_theme_font_override("font", font_display)
	if center:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


func _para(text: String, sz := 15, color := MUTED) -> Label:
	var l := _label(text, sz, color, false, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 120
	return l


func _title(text: String) -> Label:
	var l := _label(text, 26, INK, true, true)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l


func _button(text: String, kind: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	if kind == "primary":
		b.theme_type_variation = "Primary"
	elif kind == "danger":
		b.theme_type_variation = "Danger"
	elif kind == "warn":
		b.theme_type_variation = "Warn"
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return b


func _icon_button(kind: String, tip: String, cb: Callable, variation := "") -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(44, 40)
	b.tooltip_text = tip
	if variation != "":
		b.theme_type_variation = variation
	b.pressed.connect(cb)
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var ic := DrawBox.new()
	ic.kind = kind
	ic.color = DANGER if variation == "Warn" else INK
	ic.custom_minimum_size = Vector2(22, 22)
	ic.size = Vector2(22, 22)
	ic.position = Vector2(11, 9)
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ic.name = "Icon"
	b.add_child(ic)
	b.resized.connect(func(): ic.position = (b.size - ic.size) / 2)
	b.draw.connect(func(): ic.modulate.a = 0.45 if b.disabled else 1.0)
	return b


func _round_btn(text: String, cb: Callable) -> Button:
	var b := _button(text, "", cb)
	b.custom_minimum_size = Vector2(30, 30)
	var s := StyleBoxFlat.new()
	s.bg_color = SURFACE
	s.border_color = GRIDC
	s.set_border_width_all(1)
	s.set_corner_radius_all(15)
	for st in ["normal", "hover", "pressed", "disabled"]:
		b.add_theme_stylebox_override(st, s)
	b.add_theme_font_size_override("font_size", 16)
	return b


func _card() -> PanelContainer:
	var c := PanelContainer.new()
	c.theme_type_variation = "Card"
	return c


## Segmented control. Returns the outer panel; `store` gets key -> Button.
func _seg(items: Array, store: Dictionary, cb: Callable, equal := false, sz := 14, display := false) -> PanelContainer:
	var p := PanelContainer.new()
	p.theme_type_variation = "Seg"
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	p.add_child(row)
	for it in items:
		var b := Button.new()
		b.text = it[1]
		b.theme_type_variation = "SegOff"
		b.add_theme_font_size_override("font_size", sz)
		if display:
			b.add_theme_font_override("font", font_display)
		if equal:
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var key: String = it[0]
		b.pressed.connect(func(): cb.call(key))
		store[key] = b
		row.add_child(b)
	return p


func _seg_set(store: Dictionary, key: String) -> void:
	for k in store:
		store[k].theme_type_variation = "SegOn" if k == key else "SegOff"


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	col = VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	add_child(col)

	# header
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	title_hog = _hog_box(52)
	head.add_child(title_hog)
	var tbox := VBoxContainer.new()
	tbox.add_theme_constant_override("separation", 2)
	tbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tbox.alignment = BoxContainer.ALIGNMENT_CENTER
	h1 = _label("고슴도쿠", 34, INK, true)
	tbox.add_child(h1)
	tagline = _label("가시가 따가워서 서로 붙기 싫은 고슴도치들의 자리 찾기 퍼즐", 14, MUTED)
	tagline.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tbox.add_child(tagline)
	head.add_child(tbox)
	var pf := Button.new()
	pf.flat = true
	pf.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pf.tooltip_text = "내 프로필"
	pf.pressed.connect(func(): open_profile())
	var pfbox := VBoxContainer.new()
	pfbox.alignment = BoxContainer.ALIGNMENT_CENTER
	pfbox.add_theme_constant_override("separation", 2)
	pfbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pfbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	pf_avatar_panel = PanelContainer.new()
	var circ := StyleBoxFlat.new()
	circ.bg_color = SURFACE
	circ.border_color = GRIDC
	circ.set_border_width_all(2)
	circ.set_corner_radius_all(26)
	circ.set_content_margin_all(9)
	pf_avatar_panel.add_theme_stylebox_override("panel", circ)
	pf_avatar_panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	pf_avatar_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pf_avatar = TextureRect.new()
	pf_avatar.custom_minimum_size = Vector2(32, 32)
	pf_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pf_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pf_avatar_panel.add_child(pf_avatar)
	pfbox.add_child(pf_avatar_panel)
	pf_name = _label("", 12, MUTED, false, true)
	pf_name.clip_text = true
	pf_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pf_name.custom_minimum_size.x = 84
	pfbox.add_child(pf_name)
	pf.add_child(pfbox)
	pf.custom_minimum_size = Vector2(88, 74)
	pf.mouse_entered.connect(func(): circ.border_color = ACCENT)
	pf.mouse_exited.connect(func(): circ.border_color = GRIDC)
	head.add_child(pf)
	col.add_child(head)

	# controls
	var controls := VBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 8)
	top.add_child(_seg([["run", "도전"], ["practice", "연습"]], mode_btns, _on_mode, false, 16, true))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(sp)
	var help := _icon_button("help", "규칙과 조작법", open_rules)
	help.custom_minimum_size = Vector2(40, 38)
	top.add_child(help)
	lb_open_btn = Button.new()
	lb_open_btn.tooltip_text = "리더보드"
	lb_open_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lb_open_btn.pressed.connect(open_lb)
	var lbrow := HBoxContainer.new()
	lbrow.add_theme_constant_override("separation", 6)
	lbrow.alignment = BoxContainer.ALIGNMENT_CENTER
	lbrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbrow.set_anchors_preset(Control.PRESET_FULL_RECT)
	var pod := DrawBox.new()
	pod.kind = "podium"
	pod.custom_minimum_size = Vector2(18, 18)
	pod.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pod.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbrow.add_child(pod)
	lb_text = _label("리더보드", 15, INK)
	lb_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lbrow.add_child(lb_text)
	lb_open_btn.add_child(lbrow)
	lb_open_btn.custom_minimum_size = Vector2(108, 38)
	top.add_child(lb_open_btn)
	controls.add_child(top)
	var items := []
	for d in DIFFS:
		items.append([d.id, "%s %d×%d" % [d.label, d.n, d.n]])
	controls.add_child(_seg(items, diff_btns, _on_diff, true, 14))
	lock_note = _label("첫 수를 둔 뒤에는 난이도를 바꿀 수 없어요", 13, MUTED)
	controls.add_child(lock_note)
	col.add_child(controls)

	# status
	var status := HBoxContainer.new()
	status.custom_minimum_size.y = 34
	lives_box = HBoxContainer.new()
	lives_box.add_theme_constant_override("separation", 4)
	lives_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lives_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	status.add_child(lives_box)
	info_box = HBoxContainer.new()
	info_box.add_theme_constant_override("separation", 6)
	info_box.alignment = BoxContainer.ALIGNMENT_CENTER
	status.add_child(info_box)
	timer_lbl = _label("00:00", 15, MUTED)
	timer_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	timer_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status.add_child(timer_lbl)
	col.add_child(status)

	# board
	board_area = Control.new()
	board_area.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	board = BoardView.new()
	board.game = self
	board.font = font_body
	board.set_anchors_preset(Control.PRESET_FULL_RECT)
	board_area.add_child(board)
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.visible = false
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	board_area.add_child(overlay)
	col.add_child(board_area)

	# actions
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 8)
	undo_btn = _icon_button("undo", "되돌리기", undo)
	hint_btn = _icon_button("hint", "힌트", hint)
	hint_badge = DrawBox.new()
	hint_badge.kind = "badge"
	hint_badge.custom_minimum_size = Vector2(34, 18)
	hint_badge.size = Vector2(34, 18)
	hint_badge.position = Vector2(20, -9)
	hint_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hint_btn.add_child(hint_badge)
	restart_btn = _icon_button("erase", "보드 비우기", restart)
	restart_icon = restart_btn.get_node("Icon")
	quit_btn = _icon_button("flag", "도전 끝내기", open_quit, "Warn")
	for b in [undo_btn, hint_btn, restart_btn, quit_btn]:
		actions.add_child(b)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(sp2)
	autox_chk = CheckBox.new()
	autox_chk.text = "자동 × 표시"
	autox_chk.button_pressed = auto_x
	autox_chk.add_theme_font_size_override("font_size", 14)
	autox_chk.toggled.connect(func(on: bool):
		auto_x = on
		sset("autoX", on))
	actions.add_child(autox_chk)
	col.add_child(actions)

	# toast
	toast_panel = PanelContainer.new()
	var ts := StyleBoxFlat.new()
	ts.bg_color = INK
	ts.set_corner_radius_all(999)
	ts.content_margin_left = 16
	ts.content_margin_right = 16
	ts.content_margin_top = 8
	ts.content_margin_bottom = 8
	toast_panel.add_theme_stylebox_override("panel", ts)
	toast_lbl = _label("", 17, BG, true)
	toast_panel.add_child(toast_lbl)
	toast_panel.modulate.a = 0
	toast_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast_panel)

	# modals
	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)
	_build_lb()
	_build_profile()
	_build_rules()
	_build_quit()


func _layout() -> void:
	if col == null:
		return
	var vw := size.x
	var vh := size.y
	narrow = vw <= 480
	var w := minf(vw - 32, 520)
	var top := 10.0 if narrow else 20.0
	col.add_theme_constant_override("separation", 10 if narrow else 16)
	tagline.visible = not (narrow and vh < 760)
	lock_note.visible = not narrow
	lb_text.visible = not narrow
	lb_open_btn.custom_minimum_size = Vector2(44, 38) if narrow else Vector2(108, 38)
	h1.add_theme_font_size_override("font_size", 27 if narrow else 34)
	title_hog.custom_minimum_size = Vector2(40, 40) if narrow else Vector2(52, 52)
	autox_chk.text = "자동 ×" if narrow else "자동 × 표시"
	board.narrow = narrow
	# board: as large as the column, but small enough for the action row to stay on screen
	board_area.custom_minimum_size = Vector2.ZERO
	col.position = Vector2((vw - w) / 2, top)
	col.size = Vector2(w, 0)
	var used := 0.0
	var gaps := 0
	for c in col.get_children():
		if c != board_area and c.visible:
			used += c.get_combined_minimum_size().y
			gaps += 1
	var sep: float = col.get_theme_constant("separation")
	var room := vh - top - (24.0 if narrow else 40.0) - used - sep * gaps
	var bs := floorf(clampf(minf(w, room), 250, w))
	board_area.custom_minimum_size = Vector2(bs, bs)
	col.size = Vector2(w, 0)
	toast_panel.reset_size()
	toast_panel.position = Vector2((vw - toast_panel.size.x) / 2, vh - toast_panel.size.y - 24)
	_layout_modals()
	if board != null:
		board.queue_redraw()
	if overlay_card != null and is_instance_valid(overlay_card) and not overlay_peek:
		overlay_card.custom_minimum_size.x = minf(bs * 0.88, 340)


func toast(msg: String) -> void:
	toast_lbl.text = msg
	toast_panel.reset_size()
	toast_panel.position = Vector2((size.x - toast_panel.size.x) / 2, size.y - toast_panel.size.y - 24)
	if toast_tween:
		toast_tween.kill()
	toast_tween = create_tween()
	toast_panel.modulate.a = 0
	toast_tween.tween_property(toast_panel, "modulate:a", 1.0, 0.2)
	toast_tween.tween_interval(1.6)
	toast_tween.tween_property(toast_panel, "modulate:a", 0.0, 0.2)


func _on_mode(m: String) -> void:
	if m == mode:
		return
	if m == "practice":
		leave_run_mode()
		var p = sget("practice", null)
		var d: String = diff
		var lv := 1
		if p is Dictionary and _diff_of(str(p.get("diff", ""))) != null:
			d = p.diff
			var l := int(p.get("level", 1))
			lv = l if l >= 1 and l <= MAX_LEVEL else 1
		load_practice(d, lv)
	else:
		enter_run_mode()


func _on_diff(d: String) -> void:
	if d == diff or diff_btns[d].disabled:
		return
	if mode == "run":
		if not run_started():
			new_run(d)
	else:
		load_practice(d, 1)
	lb_diff = d
	render()


func _input(ev: InputEvent) -> void:
	# Escape closes the top window, even while the nickname field has focus
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
		for m in [quit_modal, rules_modal, pf_modal, lb_modal]:
			if m.visible:
				_close_modal(m)
				get_viewport().set_input_as_handled()
				return


func _unhandled_input(ev: InputEvent) -> void:
	if test_mode and ev is InputEventKey and ev.pressed and ev.keycode == KEY_F9 and playing():
		for r in P.N:
			var i := r * P.N + P.sol[r]
			if cells[i] != 2 and playing():
				place(i)
		render()
		return


# =====================================================================
# modal windows
# =====================================================================

func _modal(card: Control, on_close: Callable) -> Control:
	var m := Control.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.078, 0.063, 0.039, 0.45)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			on_close.call())
	m.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(center)
	center.add_child(card)
	m.set_meta("close", on_close)
	modal_layer.add_child(m)
	return m


func _close_modal(m: Control) -> void:
	(m.get_meta("close") as Callable).call()


func _layout_modals() -> void:
	if lb_panel == null:
		return
	var w := minf(480, size.x - 32)
	lb_panel.custom_minimum_size = Vector2(w, minf(720, size.y - 32))
	pf_modal.get_child(1).get_child(0).custom_minimum_size.x = minf(360, size.x - 32)
	rules_modal.get_child(1).get_child(0).custom_minimum_size = Vector2(minf(420, size.x - 32), 0)
	var rs: ScrollContainer = rules_modal.get_child(1).get_child(0).get_child(0)
	rs.custom_minimum_size.y = minf(size.y - 32 - 48, 640)
	quit_modal.get_child(1).get_child(0).custom_minimum_size.x = minf(340, size.x - 32)


# ----- rules -----

func _build_rules() -> void:
	var card := _card()
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	card.add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	box.add_child(_title("규칙"))
	var rules := ["색깔 덤불마다 고슴도치는 딱 한 마리.", "같은 가로줄, 같은 세로줄에는 한 마리만.",
		"가시가 따가워서 대각선으로도 붙어 있으면 안 돼요.", "찍지 말고 추리로 풀기. 틀린 자리에 놓으면 사과를 하나 잃어요."]
	for k in rules.size():
		box.add_child(_list_item("%d." % (k + 1), rules[k], true))
	box.add_child(_label("조작", 17, INK, true))
	for s in ["빈 칸 누르기: × 표시 · × 나 고슴도치 누르기: 지우기", "두 번 빠르게 누르기: 고슴도치 놓기",
			"빈 칸에서 드래그: × 긋기 · × 칸에서 드래그: × 지우기", "키보드: 방향키로 칸 이동 · Space: × · Enter: 고슴도치"]:
		box.add_child(_list_item("•", s))
	box.add_child(_label("아래 버튼", 17, INK, true))
	for it in [["undo", "되돌리기"], ["hint", "힌트 (도전에서는 사과 1개)"], ["erase", "보드 비우기 (고슴도치는 남겨요)"],
			["restart", "다시 시작 (연습)"], ["flag", "도전 끝내기"]]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var ic := DrawBox.new()
		ic.kind = it[0]
		ic.color = ACCENT
		ic.custom_minimum_size = Vector2(20, 20)
		row.add_child(ic)
		row.add_child(_label(it[1], 15, INK))
		box.add_child(row)
	var note := _para("도전 모드에서는 사과(쉬움 3개 · 보통 4개 · 어려움 5개)가 다음 판으로 그대로 이어지고, 퍼즐은 도전할 때마다 새로 만들어져요. 모든 판은 답이 하나뿐이에요. 연습 모드는 판마다 사과가 다시 차고 기록은 남지 않아요.", 13)
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	box.add_child(note)
	var row := _card_row(box)
	row.add_child(_button("알겠어요", "primary", close_rules))
	rules_modal = _modal(card, close_rules)


func _list_item(mark: String, text: String, accent := false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var m := _label(mark, 15, ACCENT if accent else MUTED, accent)
	m.custom_minimum_size.x = 18
	m.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(m)
	var l := _label(text, 15, INK)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.custom_minimum_size.x = 100
	row.add_child(l)
	return row


func open_rules() -> void:
	_layout_modals()
	rules_modal.visible = true
	var rs: ScrollContainer = rules_modal.get_child(1).get_child(0).get_child(0)
	rs.scroll_vertical = 0
	var btn: Button = rs.get_child(0).get_child(rs.get_child(0).get_child_count() - 1).get_child(0)
	btn.grab_focus.call_deferred()


func close_rules() -> void:
	rules_modal.visible = false


# ----- quit -----

func _build_quit() -> void:
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	box.add_child(_title("도전을 끝낼까요?"))
	quit_body = _para("")
	box.add_child(quit_body)
	var row := _card_row(box)
	row.add_child(_button("계속하기", "", func(): close_quit(false)))
	row.add_child(_button("끝내기", "danger", func(): close_quit(true)))
	quit_modal = _modal(card, func(): close_quit(false))


func open_quit() -> void:
	if not run_active():
		return
	quit_resume = phase == "play"
	if quit_resume:
		clock_pause()
	if int(run.cleared) > 0:
		quit_body.text = "%d레벨 클리어 · %s 기록으로 끝나요.%s" % [int(run.cleared), fmt(run.totalMs),
			" 지금 풀고 있는 레벨 %d은 기록에 들어가지 않아요." % int(run.level) if quit_resume else ""]
	else:
		quit_body.text = "아직 클리어한 레벨이 없어서 기록은 남지 않아요."
	_layout_modals()
	quit_modal.visible = true
	var row: HBoxContainer = quit_body.get_parent().get_child(2)
	row.get_child(0).grab_focus.call_deferred()


func close_quit(confirmed: bool) -> void:
	if not quit_modal.visible:
		return
	quit_modal.visible = false
	if confirmed:
		end_run("quit")
		return
	if quit_resume and phase == "play":
		clock_start()


# ----- profile -----

func set_profile(nick: String, av: String) -> void:
	nickname = nick
	avatar = valid_avatar(av)
	sset("nick", nickname)
	sset("avatar", avatar)
	render_profile_btn()
	if not lb_enabled and hold == null and pending_anim == null and lb_modal != null:
		render_lb()


func render_profile_btn() -> void:
	pf_avatar.texture = avatar_tex.get(avatar if avatar != "" else "🦔")
	pf_avatar.modulate.a = 1.0 if avatar != "" else 0.35
	pf_name.text = nickname if nickname != "" else "프로필 만들기"


func _build_profile() -> void:
	var card := _card()
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	box.add_child(_title("내 프로필"))
	pf_prev_avatar = TextureRect.new()
	pf_prev_avatar.custom_minimum_size = Vector2(48, 48)
	pf_prev_avatar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pf_prev_avatar.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	pf_prev_avatar.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(pf_prev_avatar)
	pf_prev_name = _label("", 18, INK, true, true)
	box.add_child(pf_prev_name)
	var grid := GridContainer.new()
	grid.columns = 6
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for a in AVATARS:
		var b := Button.new()
		b.custom_minimum_size = Vector2(44, 44)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.icon = avatar_tex[a]
		b.expand_icon = true
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.tooltip_text = a
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func():
			pf_draft = a
			_paint_draft())
		b.set_meta("a", a)
		pf_grid_btns.append(b)
		grid.add_child(b)
	box.add_child(grid)
	var lab := HBoxContainer.new()
	lab.add_child(_label("닉네임", 14, MUTED))
	lab.add_child(_label(" 1~12자", 12, MUTED))
	box.add_child(lab)
	pf_nick = LineEdit.new()
	pf_nick.max_length = NICK_MAX
	pf_nick.placeholder_text = "리더보드에 보일 이름"
	pf_nick.text_changed.connect(func(_t): _paint_draft())
	pf_nick.text_submitted.connect(func(_t): _save_profile())
	box.add_child(pf_nick)
	pf_msg = _label("", 13, DANGER)
	pf_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pf_msg.custom_minimum_size.x = 100
	box.add_child(pf_msg)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 8)
	row.add_child(_button("취소", "", close_profile))
	pf_save = _button("저장", "primary", _save_profile)
	row.add_child(pf_save)
	box.add_child(row)
	pf_modal = _modal(card, close_profile)


func _paint_draft() -> void:
	for b in pf_grid_btns:
		var on: bool = b.get_meta("a") == pf_draft
		var s := StyleBoxFlat.new()
		s.bg_color = ACCENT_SOFT if on else BG
		s.border_color = ACCENT if on else Color(0, 0, 0, 0)
		s.set_border_width_all(2)
		s.set_corner_radius_all(12)
		s.set_content_margin_all(6)
		for st in ["normal", "hover", "pressed"]:
			b.add_theme_stylebox_override(st, s)
	pf_prev_avatar.texture = avatar_tex.get(pf_draft if pf_draft != "" else "🦔")
	pf_prev_avatar.modulate.a = 1.0 if pf_draft != "" else 0.3
	var n := clean_nick(pf_nick.text)
	pf_prev_name.text = n if n != "" else "이름을 정해 주세요"


func open_profile(focus_name := false) -> void:
	pf_draft = avatar
	pf_nick.text = nickname
	pf_msg.text = ""
	pf_save.disabled = false
	_paint_draft()
	_layout_modals()
	pf_modal.visible = true
	if focus_name or pf_draft != "":
		pf_nick.grab_focus.call_deferred()
	else:
		pf_grid_btns[0].grab_focus.call_deferred()


func close_profile() -> void:
	pf_modal.visible = false


func _save_profile() -> void:
	var nick := clean_nick(pf_nick.text)
	if pf_draft == "":
		pf_msg.text = "이모지를 하나 골라 주세요."
		return
	if nick == "":
		pf_msg.text = "닉네임을 1~12자로 정해 주세요."
		pf_nick.grab_focus()
		return
	set_profile(nick, pf_draft)
	pf_save.disabled = true
	pf_msg.text = ""
	var res := await sync_profile()
	pf_save.disabled = false
	if not res.ok:
		pf_msg.text = "%s 이 기기에는 저장했고, 다음 기록을 올릴 때 다시 보낼게요." % res.msg
		return
	close_profile()
	toast("프로필을 저장했어요")
	if lb_enabled:
		refresh_lb()
	if last_result is Dictionary and last_result.get("needNick", false):
		try_submit()


# =====================================================================
# leaderboard (server)
# =====================================================================

func error_text(res: Dictionary) -> String:
	if ERRORS.has(res.get("error", "")):
		return ERRORS[res.error]
	return "인터넷 연결을 확인해 주세요." if res.get("net", false) else "리더보드 서버에 문제가 있어 기록을 저장하지 못했어요."


func sync_profile() -> Dictionary:
	if not lb_enabled or nickname == "":
		return {"ok": true}
	var key := "%s|%s|%s" % [player.id, nickname, avatar]
	if str(sget("profileSynced", "")) == key:
		return {"ok": true}
	var body := {"p_player": player.id, "p_secret": player.secret, "p_nickname": nickname, "p_avatar": avatar if avatar != "" else null}
	var res := await sb.request("rpc/save_profile", HTTPClient.METHOD_POST, body)
	if not res.ok:
		return {"ok": false, "msg": error_text(res)}
	sset("profileSynced", key)
	return {"ok": true}


func lb_key(d: String, period := "") -> String:
	return "%s:%s" % [period if period != "" else lb_period, d]


const VIEWS := {"all": "leaderboard", "week": "leaderboard_week"}
const COLS := "player_id,nickname,levels,time_ms,avatar"


## Loads the top rows and my own rank for one board. Returns false when the server could not be reached.
func load_lb(d: String, period := "") -> bool:
	if period == "":
		period = lb_period
	var view: String = VIEWS[period]
	var q := "diff=eq.%s" % d
	var res := await sb.request("%s?select=%s&%s&order=levels.desc,time_ms.asc,updated_at.asc&limit=%d" % [view, COLS, q, LB_TOP])
	if not res.ok or not (res.data is Array):
		return false
	var top: Array = res.data
	var mine = null
	var my_rank := 0
	for k in top.size():
		if top[k].player_id == player.id:
			mine = top[k]
			my_rank = k + 1
			break
	if mine == null:
		var me := await sb.request("%s?select=%s&%s&player_id=eq.%s" % [view, COLS, q, player.id])
		if not me.ok:
			return false
		if me.data is Array and not me.data.is_empty():
			mine = me.data[0]
			var ahead := await sb.request("%s?select=player_id&%s&or=(levels.gt.%d,and(levels.eq.%d,time_ms.lt.%d))" % [view, q, int(mine.levels), int(mine.levels), int(mine.time_ms)],
				HTTPClient.METHOD_GET, null, ["Prefer: count=exact", "Range: 0-0"])
			var total := SupaClient.count_of(ahead)
			my_rank = total + 1 if total >= 0 else 0
	lb_cache[lb_key(d, period)] = {"rows": top, "mine": mine, "myRank": my_rank}
	return true


func refresh_lb(d := "", period := "") -> void:
	if d == "":
		d = lb_diff
	if period == "":
		period = lb_period
	if not lb_enabled:
		render_lb()
		return
	lb_token += 1
	var token := lb_token
	var ok := await load_lb(d, period)
	if token != lb_token:
		return
	if ok:
		lb_state = "ready"
		lb_loaded_at = Time.get_ticks_msec()
	else:
		lb_state = "ready" if lb_cache.has(lb_key(d, period)) else "error"
		lb_status.text = "리더보드를 불러오지 못했어요."
	render_lb()


func submit_score(d: String, levels: int, time_ms: int) -> Dictionary:
	if not lb_enabled:
		return {"ok": false, "msg": "리더보드가 아직 설정되지 않아 기록은 이 기기에만 남아요."}
	if nickname == "":
		return {"ok": false, "needNick": true, "msg": "프로필에서 닉네임을 정하면 리더보드에 올라가요."}
	var res := await sb.request("rpc/submit_score", HTTPClient.METHOD_POST,
		{"p_player": player.id, "p_secret": player.secret, "p_nickname": nickname, "p_diff": d, "p_levels": levels, "p_time_ms": time_ms})
	if not res.ok:
		var e: String = res.get("error", "")
		var retry := not ERRORS.has(e) or e == "bad_nickname"
		return {"ok": false, "retry": retry, "needNick": e == "bad_nickname", "msg": error_text(res)}
	var data: Dictionary = res.data if res.data is Dictionary else {}
	# refresh both boards; the window then shows the one this run moved (all time first, else this week)
	await load_lb(d, "all")
	await load_lb(d, "week")
	lb_state = "ready"
	lb_loaded_at = Time.get_ticks_msec()
	var week: String = str(data.get("week_status", ""))
	var r_all: int = lb_cache.get(lb_key(d, "all"), {}).get("myRank", 0)
	var r_week: int = lb_cache.get(lb_key(d, "week"), {}).get("myRank", 0) if week != "" else 0
	if data.get("status", "") == "not_better" and week == "new_best":
		return {"ok": true, "done": true, "status": "new_best", "period": "week",
			"msg": "이번 주 최고 기록이에요%s (전체 최고 기록 %d레벨 · %s은 그대로)" % [" · 이번 주 %d위" % r_week if r_week > 0 else "", int(data.levels), fmt(data.time_ms)]}
	if data.get("status", "") == "not_better":
		var run_rank := 0
		var ahead := await sb.request("%s?select=player_id&diff=eq.%s&or=(levels.gt.%d,and(levels.eq.%d,time_ms.lt.%d))" % [VIEWS.all, d, levels, levels, time_ms],
			HTTPClient.METHOD_GET, null, ["Prefer: count=exact", "Range: 0-0"])
		var cnt := SupaClient.count_of(ahead)
		if cnt >= 0:
			run_rank = cnt + 1
		return {"ok": true, "done": true, "status": "not_better", "period": "all", "runRank": run_rank,
			"msg": "개인 최고 기록(%d레벨 · %s)을 넘지 못해서 리더보드는 그대로예요." % [int(data.levels), fmt(data.time_ms)]}
	var ranks := []
	if r_all > 0: ranks.append("전체 %d위" % r_all)
	if r_week > 0: ranks.append("이번 주 %d위" % r_week)
	return {"ok": true, "done": true, "status": "new_best", "period": "all",
		"msg": "리더보드에 등록했어요" + (" · " + " · ".join(ranks) if not ranks.is_empty() else "")}


# ----- this device's own board (when the online board can't be written from here) -----

func me_id() -> String:
	return player.id if lb_enabled else str(run.get("localId", "")) if run != null else ""


func _local_runs(d: String) -> Array:
	var out := []
	for x in local_board.get(d, []):
		if x is Dictionary and x.has("id") and x.has("levels") and x.has("timeMs") and x.has("at"):
			out.append(x)
	out.sort_custom(func(a, b):
		if int(a.levels) != int(b.levels): return int(a.levels) > int(b.levels)
		if int(a.timeMs) != int(b.timeMs): return int(a.timeMs) < int(b.timeMs)
		return float(a.at) < float(b.at))
	return out


func _local_name(x: Dictionary) -> String:
	var d := Time.get_datetime_dict_from_unix_time(int(float(x.at) / 1000.0) + int(Time.get_time_zone_from_system().bias) * 60)
	return "%s · %d/%d %02d:%02d" % [nickname if nickname != "" else "나", d.month, d.day, d.hour, d.minute]


func local_entries(d: String) -> Dictionary:
	var runs := _local_runs(d)
	var cur: String = str(run.get("localId", "")) if run != null else ""
	var lst := []
	for k in mini(runs.size(), LB_TOP):
		lst.append({"id": runs[k].id, "name": _local_name(runs[k]), "avatar": avatar, "levels": int(runs[k].levels), "timeMs": int(runs[k].timeMs), "pos": k + 1})
	var idx := -1
	for k in runs.size():
		if runs[k].id == cur:
			idx = k
			break
	if idx >= LB_TOP:
		lst.append(null)
		lst.append({"id": runs[idx].id, "name": _local_name(runs[idx]), "avatar": avatar, "levels": int(runs[idx].levels), "timeMs": int(runs[idx].timeMs), "pos": idx + 1})
	return {"list": lst, "myRank": idx + 1}


func add_local_run(r: Dictionary) -> void:
	var rec := {"id": "L%d%d" % [Time.get_ticks_msec(), randi() % 10000], "levels": int(r.cleared), "timeMs": int(r.totalMs),
		"at": Time.get_unix_time_from_system() * 1000.0}
	r.localId = rec.id
	var runs := _local_runs(r.diff)
	runs.append(rec)
	local_board[r.diff] = runs
	local_board[r.diff] = _local_runs(r.diff).slice(0, LOCAL_KEEP)
	var kept := false
	for x in local_board[r.diff]:
		if x.id == rec.id:
			kept = true
	if not kept:
		local_board[r.diff].append(rec)
	sset("localBoard", local_board)


func entries_for(d: String, period := ""):
	if not lb_enabled:
		return local_entries(d)
	var data = lb_cache.get(lb_key(d, period))
	if data == null:
		return null
	var lst := []
	for k in data.rows.size():
		var r = data.rows[k]
		lst.append({"id": r.player_id, "name": str(r.get("nickname", "")), "avatar": valid_avatar(str(r.get("avatar", ""))),
			"levels": int(r.levels), "timeMs": int(r.time_ms), "pos": k + 1})
	if data.mine != null and int(data.myRank) > LB_TOP:
		var m = data.mine
		lst.append(null)
		lst.append({"id": m.player_id, "name": str(m.get("nickname", "")), "avatar": valid_avatar(str(m.get("avatar", ""))),
			"levels": int(m.levels), "timeMs": int(m.time_ms), "pos": int(data.myRank)})
	return {"list": lst, "myRank": int(data.myRank)}


func try_submit() -> void:
	var r = run
	if r == null or not r.get("finished", false) or int(r.cleared) <= 0 or r.get("submitted", false):
		return
	if not lb_enabled:
		var before := local_entries(r.diff)
		add_local_run(r)
		var after := local_entries(r.diff)
		r.submitted = true
		save_run()
		last_result = {"ok": true, "done": true, "msg": "이 기기 기록에 등록했어요 · %d위" % int(after.myRank)}
		if not OS.has_feature("web") or str(JavaScriptBridge.eval("location.hostname", true)) != WRITE_HOST:
			last_result.msg += "\n(온라인 리더보드에는 smkim77.github.io/hedgedoku 에서 올릴 수 있어요)"
		pending_anim = {"diff": r.diff, "period": lb_period, "before": before, "after": after, "status": "local"}
		render_result()
		maybe_play_rank_anim()
		return
	last_result = {"ok": false, "msg": "기록 저장 중…"}
	render_result()
	var auto_named := false
	if nickname == "":
		var av: String = avatar if avatar != "" else AVATARS[randi() % AVATARS.size()]
		set_profile(auto_nick(av), av)
		auto_named = true
	await sync_profile()
	# snapshot both boards before submitting; a board whose lookup fails gets no animation rather than a guess
	var before := {}
	for p in ["all", "week"]:
		if await load_lb(r.diff, p):
			before[p] = entries_for(r.diff, p)
	hold = {"diff": r.diff, "entries": before}
	var res := await submit_score(r.diff, int(r.cleared), int(r.totalMs))
	if run != r:
		hold = null
		return
	if res.get("done", false) and auto_named:
		res.msg = str(res.msg).replace("리더보드에 등록했어요", "\"%s\" 이름으로 등록했어요" % nickname)
		res.autoNamed = true
	last_result = res
	if res.get("done", false):
		r.submitted = true
		save_run()
		var period: String = res.get("period", "all")
		lb_period = period
		_mark_period()
		var after = entries_for(r.diff, period)
		if before.has(period) and after != null:
			pending_anim = {"diff": r.diff, "period": period, "before": before[period], "after": after, "status": res.status,
				"runRank": res.get("runRank", 0)}
	else:
		hold = null
	render_result()
	if pending_anim == null:
		render_lb()
	maybe_play_rank_anim()


# =====================================================================
# leaderboard window
# =====================================================================

func _build_lb() -> void:
	lb_panel = PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = SURFACE
	ps.border_color = GRIDC
	ps.set_border_width_all(1)
	ps.set_corner_radius_all(14)
	ps.content_margin_left = 18
	ps.content_margin_right = 18
	ps.content_margin_top = 16
	ps.content_margin_bottom = 16
	ps.shadow_color = Color(0, 0, 0, 0.25)
	ps.shadow_size = 20
	ps.shadow_offset = Vector2(0, 10)
	lb_panel.add_theme_stylebox_override("panel", ps)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	lb_panel.add_child(box)
	var head := HBoxContainer.new()
	var t := _label("리더보드", 23, INK, true)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var close := _round_btn("×", close_lb)
	close.custom_minimum_size = Vector2(36, 36)
	close.add_theme_font_size_override("font_size", 20)
	head.add_child(close)
	box.add_child(head)
	# result of the challenge that just ended
	lb_result = PanelContainer.new()
	lb_result.theme_type_variation = "Soft"
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 4)
	rbox.alignment = BoxContainer.ALIGNMENT_CENTER
	lb_result.add_child(rbox)
	res_head = _label("", 14, MUTED, false, true)
	rbox.add_child(res_head)
	res_stats = _label("", 21, INK, true, true)
	rbox.add_child(res_stats)
	rank_move = VBoxContainer.new()
	rank_move.add_theme_constant_override("separation", 0)
	rank_line = HBoxContainer.new()
	rank_line.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_line.add_theme_constant_override("separation", 4)
	rank_from = _label("", 19, MUTED, true)
	rank_arrow = _label("→", 19, MUTED, true)
	rank_to = _label("", 27, ACCENT, true)
	for c in [rank_from, rank_arrow, rank_to]:
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		rank_line.add_child(c)
	rank_move.add_child(rank_line)
	rank_tag = _label("", 13, MUTED, false, true)
	rank_move.add_child(rank_tag)
	rbox.add_child(rank_move)
	save_area = VBoxContainer.new()
	save_area.alignment = BoxContainer.ALIGNMENT_CENTER
	save_area.add_theme_constant_override("separation", 6)
	rbox.add_child(save_area)
	var nr := HBoxContainer.new()
	nr.alignment = BoxContainer.ALIGNMENT_CENTER
	nr.add_child(_button("새 도전", "primary", func():
		close_lb()
		start_new_run()))
	rbox.add_child(nr)
	box.add_child(lb_result)
	# filters
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 8)
	filters.add_theme_constant_override("v_separation", 8)
	var items := []
	for d in DIFFS:
		items.append([d.id, d.label])
	filters.add_child(_seg(items, lb_seg_btns, func(k):
		lb_diff = k
		render()
		render_lb()
		maybe_play_rank_anim(), false, 13))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	filters.add_child(sp)
	lb_period_box = _seg([["all", "전체"], ["week", "이번 주"]], lb_period_btns, func(k):
		lb_period = k
		render_lb()
		maybe_play_rank_anim(), false, 13)
	lb_period_box.visible = lb_enabled
	filters.add_child(lb_period_box)
	box.add_child(filters)
	var note := _label("주어진 사과(쉬움 3개 · 보통 4개 · 어려움 5개)로 몇 레벨까지 가는지 겨뤄요. 클리어한 레벨이 많을수록, 같으면 누적 시간이 짧을수록 위에 올라가요. 난이도마다 각자 최고 기록 하나만 남아요." +
		(" 이번 주 순위는 매주 월요일 0시(한국 시간)에 새로 시작해요." if lb_enabled else ""), 12, MUTED)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.custom_minimum_size.x = 100
	box.add_child(note)
	# table
	lb_head_row = _row_controls({"pos": "순위", "name": "닉네임", "levels": "레벨", "time": "누적 시간"}, true)
	lb_head_row.custom_minimum_size.y = 26
	box.add_child(lb_head_row)
	lb_scroll = ScrollContainer.new()
	lb_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lb_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lb_scroll.custom_minimum_size.y = 160
	var lw := VBoxContainer.new()
	lw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_scroll.add_child(lw)
	lb_list = Control.new()
	lb_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lb_list.resized.connect(func():
		for r in lb_list.get_children():
			if r is Control:
				r.size.x = lb_list.size.x)
	lw.add_child(lb_list)
	lb_empty = _para("리더보드를 불러오는 중…", 14)
	lw.add_child(lb_empty)
	box.add_child(lb_scroll)
	lb_status = _label("", 12, MUTED)
	lb_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lb_status.custom_minimum_size.x = 100
	box.add_child(lb_status)
	lb_modal = _modal(lb_panel, close_lb)


## One table row: rank · avatar + name · levels · time. `head` makes the header row.
func _row_controls(r: Dictionary, head := false) -> Control:
	var row := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0, 0, 0, 0)
	s.border_color = GRIDC
	s.border_width_bottom = 1
	s.content_margin_left = 6
	s.content_margin_right = 6
	row.add_theme_stylebox_override("panel", s)
	row.set_meta("style", s)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)
	var sz := 12 if head else 17
	var rank := _label(str(r.pos), sz, MUTED if head else INK, not head, not head)
	rank.custom_minimum_size.x = 40
	rank.name = "Rank"
	if not head and int(r.pos) <= 3:
		rank.add_theme_color_override("font_color", [GOLD, SILVER, BRONZE][int(r.pos) - 1])
	h.add_child(rank)
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not head:
		var av := TextureRect.new()
		av.custom_minimum_size = Vector2(22, 22)
		av.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		av.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		av.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		av.texture = avatar_tex.get(r.avatar if r.avatar != "" else "🦔")
		av.modulate.a = 1.0 if r.avatar != "" else 0.3
		who.add_child(av)
	var nm := _label(r.name, 12 if head else 15, MUTED if head else INK, not head)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.clip_text = true
	nm.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	nm.custom_minimum_size.x = 40
	who.add_child(nm)
	h.add_child(who)
	var lv := _label(str(r.levels), sz, MUTED if head else INK, not head)
	lv.custom_minimum_size.x = 48
	lv.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	lv.name = "Levels"
	h.add_child(lv)
	var tm := _label(r.time if head else fmt(r.timeMs), 12 if head else 15, MUTED if head else INK)
	tm.custom_minimum_size.x = 72
	tm.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	tm.name = "Time"
	h.add_child(tm)
	for c in [rank, lv, tm]:
		c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return row


func _fill_table(lst: Array) -> Dictionary:
	for c in lb_list.get_children():
		c.queue_free()
	var rows := {}
	var y := 0.0
	var me := me_id()
	for r in lst:
		var ctl: Control
		if r == null:
			ctl = _label("⋯", 15, MUTED, false, true)
			ctl.custom_minimum_size.y = 22
			ctl.size = Vector2(lb_list.size.x, 22)
			ctl.position = Vector2(0, y)
			lb_list.add_child(ctl)
			y += 22
			continue
		var is_me: bool = r.id == me
		var row_r: Dictionary = r.duplicate()
		if is_me:
			row_r.name = str(r.name if r.name != "" else "이름 없는 고슴도치") + " (나)"
		elif row_r.name == "":
			row_r.name = "이름 없는 고슴도치"
		ctl = _row_controls(row_r)
		if is_me:
			(ctl.get_meta("style") as StyleBoxFlat).bg_color = ACCENT_SOFT
		ctl.position = Vector2(0, y)
		ctl.size = Vector2(lb_list.size.x, ROW_H)
		ctl.custom_minimum_size.y = ROW_H
		lb_list.add_child(ctl)
		rows[r.id] = ctl
		y += ROW_H
	lb_list.custom_minimum_size.y = y
	lb_head_row.visible = not lst.is_empty()
	return rows


func open_lb() -> void:
	var show_result: bool = mode == "run" and run != null and run.get("finished", false)
	if show_result:
		lb_diff = run.diff
	_layout_modals()
	lb_modal.visible = true
	render()
	render_result()
	render_lb()
	if lb_enabled and Time.get_ticks_msec() - lb_loaded_at > 15000 and hold == null:
		refresh_lb()
	maybe_play_rank_anim()


func close_lb() -> void:
	lb_modal.visible = false


func render_result() -> void:
	var r = run
	var finished: bool = mode == "run" and r != null and r.get("finished", false)
	lb_result.visible = finished
	if not finished:
		return
	var d = _diff_of(r.diff)
	# rebuild for each finished run, so a previous run's rank headline never carries over
	var key := "%d:%s:%d:%d" % [int(r.seed), r.diff, int(r.cleared), int(r.totalMs)]
	if res_key != key:
		res_key = key
		rank_from.text = ""
		rank_to.text = ""
		rank_tag.text = ""
		rank_from.visible = false
		rank_arrow.visible = false
	res_head.text = "이번 도전 · %s %d×%d" % [d.label, d.n, d.n]
	res_stats.text = "%d레벨 클리어 · %s" % [int(r.cleared), fmt(r.totalMs)]
	_render_save_area()
	rank_move.visible = rank_to.text != "" or rank_tag.text != ""


func _render_save_area() -> void:
	for c in save_area.get_children():
		c.queue_free()
	var res = last_result
	if res == null:
		return
	var p := _para(str(res.msg), 14, ACCENT if res.get("ok", false) else MUTED)
	save_area.add_child(p)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	if res.get("needNick", false):
		row.add_child(_button("내 프로필 열기", "", func(): open_profile(true)))
	elif res.get("retry", false):
		row.add_child(_button("다시 시도", "", try_submit))
	elif res.get("autoNamed", false):
		row.add_child(_button("프로필 꾸미기", "", func(): open_profile()))
	if row.get_child_count() > 0:
		save_area.add_child(row)


func _mark_period() -> void:
	_seg_set(lb_period_btns, lb_period)


func render_lb() -> void:
	if lb_list == null:
		return
	_seg_set(lb_seg_btns, lb_diff)
	_mark_period()
	lb_status.text = "" if lb_enabled else "이 버전에서는 온라인 리더보드에 올릴 수 없어서 이 기기의 기록만 보여요."
	var held = null
	if hold != null and hold.diff == lb_diff:
		held = hold.entries.get(lb_period)
	var ent = held if held != null else entries_for(lb_diff)
	if ent == null:
		_fill_table([])
		lb_empty.visible = true
		lb_empty.text = "리더보드를 불러오지 못했어요." if lb_state == "error" else "리더보드를 불러오는 중…"
		if lb_state != "error":
			refresh_lb(lb_diff)
		return
	if ent.list.is_empty():
		_fill_table([])
		lb_empty.visible = true
		lb_empty.text = "이번 주 기록이 아직 없어요. 이번 주 첫 주인공이 되어 보세요!" if lb_enabled and lb_period == "week" else "아직 기록이 없어요. 첫 기록의 주인공이 되어 보세요."
		return
	lb_empty.visible = false
	_fill_table(ent.list)


func maybe_play_rank_anim() -> void:
	var a = pending_anim
	if a == null or not lb_modal.visible or lb_diff != a.diff or (lb_enabled and lb_period != a.period):
		return
	pending_anim = null
	hold = null
	_play_rank_anim(a)


func _count_to(lbl: Label, from: float, to: float, dur: float, show: Callable) -> void:
	lbl.text = show.call(int(from))
	var tw := create_tween()
	tw.tween_method(func(v: float): lbl.text = show.call(int(round(v))), from, to, dur).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _play_rank_anim(a: Dictionary) -> void:
	var before: Dictionary = a.before
	var after: Dictionary = a.after
	var status: String = a.status
	var pre := "이번 주 " if lb_enabled and a.period == "week" else ""
	var old_rank := int(before.myRank)
	var new_rank := int(after.myRank)
	const DELAY := 0.35
	const MOVE := 1.1
	rank_from.visible = false
	rank_arrow.visible = false
	if status == "not_better":
		rank_to.text = "이번 기록 %d위" % int(a.get("runRank", 0)) if int(a.get("runRank", 0)) > 0 else ""
		rank_tag.text = "내 최고 기록은 %d위 그대로예요" % new_rank if new_rank > 0 else ""
	elif old_rank == 0:
		rank_tag.text = "이 기기 기록 순위" if status == "local" else pre + "첫 등록"
		var last_pos := new_rank
		for e in after.list:
			if e != null:
				last_pos = int(e.pos)
		if new_rank > 0:
			_count_to(rank_to, maxi(new_rank + 9, last_pos + 1), new_rank, MOVE + DELAY, func(v): return "%d위" % v)
		else:
			rank_to.text = ""
	else:
		rank_from.visible = true
		rank_arrow.visible = true
		rank_from.text = "%d위" % old_rank
		rank_tag.text = (pre + "%d계단 올라갔어요" % (old_rank - new_rank)) if new_rank < old_rank else (pre + "순위 유지 · 최고 기록 갱신" if new_rank == old_rank else "")
		_count_to(rank_to, old_rank, new_rank, MOVE + DELAY, func(v): return "%d위" % v)
	rank_move.visible = rank_to.text != "" or rank_tag.text != ""
	if after.list.is_empty():
		render_lb()
		return
	# old positions, then the new table with rows sliding from where they were
	var me := me_id()
	var old_y := {}
	var y := 0.0
	var old_mine = null
	for e in before.list:
		if e == null:
			y += 22
			continue
		old_y[e.id] = y
		if e.id == me:
			old_mine = e
		y += ROW_H
	var old_h := y
	lb_empty.visible = false
	var rows := _fill_table(after.list)
	await get_tree().process_frame
	var new_mine = null
	for e in after.list:
		if e != null and e.id == me:
			new_mine = e
	for id in rows:
		var row: Control = rows[id]
		var top := row.position.y
		var is_me: bool = id == me
		var from = old_y.get(id, (old_h + 24) if is_me else null)
		if from == null:
			row.modulate.a = 0
			var tw := create_tween()
			tw.tween_interval(DELAY + MOVE * 0.5)
			tw.tween_property(row, "modulate:a", 1.0, 0.5)
			continue
		if from == top and not is_me:
			continue
		row.position.y = from
		var tw := create_tween()
		tw.tween_interval(DELAY)
		tw.tween_property(row, "position:y", top, MOVE if is_me else MOVE * 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	if rows.has(me):
		var my_row: Control = rows[me]
		var st: StyleBoxFlat = my_row.get_meta("style")
		st.bg_color = Color(RING, 0.55)
		var tw := create_tween()
		tw.tween_interval(0.5)
		tw.tween_property(st, "bg_color", ACCENT_SOFT, 1.3)
		lb_scroll.scroll_vertical = int(maxf(0, my_row.position.y - lb_scroll.size.y / 2 + ROW_H / 2))
		if old_mine != null and new_mine != null:
			var h: HBoxContainer = my_row.get_child(0)
			_count_to(h.get_node("Rank"), int(old_mine.pos), int(new_mine.pos), MOVE + DELAY, func(v): return str(v))
			if int(old_mine.levels) != int(new_mine.levels):
				_count_to(h.get_node("Levels"), int(old_mine.levels), int(new_mine.levels), MOVE + DELAY, func(v): return str(v))
			if int(old_mine.timeMs) != int(new_mine.timeMs):
				_count_to(h.get_node("Time"), int(old_mine.timeMs), int(new_mine.timeMs), MOVE + DELAY, func(v): return fmt(v))
