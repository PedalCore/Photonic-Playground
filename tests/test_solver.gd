extends SceneTree

const Solver = preload("res://scripts/wave_solver.gd")
const Library = preload("res://scripts/experiments.gd")
const Table = preload("res://scripts/optical_table.gd")
var failures: int = 0

func check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: ", message)
	else:
		push_error("FAIL: " + message)
		failures += 1

func _initialize() -> void:
	var zero = Solver.new(48, 40)
	zero.step(12)
	check(zero.total_energy() == 0.0, "rest remains rest")
	var src := Library.component("source", 24, 20, 0, 0)
	src.band = 1
	var one = Solver.new(48, 40)
	one.configure([src])
	one.step(160)
	check(one.total_energy() > 0.01, "source propagates measurable energy")
	var red_blue := 0.0
	for i in range(48 * 40):
		red_blue += absf(one.field[i * 3]) + absf(one.field[i * 3 + 2])
	check(red_blue == 0.0, "independent spectral bands do not mix")
	var symmetry := 0.0
	for x in range(1, 12):
		symmetry = maxf(symmetry, absf(one.field[(20 * 48 + 24 - x) * 3 + 1] - one.field[(20 * 48 + 24 + x) * 3 + 1]))
	check(symmetry < 0.015, "point source spreads symmetrically before significant boundary effects")
	var phase_inverse := src.duplicate(true)
	phase_inverse.phase = 180.0
	var cancellation = Solver.new(48, 40)
	cancellation.configure([src, phase_inverse])
	cancellation.step(160)
	check(cancellation.total_energy() < one.total_energy() * 0.00001, "opposite coherent phases destructively interfere")
	var addition = Solver.new(48, 40)
	addition.configure([src, src.duplicate(true)])
	addition.step(160)
	check(absf(addition.total_energy() / one.total_energy() - 4.0) < 0.01, "coherent amplitude addition gives four times mean-square field")
	var barrier = Solver.new(48, 40)
	var wall := Library.component("mirror", 30, 20, 0, 40)
	barrier.configure([src, wall])
	barrier.step(160)
	var behind := 0.0
	for y in range(40):
		for x in range(32, 47):
			behind += barrier.energy[(y * 48 + x) * 3 + 1]
	check(behind == 0.0, "closed reflective barrier blocks transmission")
	var glass = Solver.new(48, 40)
	var slab := Library.component("glass", 24, 20, 0, 20)
	slab.index = 1.5
	slab.dispersion = 0.1
	glass.configure([slab])
	var center := (20 * 48 + 24) * 3
	check(absf(glass.speed_squared[center] - pow(Solver.SPEED / 1.5, 2)) < 0.000001, "refractive index changes wave speed")
	check(glass.speed_squared[center + 2] < glass.speed_squared[center], "dispersion changes speed independently by band")
	one.emitting = false
	var initial_energy: float = one.total_energy()
	one.step(600)
	check(one.total_energy() < initial_energy * 0.15, "absorbing edges and damping dissipate old waves")
	var replay = Solver.new(48, 40)
	replay.configure([src])
	replay.step(160)
	var replay2 = Solver.new(48, 40)
	replay2.configure([src])
	replay2.step(80)
	replay2.step(80)
	check(replay.field == replay2.field, "replay depends on simulation steps, not frame batching")
	for i in range(5):
		var model = Solver.new()
		model.configure(Library.layout(i))
		model.step(250)
		var finite := true
		var largest := 0.0
		for v in model.field:
			finite = finite and is_finite(v)
			largest = maxf(largest, absf(v))
		check(finite and largest < 20, "preset %d stays finite and bounded" % i)
		var data := {"schema_version": 1, "model": "scalar-wave-v1", "grid": [192, 112], "components": Library.layout(i)}
		var round_trip_error := Table.validate_snapshot(JSON.parse_string(JSON.stringify(data)))
		check(round_trip_error.is_empty(), "preset %d survives JSON round trip: %s" % [i, round_trip_error])
	var invalid := {"schema_version": 1, "model": "scalar-wave-v1", "grid": [192, 112], "components": [src.duplicate(true)]}
	invalid.components[0].index = 0.1
	check(not Table.validate_snapshot(invalid).is_empty(), "unsafe material parameters rejected")
	print("SOLVER TESTS: ", "PASS" if failures == 0 else str(failures) + " failures")
	quit(0 if failures == 0 else 1)
