class_name WaveSolver
extends RefCounted
## Dimensionless, linear scalar waves. RGB are independent frequency bands.
## u_next = (2 - gamma)u - (1 - gamma)u_old + (c/n)^2 laplacian(u).
## dt = dx = 1; c = 0.45 < 1/sqrt(2), including all permitted media.

const SPEED: float = 0.45
const BASE_WAVELENGTHS := Vector3(18.0, 14.0, 11.0)
var width: int
var height: int
var field := PackedFloat32Array()
var previous := PackedFloat32Array()
var scratch := PackedFloat32Array()
var energy := PackedFloat32Array()
var speed_squared := PackedFloat32Array()
var damping := PackedFloat32Array()
var walls := PackedByteArray()
var sources: Array[Dictionary] = []
var tick: int = 0
var emitting: bool = true
var pulsing: bool = false
var pulse_start: int = 0
var boundary_reflects: bool = false

func _init(w: int = 192, h: int = 112) -> void:
	width = w
	height = h
	# Packed arrays use copy-on-write, so resize members explicitly.
	field.resize(w * h * 3)
	previous.resize(w * h * 3)
	scratch.resize(w * h * 3)
	energy.resize(w * h * 3)
	speed_squared.resize(w * h * 3)
	damping.resize(w * h)
	walls.resize(w * h)
	configure([])

func reset() -> void:
	field.fill(0.0)
	previous.fill(0.0)
	scratch.fill(0.0)
	energy.fill(0.0)
	tick = 0
	pulse_start = 0
	pulsing = false

func pulse() -> void:
	pulsing = true
	pulse_start = tick

static func local_point(component: Dictionary, point: Vector2) -> Vector2:
	return (point - Vector2(component.x, component.y)).rotated(-deg_to_rad(component.angle))

static func triangle(component: Dictionary) -> PackedVector2Array:
	var s: float = component.size
	return PackedVector2Array([Vector2(-s * 0.52, -s * 0.55), Vector2(-s * 0.52, s * 0.55), Vector2(s * 0.58, 0)])

static func contains(component: Dictionary, point: Vector2, extra: float = 0.0) -> bool:
	var p := local_point(component, point)
	var half: float = component.size * 0.5
	match component.kind:
		"mirror", "grating":
			return absf(p.x) <= 1.0 + extra and absf(p.y) <= half + extra
		"glass":
			return absf(p.x) <= half * 0.55 + extra and absf(p.y) <= half + extra
		"prism":
			return Geometry2D.is_point_in_polygon(p, triangle(component))
		"source":
			return absf(p.x) < 2.0 + extra and absf(p.y) < maxf(2.0, half) + extra
		"detector":
			return absf(p.x) <= 2.0 + extra and absf(p.y) <= half + extra
	return false

