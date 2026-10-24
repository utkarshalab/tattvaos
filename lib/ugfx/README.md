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
│   ├── span.asm          ← span compositor: coverage rows into pixels (src-over), one colour or per pixel
│   └── mask.asm          ← A8 coverage masks: clips, intersect, invert, alpha and luminance masks
└── 2d/                   ← 2D shapes and paths
    ├── line.asm          ← line segments
    ├── circle.asm        ← circles and ellipses
    ├── polygon.asm       ← aliased polygons (assembles; not yet built or tested)
    ├── path.asm          ← paths: lines, quads, cubics, transform, bounds, flattening
    ├── shapes.asm        ← rect, rounded rect, ellipse, circle, arc, pie, ring sector, polygon, star
    ├── stroke.asm        ← stroke outlines: width, miter/round/bevel joins, butt/round/square caps
    ├── flatten.asm       ← curves to polylines; path length
    ├── dash.asm          ← dash patterns along lines and curves
    ├── paint.asm         ← paints: solid; linear, radial, two-circle and conic gradients; image patterns
    ├── context.asm       ← drawing context: state, save/restore, fill/stroke/clip, images, layers
    ├── list.asm          ← display lists: record context calls, replay them
    ├── uic.asm           ← UIC icon packs: open (validate), find, draw
    ├── svg.asm           ← SVG documents: elements, styles, shapes, drawing
    ├── svg_xml.asm       ← SVG's XML layer: tags, attributes, shared string helpers
    ├── svg_defs.asm      ← SVG definitions found first: gradients (url(#id)), CSS rules
    └── svg_syntax.asm    ← SVG attribute grammars: numbers, colours, transforms, path data
```

## 2. Planned

| Area | Contents |
|---|---|
| `core/` | Clip masks and more span operations (gradients, images) for the span compositor; draw-command lists for CPU and GPU backends |
| `2d/` | Device hairlines, region clips, and the rest of [`docs/COMPONENTS.md`](docs/COMPONENTS.md) |
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
| `ugfx_paint_image(paint, pixbuf, extend_x, extend_y, filter)` | an image: nearest or bilinear; pad, repeat, reflect or none (transparent) per axis |
| `ugfx_paint_set_transform(paint, m)` | paint space → device space (ellipses, rotation, skew, image placement and scale) |

Stops are `UgfxStop` (position, straight BGRA colour). Positions are
clamped to [0, 1] and to the previous stop, so equal positions give hard
edges; before the first and after the last stop the end colours continue.
Colours are interpolated premultiplied into a 1024-entry table per
gradient. Spread: pad, repeat, reflect. Each pixel centre goes back to
paint space through the inverse transform (`umath_affine2_invert`); the
conic angle comes from `umath_atan2_f64`, fractions from
`umath_floor_f64_fractional`. Every pixel centre is mapped on its own, so
a pixel's colour does not depend on how its row was split into spans.

Image paints use the image's pixels as paint space. Bilinear sampling
blends the four premultiplied pixels around the sample with double
weights; outside the image each axis pads with the edge pixel, repeats,
mirrors or stays transparent.

Tests: `tests/host/paint_check.py` - 39 gradient cases (every kind and
spread, focal points inside the circle and with a radius, cones with
unpainted outsides, the tangent and concentric two-circle cases, transparent and translucent stops, hard edges, unordered and
out-of-range positions, a single stop, transformed, elliptical and skewed
paints, anti-aliased shapes over a background, random) compared with a
reference built the same way, bit-exact (the two-circle reference checks
each t against the circle equation); 25 image cases (every extend mode
on each axis, nearest and bilinear, magnified, minified, rotated, skewed,
far from the origin, a 1x1 image, under anti-aliased coverage, random),
also bit-exact; and invalid paints.

## 7. Clips and masks

A `UgfxMask` is one byte of coverage per pixel (A8). Paths render into
masks with `ugfx_raster_fill_mask(raster, mask, rule)` (each pixel becomes
the union with what is there), and `ugfx_raster_set_clip(raster, mask)`
clips every later fill on that raster - solid, gradient, image, or into
another mask - by multiplying its coverage with the mask. The clipped
span splits each run where the mask value changes, so clip interiors stay
long runs.

| Function | |
|---|---|
| `ugfx_mask_init(mask, arena, w, h)` | zeroed mask |
| `ugfx_mask_fill`, `ugfx_mask_fill_rect` | constant value, everywhere or in a rectangle |
| `ugfx_mask_copy`, `ugfx_mask_intersect` | dst = src, dst = dst × src / 255 |
| `ugfx_mask_invert` | m = 255 − m (clip-out, holes) |
| `ugfx_mask_from_alpha`, `ugfx_mask_from_luminance` | from an image (CSS Masking luminance weights) |

A clip stack is a sequence of masks: rendering the next clip path into a
fresh mask while the current clip is set gives their intersection (what
HTML canvas `clip()` does); popping restores the previous mask.

Tests: `tests/host/clip_check.py` - 30 cases (anti-aliased path clips,
both fill rules, nested clips, rectangle clips on and off the buffer,
inverted clips, alpha and luminance image masks, a stroke used as a clip,
clipped solid, gradient and image fills, a transformed clip, random
sequences) against a reference that rebuilds the clip as an A8 array;
pixel-exact.

## 8. Drawing context

`UgfxContext` is the API the rest of the system draws through. It keeps a
state - transform, clip, fill and stroke paints (each with a paint to user
matrix), stroke style, dash, global alpha, fill rule, tolerance, target -
that `ugfx_ctx_save` / `ugfx_ctx_restore` push and pop (32 deep).

| Call | |
|---|---|
| `ugfx_ctx_init(ctx, arena, pixbuf)` | defaults: identity, no clip, black paints, width 1, miter 10 |
| `ugfx_ctx_set_transform`, `_transform`, `_translate`, `_scale`, `_rotate` | user → device |
| `ugfx_ctx_set_fill_color`, `_set_fill_paint`, `_set_stroke_color`, `_set_stroke_paint` | paints in user space |
| `ugfx_ctx_set_stroke_style`, `_set_dash`, `_set_alpha`, `_set_fill_rule`, `_set_tolerance` | |
| `ugfx_ctx_fill`, `_stroke`, `_clip` | a UgfxPath in user space |
| `ugfx_ctx_fill_rect`, `_stroke_rect`, `_draw_image`, `_clear` | |
| `ugfx_ctx_begin_layer(ctx, alpha)`, `_end_layer` | offscreen group, composited once |

Strokes and dashes are built in user space and transformed afterwards, so
non-uniform scales stretch them as HTML canvas does. Clips intersect by
rendering under the current clip; each save depth owns at most one mask
from a pool, so clip memory is bounded. A layer draws into a transparent
buffer of the target's size with no clip and full alpha, and is
composited at layer alpha x global alpha under the restored clip, so clip
edges are not counted twice. Global alpha multiplies coverage in the
rasterizer (`ugfx_raster_set_alpha`).

Tests: `tests/host/ctx_check.py` drives `tests/host/host_ctx` with 33
scripts (state through save/restore, user-space gradients, sheared and
turned strokes, dashes on and off, nested and repeated clips, alpha,
fill rules, rects, images, clear, layers with opacity, under clips,
nested and reused, random sequences) and 7 invalid ones, against a Python
context assembled from the separately checked pieces.

## 9. Display lists

A `UgfxList` records drawing to replay later: `ugfx_list_<call>(list, ...)`
takes the same arguments as `ugfx_ctx_<call>`, and
`ugfx_list_replay(list, ctx)` runs the records through a context - any
number of times, onto any context. Records are 8-byte aligned (opcode,
length, payload). Paths, transforms, colours, styles, rects and dash
intervals are copied in; paints are copied by value, but gradient tables
and images are referenced and must outlive the list. Replayed paths are
read-only views into the list. The record stream is also the command
format a GPU backend will take.

Tests: `tests/host/list_check.py` runs every ctx_check script drawn
directly, recorded and replayed once, and replayed twice: replay equals
direct drawing byte for byte, two replays equal the script drawn twice,
failures match; plus a stress list of hundreds of records and long curves.

## 10. Icons (UIC)

UIC is the run-time icon format ([`docs/UIC.md`](docs/UIC.md)): a pack of
named vector icons with i16 fixed-point coordinates, colour slots (slot 0
is the main colour) and stroke widths scaled by a weight at draw time.
Icons are authored as SVG and converted when the system is built.

| Function | |
|---|---|
| `ugfx_uic_open(uic, arena, data, size)` | checks header, index and every body; uses the bytes in place |
| `ugfx_uic_find(uic, name, length, pixels)` | binary search; picks the design size for the pixel size |
| `ugfx_uic_draw(uic, icon, ctx, colours, count, x, y, size, weight)` | fits the icon in a square of the context's user space |

`tools/uic.py` builds packs (choosing fraction bits, sorting the index)
and dumps them as text (`uic.py dump pack.uic`). `tools/svg2uic.py`
converts SVG icons (`svg2uic.py out.uic icons/ ...`): transforms baked
into the coordinates, currentColor (or a one-colour icon's colour) in
slot 0, other colours in further slots, opacity as OPACITY commands;
what UIC cannot express is reported. `tests/host/svg2uic_check.py`
draws every svg_check document both as SVG and converted to UIC: they
agree within 1 per channel (most are identical).

`make icons` builds the open icon sets listed in
[`icons/sources.json`](icons/sources.json) - Lucide, Tabler, Bootstrap
Icons, Heroicons, Material Design Icons, Font Awesome Free, Phosphor -
each fetched at a pinned commit, into 18 packs (33 312 icons, about
10 MB) in `build/icons/`, with every set's licence text and a NOTICE.
Sets whose licences do not allow redistribution (Flaticon) are left out.
`tools/uic_sheet.py` renders a pack's icons into a PNG contact sheet
through ugfx, for checking by eye.

Tests: `tests/host/uic_check.py` - 17 draws (filled, duotone with
opacity, even-odd, strokes at weights 0.5 / 1 / 2, non-square and offset
viewBoxes, a 512 grid, colour overrides, under a transform, a clip and
alpha, inside a layer) byte-identical to the context calls the format
defines; 17 lookups by name and size; 30 corrupt packs refused.

## 11. SVG

`ugfx_svg_parse(svg, arena, data, size)` reads an SVG document once into a
list of items (transform, path, fill and stroke: none, a colour or
currentColor, opacities folded into the alpha); `ugfx_svg_draw(svg, ctx,
current_colour, x, y, size)` draws it through a context, the viewBox
fitted and centred in the square.

The subset is what icon sets use: `svg`, `g`, `path` (all commands,
arcs through `umath_arc_svg_to_cubics`), `rect` (elliptical corners),
`circle`, `ellipse`, `line`, `polyline`, `polygon`; fill, stroke and
their opacities, stroke width / caps / joins / miter limit, fill-rule,
opacity, display, transforms, `style` declarations (which override the
attributes) and every CSS colour form icons use. Fills and strokes can be
`url(#id)` linear and radial gradients (focal points and radii,
objectBoundingBox or userSpaceOnUse, percentages, gradientTransform,
spreadMethod, href chains, stop opacity), found by a first pass over the
whole document, with the fallback colour when the id names nothing;
bounding boxes are tight (`ugfx_path_bounds_tight`). `<style>` sheets
apply too: selectors `element`, `.class`, `#id`, `element.class`, `*` and
lists, cascaded by specificity then order, between the presentation
attributes and the `style` attribute (`!important` is not
distinguished); other selectors and at-rules are skipped. `defs`, `clipPath`,
`mask`, gradients, `text` and similar are skipped with their contents;
other elements act as groups. Opacity is applied per item rather than as
a group. `tools/svgmodel.py` models the same subset in Python.

Tests: `tests/host/svg_check.py` - 37 documents (every path command
absolute and relative, smooth reflections, arcs with every flag and
tiny or zero radii, packed numbers, every shape, transforms, nested
groups, styles, currentColor, colour syntaxes, fill rules, display,
skipped content, viewBox fallbacks, Lucide-, Material- and Font
Awesome-style icons, syntax errors), each drawn two ways, compared with
the context calls svgmodel.py derives - all exact; plus 4 refused and 1
truncated document.

## 12. Using it

Assemble with `-I lib/ugfx/include/` and include `ugfx.inc`. Functions follow
the System V register order and return negative error codes. Allocating
functions take the caller's arena and call `arena_alloc` (rdi = arena,
rsi = size -> rax = pointer or 0); the program links the allocator it uses.
In debug builds (`DEBUG_BUILD=1`) pointer checks call the program's
`panic_null_ptr`.

Canvas builds these sources directly from its Makefile (`UGFX_DIR`).
