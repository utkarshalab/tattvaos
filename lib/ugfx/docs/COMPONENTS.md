# ugfx 2D Components

Every component of the 2D engine, with its phase, state and main
dependencies. IDs are `C2D-NNN`; use them in commits and issues.

- **Phase** follows the Canvas roadmap: P2 core release, P3 production
  hardening, P4 extended capabilities, P5 later.
- **State:** ✓ done and host-tested · ◐ code exists, untested or partial · blank = not started.
- Math (vectors, transforms, curves) lives in `lib/umath/geom`; ugfx only uses it.

## 1. Surfaces and pixel formats

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-001 | Pixel buffers | P2 | ◐ `core/pixbuf` | |
| C2D-002 | Formats: BGRA/BGRX 8-bit, RGB565, A8, A1, 10-bit, FP16, YUV views | P2 | | 001 |
| C2D-003 | Premultiplied ↔ straight alpha | P2 | ✓ `pixbuf_premultiply` | 001 |
| C2D-004 | Sub-surfaces and views (no copy) | P2 | | 001 |
| C2D-005 | Stride and alignment rules, SIMD-aligned rows | P2 | | 001 |
| C2D-006 | Surface lifetime: reference counting, arena ownership | P2 | ◐ refcount field | 001 |
| C2D-007 | Readback and copy between formats | P3 | | 002 |
| C2D-008 | Dirty tracking per surface | P3 | | 011 |

## 2. Geometry types (from `lib/umath/geom`)

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-009 | Points, sizes, rectangles | P2 | ◐ `core/rect` | |
| C2D-010 | Rounded rectangles (per-corner, elliptical radii) | P2 | ◐ per-corner circular radii in `2d/shapes`; elliptical pending | 009 |
| C2D-011 | Regions (rectangle sets) | P2 | ◐ `core/region` | 009 |
| C2D-012 | Affine transforms | P2 | ✓ `umath/geom/affine2` | |
| C2D-013 | Perspective transforms (2.5D) | P4 | | 012 |
| C2D-014 | Bounds: tight and conservative | P2 | ✓ `ugfx_path_bounds` (control points), `ugfx_path_bounds_tight` (curve extrema, `umath_bezier_*_bounds`) | 015 |

## 3. Paths

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-015 | Path builder: move, line, quad, cubic, conic, arc, close | P2 | ◐ `2d/path` + `add_arc`; conic pending | 012 |
| C2D-016 | Shapes: rect, rounded rect, ellipse, circle, polygon, star, pie, sector | P2 | ✓ `2d/shapes` | 015 |
| C2D-017 | Path transforms | P2 | ✓ `ugfx_path_transform`, matrix in rasterize | 012, 015 |
| C2D-018 | Flattening with error tolerance | P2 | ✓ `ugfx_path_rasterize` + `umath/geom/bezier` | 015 |
| C2D-019 | Iteration, reversal, measuring (length, point at distance, tangent) | P3 | ◐ `ugfx_path_flatten`, `ugfx_path_length`; reversal, point at distance pending | 015 |
| C2D-020 | Hit testing: point in fill, near stroke | P2 | | 018 |
| C2D-021 | Simplification (degenerate segments) | P3 | | 015 |
| C2D-022 | Boolean ops: union, intersect, difference, xor | P3 | | 018 |
| C2D-023 | Offsetting (inset, outset) | P4 | | 038 |
| C2D-024 | SVG path-data parsing | P2 | ◐ Canvas `img/svg_path` | 015 |

## 4. Rasterization

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-025 | AA area-coverage rasterizer | P2 | ✓ `core/raster` | |
| C2D-026 | Fill rules: nonzero, even-odd | P2 | ✓ `core/raster` | 025 |
| C2D-027 | Exact union where overlaps meet in a pixel | P4 | | 025 |
| C2D-028 | Aliased mode (pixel art, masks) | P3 | | 025 |
| C2D-029 | Hairlines (1 px AA lines, fast path) | P2 | | 025 |
| C2D-030 | Pixel snapping and hinting for crisp UI | P2 | | 017 |
| C2D-031 | Tile-based and multi-core rasterization | P3 | | 025 |
| C2D-032 | Coverage-mask output (A8) | P2 | ✓ `core/mask`, `ugfx_raster_fill_mask` | 025, 002 |

