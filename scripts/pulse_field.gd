extends Control
const Model = preload("res://scripts/pulse_model.gd")
const Plot = preload("res://scripts/pulse_plot.gd")
const W := 80
const H := 50
var model: PulseModel
var weights: Array[PackedFloat64Array] = []
var pixels := Image.create(W, H, false, Image.FORMAT_RGBA8)
var texture: ImageTexture

func _ready() -> void:
	for y in range(H):
		for x in range(W):
			weights.append(Model.field_weights(Vector2(float(x) / (W - 1), float(y) / (H - 1))))
	texture = ImageTexture.create_from_image(pixels)
	refresh()

func refresh() -> void:
	if not is_instance_valid(model) or weights.is_empty():
		return
	for y in range(H):
		for x in range(W):
			var field := model.field_from_weights(weights[y * W + x])
			var strength := 1.0 - exp(-5.0 * field.length_squared())
			var color := Color.from_hsv(fposmod(field.angle() / TAU + 0.5, 1.0), 0.64, 1.0)
			pixels.set_pixel(x, y, Color("08131d").lerp(color, strength))
	texture.update(pixels)
	queue_redraw()

func _draw() -> void:
	if not is_instance_valid(model) or texture == null:
		return
	var aspect: float = model.config.aspect
	var extent := Vector2(minf(size.x - 10, (size.y - 10) * aspect), minf(size.y - 10, (size.x - 10) / aspect))
	var rect := Rect2((size - extent) * 0.5, extent)
	draw_texture_rect(texture, rect, false)
	draw_rect(rect, Color("527483"), false, 1)
	var source := rect.position + Model.SOURCE * rect.size
	draw_circle(source, 6, Color.WHITE, false, 2)
	draw_string(ThemeDB.fallback_font, source + Vector2(10, 4), "IN", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
	for j in range(Model.PROBES.size()):
		var point: Vector2 = rect.position + Model.PROBES[j] * rect.size
		draw_circle(point, 5, Plot.COLORS[j])
		if model.recovery[j] > 0:
			draw_circle(point, 10, Plot.COLORS[j], false, 2)
		draw_string(ThemeDB.fallback_font, point + Vector2(8, -6), str(j + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
