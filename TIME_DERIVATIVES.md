# Pressure Time Derivatives (4th-order centered)

## What this adds

Two new diagnostic fields written alongside the existing pressure snapshots:

- `dpdt`   — first time derivative of pressure
- `d2pdt2` — second time derivative of pressure

Both are computed with the standard 4th-order accurate, 5-point centered
stencil:

```
dp/dt   |_n = ( -p_{n+2} + 8 p_{n+1} - 8 p_{n-1} + p_{n-2} ) / (12 dt)
d2p/dt2 |_n = ( -p_{n+2} + 16 p_{n+1} - 30 p_n + 16 p_{n-1} - p_{n-2} ) / (12 dt^2)
```

where `dt` here is the **snapshot spacing** `ioutput * dt_sim`, not the
solver time step.

## Why 5 snapshots

A centered, 4th-order accurate finite-difference stencil for either the
1st or 2nd derivative requires 5 sample points (offsets {-2, -1, 0, +1, +2}).
This means:

- The buffer must hold 5 consecutive pressure snapshots simultaneously.
- The derivative is valid at the **center** of that window, so each output
  is **lagged by 2 snapshots** relative to wall-clock simulation time.
- No output is produced for the first 4 snapshots (warm-up).

## Files changed

| File | Change |
|------|--------|
| `src/time_derivatives.f90` | **New** module implementing the buffer, stencil, and writes |
| `src/visu.f90` | Calls `tderiv_push_pressure` inside `write_snapshot`; registers `dpdt` / `d2pdt2` ADIOS2 variables in `visu_init` |
| `src/xcompact3d.f90` | Calls `tderiv_init` after `visu_ready()` and `tderiv_finalise` after `visu_finalise()` |
| `src/CMakeLists.txt` | Adds `time_derivatives.f90` to the executable source list |

## How it plugs in

`tderiv_push_pressure(p1, itime, ioutput*dt)` is invoked once per
snapshot, right after `rescale_pressure(ta1)` and before the existing
`pp` write. Internally:

1. Shift-buffer of 5 slots: drop oldest, slide everything down, put the
   new pressure in slot 5.
2. Same shift for the iteration tags `itag(1..5)`.
3. Until 5 snapshots have been collected, return without writing.
4. Once full: apply both stencils (whole-array Fortran), tag the output
   with `itag(3)` (the center of the window), coarsen via
   `fine_to_coarseV`, and write through `decomp_2d_write_one` on the
   existing `"solution-io"` ADIOS2 channel.

Output cadence therefore matches the snapshot cadence (`ioutput`).
Output filenames follow the same convention as `pp`: `dpdt<NNNN>` and
`d2pdt2<NNNN>` inside `data/` (BP5 archive when ADIOS2 is enabled).

## Verification

Tested with the Taylor-Green Vortex case at 33^3, `ilast=300`,
`ioutput=50` (6 snapshots -> 2 derivative outputs at iterations 150 and
200). Recomputing both stencils in Python from the stored `pp` series
matched the on-disk `dpdt` and `d2pdt2` **bit-exactly** (max difference
= 0.000e+00) for all four outputs.

## Reading the output

```bash
bpls data.bp5                       # list variables / steps
bpls -d data.bp5 dpdt                # dump dpdt
```

Or with the Python adios2 module:

```python
import adios2, numpy as np
with adios2.Stream("data.bp5", "r") as f:
    arrs = []
    for _ in f.steps():
        arrs.append(f.read("dpdt"))
dpdt = np.stack(arrs)               # shape: (nsteps, nx, ny, nz)
```

## Caveats / design notes

- The buffer holds full-resolution x-pencil arrays (no downsampling
  before the stencil), so peak memory scales as 5x a single pressure
  field per rank. This was an explicit choice for simplicity.
- The shift uses 4 full array copies per call. Fine for diagnostics;
  could be replaced with a circular index if performance ever matters.
- `io_name = "solution-io"` is hardcoded inside the routine rather than
  imported from `visu`, to avoid a circular module dependency
  (`visu` already uses `time_derivatives`).
- Δt passed to the stencil is `ioutput * dt`. If `ioutput` or `dt`
  changes mid-run, the stored derivative will be wrong for the snapshots
  that straddle the change.
