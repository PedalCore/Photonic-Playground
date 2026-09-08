class_name PulseModel
extends RefCounted
## Eight damped standing-wave modes plus six optoelectronic threshold/reset nodes.
## Reduced, dimensionless model; not a Maxwell-Bloch laser or calibrated device.

const MODES := [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(3, 1),
	Vector2i(2, 2), Vector2i(1, 3), Vector2i(3, 2), Vector2i(2, 3)]
const PROBES := [Vector2(0.25, 0.25), Vector2(0.50, 0.22), Vector2(0.75, 0.30),
	Vector2(0.28, 0.73), Vector2(0.53, 0.70), Vector2(0.77, 0.76)]
const DT := 0.025
const END_TIME := 7.6
const BINS := 8
const SOURCE := Vector2(0.20, 0.47)
var config: Dictionary
var modes: Array[Vector2] = []
var rotations: Array[Vector2] = []
var source_weights := PackedFloat64Array()
var probe_weights: Array[PackedFloat64Array] = []
var charge := PackedFloat64Array()
var recovery := PackedFloat64Array()
var power := PackedFloat64Array()
var leaky := PackedFloat64Array()
var passive_leaky := PackedFloat64Array()
var leaky_decay := PackedFloat64Array()
var spike_bins := PackedFloat64Array()
var power_bins := PackedFloat64Array()
var lif_bins := PackedFloat64Array()
var bin_counts := PackedFloat64Array()
var spikes: Array = []
var lif_spikes: Array = []
var time: float = 0.0
var tick: int = 0
var pulse_times: Array = []
var next_pulse: int = 0
var failed: bool = false
var feedback_enabled: bool
var node_decay: float
var mode_decay: float

static func defaults() -> Dictionary:
	return {"tau": 1.8, "aspect": 1.6, "threshold": 0.18, "refractory": 0.30,
		"feedback": 0.15, "jitter": 0.20, "seed": 42, "task": 0}

static func basis(point: Vector2) -> PackedFloat64Array:
	var values := PackedFloat64Array()
	for mode in MODES:
		values.append(sin(PI * mode.x * point.x) * sin(PI * mode.y * point.y))
	return values

static func normalized(values: PackedFloat64Array) -> PackedFloat64Array:
	var out := values.duplicate()
	var norm := 0.0
	for v in out:
		norm += v * v
	norm = sqrt(maxf(norm, 1e-12))
	for i in range(out.size()):
		out[i] /= norm
	return out

func _init(settings: Dictionary = {}, active_feedback: bool = false) -> void:
	config = defaults()
	config.merge(settings, true)
	feedback_enabled = active_feedback
	mode_decay = exp(-DT / float(config.tau))
	node_decay = exp(-DT / 0.25)
	source_weights = normalized(basis(SOURCE))
	var fundamental := sqrt(pow(1.0 / config.aspect, 2) + 1.0)
	for mode in MODES:
		var frequency := sqrt(pow(float(mode.x) / config.aspect, 2) + mode.y * mode.y) / fundamental
		rotations.append(Vector2(cos(TAU * frequency * DT), sin(TAU * frequency * DT)))
		modes.append(Vector2.ZERO)
	for point in PROBES:
		probe_weights.append(field_weights(point))
	charge.resize(PROBES.size())
	recovery.resize(PROBES.size())
	power.resize(PROBES.size())
	leaky.resize(PROBES.size())
	passive_leaky.resize(PROBES.size())
	for i in range(PROBES.size()):
		leaky_decay.append(exp(-DT / (config.tau * (0.55 + i * 0.24))))
	spike_bins.resize(PROBES.size() * BINS)
	power_bins.resize(PROBES.size() * BINS)
	lif_bins.resize(PROBES.size() * BINS)
	bin_counts.resize(BINS)

func reset(times: Array) -> void:
	for i in range(modes.size()):
		modes[i] = Vector2.ZERO
	charge.fill(0.0)
	recovery.fill(0.0)
	power.fill(0.0)
	leaky.fill(0.0)
	passive_leaky.fill(0.0)
	spike_bins.fill(0.0)
	power_bins.fill(0.0)
	lif_bins.fill(0.0)
	bin_counts.fill(0.0)
	spikes.clear()
	lif_spikes.clear()
	pulse_times = times.duplicate()
	next_pulse = 0
	tick = 0
	time = 0
	failed = false

