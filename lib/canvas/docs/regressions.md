# Regressions

Every bug fixed in Canvas, and the test that would fail if it came back
(QA-19). A fix lands with its test and a row here, in the same change
(`definition-of-done.md`). The tests run in `make check`.

| Bug | Fixed in | Guarded by |
|---|---|---|
| `client_accept` copied its whole stack-built pair over the caller's, uninitialised `state` and `region` included: `canvas_disconnect` freed garbage | `0e98b637` | `test_clientlib` `tc_wake` (a sentinel region kept), `tc_service` |
| Turning the magnifier off kept it on: the zoom sat in a register `ut_mem_free` clobbers | magnifier rewrite | `test_window` `tw_magnifier` |
| The clipboard receive handler overwrote `r12`, which the reply needs | clipboard rewrite | `test_window` clipboard cases (`PASTE`) |
| `line_draw` lost its framebuffer pointer and stepped steep lines wrongly | `4f5b5d93` (ugfx) | ugfx `prims_check.py` |
| Logger buckets stamped by one clock and read by another never refilled | `33948c13` | `test_log` `tl_rate` |
| Handle tables: `handle_destroy`, a kept `r15`, a handle never 0 | `713acc60` | `test_handle` |
| `vec`: init, push and growth broken | `9267354f` | `test_vec` |
| `bitset`: every operation touched the wrong memory | `4be6fa67` | `test_tree` |
| `str`: `dup`, `cat`, `find_char` | `842b074f` | `test_str` |
| `arena`: aligned allocation, child arenas, destroy | `31ed1a92` | `test_arena` (`ta_child`, `ta_child_destroy`, aligned cases) |
| `fix_div`, `fix_sqrt`, `fix_lerp` | `305cd4f8` | `test_misc` |
| Time add and subtract, timer frames | `ccd421f9` | `test_misc` |
| `gpu_ring_write` wrapping | `beff6d74` | `test_gpu` |
| Objects: creation, lookup, release | `e5e12760` | `test_proto` |
| Surfaces kept with their client; teardown | `3f67f764` | `test_client` (disconnects), `test_surface` |
| Field widths: accesses wider than their fields | `028b10b1` | `test_fields`, `make field-width-check` |
| PNG IDAT growth and the Adam7 buffer size | `3ca70521` | `test_png`, `compare_images.py` (interlaced) |
| GIF: three bugs in `gif_decode_first` | `54ef6767` | `test_jpeg` (GIF cases), `compare_images.py`, `fuzz_media.py` |
| TGA row order, grayscale, the last pixel | `4dae7d2b` | `compare_images.py` (TGA variants) |
| TIFF stack offsets and the packed sample scale | `ad342c01` | `test_jpeg` (`tiff_*`), `compare_images.py` |
| DNG stack offsets | `45a8aa0d` | `test_jpeg` (`dng_probe`) |
| Farbfeld magic, in the decoder and in sniffing | `b690ade0`, `b371a4d1` | `compare_images.py` |
| WebP: VP8 inner and simple filter edges; VP8L code lengths, one-symbol trees, distance prefixes, pixel addition and predictors | `f77ed69d`, `c098ce16`, `85ad2fa7`, `9eb4bc25` | `test_webp`, `compare_images.py` (lossy, lossless, alpha) |
| Weak copies of `fixed.inc`'s and `color.inc`'s definitions in every object | `7c6cd8d7`, `70308e7a` | `make symbol-check` |
| `wx-check` read half-written images under `-j2` and passed | Makefile | `make check` (it depends on the test images and fails on an unreadable one) |

## Not testable as a behaviour

Stack misalignment (for example in `tap_focus`) breaks nothing the host
shim can see unless an instruction needs alignment. Each function's
comment states its frame arithmetic, and review checks it. A static
checker for `PROLOGUE_SAVE` frames is the way to test it.
