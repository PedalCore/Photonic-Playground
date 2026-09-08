# Photonic Playground

A native **Godot 4.4+** playground for light-like waves on a little optical table.
Place sources, mirrors, glass, prisms, slit gratings and detectors; move things,
change their properties, and watch the waves respond. No plugins, assets, Python,
or compilation required to play.

## Run it

1. Download or clone this branch of the repository.
2. In Godot's Project Manager, click **Import** and choose `project.godot`.
3. Open the project and press **F5**.

Use the standard Godot editor; the .NET edition also works. The project uses the
Compatibility renderer. The first import generates Godot's normal local cache.

## A first five minutes

- **Wave garden:** watch two green sources interfere. Select one source, change
  its phase, and look at the bright and dark bands moving across the detector.
- **Double slit:** change the opening width and separation. The little trace next
  to the detector shows its spatial intensity profile.
- **Prism study:** three frequency bands enter a dispersive glass triangle. Rotate
  it, change its index, and compare Ripples with Intensity view.
- **Echo chamber:** a short pulse reflects around an enclosure. Remove a wall or
  add glass, then send another pulse.
- **Light the target:** try directing light around the barrier. The target is an
  open experiment with a simple light-level goal, not a scored research benchmark.

The fun to test first: can an unexpected pattern make you want to change one more
thing? These five experiments are editable starting points, not locked levels.

## Controls

| Action | Control |
| --- | --- |
| Choose a tool | Toolbar or keys **1–8** |
| Place a component | Click the table with its tool selected |
| Move a component | **Select** tool, then drag |
| Tune source/material/slits | Select the component; use the right sidebar |
| Rotate selected component | **Q / E** or mouse wheel over the table |
| Duplicate | **Ctrl+D** (Cmd+D on macOS) |
| Remove | Right-click a component, or select and press **Delete** |
| Undo / redo | **Ctrl+Z / Ctrl+Shift+Z** |
| Pause / run | **Space** or transport button |
| Single simulation step | **Step** (also pauses) |
| Short pulse | **Pulse**; turns continuous sources off |
| Clear waves, keep construction | **Reset waves** |
| Save layout | **Save table / Ctrl+S** |
| Exit placement mode | **Esc** |

The source's Size controls the length of its emitter: zero is a point source.
Sources radiate in both directions; they are not one-way ray emitters.
Different sources in the same band share a clock and interfere coherently.
Changing phase or geometry leaves existing waves in place so transitions are
visible. Use Reset waves for a fresh comparison.

**Ripples** shows instantaneous amplitude magnitude with a faint intensity trail.
**Intensity** shows an exponential average of the squared field.
**Signed field** distinguishes positive and negative scalar displacement.
RGB colours represent three independent bands, not a continuous visible spectrum.

## Save, measure, share

**Save table** writes `optical_table.json` in Godot's `user://` folder. **Files**
opens that folder. **Load** restores the geometry and restarts from a zero field.
Layouts are validated before loading. A confirmation protects unsaved constructions
when changing experiments or loading another table.

**Export readings** writes a timestamped CSV and a JSON with the current layout,
model identifier, grid dimensions and detector samples. Values are in arbitrary
units: they measure local mean-square scalar field, not calibrated optical power.
The history is capped at 4,096 samples and clears on an edit or wave reset.

For a clean comparison: finish editing, reset waves, let a chosen number of
simulation steps elapse, pause, export. Export includes the current layout but
does **not** serialize an in-flight wave field or complete edit history. Therefore
an arbitrary edited run cannot yet be reconstructed exactly from that export.

## What's being simulated?

The executable simulation is a **2D linear scalar wave model** on a 192 × 112
grid. It uses a finite-difference wave equation, reflective obstacles, a damped
boundary region, and three independently evolving frequency bands. Their fields
actually interfere and diffract through openings. Material index changes local
propagation speed; a simple band-dependent index produces dispersion.

This is an exploratory game model, **not a Maxwell solver or a validated photonic
device design tool**. There is no polarization, calibrated Fresnel response,
continuous spectrum, nonlinear material, trained reservoir readout, or quantum
state. Grid dispersion and staircase boundaries are visible approximations.
Mirrors impose a zero-field boundary (with a phase inversion). A grating here is
an array of reflective bars and openings, rather than a physical ruled glass optic.

See [the model notes](docs/model.md) for the update rule, assumptions and next steps.

## Performance

Simulation is CPU GDScript; only displaying the field uses a shader. The speed
menu chooses 1, 3 or 6 fixed simulation steps per rendered frame. Lower it if the
table feels sluggish. Simulation time is reported in **steps**, deliberately
independent of wall-clock time or frame rate. Faster GPUs alone will not speed up
this first solver. A GPU solver is a possible next iteration after playtesting.

## Development and checks

```sh
godot --headless --path . --editor --quit
godot --headless --path . --script tests/test_solver.gd
godot --headless --path . -- --smoke
```

The physics checks cover propagation, coherent addition/cancellation, blocked
transmission, damping, deterministic step batching, preset stability, and layout
validation. The scene smoke test exercises all presets, component properties,
duplicate/delete, undo/redo, save/load and measurement export.

| File | Role |
| --- | --- |
| `scripts/wave_solver.gd` | Numerical model; independent of the UI |
| `scripts/experiments.gd` | Components and starting constructions |
| `scripts/optical_table.gd` | Editing, field textures, drawing, measurements and persistence |
| `scripts/main.gd` | Native Godot interface |
| `shaders/wave_display.gdshader` | False-colour field display |

The concept renders that inspired this project were visual studies. This repository
contains the first runnable simulation, with a deliberately simpler 2D table.

