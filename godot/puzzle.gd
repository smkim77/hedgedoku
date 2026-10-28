class_name Puzzle
extends RefCounted
## Puzzle generation, ported line by line from the web version (index.html) so the same key gives the same board:
## a random queen-style permutation with no diagonal neighbours, regions grown around it, then regions nudged
## until the solver finds exactly one solution. JS 32-bit integer maths is emulated with masks.
## `prepare()` makes a puzzle a few milliseconds per frame (the web build has no threads), so the next level
## can be ready before it is needed without the game stuttering.

const M32 := 0xFFFFFFFF
const HUES := 10
const NEUTRAL := 10

var N: int
var reg: PackedInt32Array      # region of each cell
var sol: PackedInt32Array      # sol[row] = column of that row's hedgehog
var colors: PackedInt32Array   # palette index (0..10) of each region


## Spreads work over frames: after `budget_us` of work, wait for the next frame.
class Pacer:
	var tree: SceneTree
	var budget_us: int
	var t0: int

	func _init(t: SceneTree, us: int) -> void:
		tree = t
		budget_us = us
		t0 = Time.get_ticks_usec()

	func due() -> bool:
		return Time.get_ticks_usec() - t0 > budget_us

	func wait() -> void:
		await tree.process_frame
		t0 = Time.get_ticks_usec()


# ---------- JS integer helpers ----------

static func imul(a: int, b: int) -> int:
	a &= M32
	b &= M32
	var al := a & 0xFFFF
	var ah := (a >> 16) & 0xFFFF
	var bl := b & 0xFFFF
	var bh := (b >> 16) & 0xFFFF
	return ((((ah * bl + al * bh) & 0xFFFF) << 16) + al * bl) & M32


static func hash_str(s: String) -> int:
	var h := 2166136261
	for k in s.length():
		h = (h ^ s.unicode_at(k)) & M32
		h = imul(h, 16777619)
	return h


class Rng:
	var a: int

	func _init(seed: int) -> void:
		a = seed & 0xFFFFFFFF

	func next() -> float:
		a = (a + 0x6D2B79F5) & 0xFFFFFFFF
		var t := Puzzle.imul(a ^ (a >> 15), 1 | a)
		t = ((t + Puzzle.imul(t ^ (t >> 7), 61 | t)) & 0xFFFFFFFF) ^ t
		return float((t ^ (t >> 14)) & 0xFFFFFFFF) / 4294967296.0

	func below(n: int) -> int:
		return int(floor(next() * n))


