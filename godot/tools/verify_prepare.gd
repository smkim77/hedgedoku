extends SceneTree
## godot --headless --path . -s tools/verify_prepare.gd → background (frame-sliced) puzzles match the direct ones

func _init() -> void:
	var keys := {"expert:9": 11}
	var frames := 0
	var worst := 0
	for key in keys:
		Puzzle.prepare.call(key, keys[key], self)
	await process_frame   # skip start-up
	var last := Time.get_ticks_usec()
	var spikes := []
	while true:
		await process_frame
		var t := Time.get_ticks_usec()
		worst = maxi(worst, t - last)
		if t - last > 30000:
			spikes.append([frames, (t - last) / 1000])
		last = t
		frames += 1
		var done := true
		for key in keys:
			if not Puzzle._cache.has(key):
				done = false
		if done or frames > 5000:
			break
	var ok := true
	for key in keys:
		var a: Puzzle = Puzzle._cache[key]
		var b: Puzzle = Puzzle.generate.call(keys[key], Puzzle.hash_str("hedgedoku:" + key), null)
		var same := a.reg == b.reg and a.sol == b.sol and a.colors == b.colors
		ok = ok and same
		print(key, " same=", same)
	print("spikes=", spikes)
	print("frames=", frames, " worst_frame_ms=", worst / 1000.0, " all_same=", ok)
	quit()
