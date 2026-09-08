class_name OpticalTable
extends Control

signal selection_changed
signal layout_changed
signal notice(message: String)

const Solver = preload("res://scripts/wave_solver.gd")
const Library = preload("res://scripts/experiments.gd")
const ACCENT := Color("85ddc2")
const MUTED := Color("718495")
const COLORS := {"source": Color("eedba1"), "mirror": Color("c1d0e2"), "glass": Color("8fbdde"), "prism": Color("beabe8"), "grating": Color("f3b597"), "detector": Color("85ddc2")}
var solver = Solver.new()
var components: Array = []
var selected: int = -1
var tool: String = "select"
var running: bool = true
var speed: int = 3
var exposure: float = 2.3
var view_mode: int = 0
var preset: int = 0
var traces: Array = []
var history: Array = []
var future: Array = []
var boundary_reflects: bool = false
var dragging: bool = false
var drag_offset := Vector2.ZERO
var dirty: bool = false
var hovered: int = -1
var mouse_grid := Vector2(-100, -100)
var visual: TextureRect
var field_texture: ImageTexture
var energy_texture: ImageTexture
var paint_material: ShaderMaterial
var elapsed: float = 0.0
var last_sample: int = 0
var sample_ms: float = 0.0
var sample_counter: int = 0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	custom_minimum_size = Vector2(600, 350)
	visual = TextureRect.new()
	visual.mouse_filter = Control.MOUSE_FILTER_IGNORE
	visual.show_behind_parent = true
	visual.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	visual.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	add_child(visual)
	paint_material = ShaderMaterial.new()
	paint_material.shader = preload("res://shaders/wave_display.gdshader")
	visual.material = paint_material
	field_texture = ImageTexture.create_from_image(Image.create_from_data(solver.width, solver.height, false, Image.FORMAT_RGBF, solver.field.to_byte_array()))
	energy_texture = ImageTexture.create_from_image(Image.create_from_data(solver.width, solver.height, false, Image.FORMAT_RGBF, solver.energy.to_byte_array()))
	visual.texture = field_texture
	paint_material.set_shader_parameter("energy_texture", energy_texture)
	resized.connect(_fit)
	_fit()
	load_preset(0)

func _fit() -> void:
	if visual:
		visual.position = Vector2(1, 1)
		visual.size = size - Vector2(2, 2)
	queue_redraw()

func _process(delta: float) -> void:
	elapsed += delta
	if running and not dragging:
		var started := Time.get_ticks_usec()
		solver.step(speed)
		sample_ms = float(Time.get_ticks_usec() - started) / 1000.0
		if solver.tick - last_sample >= 12:
			last_sample = solver.tick
			var values: Array = []
			for i in range(components.size()):
				if components[i].kind == "detector":
					var e: Vector3 = solver.detector_reading(components[i])
					values.append({"component": i, "r": e.x, "g": e.y, "b": e.z})
			traces.append({"tick": solver.tick, "detectors": values})
			if traces.size() > 4096:
				traces.pop_front()
		update_textures()
	queue_redraw()

func update_textures() -> void:
	if field_texture:
		field_texture.update(Image.create_from_data(solver.width, solver.height, false, Image.FORMAT_RGBF, solver.field.to_byte_array()))
		energy_texture.update(Image.create_from_data(solver.width, solver.height, false, Image.FORMAT_RGBF, solver.energy.to_byte_array()))

func set_view(mode: int) -> void:
	view_mode = mode
	paint_material.set_shader_parameter("view_mode", mode)

func set_exposure(value: float) -> void:
	exposure = value
	paint_material.set_shader_parameter("exposure", value)

func screen(p: Vector2) -> Vector2:
	return p * size / Vector2(solver.width, solver.height)

func grid(p: Vector2) -> Vector2:
	return p / size * Vector2(solver.width, solver.height)

func to_screen(component: Dictionary, p: Vector2) -> Vector2:
	return screen(Vector2(component.x, component.y) + p.rotated(deg_to_rad(component.angle)))