static func shuffle(arr: Array, rng: Rng) -> Array:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.below(i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
	return arr


static func _keys(n: int) -> Array:
	var out := []
	for k in n:
		out.append(k)
	return out


static func nbrs4(i: int, n: int) -> Array:
	var r := i / n
	var c := i % n
	var out := []
	if r > 0: out.append(i - n)
	if r < n - 1: out.append(i + n)
	if c > 0: out.append(i - 1)
	if c < n - 1: out.append(i + 1)
	return out


# ---------- generation ----------

static func _perm_rec(row: int, n: int, perm: Array, used: Array, rng: Rng) -> bool:
	if row == n:
		return true
	for c in shuffle(_keys(n), rng):
		if used[c] or (row > 0 and absi(perm[row - 1] - c) <= 1):
			continue
		used[c] = true
		perm[row] = c
		if _perm_rec(row + 1, n, perm, used, rng):
			return true
		used[c] = false
	return false


static func random_perm(n: int, rng: Rng) -> Array:
	var perm := []
	perm.resize(n)
	var used := []
	used.resize(n)
	used.fill(false)
	return perm if _perm_rec(0, n, perm, used, rng) else []


static func grow_regions(n: int, perm: Array, rng: Rng, pacer: Pacer = null) -> Array:
	var r := []
	r.resize(n * n)
	r.fill(-1)
	for row in n:
		r[row * n + perm[row]] = row
	var left := n * n - n
	while left > 0:
		if pacer != null and pacer.due():
			await pacer.wait()
		var frontier := []
		for i in n * n:
			if r[i] < 0:
				for j in nbrs4(i, n):
					if r[j] >= 0:
						frontier.append(i)
						break
		var f: int = frontier[rng.below(frontier.size())]
		var opts := []
		for j in nbrs4(f, n):
			if r[j] >= 0:
				opts.append(r[j])
		r[f] = opts[rng.below(opts.size())]
		left -= 1
	return r


## Finds up to `limit` solutions; always branches on the region with the fewest open cells.
class Solver:
	var n: int
	var cells_of: Array
	var blocked: PackedInt32Array
	var used: Array
	var cur: Array
	var out: Array
	var limit: int
	var pacer: Pacer
	var steps := 0

	func _init(r: Array, size: int, lim: int, p: Pacer) -> void:
		n = size
		limit = lim
		pacer = p
		cells_of = []
		for g in n:
			cells_of.append([])
		for i in n * n:
			cells_of[r[i]].append(i)
		blocked = PackedInt32Array()
		blocked.resize(n * n)
		used = []
		used.resize(n)
		used.fill(false)
		cur = []
		cur.resize(n)
		cur.fill(-1)
		out = []

	func mark(i: int, d: int) -> void:
		var r := i / n
		var c := i % n
		for k in n:
			blocked[r * n + k] += d
			blocked[k * n + c] += d
		for dr in [-1, 1]:
			for dc in [-1, 1]:
				var rr: int = r + dr
				var cc: int = c + dc
				if rr >= 0 and rr < n and cc >= 0 and cc < n:
					blocked[rr * n + cc] += d

	func rec(placed: int) -> void:
		if pacer != null:
			steps += 1
			if steps & 63 == 0 and pacer.due():
				await pacer.wait()
		if placed == n:
			out.append(cur.duplicate())
			return
		var best := -1
		var best_count := 1 << 30
		for g in n:
			if used[g]:
				continue
			var cnt := 0
			for i in cells_of[g]:
				if blocked[i] == 0:
					cnt += 1
			if cnt < best_count:
				best_count = cnt
				best = g
				if cnt == 0:
					return
		used[best] = true
		for i in cells_of[best]:
			if blocked[i] != 0:
				continue
			cur[i / n] = i % n
			mark(i, 1)
			await rec(placed + 1)
			mark(i, -1)
			if out.size() >= limit:
				break
		used[best] = false


static func solve(r: Array, n: int, limit: int, pacer: Pacer = null) -> Array:
	var s := Solver.new(r, n, limit, pacer)
	await s.rec(0)
	return s.out


static func connected(r: Array, g: int, n: int) -> bool:
	var cells := []
	for i in n * n:
		if r[i] == g:
			cells.append(i)
	if cells.is_empty():
		return false
	var seen := {cells[0]: true}
	var stack := [cells[0]]
	while not stack.is_empty():
		var i: int = stack.pop_back()
		for j in nbrs4(i, n):
			if r[j] == g and not seen.has(j):
				seen[j] = true
				stack.append(j)
	return seen.size() == cells.size()


## Break an alternate solution by moving one of its hedgehog cells into a neighbouring region.
static func break_alt(r: Array, alt: Array, perm: Array, n: int, rng: Rng) -> bool:
	var cands := []
	for row in n:
		if alt[row] != perm[row]:
			cands.append(row * n + alt[row])
	shuffle(cands, rng)
	for i in cands:
		var a: int = r[i]
		var bs := []
		for j in nbrs4(i, n):
			if r[j] != a and not bs.has(r[j]):
				bs.append(r[j])
		for b in shuffle(bs, rng):
			r[i] = b
			if connected(r, a, n):
				return true
			r[i] = a
	return false


static func hue_dist(a: int, b: int) -> float:
	if a == NEUTRAL or b == NEUTRAL:
		return 2.5
	return float(mini(absi(a - b), HUES - absi(a - b)))


## Touching regions (including corner contact) get colours as far apart on the hue ring as possible.
static func assign_colors(r: Array, n: int, rng: Rng, pacer: Pacer = null) -> Array:
	var adj := []
	for g in n:
		adj.append({})
	for i in n * n:
		var row := i / n
		var c := i % n
		for dr in [-1, 0, 1]:
			for dc in [-1, 0, 1]:
				var rr: int = row + dr
				var cc: int = c + dc
				if rr < 0 or rr >= n or cc < 0 or cc >= n:
					continue
				var g: int = r[rr * n + cc]
				if g != r[i]:
					adj[r[i]][g] = true
	# stable sort by neighbour count, descending (JS Array.sort is stable)
	var order := shuffle(_keys(n), rng)
	for k in range(1, order.size()):
		var v = order[k]
		var j := k - 1
		while j >= 0 and adj[order[j]].size() < adj[v].size():
			order[j + 1] = order[j]
			j -= 1
		order[j + 1] = v
	var colors := []
	colors.resize(n)
	colors.fill(-1)
	var free := shuffle(_keys(HUES + 1), rng)
	for g in order:
		var best := -1
		var best_score := -1.0
		for c in free:
			var score := INF
			for h in adj[g]:
				if colors[h] >= 0:
					score = minf(score, hue_dist(c, colors[h]))
			if score > best_score:
				best_score = score
				best = c
		colors[g] = best
		free.erase(best)
	var quality := func() -> float:
		var mn := INF
		var sum := 0.0
		for g in n:
			for h in adj[g]:
				if h > g:
					var d := hue_dist(colors[g], colors[h])
					mn = minf(mn, d)
					sum += d
		return mn * 1000.0 + sum
	var q: float = quality.call()
	var improved := true
	var pass_n := 0
	while improved and pass_n < 20:
		improved = false
		for g in n:
			if pacer != null and pacer.due():
				await pacer.wait()
			for h in range(g + 1, n):
				var t = colors[g]
				colors[g] = colors[h]
				colors[h] = t
				var nq: float = quality.call()
				if nq > q:
					q = nq
					improved = true
				else:
					t = colors[g]
					colors[g] = colors[h]
					colors[h] = t
			for k in free.size():
				var old = colors[g]
				colors[g] = free[k]
				var nq: float = quality.call()
				if nq > q:
					q = nq
					improved = true
					free[k] = old
				else:
					colors[g] = old
		pass_n += 1
	return colors


## A coroutine; it only waits between frames when given a pacer (see for_key / prepare).
static func generate(n: int, seed: int, pacer: Pacer = null) -> Puzzle:
	var rng := Rng.new(seed)
	for attempt in 300:
		if pacer != null and pacer.due():
			await pacer.wait()
		var perm := random_perm(n, rng)
		if perm.is_empty():
			continue
		var r: Array = await grow_regions(n, perm, rng, pacer)
		for it in 400:
			if pacer != null and pacer.due():
				await pacer.wait()
			var sols: Array = await solve(r, n, 2, pacer)
			if sols.size() == 1:
				var p := Puzzle.new()
				p.N = n
				p.reg = PackedInt32Array(r)
				p.sol = PackedInt32Array(perm)
				p.colors = PackedInt32Array(await assign_colors(r, n, rng, pacer))
				return p
			var alt: Array = []
			for s in sols:
				for row in n:
					if s[row] != perm[row]:
						alt = s
						break
				if not alt.is_empty():
					break
			if not break_alt(r, alt, perm, n, rng):
				break
	push_error("puzzle generation failed")
	return null


static var _cache := {}
static var _preparing := {}


## The puzzle for `key`, made right away if it isn't ready yet.
static func for_key(key: String, n: int) -> Puzzle:
	if not _cache.has(key):
		# called dynamically: without a pacer the coroutine never waits, so it returns the puzzle directly
		_cache[key] = Puzzle.generate.call(n, hash_str("hedgedoku:" + key), null)
	return _cache[key]


## Make the puzzle for `key` in the background (about 6 ms per frame), so for_key() finds it ready later.
## Fire and forget: `Puzzle.prepare.call(key, n, get_tree())`.
static func prepare(key: String, n: int, tree: SceneTree) -> void:
	if _cache.has(key) or _preparing.has(key):
		return
	_preparing[key] = true
	var p: Puzzle = await generate(n, hash_str("hedgedoku:" + key), Pacer.new(tree, 6000))
	_preparing.erase(key)
	if not _cache.has(key) and p != null:
		_cache[key] = p
