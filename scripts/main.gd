extends Control

const Table = preload("res://scripts/optical_table.gd")
const Library = preload("res://scripts/experiments.gd")
const INK := Color("dce8ed")
const MUTED := Color("8799a8")
const GREEN := Color("85ddc2")
const TOOLS := ["select", "source", "mirror", "glass", "prism", "grating", "detector", "erase"]
var table: OpticalTable
var inspector: VBoxContainer
var detector_box: VBoxContainer
var guide_label: Label
var title_label: Label
var status_label: Label
var transport_label: Label
var pause_button: Button
var emission_button: CheckButton
var boundary_button: CheckButton
var tool_buttons: Array[Button] = []
var preset_buttons: Array[Button] = []
var footer: Label
var refresh_clock: float = 0.0
var inspector_locked: bool = false
var last_selection: int = -2
var readout_labels: Array[Label] = []
var readout_bars: Array[ProgressBar] = []
var confirmation: ConfirmationDialog
var pending_action: Callable
var status_until: float = 0.0
var pulse_lab: Control

func _ready() -> void:
	_build_theme()
	_build_ui()
	table.selection_changed.connect(_selection_changed)
	table.layout_changed.connect(_layout_changed)
	table.notice.connect(_notice)
	confirmation = ConfirmationDialog.new()
	confirmation.title = "Replace this table?"
	confirmation.dialog_text = "Save your current table first if you want to keep it."
	confirmation.ok_button_text = "Replace table"
	confirmation.confirmed.connect(func(): pending_action.call())
	add_child(confirmation)
	_selection_changed()
	_layout_changed()
	_choose_preset(0)
	if "--pulse-lab" in OS.get_cmdline_user_args() or "--pulse-smoke" in OS.get_cmdline_user_args() or "--pulse-capture" in OS.get_cmdline_user_args():
		_open_pulse_lab()
	if "--pulse-smoke" in OS.get_cmdline_user_args():
		await pulse_lab.smoke()
		pulse_lab.closed.emit()
		await get_tree().process_frame
		assert(not is_instance_valid(pulse_lab) and table.running)
		get_tree().quit()
		return
	if "--pulse-capture" in OS.get_cmdline_user_args():
		pulse_lab._run()
		while not pulse_lab.study.done:
			await get_tree().process_frame
		pulse_lab._replay()
		while pulse_lab.model.time < 4.5:
			await get_tree().process_frame
		pulse_lab.playing = false
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://pulse-preview.png")
		if "--preview-log" in OS.get_cmdline_user_args():
			# Optional compact CI preview when artifact storage is unavailable.
			var preview := get_viewport().get_texture().get_image()
			preview.resize(1100, roundi(preview.get_height() * 1100.0 / preview.get_width()))
			var encoded := Marshalls.raw_to_base64(preview.save_jpg_to_buffer(0.8))
			for offset in range(0, encoded.length(), 1024):
				print("PULSE_PREVIEW_CHUNK: ", encoded.substr(offset, 1024))
		print("PULSE CAPTURE PASS: ", ProjectSettings.globalize_path("user://pulse-preview.png"))
		get_tree().quit()
		return
	# Automated run/capture uses the same native game scene and solver.
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--preset="):
			_choose_preset(clampi(int(arg.get_slice("=", 1)), 0, 4))
	if "--smoke" in OS.get_cmdline_user_args():
		await get_tree().process_frame
		_smoke()
	if "--capture" in OS.get_cmdline_user_args():
		for i in range(600):
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("user://preview.png")
		print("CAPTURE: ", ProjectSettings.globalize_path("user://preview.png"))
		get_tree().quit()

func box(bg: Color, border: Color = Color("273b49"), radius: int = 7) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 9
	style.content_margin_bottom = 9
	return style