## 5. Strokes

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-033 | Stroke width, thin and hairline strokes | P2 | ◐ `2d/stroke` any width > 0; device hairline pending | 018 |
| C2D-034 | Joins: miter (limit), round, bevel | P2 | ✓ `2d/stroke` | 033 |
| C2D-035 | Caps: butt, round, square | P2 | ✓ `2d/stroke` | 033 |
| C2D-036 | Dashes (pattern, offset, along curves) | P2 | ✓ `2d/dash` | 019, 033 |
| C2D-037 | Variable-width strokes | P4 | | 033 |
| C2D-038 | Stroke to path | P2 | ✓ `ugfx_path_stroke` | 033–035 |
| C2D-039 | Non-scaling strokes | P3 | | 033, 017 |

## 6. Paint

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-040 | Solid colour | P2 | ✓ `core/span` | |
| C2D-041 | Linear gradients | P2 | ✓ `2d/paint` | 054 |
| C2D-042 | Radial gradients (with focal point) | P2 | ✓ `2d/paint` centred and two-circle (focal, cones) | 054 |
| C2D-043 | Conic (sweep) gradients | P3 | ✓ `2d/paint` | 054 |
| C2D-044 | Mesh and diamond gradients | P4 | | 054 |
| C2D-045 | Stops, spread modes, interpolation (sRGB, linear, OKLab) | P2 | ◐ stops, pad/repeat/reflect, premultiplied sRGB; linear and OKLab pending | 041 |
| C2D-046 | Image patterns (repeat, mirror, clamp, filtered) | P2 | ◐ `2d/paint` nearest and bilinear, pad/repeat/reflect/none; mipmapped and bicubic pending | 062 |
| C2D-047 | Shader composition | P3 | | 041, 046 |
| C2D-048 | Gradient dithering | P3 | | 041 |

## 7. Compositing and blending

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-049 | Porter-Duff operators | P2 | ◐ `core/blend` | |
| C2D-050 | Separable blend modes | P3 | | 049 |
| C2D-051 | Non-separable blend modes (hue, saturation, colour, luminosity) | P3 | | 049 |
| C2D-052 | Group opacity and layers | P2 | ✓ context layers | 087 |
| C2D-053 | SIMD paths (SSE2, AVX2, AVX-512) | P3 | ◐ `core/blend_*` | 049 |
| C2D-054 | Span compositor variants (solid, gradient, image, mask) | P2 | ◐ solid and per-pixel colours in `core/span`, gradient and image spans; mask pending | 040 |

## 8. Clipping and masking

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-055 | Rectangle clips | P2 | ✓ `core/clip` (rects), `ugfx_mask_fill_rect` (as clips) | |
| C2D-056 | Region clips | P2 | | 011 |
| C2D-057 | AA path clips | P2 | ✓ `ugfx_raster_set_clip` | 032 |
| C2D-058 | Clip stack | P2 | ✓ `2d/context` save/restore with a per-depth mask pool | 055–057 |
| C2D-059 | Alpha and luminance masks | P3 | ✓ `core/mask` | 032 |
| C2D-060 | Scissor fast paths | P2 | | 055 |

## 9. Images

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-061 | Draw image with an affine transform | P2 | | 012, 062 |
| C2D-062 | Filters: nearest, bilinear, bicubic, Lanczos, mipmaps | P2 | ◐ `core/scale` | |
| C2D-063 | 90/180/270 rotations and flips | P2 | ◐ `core/transform` | |
| C2D-064 | Nine-patch | P2 | | 061 |
| C2D-065 | Atlases and sprite sheets | P3 | | 061 |
| C2D-066 | Colour conversion on draw (YUV, profiles) | P3 | | 061 |

## 10. Text drawing

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-067 | Glyph outlines through the rasterizer | P2 | | 015, 025 |
| C2D-068 | Glyph cache (masks by size and subpixel offset) | P2 | | 032, 067 |
| C2D-069 | Subpixel glyph positioning | P2 | | 068 |
| C2D-070 | Text runs (shaped glyph arrays with a paint) | P2 | | 068 |
| C2D-071 | Decorations: underline, strike-through, selection | P2 | | 070 |
| C2D-072 | Text on a path | P4 | | 019, 070 |
| C2D-073 | Colour glyphs (emoji layers) | P3 | | 070 |

