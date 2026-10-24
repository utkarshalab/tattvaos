# ============================================================================
# lib/ugfx — Graphics Library: host build and tests
# Programs normally assemble ugfx sources into their own builds (Canvas does
# through UGFX_DIR); this Makefile builds the library's own test tools.
# ============================================================================

NASM      := nasm
LD        := ld
NASMFLAGS := -f elf64 -g -F dwarf -D DEBUG_BUILD=1 -I include/
# lib/umath files include each other by repo-root path
UMATHFLAGS := -f elf64 -g -F dwarf -I ../../
BUILDDIR  := build

CORE_SRCS := core/pixbuf.asm core/span.asm core/raster.asm core/mask.asm
PATH_SRCS := 2d/path.asm 2d/shapes.asm 2d/stroke.asm 2d/flatten.asm 2d/dash.asm 2d/paint.asm 2d/context.asm 2d/list.asm 2d/uic.asm 2d/svg_syntax.asm 2d/svg_xml.asm 2d/svg_defs.asm 2d/svg.asm
CORE_OBJS := $(patsubst %.asm,$(BUILDDIR)/%.o,$(CORE_SRCS))
PATH_OBJS := $(patsubst %.asm,$(BUILDDIR)/%.o,$(PATH_SRCS)) $(BUILDDIR)/core/umath_unit.o

.PHONY: all host host-check icons clean
all: host

$(BUILDDIR)/core/umath_unit.o: core/umath_unit.asm $(wildcard ../umath/geom/*.asm ../umath/math_fn/*.asm ../umath/scalar/*.asm)
	@mkdir -p $(dir $@)
	$(NASM) $(UMATHFLAGS) -o $@ $<

$(BUILDDIR)/%.o: %.asm include/ugfx.inc
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(BUILDDIR)/host_raster: $(BUILDDIR)/tests/host/host_raster.o $(CORE_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

$(BUILDDIR)/host_path: $(BUILDDIR)/tests/host/host_path.o $(CORE_OBJS) $(PATH_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

$(BUILDDIR)/host_ctx: $(BUILDDIR)/tests/host/host_ctx.o $(CORE_OBJS) $(PATH_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

host: $(BUILDDIR)/host_raster $(BUILDDIR)/host_path $(BUILDDIR)/host_ctx

host-check: host
	python3 tests/host/raster_check.py $(BUILDDIR)/host_raster
	python3 tests/host/path_check.py $(BUILDDIR)/host_path
	python3 tests/host/stroke_check.py $(BUILDDIR)/host_path
	python3 tests/host/dash_check.py $(BUILDDIR)/host_path
	python3 tests/host/paint_check.py $(BUILDDIR)/host_path
	python3 tests/host/clip_check.py $(BUILDDIR)/host_path
	python3 tests/host/ctx_check.py $(BUILDDIR)/host_ctx $(BUILDDIR)/host_path
	python3 tests/host/list_check.py $(BUILDDIR)/host_ctx
	python3 tests/host/uic_check.py $(BUILDDIR)/host_ctx
	python3 tests/host/svg_check.py $(BUILDDIR)/host_ctx
	python3 tests/host/svg2uic_check.py $(BUILDDIR)/host_ctx

# icon packs from the open sets in icons/sources.json (fetches them; needs git)
icons:
	python3 tools/build_icons.py icons/sources.json $(BUILDDIR)/icons

clean:
	rm -rf $(BUILDDIR)