func configure(components: Array) -> void:
	sources.clear()
	walls.fill(0)
	speed_squared.fill(SPEED * SPEED)
	for y in range(height):
		for x in range(width):
			var i := y * width + x
			var edge := mini(mini(x, width - 1 - x), mini(y, height - 1 - y))
			# Smooth sponge: absorbs outgoing waves; outermost edge stays fixed.
			damping[i] = 0.0006 if boundary_reflects else 0.0006 + 0.13 * pow(maxf(0.0, (12.0 - edge) / 12.0), 2.0)
			if edge == 0:
				walls[i] = 1
	for component in components:
		if component.kind == "source":
			var samples: Array[int] = []
			var weights: Array[float] = []
			var seen := {}
			var half: int = maxi(0, roundi(component.size * 0.5))
			for a in range(-half, half + 1):
				var pos := Vector2(component.x, component.y) + Vector2(0, a).rotated(deg_to_rad(component.angle))
				var x := clampi(roundi(pos.x), 1, width - 2)
				var y := clampi(roundi(pos.y), 1, height - 2)
				var idx := y * width + x
				if not seen.has(idx):
					seen[idx] = true
					samples.append(idx)
					weights.append(1.0 if half <= 1 else 0.5 + 0.5 * cos(PI * float(a) / (half + 1)))
			sources.append({"component": component.duplicate(true), "samples": samples, "weights": weights})
			continue
		if component.kind == "detector":
			continue
		var extent: float = component.size + 3.0
		for y in range(maxi(1, int(component.y - extent)), mini(height - 1, int(component.y + extent + 1))):
			for x in range(maxi(1, int(component.x - extent)), mini(width - 1, int(component.x + extent + 1))):
				var point := Vector2(x, y)
				if not contains(component, point):
					continue
				var i := y * width + x
				if component.kind == "mirror":
					walls[i] = 1
				elif component.kind == "grating":
					var ly := local_point(component, point).y
					# Two slit centres for the interference preset, periodic slits otherwise.
					var open_slit: bool
					if component.get("double_slit", false):
						open_slit = absf(absf(ly) - component.spacing * 0.5) < component.slit_width * 0.5
					else:
						open_slit = absf(fposmod(ly + component.spacing * 0.5, component.spacing) - component.spacing * 0.5) < component.slit_width * 0.5
					if not open_slit:
						walls[i] = 1
				else:
					var n: float = component.index
					var dispersion: float = component.get("dispersion", 0.0)
					for band in range(3):
						speed_squared[i * 3 + band] = pow(SPEED / (n + dispersion * band), 2)
	# A newly placed wall must never retain an old oscillation.
	for i in range(walls.size()):
		if walls[i]:
			for b in range(3):
				field[i * 3 + b] = 0.0
				previous[i * 3 + b] = 0.0
				energy[i * 3 + b] = 0.0

func step(count: int = 1) -> void:
	var stride := width * 3
	for iteration in range(count):
		for y in range(1, height - 1):
			for x in range(1, width - 1):
				var cell := y * width + x
				var j := cell * 3
				if walls[cell]:
					scratch[j] = 0.0
					scratch[j + 1] = 0.0
					scratch[j + 2] = 0.0
					continue
				var d := damping[cell]
				for b in range(3):
					var i := j + b
					var u := field[i]
					var lap := field[i - 3] + field[i + 3] + field[i - stride] + field[i + stride] - 4.0 * u
					scratch[i] = (2.0 - d) * u - (1.0 - d) * previous[i] + speed_squared[i] * lap
					energy[i] = energy[i] * 0.975 + u * u * 0.025
		if emitting or pulsing:
			var age := float(tick - pulse_start)
			var envelope := exp(-pow((age - 35.0) / 13.0, 2.0)) if pulsing else minf(float(tick + 1) / 40.0, 1.0)
			for src in sources:
				var comp: Dictionary = src.component
				for b in range(3):
					if comp.band != 3 and comp.band != b:
						continue
					var omega: float = TAU * SPEED / (BASE_WAVELENGTHS[b] * comp.wavelength)
					var value: float = 0.07 * envelope * sin(omega * tick + deg_to_rad(comp.phase))
					for k in range(src.samples.size()):
						var cell: int = src.samples[k]
						if walls[cell] == 0:
							scratch[cell * 3 + b] += value * src.weights[k]
			if pulsing and age > 90.0:
				pulsing = false
		var old := previous
		previous = field
		field = scratch
		scratch = old
		tick += 1

func detector_reading(component: Dictionary) -> Vector3:
	var result := Vector3.ZERO
	var total: int = 0
	var half: int = maxi(1, roundi(component.size * 0.5))
	for y in range(-half, half + 1):
		var p := Vector2(component.x, component.y) + Vector2(0, y).rotated(deg_to_rad(component.angle))
		var x := clampi(roundi(p.x), 1, width - 2)
		var iy := clampi(roundi(p.y), 1, height - 2)
		var i := (iy * width + x) * 3
		result += Vector3(energy[i], energy[i + 1], energy[i + 2])
		total += 1
	return result / float(total)

func total_energy() -> float:
	var result := 0.0
	for v in energy:
		result += v
	return result
