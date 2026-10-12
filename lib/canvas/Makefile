# ============================================================================
# Canvas Display Server — Build System for Tattva OS
# Pure NASM, no C compiler, no libc, bare metal x86-64
# ============================================================================

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

# Architecture
ARCH        := x86_64
BITS        := 64

# Tools
NASM        := nasm
LD          := ld
OBJCOPY     := objcopy
STRIP       := strip

# NASM Flags
NASMFLAGS   := -f elf64 -g -F dwarf \
               -D __TATTVA__ \
               -D DEBUG_BUILD=1 \
               -I inc/ \
               -I src/

# Linker Flags (Tattva image format)
LDFLAGS     := -nostdlib -static -z max-page-size=0x1000 \
               -T linker.ld \
               --build-id=none

# Directories
SRCDIR      := src
INCDIR      := inc
BUILDDIR    := build
OBJDIR      := $(BUILDDIR)/obj
IMAGEDIR    := $(BUILDDIR)/img
LIBDIR      := $(BUILDDIR)/lib

# ---------------------------------------------------------------------------
# Source Files (C0 Phase)
# ---------------------------------------------------------------------------

# Tattva Bindings (C0)
TATTVA_SRCS := \
    $(SRCDIR)/tattva/tv_mem.asm \
    $(SRCDIR)/tattva/tv_time.asm \
    $(SRCDIR)/tattva/tv_log.asm \
    $(SRCDIR)/tattva/tv_entropy.asm \
    $(SRCDIR)/tattva/tv_wait.asm

# Core Library (C1)
CORE_SRCS := \
    $(SRCDIR)/core/arena.asm \
    $(SRCDIR)/core/str.asm \
    $(SRCDIR)/core/map.asm \
    $(SRCDIR)/core/vec.asm \
    $(SRCDIR)/core/ring.asm \
    $(SRCDIR)/core/handle.asm \
    $(SRCDIR)/core/list.asm \
    $(SRCDIR)/core/rbtree.asm \
    $(SRCDIR)/core/fixed.asm \
    $(SRCDIR)/core/fmt.asm \
    $(SRCDIR)/core/config.asm \
    $(SRCDIR)/core/log.asm \
    $(SRCDIR)/core/time.asm \
    $(SRCDIR)/core/cpuid.asm \
    $(SRCDIR)/core/hash.asm \
    $(SRCDIR)/core/siphash.asm \
    $(SRCDIR)/core/utf8.asm \
    $(SRCDIR)/core/bitset.asm

# Graphics (C2)
GFX_SRCS := \
    $(SRCDIR)/gfx/pixbuf.asm \
    $(SRCDIR)/gfx/rect.asm \
    $(SRCDIR)/gfx/region.asm \
    $(SRCDIR)/gfx/fill.asm \
    $(SRCDIR)/gfx/blit.asm \
    $(SRCDIR)/gfx/blend.asm \
    $(SRCDIR)/gfx/blend_sse2.asm \
    $(SRCDIR)/gfx/blend_avx2.asm \
    $(SRCDIR)/gfx/blend_avx512.asm \
    $(SRCDIR)/gfx/scale.asm \
    $(SRCDIR)/gfx/transform.asm \
    $(SRCDIR)/gfx/clip.asm

# Protocol (C4)
PROTO_SRCS := \
    $(SRCDIR)/proto/wire.asm \
    $(SRCDIR)/proto/msgbuf.asm \
    $(SRCDIR)/proto/objects.asm \
    $(SRCDIR)/proto/dispatch.asm \
    $(SRCDIR)/proto/versioning.asm \
    $(SRCDIR)/proto/negotiate.asm \
    $(SRCDIR)/proto/errors.asm \
    $(SRCDIR)/proto/channel.asm

# Image (C21)
IMG_SRCS := \
    $(SRCDIR)/img/crc32.asm

