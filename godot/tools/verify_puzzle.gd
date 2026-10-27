extends SceneTree
## godot --headless --path . -s tools/verify_puzzle.gd  → prints boards to compare with the web version

func _init() -> void:
	for key in ["normal:1", "hard:3", "expert:2", "run:12345:1"]:
		var n := 11 if key.begins_with("expert") else 9 if key.begins_with("hard") else 7
		var t := Time.get_ticks_msec()
		var p := Puzzle.for_key(key, n)
		print(key, " reg=", ",".join(Array(p.reg).map(func(x): return str(x))), " sol=", ",".join(Array(p.sol).map(func(x): return str(x))), " colors=", ",".join(Array(p.colors).map(func(x): return str(x))), " ms=", Time.get_ticks_msec() - t)
	quit()