func _build_theme() -> void:
	var t := Theme.new()
	t.default_font_size = 14
	t.set_color("font_color", "Label", INK)
	t.set_color("font_color", "Button", INK)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", GREEN)
	t.set_stylebox("normal", "Button", box(Color("14222d")))
	t.set_stylebox("hover", "Button", box(Color("203540"), Color("527169")))
	t.set_stylebox("pressed", "Button", box(Color("1c3b37"), Color("6ea995")))
	t.set_stylebox("focus", "Button", box(Color(0, 0, 0, 0), GREEN))
	t.set_stylebox("normal", "PanelContainer", box(Color("0e1a24")))
	t.set_stylebox("background", "ProgressBar", box(Color("142a33"), Color("142a33"), 3))
	t.set_stylebox("fill", "ProgressBar", box(GREEN, GREEN, 3))
	t.set_constant("separation", "VBoxContainer", 10)
	t.set_constant("separation", "HBoxContainer", 8)
	theme = t

func label(text: String, font_size: int = 14, color: Color = INK) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node

func button(text: String, action: Callable, hint: String = "") -> Button:
	var node := Button.new()
	node.text = text
	node.tooltip_text = hint
	node.pressed.connect(action)
	node.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	return node

func spacer(parent: Control) -> void:
	var s := Control.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(s)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 22)
	add_child(margin)
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 14)
	margin.add_child(root)
	var header := HBoxContainer.new()
	root.add_child(header)
	var brand := VBoxContainer.new()
	brand.add_theme_constant_override("separation", 0)
	header.add_child(brand)
	brand.add_child(label("PHOTONIC  /  playground", 26))
	brand.add_child(label("A little table for big wave ideas.", 13, MUTED))
	spacer(header)
	header.add_child(button("Pulse lab", _open_pulse_lab, "Run pulse timing, spiking and cavity computation experiments"))
	header.add_child(button("Save table", table_save, "Ctrl+S · Save layout to your Godot user-data folder"))
	header.add_child(button("Load", func(): _replace(table_load), "Load your saved layout"))
	header.add_child(button("Export readings", table_export, "Detector CSV and layout/measurement JSON"))
	header.add_child(button("Files", func(): OS.shell_open(ProjectSettings.globalize_path("user://")), "Open the folder containing saved tables and readings"))
	var toolbar := HBoxContainer.new()
	root.add_child(toolbar)
	for i in range(TOOLS.size()):
		var name: String = TOOLS[i]
		var b := button(str(i + 1) + "  " + name.capitalize(), _select_tool.bind(name), "Click to choose; click the table to place. Use Select to move components.")
		b.toggle_mode = true
		b.button_pressed = i == 0
		tool_buttons.append(b)
		toolbar.add_child(b)
	spacer(toolbar)
	toolbar.add_child(button("Undo", func(): table.undo(), "Ctrl+Z"))
	toolbar.add_child(button("Redo", func(): table.undo(true), "Ctrl+Shift+Z"))
	var middle := HBoxContainer.new()
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_theme_constant_override("separation", 18)
	root.add_child(middle)
	var workspace := VBoxContainer.new()
	workspace.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	middle.add_child(workspace)
	var heading := HBoxContainer.new()
	workspace.add_child(heading)
	title_label = label("01  /  WAVE GARDEN", 14, GREEN)
	heading.add_child(title_label)
	spacer(heading)
	transport_label = label("192 × 112  ·  LIVE", 12, MUTED)
	heading.add_child(transport_label)
	var aspect := AspectRatioContainer.new()
	aspect.ratio = 192.0 / 112.0
	aspect.stretch_mode = AspectRatioContainer.STRETCH_FIT
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	workspace.add_child(aspect)
	table = Table.new()
	aspect.add_child(table)
	var transport := HBoxContainer.new()
	workspace.add_child(transport)
	pause_button = button("Pause", _pause, "Space · Pause or resume wave propagation")
	transport.add_child(pause_button)
	transport.add_child(button("Step", _step, "Advance one simulation step while paused"))
	transport.add_child(button("Pulse", _pulse, "Send one short wave packet"))
	transport.add_child(button("Reset waves", func(): table.reset_waves(), "Clear waves, keeping all components"))
	spacer(transport)
	transport.add_child(label("View", 12, MUTED))
	var views := OptionButton.new()
	for item in ["Ripples", "Intensity", "Signed field"]:
		views.add_item(item)
	views.item_selected.connect(func(i: int): table.set_view(i))
	transport.add_child(views)
	var speed_menu := OptionButton.new()
	for item in ["1 step/frame", "3 steps/frame", "6 steps/frame"]:
		speed_menu.add_item(item)
	speed_menu.select(0)
	speed_menu.item_selected.connect(func(i: int): table.speed = [1, 3, 6][i])
	transport.add_child(speed_menu)
	guide_label = label(Library.NOTES[0], 13, MUTED)
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	guide_label.custom_minimum_size.y = 40
	workspace.add_child(guide_label)
	var sidebar := PanelContainer.new()
	sidebar.custom_minimum_size.x = 256
	middle.add_child(sidebar)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sidebar.add_child(scroll)
	var side := VBoxContainer.new()
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	side.custom_minimum_size.x = 228
	scroll.add_child(side)
	side.add_child(label("ON THE TABLE", 12, GREEN))
	inspector = VBoxContainer.new()
	side.add_child(inspector)
	side.add_child(HSeparator.new())
	side.add_child(label("LIGHT & TIME", 12, GREEN))
	emission_button = CheckButton.new()
	emission_button.text = "Continuous sources"
	emission_button.button_pressed = true
	emission_button.toggled.connect(func(value: bool): table.solver.emitting = value; table.solver.pulsing = false)
	side.add_child(emission_button)
	boundary_button = CheckButton.new()
	boundary_button.text = "Reflective table edges"
	boundary_button.toggled.connect(func(value: bool): table.boundary_reflects = value; table.apply_layout())
	side.add_child(boundary_button)
	_add_slider(side, "Brightness", 0.5, 6, 0.1, 2.3, func(value: float): table.set_exposure(value))
	side.add_child(HSeparator.new())
	side.add_child(label("DETECTORS", 12, GREEN))
	detector_box = VBoxContainer.new()
	side.add_child(detector_box)
	var caption := label("Local mean-square field · arbitrary units\nRGB = three independent frequency bands", 11, MUTED)
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side.add_child(caption)
	var experiments_row := HBoxContainer.new()
	root.add_child(experiments_row)
	for i in range(Library.TITLES.size()):
		var b := button("0%d   %s" % [i + 1, Library.TITLES[i]], func(): _replace(_choose_preset.bind(i)), Library.NOTES[i])
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preset_buttons.append(b)
		experiments_row.add_child(b)
	var bottom := HBoxContainer.new()
	root.add_child(bottom)
	footer = label("1–8 tools  ·  drag to move  ·  Q/E or scroll to rotate  ·  right-click to remove  ·  Ctrl+D duplicate", 11, MUTED)
	bottom.add_child(footer)
	spacer(bottom)
	bottom.add_child(label("SCALAR WAVE LAB  /  v0.1", 11, Color("577580")))
	status_label = label("Place something. Let the waves surprise you.", 12, GREEN)
	root.add_child(status_label)