func inject(weights: PackedFloat64Array, amplitude: float = 1.0) -> void:
	for i in range(modes.size()):
		modes[i].x += weights[i] * amplitude

func field_at(point: Vector2) -> Vector2:
	return field_from_weights(field_weights(point))

static func field_weights(point: Vector2) -> PackedFloat64Array:
	var values := basis(point)
	for i in range(values.size()):
		values[i] *= 0.5
	return values

func field_from_weights(weights: PackedFloat64Array) -> Vector2:
	var value := Vector2.ZERO
	for i in range(modes.size()):
		value += modes[i] * weights[i]
	return value

func step() -> void:
	if failed:
		return
	tick += 1
	time = tick * DT
	var bin := clampi(int(time / END_TIME * BINS), 0, BINS - 1)
	# Exact damped rotations between input/feedback events; source times round up
	# to the next DT boundary, recorded explicitly in the exported protocol.
	for i in range(modes.size()):
		var a := modes[i]
		var r := rotations[i]
		modes[i] = Vector2(a.x * r.x - a.y * r.y, a.x * r.y + a.y * r.x) * mode_decay
	for j in range(PROBES.size()):
		leaky[j] *= leaky_decay[j]
		passive_leaky[j] *= leaky_decay[j]
	while next_pulse < pulse_times.size() and pulse_times[next_pulse] <= time + 1e-9:
		inject(source_weights)
		for j in range(PROBES.size()):
			leaky[j] += 1.0
			passive_leaky[j] += 1.0
		next_pulse += 1
	var firing: Array[int] = []
	for j in range(PROBES.size()):
		power[j] = field_from_weights(probe_weights[j]).length_squared()
		power_bins[j * BINS + bin] += power[j]
		if leaky[j] >= 1.4:
			lif_bins[j * BINS + bin] += 1
			lif_spikes.append([time, j])
			leaky[j] = 0
		recovery[j] = maxf(0.0, recovery[j] - DT)
		if recovery[j] > 0:
			charge[j] = 0
		else:
			charge[j] = node_decay * charge[j] + (1.0 - node_decay) * 12.0 * power[j]
			if charge[j] >= config.threshold:
				firing.append(j)
				spikes.append([time, j])
				spike_bins[j * BINS + bin] += 1
				charge[j] = 0
				recovery[j] = config.refractory
	# Simultaneous feedback: all nodes observe the same pre-feedback field.
	# Each emitted kick is supplied by an external pump; it is not free energy.
	if feedback_enabled:
		for j in firing:
			inject(normalized(probe_weights[j]), config.feedback)
	bin_counts[bin] += 1
	for a in modes:
		if not a.is_finite() or a.length_squared() > 10000:
			failed = true

func features() -> Dictionary:
	var average := power_bins.duplicate()
	var counts := PackedFloat64Array()
	counts.resize(PROBES.size())
	for j in range(PROBES.size()):
		for b in range(BINS):
			average[j * BINS + b] /= maxf(1.0, bin_counts[b])
			counts[j] += spike_bins[j * BINS + b]
	return {"power_bins": average, "spike_bins": spike_bins.duplicate(), "spike_counts": counts,
		"final_power": power.duplicate(), "leaky_state": passive_leaky.duplicate(), "lif_bins": lif_bins.duplicate()}

static func pair_response(gap: float, tau: float = 1.8, threshold: float = 1.4, reset_on_spike: bool = true) -> Dictionary:
	var rows: Array = []
	var events := {"integrator": [], "resonator": []}
	var v := 0.0
	var z := Vector2.ZERO
	var dt := 0.005
	var d := exp(-dt / tau)
	var c := cos(TAU * dt)
	var s := sin(TAU * dt)
	for i in range(801):
		var t := i * dt
		v *= d
		z = Vector2(z.x * c - z.y * s, z.x * s + z.y * c) * d
		if i == 50 or i == roundi((0.25 + gap) / dt):
			v += 1
			z.x += 1
		rows.append([t, v, z.x])
		if reset_on_spike:
			if v >= threshold:
				events.integrator.append(t)
				v = 0
			if z.x >= threshold:
				events.resonator.append(t)
				z = Vector2.ZERO
	return {"rows": rows, "events": events, "pulses": [0.25, 0.25 + gap], "threshold": threshold}
