class_name PulseStudy
extends RefCounted
## Incremental deterministic benchmark; advance() keeps the native UI responsive.

const Model = preload("res://scripts/pulse_model.gd")
const Readout = preload("res://scripts/pulse_readout.gd")
const NAMES := ["Input count", "Full timing (linear)", "Timing + products", "Leaky state", "LIF spike timing",
	"Passive: final power", "Passive: power history", "Passive: spike history",
	"Feedback: power history", "Feedback: spike history"]
var config: Dictionary
var counts: Array = [160, 80, 160]
var datasets: Array = []
var split_index := 0
var sample_index := 0
var fit_index := 0
var done := false
var cancelled := false
var error := ""
var results: Dictionary = {}
var predictors: Dictionary = {}
var passive_model: PulseModel
var active_model: PulseModel

static func sequence(label: int, jitter: float, rng: RandomNumberGenerator) -> Array:
	var gaps: Array = []
	var total := 0.0
	for base in [1.0, 2.0, 3.0]:
		var gap: float = base * (1.0 + rng.randf_range(-jitter, jitter))
		gaps.append(gap)
		total += gap
	for i in range(3):
		gaps[i] *= 6.0 / total
	if label == 1:
		gaps.reverse()
	return [0.4, 0.4 + gaps[0], 0.4 + gaps[0] + gaps[1], 6.4]

func begin(settings: Dictionary, sizes: Array = [160, 80, 160]) -> void:
	config = Model.defaults()
	config.merge(settings, true)
	counts = sizes.duplicate()
	datasets.clear()
	predictors.clear()
	results.clear()
	split_index = 0
	sample_index = 0
	fit_index = 0
	done = false
	cancelled = false
	error = ""
	passive_model = Model.new(config, false)
	active_model = Model.new(config, true)
	for split in range(3):
		var rng := RandomNumberGenerator.new()
		rng.seed = int(config.seed) + [0, 104729, 209759][split]
		var sequences: Array = []
		var labels: Array = []
		# Each matched pair has exactly the same jittered intervals, reversed.
		# Thus count, total duration and interval multiset cannot reveal its class.
		if int(config.task) == 0:
			for pair in range(int(counts[split]) / 2):
				var forward := sequence(0, config.jitter, rng)
				var reverse := [0.4, 6.8 - forward[2], 6.8 - forward[1], 6.4]
				sequences.append(forward)
				sequences.append(reverse)
				labels.append(0.0)
				labels.append(1.0)
		else:
			for group in range(int(counts[split]) / 4):
				var first: Array = []
				var last: Array = []
				for base in [0.8, 1.6]:
					first.append(base * (1.0 + rng.randf_range(-config.jitter, config.jitter)))
					last.append(base * (1.0 + rng.randf_range(-config.jitter, config.jitter)))
				for a in range(2):
					for b in range(2):
						sequences.append([0.4, 0.4 + first[a], 6.4 - last[b], 6.4])
						labels.append(float(a ^ b))
		var features := {}
		for name in NAMES:
			features[name] = []
		datasets.append({"sequences": sequences, "labels": labels, "features": features})

func progress() -> float:
	if done:
		return 1
	var total: float = counts[0] + counts[1] + counts[2]
	var completed := sample_index
	for i in range(mini(split_index, 3)):
		completed += int(counts[i])
	return 0.85 * completed / total + 0.15 * fit_index / NAMES.size()

func stage() -> String:
	if not error.is_empty():
		return error
	if done:
		return "Complete — readouts frozen; test sequences were held out."
	if split_index < 3:
		return "%s: %d / %d pulse sequences" % [["Training", "Validation", "Test"][split_index], sample_index, counts[split_index]]
	return "Fitting readouts: %d / %d" % [fit_index, NAMES.size()]

