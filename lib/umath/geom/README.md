# geom — umath 2D Geometry

**Module:** `geom/`
**Tier:** 1 (uses `math_fn/` for sin, cos and tan)
**Part of:** umath — unified math library

---

## Overview

`geom` holds the geometry the graphics stack (`lib/ugfx`) needs: 2D affine
transforms and Bezier curves, all in f64. Graphics code keeps no math of its
own and calls these instead.

## Files

| File | Contents |
|---|---|
| `affine2.asm` | 2×3 affine transforms `{a, b, c, d, e, f}`: identity, translate, scale, rotate, skew, multiply (`m1 * m2` applies `m2` first), determinant, invert (fails cleanly on singular or non-finite input), apply to a point, a vector or an array of points |
| `bezier.asm` | Quadratic and cubic Beziers: evaluate, tangent, de Casteljau split, and the segment count that keeps a polyline within a tolerance (Wang's formula, capped at 4096) |

## Conventions

- Points travel as `(x, y)` in `xmm0` / `xmm1`, and are returned the same way
  (a struct of two doubles under the System V ABI).
- Arrays of points are interleaved `x0 y0 x1 y1 ...`.
- In-place use (`out` equal to an input) is allowed for `affine2_multiply`,
  `affine2_invert` and `affine2_apply_array`; the split functions need a
  separate output.

## Tests

`tests/test_geom.py`, run by `tests/run_tests.sh`: transforms against direct
formulas, multiply/invert round trips, singular and non-finite inverses,
curve evaluation against the Bernstein form, split halves retracing the
curve, and polylines from the segment count staying within the tolerance.

## Planned

Rounded rectangles and ellipse geometry, elliptical-arc to cubic conversion,
curve bounds and extrema, closest point and intersection, path measuring
(arc length) and perspective transforms — added as `lib/ugfx` reaches them.
