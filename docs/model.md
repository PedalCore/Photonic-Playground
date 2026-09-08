# Scalar wave model v1

## Update rule and units

Each colour band evolves independently on the same Cartesian grid. We use
dimensionless grid spacing dx = 1 and simulation time step dt = 1:

`u_next = (2 - gamma) u - (1 - gamma) u_previous + (c / n)^2 laplacian(u)`

The Laplacian is the standard five-point stencil. `c = 0.45` cells/step, below
the uniform 2D Courant limit `1/sqrt(2)`. All supported refractive indices are at
least 1. Source base wavelengths are 18, 14 and 11 grid cells (red, green, blue
display channels). A common source wavelength scale is adjustable from 0.8 to 2.

The grid is coarse. Large index and short wavelength settings have appreciable
numerical dispersion: satisfying the stability bound is not evidence of accuracy.
Do convergence studies with finer grids before interpreting device performance.

## Sources and media

- Sources add a tapered sinusoidal forcing to a point or finite line. Sources in
  one band are coherent by construction. A line emits to both sides.
- A pulsed source uses a Gaussian temporal envelope centered at 35 steps, with
  width parameter 13. The pulse operation is shared across all current sources.
- Glass uses a local refractive index. For channel b, `n_b = index + b*dispersion`.
  This is an illustrative dispersion law, not a fitted optical material.
- Mirrors and grating bars hold the field at zero; energy is reflected with a
  phase inversion. Grating openings are gaps in that boundary.
- The outermost cells are fixed. Unless reflective edges are selected, a 12-cell
  sponge damps outgoing waves before they reach the edge. Some residual boundary
  reflection is expected; this is not a perfectly matched layer.
- A small damping term is present everywhere, including reflective-edge mode.

Overlapping solids remain solid. When glass objects overlap, the later object
sets the local index. Placing a wall zeros the field inside its cells. Other edits
retain the current field, so time-dependent geometry can add/remove energy. Reset
before comparing static layouts quantitatively.

## Readouts

At every step `E = 0.975*E + 0.025*u*u`. A detector reports the mean of E along
its sampled line. This is an intensity-like local observable, not energy flux:
it does not account for propagation direction or the electromagnetic Poynting
vector. Display brightness does not change detector readings. The thin graph next
to a detector displays its spatial E profile; exported samples are its line mean.

Independent frequency bands are combined for display only. There is no
cross-frequency interference, four-wave mixing or frequency conversion.

## What to try next

1. Playtest whether moving components and reading wave patterns is enjoyable.
2. Add saved A/B comparisons with equal step counts and a complete input/event log.
3. Establish convergence and energy accounting against analytic slit/interface cases.
4. Implement a GPU version of the same solver and compare it against CPU fixtures.
5. Add beam splitters/phase masks with explicit, tested semantics.
6. Try a delayed-signal task with a fitted readout; add a nonlinear element only
   when its physical approximation and gameplay purpose are clear.
7. Validate candidate optical designs with a suitable electromagnetic solver.

## Research and implementation references

- [Programmable photonic processor](https://www.nature.com/articles/s41467-024-45888-7): interference along programmable optical paths.
- [Diffractive optical computing](https://arxiv.org/abs/1804.08711): passive diffractive layers designed for optical transformations.
- [Photonic reservoir wave dynamics](https://www.nature.com/articles/s41598-019-55247-y): inspiration for nonlinear cavity models. Our [research bench](../research/README.md) now trains an electronic readout of the passive scalar wave history; it does not implement this paper's nonlinear gain medium.
- [Meep introduction](https://meep.readthedocs.io/en/latest/Introduction/): electromagnetic FDTD and a possible validation route. The current model is not Meep.
- [Godot ImageTexture](https://docs.godotengine.org/en/4.4/classes/class_imagetexture.html): dynamic field textures.