static func capture_features(passive: PulseModel, active: PulseModel, times: Array) -> Dictionary:
	passive.reset(times)
	active.reset(times)
	while passive.time < Model.END_TIME:
		passive.step()
		active.step()
		if passive.failed or active.failed:
			return {}
	var p := passive.features()
	var a := active.features()
	var g := PackedFloat64Array([times[1] - times[0], times[2] - times[1], times[3] - times[2]])
	return {"Input count": PackedFloat64Array([float(times.size())]),
		"Full timing (linear)": g,
		"Timing + products": PackedFloat64Array([g[0], g[1], g[2], g[0]*g[1], g[0]*g[2], g[1]*g[2]]),
		"Leaky state": p.leaky_state, "LIF spike timing": p.lif_bins,
		"Passive: final power": p.final_power, "Passive: power history": p.power_bins,
		"Passive: spike history": p.spike_bins, "Feedback: power history": a.power_bins,
		"Feedback: spike history": a.spike_bins}

func advance(budget: int = 2) -> void:
	if done or cancelled:
		return
	if split_index < 3:
		for iteration in range(budget):
			var data: Dictionary = datasets[split_index]
			var features := capture_features(passive_model, active_model, data.sequences[sample_index])
			if features.is_empty():
				error = "Unstable run. Reduce feedback or increase loss. No scores were fitted."
				done = true
				return
			for name in NAMES:
				data.features[name].append(features[name])
			sample_index += 1
			if sample_index >= data.sequences.size():
				split_index += 1
				sample_index = 0
				break
		return
	if fit_index < NAMES.size():
		_fit(NAMES[fit_index])
		fit_index += 1
		return
	done = true

func _fit(name: String) -> void:
	var best_error := INF
	var best_model: PulseReadout
	var chosen := 0.0
	for regularization in [0.001, 0.01, 0.1, 1.0]:
		var model := Readout.new()
		model.fit(datasets[0].features[name], datasets[0].labels, regularization)
		var loss := 0.0
		for i in range(datasets[1].labels.size()):
			loss += pow(model.predict(datasets[1].features[name][i]) - datasets[1].labels[i], 2)
		loss /= datasets[1].labels.size()
		if loss < best_error:
			best_error = loss
			best_model = model
			chosen = regularization
	var correct := 0
	var confusion := [0, 0, 0, 0]
	var predictions: Array = []
	for i in range(datasets[2].labels.size()):
		var value := best_model.predict(datasets[2].features[name][i])
		var guess := classify(value)
		var target := int(datasets[2].labels[i])
		correct += int(guess == target)
		confusion[target * 2 + guess] += 1
		predictions.append(value)
	predictors[name] = best_model
	results[name] = {"test_accuracy": float(correct) / datasets[2].labels.size(),
		"feature_count": datasets[0].features[name][0].size(), "validation_mse": best_error,
		"regularization": chosen, "confusion_rows_target": confusion, "test_predictions": predictions,
		"readout": best_model.snapshot()}

func snapshot() -> Dictionary:
	return {"schema_version": 1, "model": "pulse-modal-v1", "config": config.duplicate(true),
		"mode_count": Model.MODES.size(), "detector_count": Model.PROBES.size(),
		"dt": Model.DT, "end_time": Model.END_TIME, "time_bins": Model.BINS,
		"input_time_rule": "Commands round up to the next dt boundary (comparison tolerance 1e-9); timing baselines use commanded intervals.",
		"counts": counts, "split_seed_offsets": [0, 104729, 209759],
		"task": "Interval order 1-2-3 versus 3-2-1" if int(config.task) == 0 else "XOR of first and last interval categories (short/long)",
		"labels": "0 = short-middle-long; 1 = long-middle-short" if int(config.task) == 0 else "0 = same category; 1 = different categories",
		"detection": "Within-bin mean power; threshold nodes integrate power, reset and recover. Feedback is pump-supplied.",
		"error": error, "complete": done and not cancelled and error.is_empty(),
		"results": results.duplicate(true), "datasets": datasets.duplicate(true)}

static func classify(value: float) -> int:
	# A constant least-squares fit at 0.5 must not classify using roundoff noise.
	return 1 if value > 0.5 + 1e-8 else 0
