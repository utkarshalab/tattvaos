# lib/ugfx — Graphics Library

The **`lib/ugfx`** library is the single graphics library of Utkarsha OS: pixel
buffers, compositing, 2D drawing, and later 3D, on one shared core. The Canvas
display server, the icon library, the web engine and applications all draw
through it.

ugfx contains no math of its own. Vectors, matrices, fixed point and curve
evaluation come from [`lib/umath`](../umath/).

---

## 1. Layout

```
lib/ugfx/
├── include/
│   └── ugfx.inc          ← calling-convention macros, error codes, object layouts
├── core/                 ← shared by 2D and 3D
│   ├── pixbuf.asm        ← pixel buffers (premultiplied BGRA)
│   ├── rect.asm          ← rectangle operations
│   ├── region.asm        ← rectangle sets: union, intersect, subtract
│   ├── clip.asm          ← rectangle clipping
│   ├── fill.asm          ← solid fills
│   ├── blit.asm          ← pixel copies
│   ├── blend.asm         ← Porter-Duff compositing (scalar)
│   ├── blend_sse2.asm    ← 4 pixels per iteration
│   ├── blend_avx2.asm    ← 8 pixels per iteration
│   ├── blend_avx512.asm  ← 16 pixels per iteration
│   ├── scale.asm         ← nearest and bilinear scaling
│   ├── transform.asm     ← 90/180/270 rotation and flips
│   ├── raster.asm        ← anti-aliased area-coverage rasterizer (nonzero, even-odd)
│   └── span.asm          ← span compositor: coverage rows into pixels (src-over), one colour or per pixel
└── 2d/                   ← 2D shapes and paths
    ├── line.asm          ← line segments
    ├── circle.asm        ← circles and ellipses
    ├── polygon.asm       ← aliased polygons (assembles; not yet built or tested)
    ├── path.asm          ← paths: lines, quads, cubics, transform, bounds, flattening
    ├── shapes.asm        ← rect, rounded rect, ellipse, circle, arc, pie, ring sector, polygon, star
    ├── stroke.asm        ← stroke outlines: width, miter/round/bevel joins, butt/round/square caps
    ├── flatten.asm       ← curves to polylines; path length
    ├── dash.asm          ← dash patterns along lines and curves
    └── paint.asm         ← paints: solid, linear, radial and conic gradients
```

## 2. Planned

| Area | Contents |
|---|---|
| `core/` | Clip masks and more span operations (gradients, images) for the span compositor; draw-command lists for CPU and GPU backends |
| `2d/` | Device hairlines, image patterns, and the rest of [`docs/COMPONENTS.md`](docs/COMPONENTS.md) |
| `3d/` | Meshes, vertex transform, clipping, triangle setup, depth test, shading, textures |
| `backend/` | CPU (scalar and SIMD) now; GPU later through Canvas's command rings |
| `tests/` | Host-run tests against a reference renderer and golden images |

The work items are tracked as `G2D-*` in [`lib/canvas/docs/ROADMAP.md`](../canvas/docs/ROADMAP.md).

## 3. Rasterizer

`ugfx_raster_init` / `move_to` / `line_to` / `close` / `fill` take edges in
24.8 fixed-point device pixels and composite a solid premultiplied colour
through `ugfx_span_fill_solid`. Coverage is the exact area of the shape in
each pixel (0..255). Where overlapping parts of one shape meet inside a
single pixel, coverage is their accumulated winding area, clamped (nonzero)
or folded (even-odd), as in the classic area rasterizers; an exact-union
mode is roadmap item G2D-15. Coordinates outside the target are handled
(left edges keep carrying cover, the rest is clipped).

Tests: `make host-check` builds `tests/host/host_raster` and runs
`tests/host/raster_check.py`, which compares 72 shape/rule cases against an
independent 256-sub-scanline reference and checks compositing exactly.

## 4. Paths

`ugfx_path_*` builds contours in f64 user space (`move_to`, `line_to`,
`quad_to`, `cubic_to`, `close`, plus the shape builders in `2d/shapes.asm`),
transforms them, and `ugfx_path_rasterize` feeds them to a `UgfxRaster`
with an optional matrix and a tolerance in device pixels. Curves are
transformed first, then flattened into Wang's segment count, so the error
bound holds at any zoom. Arcs and rounded shapes are cubics from
`lib/umath/geom/arc`. `core/umath_unit.asm` links the umath code ugfx uses
as one object.

Tests: `tests/host/path_check.py` runs 36 path, shape and transform cases
against a model built from exact geometry, plus invalid-input cases.

## 5. Strokes

