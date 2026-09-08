extends SceneTree
## Headless measurements from the same finite-difference solver used by the table.
## godot --headless --path . --script research/capture.gd -- --output=research/raw.json

const Solver = preload("res://scripts/wave_solver.gd")
const Parts = preload("res://scripts/experiments.gd")
const PERIOD := 32
const MEMORY_SYMBOLS := 128
const W := 64
const H := 48

func source(x: float, y: float) -> Dictionary:
	var s := Parts.component("source", x, y, 0, 0)
	s.band = 1
	s.wavelength = PERIOD * Solver.SPEED / Solver.BASE_WAVELENGTHS.y
	return s

func fresh(components: Array):
	var model = Solver.new(W, H)
	model.configure(components)
	for i in range(model.sources.size()):
		model.set_source_amplitude(i, 0.0)
	# Advance through the UI source's startup ramp with no forcing. Field stays zero.
	model.step(PERIOD * 2)
	return model

func sample(model, probes: Array) -> Array:
	var values: Array = []
	for p in probes:
		values.append(model.field[(int(p[1]) * W + int(p[0])) * 3 + 1])
	return values

func matrix_experiment() -> Dictionary:
	var slab := Parts.component("glass", 32, 24, 25, 24)
	slab.index = 1.35
	var layout := [source(16, 18), source(16, 30), slab]
	var probes := [[42, 15], [46, 24], [42, 34]]
	var vectors := [[1.0, 0.0], [0.0, 1.0], [0.7, -0.4], [-0.2, 0.9], [1.0, 1.0]]
	var runs: Array = []
	for vector in vectors:
		var model = fresh(layout)
		for i in range(2):
			model.set_source_amplitude(i, vector[i])
		model.step(PERIOD * 8)
		var rows: Array = []
		for t in range(PERIOD * 8):
			model.step()
			rows.append(sample(model, probes))
		runs.append({"input": vector, "field": rows})
	print("Measured two basis inputs and three independent simultaneous-input runs.")
	return {"components": layout, "probes": probes, "runs": runs,
		"first_sample_tick": PERIOD * 10 + 1, "sample_count": PERIOD * 8}

func reservoir_experiment(with_mirrors: bool) -> Dictionary:
	var layout := [source(16, 24)]
	if with_mirrors:
		# An open cavity: light can escape through the left side and the sponge.
		layout.append(Parts.component("mirror", 39, 11, 90, 28))
		layout.append(Parts.component("mirror", 53, 24, 0, 26))
		layout.append(Parts.component("mirror", 39, 37, 90, 28))
	var probes: Array = []
	for y in [15, 21, 27, 33]:
		for x in [21, 27, 33, 39, 45, 49]:
			probes.append([x, y])
	var model = fresh(layout)
	var impulse: Array = []
	for symbol in range(MEMORY_SYMBOLS):
		model.set_source_amplitude(0, 1.0 if symbol == 0 else 0.0)
		var rows: Array = []
		for t in range(PERIOD):
			model.step()
			rows.append(sample(model, probes))
		impulse.append(rows)
	# A fresh direct run checks convolution against native stepping, including history.
	var rng := RandomNumberGenerator.new()
	rng.seed = 913
	var bits: Array = []
	var direct: Array = []
	model = fresh(layout)
	for symbol in range(192):
		var bit := rng.randi_range(0, 1)
		bits.append(bit)
		model.set_source_amplitude(0, float(bit))
		var rows: Array = []
		for t in range(PERIOD):
			model.step()
			rows.append(sample(model, probes))
		direct.append(rows)
	print("Captured ", "open cavity" if with_mirrors else "empty table", " impulse response and direct bit-stream check.")
	return {"components": layout, "probes": probes, "impulse_field": impulse,
		"direct_bits": bits, "direct_field": direct}

func _initialize() -> void:
	var output := "res://research/raw.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--output="):
			output = arg.trim_prefix("--output=")
	var data := {"schema_version": 1, "model": "scalar-wave-v1", "grid": [W, H],
		"godot_version": Engine.get_version_info().string, "period_steps": PERIOD,
		"memory_symbols": MEMORY_SYMBOLS,
		"matrix": matrix_experiment(),
		"reservoirs": {"empty": reservoir_experiment(false), "cavity": reservoir_experiment(true)}}
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write measurements: " + output)
		quit(1)
		return
	file.store_string(JSON.stringify(data))
	file.close()
	print("RESEARCH CAPTURE PASS: ", ProjectSettings.globalize_path(output))
	quit()
