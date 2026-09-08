class_name Experiments
extends RefCounted

const TITLES := ["Wave garden", "Double slit", "Prism study", "Echo chamber", "Light the target"]
const NOTES := [
	"Two coherent sources. Move one or change its phase to reshape the bright and dark bands.",
	"A wave meets two openings. Change the slit separation, then watch the detector profile.",
	"Three frequency bands enter glass. Rotate the prism and change its refractive index.",
	"A pulse in a reflective enclosure. Watch the echoes overlap, then open a route out.",
	"Use mirrors and glass to carry light around the barrier to the target. Experiment freely."
]

static func component(kind: String, x: float, y: float, angle: float = 0.0, span: float = 24.0) -> Dictionary:
	return {"kind": kind, "x": x, "y": y, "angle": angle, "size": span,
		"index": 1.45, "dispersion": 0.12 if kind == "prism" else 0.0,
		"phase": 0.0, "band": 3, "wavelength": 1.0,
		"spacing": 14.0, "slit_width": 4.0, "double_slit": false}

static func layout(preset: int) -> Array:
	var objects: Array = []
	match preset:
		0:
			var a := component("source", 46, 40, 0, 0)
			a.band = 1
			var b := component("source", 46, 72, 0, 0)
			b.band = 1
			objects = [a, b, component("detector", 149, 56, 0, 66)]
		1:
			var source := component("source", 24, 56, 0, 78)
			source.band = 1
			var slits := component("grating", 62, 56, 0, 110)
			slits.double_slit = true
			slits.spacing = 25.0
			objects = [source, slits, component("detector", 155, 56, 0, 84)]
		2:
			objects = [component("source", 26, 56, 0, 34), component("prism", 87, 56, 0, 65), component("detector", 155, 56, 0, 80)]
		3:
			var source := component("source", 72, 55, 0, 0)
			source.band = 2
			objects = [source, component("mirror", 43, 56, 0, 70), component("mirror", 130, 56, 0, 70),
				component("mirror", 86, 21, 90, 88), component("mirror", 86, 91, 90, 88), component("detector", 106, 56, 0, 18)]
		4:
			var source := component("source", 32, 77, 0, 6)
			source.band = 1
			var goal := component("detector", 151, 77, 0, 14)
			goal["target"] = true
			objects = [source, component("mirror", 95, 74, 0, 70), goal,
				component("mirror", 49, 26, -35, 24), component("mirror", 144, 28, 35, 24)]
	return objects