## 11. Effects and filters

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-074 | Gaussian and box blur (separable) | P3 | ◐ `2d/filter` Gaussian as three box blurs per axis | 001 |
| C2D-075 | Drop and inner shadows | P3 | ◐ drop shadow (SVG feDropShadow as a filter graph); inner pending | 074 |
| C2D-076 | Backdrop blur | P3 | | 074, 087 |
| C2D-077 | Colour matrix filters | P3 | ✓ `2d/filter` colour matrix, component transfer, sRGB / linearRGB | |
| C2D-078 | Morphology (dilate, erode) | P4 | ✓ `2d/filter` | |
| C2D-079 | Convolution kernels | P4 | ✓ `2d/filter` any order, divisor, bias, target, edge modes, preserveAlpha | |
| C2D-080 | Displacement and turbulence | P4 | ✓ `2d/filter` displacement map; turbulence / fractal noise (the SVG reference noise, stitching) | |
| C2D-081 | Lighting filters | P5 | ✓ `2d/filter` diffuse and specular; distant, point and spot lights | |
| C2D-082 | Filter graph | P4 | ✓ `2d/filter` + ugfx_ctx_filter: flood, offset, blur, merge, blend, composite, colour matrix, transfer, morphology, tile, convolution, displacement, turbulence, lighting, image | 074–081 |

## 12. Drawing API and state

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-083 | Context: transform, clip, paint, stroke style, alpha; save/restore | P2 | ✓ `2d/context` | 012, 058 |
| C2D-084 | Draw calls: fill, stroke, image, text, clear, shapes | P2 | ◐ `2d/context` fill, stroke, clip, rects, image, clear; text pending | 083 |
| C2D-085 | Display lists (record and replay) | P2 | ✓ `2d/list` | 084 |
| C2D-086 | Draw commands for CPU now, GPU later | P3 | ◐ the `2d/list` record stream; GPU backend pending | 085 |
| C2D-087 | Layers and offscreen targets | P2 | ✓ `ugfx_ctx_begin_layer` / `_end_layer` | 001 |
| C2D-088 | Dirty-region tracking and partial redraw | P3 | | 011 |

## 13. Vector content formats

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-089 | UIC icon format (layers, colour slots, stroke weights) | P2 | ✓ `2d/uic`, `docs/UIC.md`, `tools/uic.py`, `tools/svg2uic.py` | 038, 085 |
| C2D-090 | SVG rendering | P2 | ✓ `2d/svg` static SVG 1.1: structure, viewports, paint (gradients, patterns), CSS (combinators, attribute and structural selectors), entities, groups, clip paths, masks, markers, images, text (textPath, baselines, decoration), every filter primitive | 024, 084 |
| C2D-091 | Vector animation | P4 | | 085 |
| C2D-092 | Vector export (print, PDF-style) | P4 | | 085 |

## 14. Hit testing and geometry queries

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-093 | Point in fill, near stroke | P2 | | 020 |
| C2D-094 | Shape/rectangle intersection | P3 | | 018 |
| C2D-095 | Nearest point on a path | P3 | | 019 |

## 15. Performance and quality

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-096 | SIMD dispatch chosen at startup | P3 | | 053 |
| C2D-097 | Multi-threaded tiles and job splitting | P3 | | 031 |
| C2D-098 | Caches: paths, gradients, glyphs, masks | P3 | | 032 |
| C2D-099 | Memory limits per draw, failure modes | P2 | | |
| C2D-100 | Precision rules: fixed point vs float, tolerances | P2 | | |

## 16. Testing

| ID | Component | Phase | State | Depends |
|---|---|---|---|---|
| C2D-101 | Reference renderer per component | P2 | ◐ rasterizer | |
| C2D-102 | Golden-image corpus | P2 | | |
| C2D-103 | Fuzzing paths and transforms | P3 | | |
| C2D-104 | Benchmarks per component | P3 | | |

## Build order

1. Geometry math in `umath/geom` (012, 018) — **done**
2. Path builder, shapes, transforms, flattening, path fill (015–018, 014) — **done** (conic, tight bounds pending)
3. Strokes: width, joins, caps, stroke to path, dashes (033–036, 038) — **done** except device hairlines
4. Span variants and paint: gradients, image patterns (054, 041–046)
5. Clipping and masks, coverage masks (032, 055–060)
6. Context, draw calls, display lists, layers (083–087)
7. UIC icons and SVG (089, 090), then text, effects and the rest