`ugfx_path_stroke(dst, src, style, tolerance)` appends the outline of each
contour's stroke to `dst`, to be filled with the nonzero rule. Contours are
flattened in user space and offset by half the width. Outer corners get the
join (miter within `miter_limit`, else bevel; round; bevel); inner corners
end where the two inner offset lines meet when that point lies within the
near half of both segments, so the outline does not overlap itself, and
otherwise pass through the vertex. Open contours get caps and become one
outline; closed contours become two loops of opposite winding.

Tests: `tests/host/stroke_check.py` compares 30 stroke cases against the
exact union of segment, join and cap pieces (supersampled), requiring ugfx
to stay between that union and the pieces' summed coverage (overlap
accumulation, C2D-027), plus invalid styles.

### Dashes

`ugfx_path_dash(dst, src, dash, tolerance)` cuts each contour into the on
runs of a `UgfxDash` (alternating on/off lengths starting with on; an odd
list repeats; `offset` shifts the pattern) and appends them to `dst` as
open polylines; stroke `dst` for dashed lines. The source is flattened
first (`ugfx_path_flatten`), so dashes follow curves by arc length, and
every contour restarts the pattern. A dash that crosses a vertex keeps it,
so the stroke joins there; a zero-length dash is one point (a dot with
round or square caps). On a closed contour that starts inside a dash, the
first run is drawn last, continuing the final dash through the start
point, and a contour inside a single dash stays closed.

`ugfx_path_flatten(dst, src, tolerance)` copies a path with curves turned
into lines (MOVE and CLOSE kept); `ugfx_path_length(path, arena,
tolerance)` sums the flattened length, closing segments included.

Tests: `tests/host/dash_check.py` - 29 dash cases (offsets, odd and
three-interval patterns, joins across vertices, closed contours joining at
the start, dots, curves, restarts per contour, random) against an
arc-length reference stroked with the same pieces as `stroke_check.py`;
invalid patterns; flattened fills against the originals; lengths of
lines, polygons, circles and curves.

## 6. Paint

`ugfx_raster_fill_paint(raster, pixbuf, paint, rule)` fills like
`ugfx_raster_fill` with a `UgfxPaint` under the coverage: the sweep calls
the paint's own span function, which colours each visible run in chunks
and blends it with `ugfx_span_blend_colors` (one colour per pixel, the
same source-over rounding as solid fills).

| Constructor | Paint |
|---|---|
| `ugfx_paint_solid(paint, colour)` | one premultiplied colour |
| `ugfx_paint_linear(paint, arena, stops, n, spread, x0, y0, x1, y1)` | t along p0 → p1 |
| `ugfx_paint_radial(paint, arena, stops, n, spread, cx, cy, r)` | t = distance / r |
| `ugfx_paint_radial2(paint, arena, stops, n, spread, x0, y0, r0, x1, y1, r1)` | two circles: focal points, cones; t of the largest circle through the pixel, none = unpainted |
| `ugfx_paint_conic(paint, arena, stops, n, cx, cy, start)` | t = angle in turns from `start` |
| `ugfx_paint_set_transform(paint, m)` | paint space → device space (ellipses, rotation, skew) |

Stops are `UgfxStop` (position, straight BGRA colour). Positions are
clamped to [0, 1] and to the previous stop, so equal positions give hard
edges; before the first and after the last stop the end colours continue.
Colours are interpolated premultiplied into a 1024-entry table per
gradient. Spread: pad, repeat, reflect. Each pixel centre goes back to
paint space through the inverse transform (`umath_affine2_invert`); the
conic angle comes from `umath_atan2_f64`, fractions from
`umath_floor_f64_fractional`.

Tests: `tests/host/paint_check.py` - 39 gradient cases (every kind and
spread, focal points inside the circle and with a radius, cones with
unpainted outsides, the tangent and concentric two-circle cases, transparent and translucent stops, hard edges, unordered and
out-of-range positions, a single stop, transformed, elliptical and skewed
paints, anti-aliased shapes over a background, random) compared with a
reference built the same way, bit-exact (the two-circle reference checks
each t against the circle equation); and invalid paints.

## 7. Using it

Assemble with `-I lib/ugfx/include/` and include `ugfx.inc`. Functions follow
the System V register order and return negative error codes. Allocating
functions take the caller's arena and call `arena_alloc` (rdi = arena,
rsi = size -> rax = pointer or 0); the program links the allocator it uses.
In debug builds (`DEBUG_BUILD=1`) pointer checks call the program's
`panic_null_ptr`.

Canvas builds these sources directly from its Makefile (`UGFX_DIR`).