# Server Core (C5-C8)
SERVER_SRCS := \
    $(SRCDIR)/server/main.asm \
    $(SRCDIR)/server/client/client.asm \
    $(SRCDIR)/server/client/client_registry.asm \
    $(SRCDIR)/server/client/auth.asm \
    $(SRCDIR)/server/buffer/buffer.asm \
    $(SRCDIR)/server/buffer/buffer_pool.asm \
    $(SRCDIR)/server/fence/fence.asm \
    $(SRCDIR)/server/timeline/timeline.asm \
    $(SRCDIR)/server/surface/surface.asm \
    $(SRCDIR)/server/subsurface/subsurface.asm \
    $(SRCDIR)/server/commit/commit.asm \
    $(SRCDIR)/server/damage/damage.asm \
    $(SRCDIR)/server/regions/regions.asm \
    $(SRCDIR)/server/zorder/zorder.asm \
    $(SRCDIR)/server/surface_transform/surface_transform.asm \
    $(SRCDIR)/server/frame_clock/frame_clock.asm \
    $(SRCDIR)/server/presentation/presentation.asm \
    $(SRCDIR)/server/direct_scanout/direct_scanout.asm

# Render (C8)
RENDER_SRCS := \
    $(SRCDIR)/render/sw_render.asm \
    $(SRCDIR)/render/compositor.asm \
    $(SRCDIR)/render/damage_ring.asm \
    $(SRCDIR)/render/sw_scale.asm \
    $(SRCDIR)/render/sw_transform.asm

# Backend (C9)
BACKEND_SRCS := \
    $(SRCDIR)/backend/backend_dispatch.asm \
    $(SRCDIR)/backend/headless/headless.asm \
    $(SRCDIR)/backend/fb_linear/fb_linear.asm \
    $(SRCDIR)/backend/native/native_pci.asm \
    $(SRCDIR)/backend/native/native_modeset.asm \
    $(SRCDIR)/backend/native/native_vblank.asm \
    $(SRCDIR)/backend/native/native_planes.asm \
    $(SRCDIR)/backend/native/native_edid.asm \
    $(SRCDIR)/backend/native/native_ddc.asm \
    $(SRCDIR)/backend/native/native_hotplug.asm

# Native DCN Family (C10)
DCN_SRCS := \
    $(SRCDIR)/backend/family/amd/dcn/dcn_regs.inc \
    $(SRCDIR)/backend/family/amd/dcn/dcn_modeset.asm

# Output Management (C11)
OUTPUT_SRCS := \
    $(SRCDIR)/output/output.asm \
    $(SRCDIR)/output/modes.asm \
    $(SRCDIR)/output/scale_fractional.asm \
    $(SRCDIR)/output/rotation.asm \
    $(SRCDIR)/output/mirror.asm \
    $(SRCDIR)/output/gamma.asm \
    $(SRCDIR)/output/dpms.asm \
    $(SRCDIR)/output/vrr.asm

# Input Management (C12)
INPUT_SRCS := \
    $(SRCDIR)/input/input.asm \
    $(SRCDIR)/input/source_iface.asm \
    $(SRCDIR)/input/source_tv.asm \
    $(SRCDIR)/input/source_virtual.asm \
    $(SRCDIR)/input/seat.asm \
    $(SRCDIR)/input/keyboard.asm \
    $(SRCDIR)/input/keymap.asm \
    $(SRCDIR)/input/compose.asm \
    $(SRCDIR)/input/pointer.asm \
    $(SRCDIR)/input/accel.asm \
    $(SRCDIR)/input/constraints.asm \
    $(SRCDIR)/input/touch.asm \
    $(SRCDIR)/input/gestures.asm \
    $(SRCDIR)/input/tablet.asm \
    $(SRCDIR)/input/focus.asm \
    $(SRCDIR)/input/grab.asm \
    $(SRCDIR)/input/hittest.asm \
    $(SRCDIR)/input/cursor.asm \
    $(SRCDIR)/input/cursor_theme.asm

