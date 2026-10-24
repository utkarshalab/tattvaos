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
│   └── transform.asm     ← 90/180/270 rotation and flips
└── 2d/                   ← 2D shapes and paths
    ├── line.asm          ← line segments
    ├── circle.asm        ← circles and ellipses
    ├── polygon.asm       ← polygons (assembles; not yet built or tested)
    ├── arc.asm           ← not built: needs sin/cos from lib/umath
    ├── path.asm          ← not built: superseded by the path engine below
    └── rounded_rect.asm  ← not built: superseded by the path engine below
```

## 2. Planned

| Area | Contents |
|---|---|
| `core/` | AA coverage span engine shared by 2D fills and 3D triangles; span compositor with clip masks; draw-command lists for CPU and GPU backends |
| `2d/` | Paths (move, line, quadratic, cubic, arc, close), tolerance-based flattening, nonzero and even-odd fills, strokes (joins, caps, dashes), gradients, patterns |
| `3d/` | Meshes, vertex transform, clipping, triangle setup, depth test, shading, textures |
| `backend/` | CPU (scalar and SIMD) now; GPU later through Canvas's command rings |
| `tests/` | Host-run tests against a reference renderer and golden images |

The work items are tracked as `G2D-*` in [`lib/canvas/docs/ROADMAP.md`](../canvas/docs/ROADMAP.md).

## 3. Using it

Assemble with `-I lib/ugfx/include/` and include `ugfx.inc`. Functions follow
the System V register order and return negative error codes. Allocating
functions take the caller's arena and call `arena_alloc` (rdi = arena,
rsi = size -> rax = pointer or 0); the program links the allocator it uses.
In debug builds (`DEBUG_BUILD=1`) pointer checks call the program's
`panic_null_ptr`.

Canvas builds these sources directly from its Makefile (`UGFX_DIR`).