func _replace(action: Callable) -> void:
	if table.dirty:
		pending_action = action
		confirmation.popup_centered()
	else:
		action.call()

func _choose_preset(index: int) -> void:
	table.load_preset(index)
	table.dirty = false
	emission_button.set_pressed_no_signal(table.solver.emitting)
	for i in range(preset_buttons.size()):
		preset_buttons[i].set_pressed_no_signal(index == i)
	title_label.text = "0%d  /  %s" % [index + 1, Library.TITLES[index].to_upper()]
	guide_label.text = Library.NOTES[index]
	_notice("Experiment loaded. Try moving a component or tuning a source.")

func _select_tool(name: String) -> void:
	table.tool = name
	for i in range(TOOLS.size()):
		tool_buttons[i].set_pressed_no_signal(TOOLS[i] == name)
	_notice("Drag components to move them." if name == "select" else "Click the table to place a %s. Select it to tune its properties." % name)

func _add_slider(parent: Control, text: String, low: float, high: float, increment: float, initial: float, action: Callable, records_undo: bool = false) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	row.add_child(label(text, 12, MUTED))
	spacer(row)
	var value_label := label("%.2f" % initial, 12)
	row.add_child(value_label)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = increment
	slider.value = initial
	slider.custom_minimum_size.y = 20
	if records_undo:
		slider.drag_started.connect(func(): table.remember(); inspector_locked = true)
		slider.drag_ended.connect(func(_changed: bool): inspector_locked = false)
	slider.value_changed.connect(func(value: float):
		value_label.text = "%.2f" % value
		if records_undo and not inspector_locked:
			table.remember()
		action.call(value)
	)
	parent.add_child(slider)

