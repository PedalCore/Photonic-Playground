extends SceneTree
const Model = preload("res://scripts/pulse_model.gd")
const Study = preload("res://scripts/pulse_study.gd")
const Readout = preload("res://scripts/pulse_readout.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		push_error("FAIL: " + message)
		failures += 1

func _initialize() -> void:
	var half := Model.pair_response(0.5)
	var whole := Model.pair_response(1.0)
	check(half.events.resonator.size() == 0 and whole.events.resonator.size() == 1, "resonator distinguishes half-period and full-period pulse gaps")
	check(half.events.integrator.size() == 1 and whole.events.integrator.size() == 1, "matched leaky integrator fires on both pulse pairs")
	check(Model.pair_response(1.0, 1.8, 1.4, false).events.resonator.is_empty(), "free-response mode disables threshold and reset")
	var model := Model.new()
	model.reset([])
	for i in range(40):
		model.step()
	check(model.field_at(Model.SOURCE) == Vector2.ZERO and model.spikes.is_empty(), "unforced resting cavity remains at rest")
	model.inject(model.source_weights)
	for i in range(40):
		model.step()
	var norm := 0.0
	for mode in model.modes:
		norm += mode.length_squared()
	check(absf(norm - exp(-2.0 / model.config.tau)) < 1e-6, "modal norm follows analytic passive energy decay")
	var boundary := 0.0
	for i in range(21):
		for point in [Vector2(i / 20.0, 0), Vector2(i / 20.0, 1), Vector2(0, i / 20.0), Vector2(1, i / 20.0)]:
			boundary = maxf(boundary, model.field_at(point).length())
	check(boundary < 1e-7, "analytic field has zero boundary on all four cavity walls")
	var passive := Model.new({"feedback": 0.0}, false)
	var active := Model.new({"feedback": 0.0}, true)
	var features := Study.capture_features(passive, active, [0.4, 1.4, 3.4, 6.4])
	check(features["Passive: power history"] == features["Feedback: power history"] and passive.spikes == active.spikes, "zero feedback exactly reproduces passive field and spikes")
	var last := [-100.0, -100.0, -100.0, -100.0, -100.0, -100.0]
	var recovered := true
	for spike in passive.spikes:
		if spike[0] - last[spike[1]] < passive.config.refractory - 1e-7:
			recovered = false
		last[spike[1]] = spike[0]
	check(recovered and not passive.spikes.is_empty(), "each node respects its refractory interval")
	model.reset([0.401])
	for i in range(16):
		model.step()
	check(model.next_pulse == 0, "off-grid input does not fire early")
	model.step()
	check(model.next_pulse == 1 and is_equal_approx(model.time, 0.425), "input fires at the next fixed time boundary")
	var fit := Readout.new()
	fit.fit([[-2.0, 1.0, 4.0], [-1.0, -1.0, 4.0], [1.0, -1.0, 4.0], [2.0, 1.0, 4.0]], [-6.0, 7.0, 13.0, 6.0], 0.000001)
	# Target = 5 + 3*x - 5*y; includes a constant feature.
	check(absf(fit.predict([0.5, 0.2, 4.0]) - 5.5) < 0.0001, "native ridge readout generalizes a known affine function with a constant column")
	var restored: Dictionary = JSON.parse_string(JSON.stringify(fit.snapshot()))
	var score: float = restored.bias
	for j in range(3):
		score += restored.weights[j] * ([0.5, 0.2, 4.0][j] - restored.mean[j]) / restored.scale[j]
	check(absf(score - fit.predict([0.5, 0.2, 4.0])) < 1e-9, "exported weights and scaling reproduce predictions")
	var study := Study.new()
	study.begin({}, [40, 20, 40])
	var matched := true
	for data in study.datasets:
		for i in range(0, data.sequences.size(), 2):
			var a: Array = data.sequences[i]
			var b: Array = data.sequences[i + 1]
			for j in range(3):
				matched = matched and absf((a[j + 1] - a[j]) - (b[3 - j] - b[2 - j])) < 1e-7
	check(matched, "opposite-order examples preserve exact interval multisets and duration")
	check(study.datasets[0].sequences[0] != study.datasets[2].sequences[0], "train and test use different jitter draws")
	while not study.done:
		study.advance(10)
	check(study.error.is_empty() and study.results["Input count"].test_accuracy == 0.5, "count-only control remains at chance on balanced data")
	check(study.results["Full timing (linear)"].test_accuracy > 0.9, "full input timing solves order without a cavity")
	study.begin({"task": 1}, [40, 20, 40])
	while not study.done:
		study.advance(10)
	check(study.results["Full timing (linear)"].test_accuracy == 0.5 and study.results["Timing + products"].test_accuracy > 0.9, "timing XOR needs interactions; digital product control solves it")
	study.begin({})
	study.cancelled = true
	study.advance(10)
	check(study.sample_index == 0 and study.results.is_empty(), "cancellation prevents further collection or fitting")
	if failures == 0:
		print("PULSE NUMERICAL PASS")
	quit(0 if failures == 0 else 1)