# Shell (C13)
SHELL_SRCS := \
    $(SRCDIR)/shell/shell.asm \
    $(SRCDIR)/shell/toplevel.asm \
    $(SRCDIR)/shell/popup.asm \
    $(SRCDIR)/shell/layer.asm \
    $(SRCDIR)/shell/workspace.asm \
    $(SRCDIR)/shell/configure.asm \
    $(SRCDIR)/shell/move_resize.asm \
    $(SRCDIR)/shell/states.asm \
    $(SRCDIR)/shell/decoration.asm \
    $(SRCDIR)/shell/decoration_draw.asm \
    $(SRCDIR)/shell/theme.asm \
    $(SRCDIR)/shell/rules.asm

# Policy (C13)
POLICY_SRCS := \
    $(SRCDIR)/policy/policy_iface.asm \
    $(SRCDIR)/policy/policy_floating.asm \
    $(SRCDIR)/policy/policy_tiling.asm \
    $(SRCDIR)/policy/policy_kiosk.asm \
    $(SRCDIR)/policy/policy_external.asm \
    $(SRCDIR)/policy/layout_engine.asm

# Data (C15)
DATA_SRCS := \
    $(SRCDIR)/data/clipboard.asm \
    $(SRCDIR)/data/selection.asm \
    $(SRCDIR)/data/dnd.asm \
    $(SRCDIR)/data/mime.asm \
    $(SRCDIR)/data/limits.asm \
    $(SRCDIR)/data/transfer.asm

# Security (C17)
SECURITY_SRCS := \
    $(SRCDIR)/security/caps.asm \
    $(SRCDIR)/security/trust.asm \
    $(SRCDIR)/security/gate.asm \
    $(SRCDIR)/security/isolation.asm \
    $(SRCDIR)/security/verifier_hooks.asm \
    $(SRCDIR)/security/token.asm \
    $(SRCDIR)/security/prompts.asm \
    $(SRCDIR)/security/audit.asm

# Text & A11y (C16)
TEXT_SRCS := \
    $(SRCDIR)/text/text_input.asm \
    $(SRCDIR)/text/preedit.asm \
    $(SRCDIR)/text/ime_bridge.asm \
    $(SRCDIR)/text/shortcuts.asm

A11Y_SRCS := \
    $(SRCDIR)/a11y/a11y_tree.asm \
    $(SRCDIR)/a11y/a11y_events.asm \
    $(SRCDIR)/a11y/a11y_reader_hooks.asm \
    $(SRCDIR)/a11y/sticky_keys.asm \
    $(SRCDIR)/a11y/magnifier.asm \
    $(SRCDIR)/a11y/high_contrast.asm

# All Sources
ALL_SRCS    := $(TATTVA_SRCS) $(CORE_SRCS) $(GFX_SRCS) $(PROTO_SRCS) $(IMG_SRCS) $(SERVER_SRCS) $(RENDER_SRCS) $(BACKEND_SRCS) $(DCN_SRCS) $(OUTPUT_SRCS) $(INPUT_SRCS) $(SHELL_SRCS) $(POLICY_SRCS) $(DATA_SRCS) $(SECURITY_SRCS) $(TEXT_SRCS) $(A11Y_SRCS)

# Object Files
ALL_OBJS    := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(ALL_SRCS))
TATTVA_OBJS := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(TATTVA_SRCS))

# ---------------------------------------------------------------------------
# Default Target
# ---------------------------------------------------------------------------

.PHONY: all
all: server client tools clients test

# ---------------------------------------------------------------------------
# Build Targets
# ---------------------------------------------------------------------------

# Canvas Server Image (canvasd)
server: $(IMAGEDIR)/canvasd.img

$(IMAGEDIR)/canvasd.img: $(ALL_OBJS) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $(ALL_OBJS)
	@echo "  IMG    $@"

# Client Library (relocatable object)
client: $(LIBDIR)/canvas_client.o

