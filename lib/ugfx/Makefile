# ============================================================================
# lib/ugfx — Graphics Library: host build and tests
# Programs normally assemble ugfx sources into their own builds (Canvas does
# through UGFX_DIR); this Makefile builds the library's own test tools.
# ============================================================================

NASM      := nasm
LD        := ld
NASMFLAGS := -f elf64 -g -F dwarf -D DEBUG_BUILD=1 -I include/
BUILDDIR  := build

CORE_SRCS := core/pixbuf.asm core/span.asm core/raster.asm
CORE_OBJS := $(patsubst %.asm,$(BUILDDIR)/%.o,$(CORE_SRCS))

.PHONY: all host host-check clean
all: host

$(BUILDDIR)/%.o: %.asm include/ugfx.inc
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(BUILDDIR)/host_raster: $(BUILDDIR)/tests/host/host_raster.o $(CORE_OBJS)
	$(LD) -nostdlib -static -e _start -o $@ $^

host: $(BUILDDIR)/host_raster

host-check: host
	python3 tests/host/raster_check.py $(BUILDDIR)/host_raster

clean:
	rm -rf $(BUILDDIR)