func _selection_changed() -> void:
	for child in inspector.get_children():
		inspector.remove_child(child)
		child.queue_free()
	if table.selected < 0:
		inspector.add_child(label("An open invitation", 19))
		var text := label("Select a source or component to tune it.\n\nBuild a path, split a wave, or simply see what happens.", 13, MUTED)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.y = 105
		inspector.add_child(text)
		return
	var c: Dictionary = table.components[table.selected]
	inspector.add_child(label(c.kind.capitalize(), 20))
	var coords := label("POSITION   %.0f, %.0f" % [c.x, c.y], 11, MUTED)
	inspector.add_child(coords)
	_add_slider(inspector, "Angle", 0, 355, 5, fposmod(c.angle, 360), func(v: float): table.change_selected("angle", v, false), true)
	_add_slider(inspector, "Size", 0 if c.kind == "source" else 4, 110, 1, c.size, func(v: float): table.change_selected("size", v, false), true)
	if c.kind == "source":
		var colors := OptionButton.new()
		for s in ["Red band", "Green band", "Blue band", "White · all three"]:
			colors.add_item(s)
		colors.select(int(c.band))
		colors.item_selected.connect(func(i: int): table.change_selected("band", i))
		inspector.add_child(colors)
		_add_slider(inspector, "Phase (degrees)", 0, 360, 5, c.phase, func(v: float): table.change_selected("phase", v, false), true)
		_add_slider(inspector, "Wavelength scale", 0.8, 2, 0.05, c.wavelength, func(v: float): table.change_selected("wavelength", v, false), true)
	if c.kind in ["glass", "prism"]:
		_add_slider(inspector, "Refractive index", 1, 2, 0.05, c.index, func(v: float): table.change_selected("index", v, false), true)
		_add_slider(inspector, "Dispersion", 0, 0.25, 0.01, c.dispersion, func(v: float): table.change_selected("dispersion", v, false), true)
	if c.kind == "grating":
		var double_slit := CheckButton.new()
		double_slit.text = "Two slits only"
		double_slit.button_pressed = c.double_slit
		double_slit.toggled.connect(func(v: bool): table.change_selected("double_slit", v))
		inspector.add_child(double_slit)
		_add_slider(inspector, "Slit separation", 6, 40, 1, c.spacing, func(v: float): table.change_selected("spacing", v, false), true)
		_add_slider(inspector, "Slit width", 2, 10, 1, c.slit_width, func(v: float): table.change_selected("slit_width", v, false), true)
	var actions := HBoxContainer.new()
	inspector.add_child(actions)
	actions.add_child(button("Duplicate", func(): table.duplicate_selected(), "Ctrl+D"))
	actions.add_child(button("Remove", func(): table.delete_at(table.selected), "Delete"))

func _layout_changed() -> void:
	for child in detector_box.get_children():
		detector_box.remove_child(child)
		child.queue_free()
	readout_labels.clear()
	readout_bars.clear()
	var count := 0
	for c in table.components:
		if c.kind == "detector":
			count += 1
			var readout := label("D%d   waiting for light" % count, 12)
			readout_labels.append(readout)
			detector_box.add_child(readout)
			var bar := ProgressBar.new()
			bar.custom_minimum_size.y = 5
			bar.show_percentage = false
			bar.max_value = 0.15
			readout_bars.append(bar)
			detector_box.add_child(bar)
	if count == 0:
		detector_box.add_child(label("Place a detector to measure light.", 12, MUTED))
	boundary_button.set_pressed_no_signal(table.boundary_reflects)
	emission_button.set_pressed_no_signal(table.solver.emitting)

func _pause() -> void:
	table.running = not table.running
	pause_button.text = "Pause" if table.running else "Run"

func _step() -> void:
	table.running = false
	pause_button.text = "Run"
	table.solver.step()
	table.update_textures()

