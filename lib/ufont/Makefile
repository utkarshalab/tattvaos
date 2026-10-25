# ============================================================================
# lib/ufont — Font Library: host build and tests
# Programs normally assemble ufont sources into their own builds (Canvas does
# through UFONT_DIR); this Makefile builds the library's own test tool. ufont
# writes outlines into lib/ugfx paths, so the tool links ugfx's path code.
# ============================================================================

NASM      := nasm
LD        := ld
UGFX      := ../ugfx
NASMFLAGS := -f elf64 -g -F dwarf -I include/ -I layout/ -I $(UGFX)/include/
UGFXFLAGS := -f elf64 -g -F dwarf -D DEBUG_BUILD=1 -I $(UGFX)/include/
UMATHFLAGS := -f elf64 -g -F dwarf -I ../../
BUILDDIR  := build

SRCS      := sfnt/sfnt.asm match/fontset.asm              layout/ucd.asm layout/indic_table.asm layout/unicode.asm layout/buffer.asm              layout/normalize.asm layout/otl.asm layout/map.asm layout/apply.asm layout/gsub.asm              layout/gpos.asm layout/shape.asm layout/indic.asm
OBJS      := $(patsubst %.asm,$(BUILDDIR)/%.o,$(SRCS))
UGFX_OBJS := $(BUILDDIR)/ugfx/2d/path.o $(BUILDDIR)/ugfx/core/raster.o $(BUILDDIR)/ugfx/core/span.o \
             $(BUILDDIR)/ugfx/core/mask.o $(BUILDDIR)/ugfx/core/umath_unit.o

.PHONY: all host host-check clean
all: host

$(BUILDDIR)/%.o: %.asm include/ufont.inc layout/shape.inc $(UGFX)/include/ugfx.inc
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(BUILDDIR)/ugfx/core/umath_unit.o: $(UGFX)/core/umath_unit.asm
	@mkdir -p $(dir $@)
	$(NASM) $(UMATHFLAGS) -o $@ $<

$(BUILDDIR)/ugfx/%.o: $(UGFX)/%.asm $(UGFX)/include/ugfx.inc
	@mkdir -p $(dir $@)
	$(NASM) $(UGFXFLAGS) -o $@ $<

$(BUILDDIR)/host_font: $(BUILDDIR)/tests/host/host_font.o $(OBJS) $(UGFX_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

$(BUILDDIR)/host_shape: $(BUILDDIR)/tests/host/host_shape.o $(OBJS) $(UGFX_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

host: $(BUILDDIR)/host_font $(BUILDDIR)/host_shape

host-check: host
	python3 tests/host/font_check.py $(BUILDDIR)/host_font fonts
	python3 tests/host/shape_check.py $(BUILDDIR)/host_shape fonts

clean:
	rm -rf $(BUILDDIR)
