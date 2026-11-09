# Decision 0012: Fractional Output Scale

**Status**: Accepted (2026-11-07); built: `cw_output`,
`cw_surface.set_buffer_scale`, the logical layout (2026-11-08) and composing
at each output's pixels with edges on whole pixels (2026-11-09)
**Date**: 2026-11-07
**Phase**: P2 (OUT-08, PRO-16; snapping rules CMP-22 in P3)

## Context
Canvas measures everything in one space: the layout, window places and
sizes, the pointer, damage and hit tests are all in output pixels. That is
right while every screen has the same pixel density. A dense laptop panel
next to an ordinary monitor needs each output to have its own scale, and
values like 1.25 and 1.5 as well as 2.

What exists today:
- `Output.scale` (16.16), set by `scale_fractional_compute`; nothing in
  drawing reads it except the software cursor.
- `output/scale_fractional`: tested helpers, not part of drawing.
- `ugfx` `scale_nearest_rect` and `scale_bilinear_rect`: tested, and used to
  copy pixels into scaled mirrors. They copy and do not blend.
- The software cursor already draws at each output's scale rounded to 1x or
  2x.
- There is no `cw_output` interface, so clients cannot learn a scale.

## Options
| Option | Problem |
|---|---|
| A. Logical layout, each output converts to its own pixels | More work in the compositor and in damage |
| B. Physical pixels everywhere, clients draw bigger | A window across two outputs of different scales cannot be right on both; every size the shell picks changes with the screen |
| C. Whole-number scales only | 1.25 and 1.5 panels get a choice of too small or too big |

## Decision
**Option A.**

- **Logical units.** The layout, window places and sizes, the pointer, hit
  tests and damage are in logical units, one unit being a pixel at scale 1.
  An output's logical size is its pixel size divided by its scale, rounded.
  Outputs sit side by side in logical units, as they do in pixels today.
- **Converting when drawing.** An output draws its part at
  `pixel = (logical - output origin) * scale`. A damaged rectangle is
  mapped into the output's pixels rounded outwards, as `mirror_copy`
  already does for mirrors.
- **Scales in 120ths.** The protocol carries a scale as a whole number of
  120ths (150 is 1.25, 180 is 1.5, 240 is 2), which gives the common steps
  exactly. Internally `Output.scale` stays 16.16.
- **Clients.** A new `cw_output` interface tells clients each output's
  logical size and preferred scale. A surface says what scale its buffer was
  drawn at (`cw_surface.set_buffer_scale`, in 120ths). A buffer drawn at the
  output's own scale is placed pixel for pixel; any other is scaled when
  drawn.
- **Blending when scaled.** Scaled drawing needs a variant of
  `scale_bilinear_rect` that blends with what is under it, since windows can
  be translucent.
- **Snapping (CMP-22).** Window places and sizes are chosen so that their
  edges land on whole pixels of the output they are on. Server-drawn parts
  (title bars, the cursor) are sized in logical units and drawn at the
  output's pixels.
- **Mirrors** are unchanged: they copy their source's pixels.

## Consequences
- `compositor`: per-output conversion of positions and damage; the 1:1 path
  stays for scale 1.
- `input`: pointer motion in logical units; a device's pixels converted by
  the output it is on.
- `shell/window`, `shell/titlebar`, `desktop/taskbar`, `session/greeter`:
  sizes in logical units.
- `proto`: `cw_output` (logical size, scale, a change event) and
  `cw_surface.set_buffer_scale`.
- `ugfx`: a blending scaled draw.
- Tests: an output at 1.5 next to one at 1; a window across the edge
  between them; damage mapped outwards; snapping.

## Related
- ROADMAP OUT-07 (layout, mirrors), OUT-08, PRO-16, CMP-22, PTR-11
- Decision 0002 (pixel format)
- `src/output/scale_fractional.asm`, `src/render/sw_cursor.asm`,
  `lib/ugfx/core/scale.asm`

## Progress
1. `cw_output` (`output/output_watch`): each output's id, place, logical
   size and scale.
2. `cw_surface.set_buffer_scale`: a buffer drawn at another scale is
   scaled to its surface's size, blended, when drawn.
3. The logical layout (`output/output_scale`): `output_set_scale` makes an
   output's size in the layout its pixel size divided by its scale and
   moves the outputs to its right. An output at a scale other than 1
   composes its part at that logical size and `output_present` scales the
   frame into its pixels, bilinear, the damage mapped outwards. That is the
   revisit criteria's way round, taken first: everything already draws in
   logical units, and nothing else had to change. Edges are soft on a dense
   panel.
4. Composing at each output's pixels (`render/sw_render`): a frame of a
   scaled output is its pixels (`FrameCtx.px_scale`), and the drawing calls
   map what they are given from logical units there (`frame_map_rect`),
   each edge rounded to the nearest pixel, so what meets in the layout meets
   on the screen with no gap or overlap. A buffer the size its surface comes
   out, within a pixel, is copied pixel for pixel; another is scaled to it.
   Title bars, Alt+Tab and text are drawn at the output's scale, the pointer
   at it rounded to 1x or 2x. While an output is mirrored or the magnifier
   is on it keeps step 3's way, its logical frame scaled after; a change of
   way draws it whole.
5. Snapped places (`shell/window`): a toplevel or popup is placed a whole
   number of its output's pixels from the output's corner, moved back to
   the nearest multiple of 120 / gcd(scale, 120) units.
6. Still open: sizes (a maximized window at 1.5 cannot fill 64 pixels in
   whole units), layers and Alt+drag moves are not snapped, and buffers of
   another scale blend at the edges of a partial redraw.

## Revisit Criteria
If composing at full scale costs too much on the software renderer, compose
each output at the next whole scale and scale the result down once.
