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
│   └── span.asm          ← span compositor: coverage rows into pixels (src-over)
└── 2d/                   ← 2D shapes and paths
    ├── line.asm          ← line segments
    ├── circle.asm        ← circles and ellipses
    ├── polygon.asm       ← aliased polygons (assembles; not yet built or tested)
    ├── path.asm          ← paths: lines, quads, cubics, transform, bounds, flattening
    └── shapes.asm        ← rect, rounded rect, ellipse, circle, arc, pie, ring sector, polygon, star
```

## 2. Planned

| Area | Contents |
|---|---|
| `core/` | Clip masks and more span operations (gradients, images) for the span compositor; draw-command lists for CPU and GPU backends |
| `2d/` | Strokes (joins, caps, dashes), gradients, patterns, and the rest of [`docs/COMPONENTS.md`](docs/COMPONENTS.md) |
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

## 5. Using it

Assemble with `-I lib/ugfx/include/` and include `ugfx.inc`. Functions follow
the System V register order and return negative error codes. Allocating
functions take the caller's arena and call `arena_alloc` (rdi = arena,
rsi = size -> rax = pointer or 0); the program links the allocator it uses.
In debug builds (`DEBUG_BUILD=1`) pointer checks call the program's
`panic_null_ptr`.

Canvas builds these sources directly from its Makefile (`UGFX_DIR`).