func _pulse() -> void:
	table.solver.emitting = false
	emission_button.set_pressed_no_signal(false)
	table.solver.pulse()
	table.running = true
	pause_button.text = "Pause"

func table_save() -> void:
	table.save_layout()

func table_load() -> void:
	if not table.load_layout():
		return
	emission_button.set_pressed_no_signal(table.solver.emitting)
	title_label.text = "SAVED TABLE  /  YOUR EXPERIMENT"
	guide_label.text = "Your layout, restarted from rest. Change a component and see where the light goes."

func table_export() -> void:
	table.export_measurements()

func _notice(text: String) -> void:
	status_label.text = text
	status_until = Time.get_ticks_msec() + 6000

func _process(delta: float) -> void:
	if is_instance_valid(pulse_lab):
		return
	if not table:
		return
	refresh_clock += delta
	if refresh_clock < 0.15:
		return
	refresh_clock = 0
	transport_label.text = "t %05d   ·   %s   ·   %d fps" % [table.solver.tick, "LIVE" if table.running else "PAUSED", Engine.get_frames_per_second()]
	var index := 0
	for c in table.components:
		if c.kind == "detector" and index < readout_labels.size():
			var energy: Vector3 = table.solver.detector_reading(c)
			var power := energy.x + energy.y + energy.z
			readout_labels[index].text = "D%d   %.4f" % [index + 1, power]
			readout_bars[index].value = power
			index += 1
			if c.get("target", false) and Time.get_ticks_msec() > status_until:
				status_label.text = "Target light level: %.4f  /  0.0100   %s" % [power, "— target illuminated!" if power >= 0.01 else "— try a new route"]

func _input(event: InputEvent) -> void:
	if is_instance_valid(pulse_lab):
		return
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var handled := true
	if event.ctrl_pressed or event.meta_pressed:
		match event.keycode:
			KEY_S: table.save_layout()
			KEY_Z: table.undo(event.shift_pressed)
			KEY_D: table.duplicate_selected()
			_: handled = false
		if handled:
			get_viewport().set_input_as_handled()
		return
	match event.keycode:
		KEY_SPACE: _pause()
		KEY_DELETE, KEY_BACKSPACE: table.delete_at(table.selected)
		KEY_ESCAPE: _select_tool("select"); table.selected = -1; _selection_changed()
		KEY_Q, KEY_E:
			if table.selected >= 0:
				var angle: float = table.components[table.selected].angle + (-5 if event.keycode == KEY_Q else 5)
				table.change_selected("angle", fposmod(angle, 360))
				_selection_changed()
		_:
			if event.keycode >= KEY_1 and event.keycode <= KEY_8:
				_select_tool(TOOLS[event.keycode - KEY_1])
			else:
				handled = false
	if handled:
		get_viewport().set_input_as_handled()

func _smoke() -> void:
	table.running = false
	for i in range(5):
		_choose_preset(i)
		table.solver.step(12)
		table.update_textures()
		table.selected = 0
		_selection_changed()
		table.change_selected("phase", 90.0)
		table.duplicate_selected()
		table.undo()
		table.undo(true)
		table.delete_at(table.components.size() - 1)
		assert(Table.validate_snapshot(table.snapshot()).is_empty())
	table.save_layout()
	var saved: Dictionary = table.snapshot()
	table.components.clear()
	assert(table.load_layout())
	assert(table.components.size() == saved.components.size())
	assert(Table.validate_snapshot(table.snapshot()).is_empty())
	table.export_measurements()
	print("SMOKE PASS: all presets, inspector, edits, undo/redo, layout IO, export")
	get_tree().quit()

func _open_pulse_lab() -> void:
	if is_instance_valid(pulse_lab):
		return
	var was_running := table.running
	table.running = false
	table.process_mode = Node.PROCESS_MODE_DISABLED
	pulse_lab = preload("res://scripts/pulse_lab.gd").new()
	pulse_lab.closed.connect(func():
		pulse_lab.queue_free()
		table.process_mode = Node.PROCESS_MODE_INHERIT
		table.running = was_running)
	add_child(pulse_lab)
