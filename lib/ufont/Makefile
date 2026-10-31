# ============================================================================
# lib/ufont — Font Library: host build and tests
# Programs normally assemble ufont sources into their own builds (Canvas does
# through UFONT_DIR); this Makefile builds the library's own test tool. ufont
# writes outlines into lib/ugfx paths, so the tool links ugfx's path code;
# WOFF fonts need inflate, which the tool takes from Canvas (as Canvas
# itself provides it to ufont).
# ============================================================================

NASM      := nasm
LD        := ld
UGFX      := ../ugfx
NASMFLAGS := -f elf64 -g -F dwarf -I include/ -I layout/ -I $(UGFX)/include/
UGFXFLAGS := -f elf64 -g -F dwarf -D DEBUG_BUILD=1 -I $(UGFX)/include/
UMATHFLAGS := -f elf64 -g -F dwarf -I ../../
BUILDDIR  := build

SRCS      := sfnt/sfnt.asm sfnt/cff.asm sfnt/woff.asm sfnt/woff2.asm sfnt/brotli.asm sfnt/brotli_tables.asm sfnt/var.asm match/fontset.asm              layout/ucd.asm layout/indic_table.asm layout/unicode.asm layout/buffer.asm              layout/normalize.asm layout/otl.asm layout/map.asm layout/apply.asm layout/gsub.asm              layout/gpos.asm layout/shape.asm layout/indic.asm layout/arabic.asm layout/fallback.asm layout/bidi.asm layout/thai.asm layout/hangul.asm layout/syllabic.asm layout/khmer.asm layout/myanmar.asm layout/use.asm layout/use_table.asm
OBJS      := $(patsubst %.asm,$(BUILDDIR)/%.o,$(SRCS))
UGFX_OBJS := $(BUILDDIR)/ugfx/2d/path.o $(BUILDDIR)/ugfx/core/raster.o $(BUILDDIR)/ugfx/core/span.o \
             $(BUILDDIR)/ugfx/core/mask.o $(BUILDDIR)/ugfx/core/umath_unit.o              $(BUILDDIR)/canvas/inflate.o

.PHONY: all host host-check clean
all: host

$(BUILDDIR)/%.o: %.asm include/ufont.inc layout/shape.inc $(UGFX)/include/ugfx.inc
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(BUILDDIR)/ugfx/core/umath_unit.o: $(UGFX)/core/umath_unit.asm
	@mkdir -p $(dir $@)
	$(NASM) $(UMATHFLAGS) -o $@ $<

$(BUILDDIR)/canvas/inflate.o: ../canvas/src/img/inflate.asm
	@mkdir -p $(dir $@)
	$(NASM) -f elf64 -g -F dwarf -I ../canvas/ -o $@ $<

$(BUILDDIR)/ugfx/%.o: $(UGFX)/%.asm $(UGFX)/include/ugfx.inc
	@mkdir -p $(dir $@)
	$(NASM) $(UGFXFLAGS) -o $@ $<

$(BUILDDIR)/host_font: $(BUILDDIR)/tests/host/host_font.o $(OBJS) $(UGFX_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

$(BUILDDIR)/host_shape: $(BUILDDIR)/tests/host/host_shape.o $(OBJS) $(UGFX_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

$(BUILDDIR)/host_bidi: $(BUILDDIR)/tests/host/host_bidi.o $(OBJS) $(UGFX_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

$(BUILDDIR)/host_brotli: $(BUILDDIR)/tests/host/host_brotli.o $(OBJS) $(UGFX_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

host: $(BUILDDIR)/host_font $(BUILDDIR)/host_shape $(BUILDDIR)/host_bidi $(BUILDDIR)/host_brotli

host-check: host
	python3 tests/host/font_check.py $(BUILDDIR)/host_font fonts
	python3 tests/host/shape_check.py $(BUILDDIR)/host_shape fonts
	python3 tests/host/brotli_check.py $(BUILDDIR)/host_brotli
	python3 tests/host/var_check.py $(BUILDDIR)/host_font $(BUILDDIR)/host_shape tests/fonts
	@if [ -n "$(UCD)" ]; then python3 tests/host/bidi_check.py $(UCD) $(BUILDDIR)/host_bidi; 	else echo "bidi_check skipped: make host-check UCD=<Unicode 17 UCD directory with BidiTest.txt>"; fi

clean:
	rm -rf $(BUILDDIR)
