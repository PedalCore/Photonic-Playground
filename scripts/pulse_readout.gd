class_name PulseReadout
extends RefCounted
## Ridge regression with training-only standardization and an unpenalized bias.

var mean := PackedFloat64Array()
var scale := PackedFloat64Array()
var weights := PackedFloat64Array()
var bias: float = 0.0

func fit(rows: Array, labels: Array, regularization: float) -> void:
	var n := rows.size()
	var p: int = rows[0].size()
	mean.resize(p)
	scale.resize(p)
	mean.fill(0)
	scale.fill(0)
	bias = 0
	for k in range(n):
		bias += float(labels[k]) / n
		for j in range(p):
			mean[j] += rows[k][j] / n
	for row in rows:
		for j in range(p):
			scale[j] += pow(row[j] - mean[j], 2) / n
	for j in range(p):
		scale[j] = maxf(sqrt(scale[j]), 1e-9)
	var gram := PackedFloat64Array()
	gram.resize(p * p)
	var rhs := PackedFloat64Array()
	rhs.resize(p)
	for k in range(n):
		var x := PackedFloat64Array()
		x.resize(p)
		for j in range(p):
			x[j] = (rows[k][j] - mean[j]) / scale[j]
		for i in range(p):
			rhs[i] += x[i] * (labels[k] - bias) / n
			for j in range(i + 1):
				gram[i * p + j] += x[i] * x[j] / n
	# Cholesky: positive regularization makes the normalized Gram matrix SPD.
	var lower := PackedFloat64Array()
	lower.resize(p * p)
	for i in range(p):
		for j in range(i + 1):
			var v: float = gram[i * p + j] + (regularization if i == j else 0.0)
			for k in range(j):
				v -= lower[i * p + k] * lower[j * p + k]
			lower[i * p + j] = sqrt(maxf(v, 1e-15)) if i == j else v / lower[j * p + j]
	var intermediate := PackedFloat64Array()
	intermediate.resize(p)
	for i in range(p):
		var v := rhs[i]
		for k in range(i):
			v -= lower[i * p + k] * intermediate[k]
		intermediate[i] = v / lower[i * p + i]
	weights.resize(p)
	for i in range(p - 1, -1, -1):
		var v := intermediate[i]
		for k in range(i + 1, p):
			v -= lower[k * p + i] * weights[k]
		weights[i] = v / lower[i * p + i]

func predict(row) -> float:
	var value := bias
	for j in range(weights.size()):
		value += weights[j] * (row[j] - mean[j]) / scale[j]
	return value

func snapshot() -> Dictionary:
	return {"mean": Array(mean), "scale": Array(scale), "weights": Array(weights), "bias": bias}
