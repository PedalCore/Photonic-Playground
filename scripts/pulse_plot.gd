extends Control
## Native trace plot: no decorative or precomputed simulation data.
var pair: Dictionary = {}
var rows: Array = []
var spikes: Array = []
var pulses: Array = []
var duration := 7.6
const COLORS := [Color("80e0cb"), Color("f5bd77"), Color("afa5ff"), Color("eb89ae"), Color("82b8fb"), Color("d2db89")]

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var rect := Rect2(42, 22, maxf(10, size.x - 58), maxf(10, size.y - 48))
	draw_style_box(_background(), Rect2(Vector2.ZERO, size))
	var is_pair := not pair.is_empty()
	var trace: Array = pair.rows if is_pair else rows
	var end := 4.0 if is_pair else duration
	var lo := -1.1 if is_pair else 0.0
	var hi := 2.1 if is_pair else 0.05
	if not is_pair:
		for row in trace:
			for j in range(1, row.size()):
				hi = maxf(hi, float(row[j]) * 1.08)
	var plot_height := rect.size.y if is_pair else rect.size.y * 0.66
	for k in range(5):
		var x := rect.position.x + rect.size.x * k / 4.0
		draw_line(Vector2(x, rect.position.y), Vector2(x, rect.end.y), Color("233642"))
		draw_string(font, Vector2(x - 5, size.y - 9), "%.1f" % (end * k / 4.0), HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8b9ea9"))
	draw_string(font, Vector2(5, 14), "state" if is_pair else "power", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8b9ea9"))
	draw_string(font, Vector2(size.x - 52, size.y - 9), "t / T₀", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color("8b9ea9"))
	draw_string(font, Vector2(3, 33), "%.2f" % hi, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("8b9ea9"))
	var input: Array = pair.pulses if is_pair else pulses
	for t in input:
		var x: float = rect.position.x + rect.size.x * t / end
		draw_line(Vector2(x, 8), Vector2(x, 19), Color.WHITE, 2)
	if is_pair:
		for level in [0.0, float(pair.threshold)]:
			var y: float = rect.position.y + (hi - level) / (hi - lo) * plot_height
			draw_dashed_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color("657787"), 1, 4)
		var ty: float = rect.position.y + (hi - float(pair.threshold)) / (hi - lo) * plot_height
		draw_string(font, Vector2(rect.end.x - 87, ty - 5), "threshold 1.4", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("9daeb8"))
	var count := 2 if is_pair else 6
	for j in range(count):
		var points := PackedVector2Array()
		for row in trace:
			points.append(Vector2(rect.position.x + float(row[0]) / end * rect.size.x, rect.position.y + (hi - float(row[j + 1])) / (hi - lo) * plot_height))
		if points.size() > 1:
			draw_polyline(points, COLORS[j], 1.5, true)
	if not is_pair:
		var raster_y := rect.position.y + plot_height + 13
		var spacing := maxf(3, (rect.end.y - raster_y) / 6.0)
		for j in range(6):
			var y := raster_y + j * spacing
			draw_string(font, Vector2(21, y + 3), str(j + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 9, COLORS[j])
			draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), Color("1d2d38"))
		for event in spikes:
			var x: float = rect.position.x + event[0] / end * rect.size.x
			var y: float = raster_y + event[1] * spacing
			draw_line(Vector2(x, y - 3), Vector2(x, y + 3), COLORS[int(event[1])], 2)

func _background() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color("08131d")
	style.set_corner_radius_all(6)
	return style
