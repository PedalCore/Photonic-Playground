extends Control
signal closed
const Model = preload("res://scripts/pulse_model.gd")
const Study = preload("res://scripts/pulse_study.gd")
const Plot = preload("res://scripts/pulse_plot.gd")
const Field = preload("res://scripts/pulse_field.gd")
const MUTED := Color("8fa6b4")
const GREEN := Color("80e0cb")
var config := Model.defaults()
var model: PulseModel
var study: PulseStudy
var field: Control
var trace: Control
var pair_plot: Control
var task_menu: OptionButton
var pattern_menu: OptionButton
var feedback_toggle: CheckButton
var reset_toggle: CheckButton
var gap_control: SpinBox
var run_button: Button
var export_button: Button
var replay_button: Button
var cancel_button: Button
var progress_bar: ProgressBar
var status: Label
var clock: Label
var pair_caption: Label
var prediction: Label
var task_caption: Label
var result_labels: Dictionary = {}
var controls: Array[Control] = []
var settings: Dictionary = {}
var playing := true
var elapsed := 0.0
var sample_counter := 0
var example_times: Array = []
var example_target := 0
var trace_rows: Array = []
var current_predictions: Dictionary = {}
var last_export := ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Color("09121c")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var root := VBoxContainer.new()
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	header.add_child(_label("PULSE LAB", 23, GREEN))
	var sub := _label("Timing → wave memory → spikes → prediction", 14, MUTED)
	sub.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(sub)
	header.add_child(_button("Back to table", func(): closed.emit()))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(scroll)
	var columns := HBoxContainer.new()
	columns.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 16)
	scroll.add_child(columns)
	var left := _column(columns, 245, false)
	var center := _column(columns, 350, true)
	var right := _column(columns, 300, false)
	_build_controls(left)
	center.add_child(_label("A cavity that remembers", 20))
	center.add_child(_paragraph("Eight damped wave modes. Six probes integrate local power, fire and recover. Rings mark recovery.", MUTED))
	field = Field.new()
	field.custom_minimum_size.y = 255
	center.add_child(field)
	center.add_child(_paragraph("Hue = field phase · brightness = intensity (fixed scale). False colour, not a spectrum.", MUTED, 12))
	var transport := HBoxContainer.new()
	center.add_child(transport)
	replay_button = _button("Replay", _replay)
	transport.add_child(replay_button)
	transport.add_child(_button("Pause / play", func(): playing = not playing))
	clock = _label("", 13, MUTED)
	transport.add_child(clock)
	center.add_child(_label("Probe power & emitted spikes", 15))
	trace = Plot.new()
	trace.custom_minimum_size.y = 222
	center.add_child(trace)
	center.add_child(_paragraph("White ticks: input pulses. Coloured lines: power at probes 1–6. Raster: their output spikes. Time is in fundamental periods T₀.", MUTED, 12))
	center.add_child(_label("One neuron · change the pulse gap", 17))
	pair_plot = Plot.new()
	pair_plot.custom_minimum_size.y = 155
	center.add_child(pair_plot)
	pair_caption = _paragraph("", MUTED, 12)
	center.add_child(pair_caption)
	_build_results(right)
	status = _paragraph("Change a parameter, replay a sequence, then run the comparison.", MUTED, 12)
	root.add_child(status)
	_refresh_task()
	_refresh_pair()
	_new_example()

