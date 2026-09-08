extends SceneTree
const Study = preload("res://scripts/pulse_study.gd")
const Model = preload("res://scripts/pulse_model.gd")

func _initialize() -> void:
	var quick := "--quick" in OS.get_cmdline_user_args()
	var output := "res://research/results/pulse-study.json"
	var task := 0
	for arg in OS.get_cmdline_user_args():
		if arg == "--xor":
			task = 1
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	var runs: Array = []
	for seed_value in ([42] if quick else [42, 101, 2026]):
		var settings := Model.defaults()
		settings.seed = seed_value
		settings.task = task
		var study := Study.new()
		study.begin(settings, [40, 20, 40] if quick else [160, 80, 160])
		var start := Time.get_ticks_msec()
		while not study.done:
			study.advance(10)
		if not study.error.is_empty():
			push_error(study.error)
			quit(1)
			return
		var result := study.snapshot()
		# Keep predictions, weights, parameters and exact input times. Full feature
		# matrices can be exported from the UI; omit them in this compact report.
		for split in result.datasets:
			split.erase("features")
		runs.append(result)
		print("Seed ", seed_value, " (", (Time.get_ticks_msec() - start) / 1000.0, "s)")
		for name in Study.NAMES:
			print("  ", name, ": ", snapped(study.results[name].test_accuracy * 100, 0.1), "% / ", study.results[name].feature_count, " features")
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write " + output)
		quit(1)
		return
	file.store_string(JSON.stringify({"godot": Engine.get_version_info().string, "quick": quick, "runs": runs}, "  "))
	file.close()
	print("PULSE STUDY PASS: ", output)
	quit()