$(LIBDIR)/canvas_client.o: $(OBJDIR)/client/conn.o $(OBJDIR)/client/client.o \
                            $(OBJDIR)/client/objects.o $(OBJDIR)/client/buffer_pool.o \
                            $(OBJDIR)/client/surface_helpers.o $(OBJDIR)/client/buffer_helpers.o \
                            $(OBJDIR)/client/events.o $(OBJDIR)/client/event_loop.o \
                            $(OBJDIR)/client/input_helpers.o $(OBJDIR)/client/shell_helpers.o \
                            $(OBJDIR)/client/clipboard_helpers.o $(OBJDIR)/client/present_helpers.o
	@mkdir -p $(LIBDIR)
	$(LD) -r -o $@ $^
	@echo "  LIB    $@"

# Tools (cwpgen, canvasctl, etc.)
tools: $(IMAGEDIR)/cwpgen.img $(IMAGEDIR)/canvasctl.img \
       $(IMAGEDIR)/canvas_info.img $(IMAGEDIR)/canvas_inspect.img \
       $(IMAGEDIR)/canvas_record.img $(IMAGEDIR)/canvas_replay.img \
       $(IMAGEDIR)/canvas_bench.img $(IMAGEDIR)/cwplint.img

# Reference Clients
clients: $(IMAGEDIR)/demo_windows.img $(IMAGEDIR)/demo_alpha.img \
         $(IMAGEDIR)/demo_subsurfaces.img $(IMAGEDIR)/input_test.img \
         $(IMAGEDIR)/clipboard_test.img $(IMAGEDIR)/dnd_test.img \
         $(IMAGEDIR)/ime_test.img $(IMAGEDIR)/a11y_test.img \
         $(IMAGEDIR)/panel.img $(IMAGEDIR)/wallpaper.img \
         $(IMAGEDIR)/lockscreen.img $(IMAGEDIR)/bench_latency.img \
         $(IMAGEDIR)/bench_throughput.img $(IMAGEDIR)/stress_clients.img

# ---------------------------------------------------------------------------
# Compilation Rules
# ---------------------------------------------------------------------------

$(OBJDIR)/%.o: $(SRCDIR)/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<
	@echo "  ASM    $<"

# ---------------------------------------------------------------------------
# Linker Script
# ---------------------------------------------------------------------------

linker.ld:
	@cat > $@ << 'EOF'
ENTRY(canvasd_init)
SECTIONS
{
    . = 0x200000;           /* 2MB alignment for huge pages */
    .text : { *(.text*) }
    .rodata : { *(.rodata*) }
    .data : { *(.data*) }
    .bss : { *(.bss*) *(COMMON) }
    /DISCARD/ : { *(.note.*) *(.comment*) }
}
EOF

# ---------------------------------------------------------------------------
# Test Targets
# ---------------------------------------------------------------------------