func _column(parent: Control, width: float, expand: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	column.custom_minimum_size.x = width
	column.size_flags_horizontal = SIZE_EXPAND_FILL if expand else SIZE_FILL
	parent.add_child(column)
	return column

func _label(text: String, font_size := 14, color := Color("dce8ed")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _paragraph(text: String, color := Color("dce8ed"), font_size := 13) -> Label:
	var label := _label(text, font_size, color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	return label

func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	return button

func _spin(parent: Control, text: String, low: float, high: float, step: float, value: float, action: Callable) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := _label(text, 13)
	label.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(label)
	var spin := SpinBox.new()
	spin.min_value = low
	spin.max_value = high
	spin.step = step
	spin.value = value
	spin.custom_minimum_size.x = 94
	spin.value_changed.connect(action)
	row.add_child(spin)
	controls.append(spin)
	return spin

func _build_controls(parent: Control) -> void:
	parent.add_child(_label("01 / Choose a question", 16, GREEN))
	task_menu = OptionButton.new()
	task_menu.add_item("Pulse order: 1–2–3 / 3–2–1")
	task_menu.add_item("Timing XOR: same / different")
	task_menu.item_selected.connect(func(index):
		config.task = index
		_refresh_task()
		_changed())
	parent.add_child(task_menu)
	controls.append(task_menu)
	task_caption = _paragraph("", MUTED)
	parent.add_child(task_caption)
	pattern_menu = OptionButton.new()
	pattern_menu.item_selected.connect(func(_index): _new_example())
	parent.add_child(pattern_menu)
	controls.append(pattern_menu)
	var new_button := _button("Try a new sequence", _new_example)
	parent.add_child(new_button)
	controls.append(new_button)
	parent.add_child(_label("02 / Tune the dynamics", 16, GREEN))
	for spec in [["tau", "Decay τ / T₀", 0.6, 4.0, 0.1], ["aspect", "Width / height", 0.8, 2.2, 0.1],
		["threshold", "Firing threshold", 0.06, 0.5, 0.01], ["refractory", "Recovery / T₀", 0.1, 0.8, 0.05],
		["feedback", "Feedback amplitude", 0.0, 0.3, 0.01], ["jitter", "Interval jitter ±", 0.0, 0.3, 0.05], ["seed", "Dataset seed", 1, 999999, 1]]:
		var key: String = spec[0]
		settings[key] = _spin(parent, spec[1], spec[2], spec[3], spec[4], config[key], func(value):
			config[key] = value
			_changed())
	feedback_toggle = CheckButton.new()
	feedback_toggle.text = "Show spike feedback"
	feedback_toggle.toggled.connect(func(_on): _replay())
	parent.add_child(feedback_toggle)
	controls.append(feedback_toggle)
	parent.add_child(_paragraph("Feedback injects externally powered pulses at firing probes. The comparison always runs both passive and feedback models.", MUTED, 12))
	parent.add_child(_label("03 / Compare readouts", 16, GREEN))
	run_button = _button("Run comparison", _run)
	parent.add_child(run_button)
	controls.append(run_button)
	cancel_button = _button("Cancel run", _cancel)
	cancel_button.disabled = true
	parent.add_child(cancel_button)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 8
	progress_bar.show_percentage = false
	parent.add_child(progress_bar)
	parent.add_child(_label("Single-neuron controls", 15))
	gap_control = _spin(parent, "Pulse gap / T₀", 0.2, 2.0, 0.05, 0.5, func(_value): _refresh_pair())
	reset_toggle = CheckButton.new()
	reset_toggle.text = "Threshold & reset"
	reset_toggle.button_pressed = true
	reset_toggle.toggled.connect(func(_on): _refresh_pair())
	parent.add_child(reset_toggle)
	controls.append(reset_toggle)

func _build_results(parent: Control) -> void:
	parent.add_child(_label("What can each readout tell?", 19))
	parent.add_child(_paragraph("Held-out accuracy · chance is 50%\n160 train / 80 validation / 160 test", MUTED))
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 11)
	parent.add_child(grid)
	for heading in ["Readout", "Features", "Test"]:
		grid.add_child(_label(heading, 12, MUTED))
	for name in Study.NAMES:
		grid.add_child(_label(name, 12))
		var dimensions := _label("—", 12, MUTED)
		var accuracy := _label("—", 13, GREEN)
		grid.add_child(dimensions)
		grid.add_child(accuracy)
		result_labels[name] = [dimensions, accuracy]
	parent.add_child(_paragraph("All rows use a fitted linear readout. Timing + products adds explicit digital interactions. Power is square-law detection; spikes add threshold and reset.", MUTED, 12))
	parent.add_child(_paragraph("Only the readout weights learn. Validation selects regularization; the test set supplies the score. Repeated tuning on a seed makes that seed a development set—use fresh seeds for final evaluation.", MUTED, 12))
	parent.add_child(_label("Try the frozen readouts", 16, GREEN))
	prediction = _paragraph("Run a comparison, then try new sequences. Predictions use the completed sequence; they are not live forecasts.")
	parent.add_child(prediction)
	export_button = _button("Export experiment JSON", _export)
	export_button.disabled = true
	parent.add_child(export_button)
	parent.add_child(_button("Open experiment files", func(): OS.shell_open(ProjectSettings.globalize_path("user://"))))
	parent.add_child(_paragraph("A reduced research model\nEight analytic standing-wave modes with optoelectronic threshold nodes. This is separate from the editable wave table. No calibrated laser, Kerr medium, polarization or device noise is modelled.", MUTED, 12))
	parent.add_child(_paragraph("A good first test: compare gaps 0.5 and 1.0 below. The resonator can prefer the wider gap because the second kick arrives in phase.", GREEN, 13))

func _refresh_task() -> void:
	pattern_menu.clear()
	if int(config.task) == 0:
		pattern_menu.add_item("A · short → middle → long")
		pattern_menu.add_item("B · long → middle → short")
		task_caption.text = "Four equal kicks. Same duration and interval multiset; only the order changes. Can the readout recover it?"
	else:
		for text in ["00 · short / short", "01 · short / long", "10 · long / short", "11 · long / long"]:
			pattern_menu.add_item(text)
		task_caption.text = "Four equal kicks. Are the first and last gaps the same category? The middle gap adjusts to keep the total duration fixed."

func _changed() -> void:
	study = null
	current_predictions.clear()
	for labels in result_labels.values():
		labels[0].text = "—"
		labels[1].text = "—"
	export_button.disabled = true
	progress_bar.value = 0
	prediction.text = "Parameters changed. Run a new comparison to train matching readouts."
	status.text = "Results cleared because the model or dataset changed."
	_refresh_pair()
	_new_example()

func _refresh_pair() -> void:
	if pair_plot == null:
		return
	pair_plot.pair = Model.pair_response(gap_control.value, config.tau, 1.4, reset_toggle.button_pressed)
	pair_plot.queue_redraw()
	pair_caption.text = "Mint: leaky integrator. Amber: resonator. Same decay τ = %.1f. Output spikes: %d / %d. %s" % [config.tau,
		pair_plot.pair.events.integrator.size(), pair_plot.pair.events.resonator.size(), "Reset enabled." if reset_toggle.button_pressed else "Free responses; firing disabled."]

func _new_example() -> void:
	sample_counter += 1
	var rng := RandomNumberGenerator.new()
	rng.seed = int(config.seed) + 1000003 + sample_counter * 7919
	var chosen := pattern_menu.selected
	if int(config.task) == 0:
		example_target = chosen
		example_times = Study.sequence(chosen, config.jitter, rng)
	else:
		var a := chosen / 2
		var b := chosen % 2
		example_target = a ^ b
		var first: float = [0.8, 1.6][a] * (1.0 + rng.randf_range(-config.jitter, config.jitter))
		var last: float = [0.8, 1.6][b] * (1.0 + rng.randf_range(-config.jitter, config.jitter))
		example_times = [0.4, 0.4 + first, 6.4 - last, 6.4]
	_predict_example()
	_replay()

func _replay() -> void:
	if example_times.is_empty():
		return
	model = Model.new(config, feedback_toggle.button_pressed)
	model.reset(example_times)
	field.model = model
	field.refresh()
	trace_rows.clear()
	trace.rows = trace_rows
	trace.spikes = model.spikes
	trace.pulses = example_times
	trace.queue_redraw()
	playing = true
	elapsed = 0
	clock.text = "0.00 / 7.60 T₀"

func _process(delta: float) -> void:
	if study != null and not study.done and not study.cancelled:
		study.advance(2)
		progress_bar.value = 100 * study.progress()
		status.text = study.stage()
		if study.done:
			_complete()
		return
	if not playing or model == null or model.failed:
		return
	elapsed += minf(delta, 0.2)
	var steps := 0
	while elapsed >= Model.DT and model.time < Model.END_TIME and steps < 8:
		model.step()
		var row: Array = [model.time]
		row.append_array(Array(model.power))
		trace_rows.append(row)
		elapsed -= Model.DT
		steps += 1
	if steps > 0:
		field.refresh()
		trace.queue_redraw()
		clock.text = "%.2f / 7.60 T₀" % model.time
	if model.failed:
		status.text = "Unstable playback. Reduce feedback or increase loss."
		playing = false
	if model.time >= Model.END_TIME:
		playing = false

func _lock(value: bool) -> void:
	for control in controls:
		if control is SpinBox:
			control.editable = not value
		elif control is BaseButton:
			control.disabled = value
	cancel_button.disabled = not value
	export_button.disabled = value or study == null or not study.done or not study.error.is_empty() or study.cancelled

func _run(sizes: Array = [160, 80, 160]) -> void:
	study = Study.new()
	study.begin(config, sizes)
	playing = false
	for labels in result_labels.values():
		labels[0].text = "—"
		labels[1].text = "—"
	prediction.text = "Collecting independent sequences and fitting readouts…"
	_lock(true)

func _cancel() -> void:
	if study != null:
		study.cancelled = true
	_lock(false)
	status.text = "Run cancelled. No completed scores are available."
	prediction.text = "Run a comparison to train readouts."

func _complete() -> void:
	_lock(false)
	if not study.error.is_empty():
		prediction.text = study.error
		return
	for name in Study.NAMES:
		result_labels[name][0].text = str(study.results[name].feature_count)
		result_labels[name][1].text = "%.1f%%" % (100 * study.results[name].test_accuracy)
	_predict_example()

func _predict_example() -> void:
	current_predictions.clear()
	if study == null or not study.done or study.cancelled or not study.error.is_empty():
		return
	var features := Study.capture_features(Model.new(config, false), Model.new(config, true), example_times)
	if features.is_empty():
		prediction.text = "This new sequence is unstable; no prediction."
		return
	var lines := ["New sequence · target %d" % example_target]
	for name in Study.NAMES:
		var score: float = study.predictors[name].predict(features[name])
		current_predictions[name] = {"score": score, "class": Study.classify(score)}
	for name in ["Timing + products", "Passive: power history", "Feedback: spike history"]:
		lines.append("%s: %d (%.2f)" % [name, current_predictions[name].class, current_predictions[name].score])
	lines.append("Scores are linear outputs, not probabilities.")
	prediction.text = "\n".join(lines)

func _export() -> void:
	if study == null or not study.done or study.cancelled or not study.error.is_empty():
		return
	var data := study.snapshot()
	data["godot"] = Engine.get_version_info().string
	data["example"] = {"sample_counter": sample_counter, "target": example_target, "pulse_times": example_times,
		"feedback_shown": feedback_toggle.button_pressed, "trace_columns": ["t", "power1", "power2", "power3", "power4", "power5", "power6"],
		"trace": trace_rows, "spikes": model.spikes, "time_reached": model.time, "predictions": current_predictions}
	data["pair"] = {"gap": gap_control.value, "tau": config.tau, "reset": reset_toggle.button_pressed, "response": pair_plot.pair}
	last_export = "user://pulse-lab-%s-%s.json" % [Time.get_datetime_string_from_system().replace(":", "-"), Time.get_ticks_msec()]
	var file := FileAccess.open(last_export, FileAccess.WRITE)
	if file == null:
		status.text = "Export failed: %s" % error_string(FileAccess.get_open_error())
		return
	file.store_string(JSON.stringify(data, "  "))
	file.close()
	status.text = "Saved model, datasets, fitted weights and example trace: " + ProjectSettings.globalize_path(last_export)

func smoke() -> void:
	_run([40, 20, 40])
	while not study.done:
		await get_tree().process_frame
	assert(study.error.is_empty())
	assert(study.results["Full timing (linear)"].test_accuracy > 0.9)
	_new_example()
	assert(current_predictions.size() == Study.NAMES.size())
	_export()
	var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string(last_export))
	assert(saved is Dictionary and saved.complete and saved.datasets[0].features["Input count"].size() == 40)
	assert(saved.example.predictions.size() == Study.NAMES.size())
	task_menu.select(1)
	task_menu.item_selected.emit(1)
	pattern_menu.select(2)
	pattern_menu.item_selected.emit(2)
	assert(example_target == 1 and study == null)
	_run([40, 20, 40])
	while not study.done:
		await get_tree().process_frame
	assert(study.results["Timing + products"].test_accuracy > 0.9)
	assert(current_predictions.size() == Study.NAMES.size())
	settings.tau.value = 2.0
	assert(study == null and export_button.disabled)
	_run([40, 20, 40])
	_cancel()
	assert(study.cancelled and export_button.disabled and not run_button.disabled)
	print("PULSE UI SMOKE PASS")