func _draw() -> void:
	# A quiet chip grid remains visible over the wave field.
	for x in range(0, solver.width + 1, 8):
		draw_line(screen(Vector2(x, 0)), screen(Vector2(x, solver.height)), Color(0.3, 0.5, 0.6, 0.065), 1)
	for y in range(0, solver.height + 1, 8):
		draw_line(screen(Vector2(0, y)), screen(Vector2(solver.width, y)), Color(0.3, 0.5, 0.6, 0.065), 1)
	draw_rect(Rect2(Vector2.ZERO, size), Color("314452"), false, 2)
	for i in range(components.size()):
		_draw_component(components[i], i == selected, i == hovered)
	if tool != "select" and tool != "erase" and Rect2(Vector2(3, 3), Vector2(solver.width - 6, solver.height - 6)).has_point(mouse_grid):
		var ghost := Library.component(tool, mouse_grid.x, mouse_grid.y, 0, 28)
		if tool == "source":
			ghost.size = 0.0
		_draw_component(ghost, false, false, true)

func _draw_component(comp: Dictionary, chosen: bool, hover: bool, ghost: bool = false) -> void:
	var center := screen(Vector2(comp.x, comp.y))
	var color: Color = COLORS[comp.kind]
	if ghost:
		color.a = 0.35
	var a := to_screen(comp, Vector2(0, -comp.size * 0.5))
	var b := to_screen(comp, Vector2(0, comp.size * 0.5))
	match comp.kind:
		"source":
			if comp.size > 1:
				draw_line(a, b, Color(color, 0.12), 14, true)
				draw_line(a, b, color, 2, true)
			draw_circle(center, 11, Color(color, 0.12))
			draw_circle(center, 4.5, color)
			draw_arc(center, 17, -PI * 0.7, PI * 0.7, 32, Color(color, 0.38), 1.0, true)
		"mirror":
			draw_line(a, b, Color("121e2b"), 9, true)
			draw_line(a, b, color, 3, true)
			var n := (b - a).orthogonal().normalized() * 6
			for t in range(1, 9):
				var p := a.lerp(b, t / 10.0)
				draw_line(p, p + n + (b - a).normalized() * 4, Color(color, 0.4), 1.0, true)
		"glass", "prism":
			var pts := Solver.triangle(comp) if comp.kind == "prism" else PackedVector2Array([Vector2(-comp.size * 0.275, -comp.size * 0.5), Vector2(comp.size * 0.275, -comp.size * 0.5), Vector2(comp.size * 0.275, comp.size * 0.5), Vector2(-comp.size * 0.275, comp.size * 0.5)])
			var polygon := PackedVector2Array()
			for p in pts:
				polygon.append(to_screen(comp, p))
			draw_colored_polygon(polygon, Color(color, 0.075))
			polygon.append(polygon[0])
			draw_polyline(polygon, Color(color, 0.8), 1.5, true)
			draw_string(ThemeDB.fallback_font, center + Vector2(-18, 5), "n %.2f" % comp.index, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
		"grating":
			for v in range(-int(comp.size * 0.5), int(comp.size * 0.5)):
				var gap: bool = absf(absf(float(v)) - comp.spacing * 0.5) < comp.slit_width * 0.5 if comp.double_slit else absf(fposmod(v + comp.spacing * 0.5, comp.spacing) - comp.spacing * 0.5) < comp.slit_width * 0.5
				if not gap:
					draw_line(to_screen(comp, Vector2(0, v)), to_screen(comp, Vector2(0, v + 1)), color, 4.0)
		"detector":
			draw_line(a, b, Color(color, 0.18), 12, true)
			draw_line(a, b, color, 1.5, true)
			draw_circle(a, 3, color)
			draw_circle(b, 3, color)
			if not ghost:
				var power: Vector3 = solver.detector_reading(comp)
				var normal := (b - a).orthogonal().normalized()
				var profile := PackedVector2Array()
				for j in range(maxi(2, int(comp.size))):
					var pos := Vector2(comp.x, comp.y) + Vector2(0, j - comp.size * 0.5).rotated(deg_to_rad(comp.angle))
					var x := clampi(roundi(pos.x), 1, solver.width - 2)
					var y := clampi(roundi(pos.y), 1, solver.height - 2)
					var idx: int = (y * solver.width + x) * 3
					var amount: float = solver.energy[idx] + solver.energy[idx + 1] + solver.energy[idx + 2]
					profile.append(screen(pos) - normal * minf(65, amount * 160))
				draw_polyline(profile, Color(color, 0.75), 1.5, true)
				draw_string(ThemeDB.fallback_font, b + Vector2(8, 16), "%.4f" % (power.x + power.y + power.z), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, color)
	if chosen or hover:
		draw_arc(center, 22, 0, TAU, 48, ACCENT if chosen else Color(ACCENT, 0.35), 1.4, true)
		if chosen:
			var handle := to_screen(comp, Vector2(9, 0))
			draw_line(center, handle, Color(ACCENT, 0.45), 1.0, true)
			draw_circle(handle, 3, ACCENT)

func hit_test(point: Vector2) -> int:
	for i in range(components.size() - 1, -1, -1):
		if Solver.contains(components[i], point, 3.0):
			return i
	return -1

func remember() -> void:
	history.append(components.duplicate(true))
	if history.size() > 50:
		history.pop_front()
	future.clear()

func apply_layout(reset_field: bool = false) -> void:
	solver.boundary_reflects = boundary_reflects
	solver.configure(components)
	if reset_field:
		solver.reset()
	traces.clear()
	last_sample = solver.tick
	dirty = true
	layout_changed.emit()
	update_textures()
	queue_redraw()

func load_preset(index: int) -> void:
	preset = index
	components = Library.layout(index)
	selected = -1
	history.clear()
	future.clear()
	solver.emitting = index != 3
	solver.pulsing = false
	apply_layout(true)
	if index == 3:
		solver.pulse()
	selection_changed.emit()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		mouse_grid = grid(event.position)
		hovered = hit_test(mouse_grid)
		if dragging and selected >= 0:
			var p := mouse_grid + drag_offset
			components[selected].x = clampf(p.x, 3, solver.width - 4)
			components[selected].y = clampf(p.y, 3, solver.height - 4)
		queue_redraw()
	if event is InputEventMouseButton:
		var p := grid(event.position)
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var found := hit_test(p)
				if tool == "erase":
					delete_at(found)
				elif tool == "select":
					selected = found
					selection_changed.emit()
					if found >= 0:
						remember()
						dragging = true
						drag_offset = Vector2(components[found].x, components[found].y) - p
				elif components.size() < 80:
					remember()
					var comp := Library.component(tool, clampf(p.x, 3, solver.width - 4), clampf(p.y, 3, solver.height - 4))
					if tool == "source":
						comp.size = 0.0
					components.append(comp)
					selected = components.size() - 1
					apply_layout()
					selection_changed.emit()
				else:
					notice.emit("The table supports up to 80 components.")
			else:
				if dragging:
					dragging = false
					apply_layout()
					selection_changed.emit()
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			delete_at(hit_test(p))
		elif event.pressed and selected >= 0 and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			change_selected("angle", fposmod(components[selected].angle + (5.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -5.0), 360.0))
			selection_changed.emit()
		accept_event()

func delete_at(index: int) -> void:
	if index < 0 or index >= components.size():
		return
	remember()
	components.remove_at(index)
	selected = -1
	apply_layout()
	selection_changed.emit()

func change_selected(key: String, value: Variant, record: bool = true) -> void:
	if selected < 0:
		return
	if record:
		remember()
	components[selected][key] = value
	apply_layout()

func duplicate_selected() -> void:
	if selected < 0 or components.size() >= 80:
		return
	remember()
	var copy: Dictionary = components[selected].duplicate(true)
	copy.x = clampf(copy.x + 8.0, 3, solver.width - 4)
	copy.y = clampf(copy.y + 8.0, 3, solver.height - 4)
	components.append(copy)
	selected = components.size() - 1
	apply_layout()
	selection_changed.emit()

func undo(redo: bool = false) -> void:
	var stack: Array = future if redo else history
	if stack.is_empty():
		return
	if redo:
		history.append(components.duplicate(true))
	else:
		future.append(components.duplicate(true))
	components = stack.pop_back()
	selected = -1
	apply_layout(true)
	selection_changed.emit()

func reset_waves() -> void:
	solver.reset()
	traces.clear()
	last_sample = 0
	if not solver.emitting:
		solver.pulse()
	update_textures()

func snapshot() -> Dictionary:
	return {"schema_version": 1, "model": "scalar-wave-v1", "grid": [solver.width, solver.height], "preset": preset,
		"boundary_reflects": boundary_reflects, "emitting": solver.emitting, "components": components.duplicate(true)}

static func validate_snapshot(data: Variant) -> String:
	if not data is Dictionary or data.get("schema_version") != 1 or data.get("model") != "scalar-wave-v1":
		return "Unsupported layout format. Expected a Photonic Playground v1 layout."
	var dims: Variant = data.get("grid")
	if not dims is Array or dims.size() != 2:
		return "Invalid grid."
	for dimension in dims:
		if not dimension is float and not dimension is int:
			return "Invalid grid dimension."
	if float(dims[0]) != 192.0 or float(dims[1]) != 112.0 or not data.get("components") is Array or data.components.size() > 80:
		return "Invalid grid or component count."
	for c in data.components:
		if not c is Dictionary or not COLORS.has(c.get("kind", "")):
			return "Unknown component in layout."
		for key in ["x", "y", "size", "angle", "index", "dispersion", "phase", "band", "wavelength", "spacing", "slit_width"]:
			if not c.get(key) is float and not c.get(key) is int:
				return "Missing or invalid component property: " + key
			if not is_finite(float(c[key])):
				return "Component values must be finite."
		if c.x < 1 or c.x > 190 or c.y < 1 or c.y > 110 or c.size < 0 or c.size > 112 or c.index < 1.0 or c.index > 2.0 or c.dispersion < 0 or c.dispersion > 0.25 or c.wavelength < 0.8 or c.wavelength > 2.0 or c.spacing < 6 or c.spacing > 40 or c.slit_width < 2 or c.slit_width > 10 or c.band < 0 or c.band > 3 or c.band != int(c.band):
			return "Component properties are outside the supported range."
		if not c.get("double_slit", false) is bool:
			return "Invalid slit mode."
	if not data.get("boundary_reflects", false) is bool or not data.get("emitting", true) is bool:
		return "Invalid simulation settings."
	return ""

func save_layout() -> void:
	var file := FileAccess.open("user://optical_table.json", FileAccess.WRITE)
	if file == null:
		notice.emit("Could not save the table: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(snapshot(), "\t"))
	dirty = false
	notice.emit("Saved optical_table.json in your Godot user-data folder.")

func load_layout() -> void:
	if not FileAccess.file_exists("user://optical_table.json"):
		notice.emit("No saved table yet. Use Save table first.")
		return
	var file := FileAccess.open("user://optical_table.json", FileAccess.READ)
	if file == null or file.get_length() > 262144:
		notice.emit("Could not read layout, or file exceeds 256 KB.")
		return
	var data: Variant = JSON.parse_string(file.get_as_text())
	var error := validate_snapshot(data)
	if not error.is_empty():
		notice.emit(error)
		return
	remember()
	components = data.components.duplicate(true)
	for c in components:
		c["double_slit"] = c.get("double_slit", false)
	preset = clampi(int(data.get("preset", 0)), 0, Library.TITLES.size() - 1)
	boundary_reflects = data.get("boundary_reflects", false)
	solver.emitting = data.get("emitting", true)
	solver.pulsing = false
	selected = -1
	apply_layout(true)
	selection_changed.emit()
	notice.emit("Table loaded. Waves restarted from rest.")

func export_measurements() -> void:
	var stem := "user://measurement_%s" % Time.get_datetime_string_from_system().replace(":", "-")
	var file := FileAccess.open(stem + ".json", FileAccess.WRITE)
	if file == null:
		notice.emit("Could not export measurements.")
		return
	var data := snapshot()
	data["notes"] = "Detector values: local exponential mean of field squared, arbitrary units. Trace starts after last layout edit; initial wave state is not saved."
	data["samples"] = traces
	data["last_tick"] = solver.tick
	file.store_string(JSON.stringify(data, "\t"))
	var csv := FileAccess.open(stem + ".csv", FileAccess.WRITE)
	if csv == null:
		notice.emit("JSON saved; could not write CSV.")
		return
	csv.store_csv_line(PackedStringArray(["tick", "detector_component", "red", "green", "blue"]))
	for sample in traces:
		for d in sample.detectors:
			csv.store_csv_line(PackedStringArray([str(sample.tick), str(d.component), str(d.r), str(d.g), str(d.b)]))
	notice.emit("Exported detector CSV + layout/measurement JSON to the user-data folder.")