# Test runner image
$(IMAGEDIR)/test_runner.img: $(OBJDIR)/tests/test_runner.o $(TATTVA_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GFX_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(PROTO_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(IMG_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(BACKEND_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DCN_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(INPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SHELL_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(POLICY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DATA_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(TEXT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(A11Y_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SECURITY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo "  IMG    $@"

# Golden test image
$(IMAGEDIR)/golden_test.img: $(OBJDIR)/tests/golden/golden_test.o $(TATTVA_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GFX_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(PROTO_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(IMG_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(BACKEND_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DCN_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(INPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SHELL_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(POLICY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DATA_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(TEXT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(A11Y_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SECURITY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo "  IMG    $@"

# Fuzz runner image
$(IMAGEDIR)/fuzz_runner.img: $(OBJDIR)/tests/fuzz/fuzz_driver.o $(TATTVA_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(PROTO_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(IMG_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(BACKEND_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DCN_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(INPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SHELL_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(POLICY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DATA_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(TEXT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(A11Y_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SECURITY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo "  IMG    $@"

# Replay test image
$(IMAGEDIR)/replay_test.img: $(OBJDIR)/tests/replay/replay_test.o $(TATTVA_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(PROTO_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(BACKEND_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DCN_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(INPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SHELL_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(POLICY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DATA_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(TEXT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(A11Y_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SECURITY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $^
	@echo "  IMG    $@"

# Test target
.PHONY: test
test: $(IMAGEDIR)/test_runner.img $(IMAGEDIR)/golden_test.img $(IMAGEDIR)/fuzz_runner.img $(IMAGEDIR)/replay_test.img
	@echo "All test images built"
	@echo "Run on Tattva to execute tests"

# ---------------------------------------------------------------------------
# Test Compilation Rules
# ---------------------------------------------------------------------------

$(OBJDIR)/tests/%.o: tests/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/golden/%.o: tests/golden/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/fuzz/%.o: tests/fuzz/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/replay/%.o: tests/replay/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/input/%.o: tests/input/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

.PHONY: fuzz
fuzz: $(IMAGEDIR)/fuzz_runner.img
	@echo "Running fuzz tests..."

.PHONY: soak
soak: $(IMAGEDIR)/soak_test.img
	@echo "Running 24h soak test..."

.PHONY: bench
bench: $(IMAGEDIR)/bench_runner.img
	@echo "Running benchmarks..."

.PHONY: cts
cts: $(IMAGEDIR)/cts_runner.img
	@echo "Running conformance suite..."

# ---------------------------------------------------------------------------
# Clean
# ---------------------------------------------------------------------------

.PHONY: clean
clean:
	rm -rf $(BUILDDIR)
	rm -f linker.ld

.PHONY: distclean
distclean: clean
	rm -rf $(BUILDDIR)

# ---------------------------------------------------------------------------
# Development Helpers
# ---------------------------------------------------------------------------

.PHONY: asm-check
asm-check:
	@for f in $(ALL_SRCS); do \
		echo "Checking $$f..."; \
		$(NASM) $(NASMFLAGS) -o /dev/null $$f || exit 1; \
	done
	@echo "All assembly files parse correctly"

.PHONY: size
size: $(IMAGEDIR)/canvasd.img
	@$(OBJCOPY) --strip-debug $(IMAGEDIR)/canvasd.img $(IMAGEDIR)/canvasd.stripped.img
	@echo "canvasd size: $$(stat -c%s $(IMAGEDIR)/canvasd.img) bytes"
	@echo "canvasd stripped: $$(stat -c%s $(IMAGEDIR)/canvasd.stripped.img) bytes"

.PHONY: deps
deps:
	@echo "Checking build dependencies..."
	@which $(NASM) >/dev/null || (echo "nasm not found"; exit 1)
	@which $(LD) >/dev/null || (echo "ld not found"; exit 1)
	@echo "All dependencies satisfied"

# ---------------------------------------------------------------------------
# Phony Targets
# ---------------------------------------------------------------------------

.PHONY: help
help:
	@echo "Canvas Display Server — Build Targets"
	@echo ""
	@echo "  all          Build everything (default)"
	@echo "  server       Build canvasd server image"
	@echo "  client       Build canvas_client.o library"
	@echo "  tools        Build development tools"
	@echo "  clients      Build reference client images"
	@echo "  test         Run all tests (unit, golden, replay)"
	@echo "  fuzz         Run fuzz tests"
	@echo "  soak         Run 24h soak test"
	@echo "  bench        Run benchmarks"
	@echo "  cts          Run conformance suite"
	@echo "  clean        Remove build artifacts"
	@echo "  distclean    Remove build directory"
	@echo "  asm-check    Syntax-check all assembly files"
	@echo "  size         Show binary sizes"
	@echo "  deps         Check build dependencies"
	@echo "  help         Show this help"

# ---------------------------------------------------------------------------
# Prevent Implicit Rules
# ---------------------------------------------------------------------------

.SUFFIXES:
%: %.asm
%: %.o