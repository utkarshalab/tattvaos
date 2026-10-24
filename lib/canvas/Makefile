# ============================================================================
# Canvas Display Server — Build System for Utkarsha OS
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
               -D __UT__ \
               -D DEBUG_BUILD=1 \
               -I inc/ \
               -I src/ \
               -I ../ugfx/include/

# Linker Flags (Utkarsha image format)
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

# Utkarsha Bindings (C0)
UT_SRCS := \
    $(SRCDIR)/ut/ut_mem.asm \
    $(SRCDIR)/ut/ut_time.asm \
    $(SRCDIR)/ut/ut_log.asm \
    $(SRCDIR)/ut/ut_entropy.asm \
    $(SRCDIR)/ut/ut_wait.asm \
    $(SRCDIR)/ut/ut_platform.asm

# Core Library (C1)
CORE_SRCS := \
    $(SRCDIR)/core/arena.asm \
    $(SRCDIR)/core/str.asm \
    $(SRCDIR)/core/memops.asm \
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

# Graphics (C2) — lib/ugfx, the shared 2D/3D graphics library
UGFX_DIR := ../ugfx
GFX_SRCS := \
    $(UGFX_DIR)/core/pixbuf.asm \
    $(UGFX_DIR)/core/rect.asm \
    $(UGFX_DIR)/core/region.asm \
    $(UGFX_DIR)/core/fill.asm \
    $(UGFX_DIR)/core/blit.asm \
    $(UGFX_DIR)/core/blend.asm \
    $(UGFX_DIR)/core/blend_sse2.asm \
    $(UGFX_DIR)/core/blend_avx2.asm \
    $(UGFX_DIR)/core/blend_avx512.asm \
    $(UGFX_DIR)/core/scale.asm \
    $(UGFX_DIR)/core/transform.asm \
    $(UGFX_DIR)/core/clip.asm \
    $(UGFX_DIR)/2d/line.asm \
    $(UGFX_DIR)/2d/circle.asm \
    $(UGFX_DIR)/core/span.asm \
    $(UGFX_DIR)/core/raster.asm \
    $(UGFX_DIR)/core/mask.asm \
    $(UGFX_DIR)/core/umath_unit.asm \
    $(UGFX_DIR)/2d/path.asm \
    $(UGFX_DIR)/2d/shapes.asm \
    $(UGFX_DIR)/2d/stroke.asm \
    $(UGFX_DIR)/2d/flatten.asm \
    $(UGFX_DIR)/2d/dash.asm \
    $(UGFX_DIR)/2d/paint.asm \
    $(UGFX_DIR)/2d/context.asm \
    $(UGFX_DIR)/2d/list.asm \
    $(UGFX_DIR)/2d/uic.asm \
    $(UGFX_DIR)/2d/svg_syntax.asm \
    $(UGFX_DIR)/2d/svg_xml.asm \
    $(UGFX_DIR)/2d/svg_defs.asm \
    $(UGFX_DIR)/2d/svg.asm
GFX_OBJS := $(patsubst $(UGFX_DIR)/%.asm,$(OBJDIR)/ugfx/%.o,$(GFX_SRCS))

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

# Image (C21/C23)
IMG_SRCS := \
    $(SRCDIR)/img/crc32.asm \
    $(SRCDIR)/img/adler32.asm \
    $(SRCDIR)/img/huffman.asm \
    $(SRCDIR)/img/inflate.asm \
    $(SRCDIR)/img/zlib.asm \
    $(SRCDIR)/img/sniff.asm \
    $(SRCDIR)/img/png.asm \
    $(SRCDIR)/img/png_filter.asm \
    $(SRCDIR)/img/png_adam7.asm \
    $(SRCDIR)/img/jpeg.asm \
    $(SRCDIR)/img/jpeg_entropy.asm \
    $(SRCDIR)/img/jpeg_huff.asm \
    $(SRCDIR)/img/jpeg_mcu.asm \
    $(SRCDIR)/img/jpeg_idct.asm \
    $(SRCDIR)/img/jpeg_color.asm \
    $(SRCDIR)/img/jpeg_lossless.asm \
    $(SRCDIR)/img/lzw.asm \
    $(SRCDIR)/img/gif.asm \
    $(SRCDIR)/img/gif_animation.asm \
    $(SRCDIR)/img/bmp.asm \
    $(SRCDIR)/img/qoi.asm \
    $(SRCDIR)/img/tga.asm \
    $(SRCDIR)/img/pnm.asm \
    $(SRCDIR)/img/raw.asm \
    $(SRCDIR)/img/sensor.asm \
    $(SRCDIR)/img/dng.asm \
    $(SRCDIR)/img/dng_matrix.asm \
    $(SRCDIR)/img/pcx.asm \
    $(SRCDIR)/img/ico.asm \
    $(SRCDIR)/img/tiff.asm \
    $(SRCDIR)/img/tiff_lzw.asm \
    $(SRCDIR)/img/texture.asm \
    $(SRCDIR)/img/bc.asm \
    $(SRCDIR)/img/hdr.asm \
    $(SRCDIR)/img/exr.asm \
    $(SRCDIR)/img/psd.asm \
    $(SRCDIR)/img/camera.asm \
    $(SRCDIR)/img/modern.asm \
    $(SRCDIR)/img/farbfeld.asm \
    $(SRCDIR)/img/webp.asm \
    $(SRCDIR)/img/webp_animation.asm \
    $(SRCDIR)/img/webp_decode.asm \
    $(SRCDIR)/img/webp_entropy.asm \
    $(SRCDIR)/img/webp_vp8.asm \
    $(SRCDIR)/img/webp_vp8_tokens.asm \
    $(SRCDIR)/img/webp_vp8_macroblock.asm \
    $(SRCDIR)/img/webp_vp8_quant.asm \
      $(SRCDIR)/img/webp_vp8_recon.asm \
      $(SRCDIR)/img/webp_vp8_frame.asm \
      $(SRCDIR)/img/webp_vp8_filter.asm \
    $(SRCDIR)/img/webp_huffman.asm \
    $(SRCDIR)/img/webp_vp8l.asm \
    $(SRCDIR)/img/webp_transform.asm \
    $(SRCDIR)/img/webp_predict.asm \
    $(SRCDIR)/img/svg.asm

# Fonts (C22)
FONT_SRCS := \
    $(SRCDIR)/font/ttf.asm \
    $(SRCDIR)/font/ttf_tables.asm \
    $(SRCDIR)/font/cmap.asm \
    $(SRCDIR)/font/glyf.asm \
    $(SRCDIR)/font/outline.asm \
    $(SRCDIR)/font/flatten.asm \
    $(SRCDIR)/font/scanline.asm \
    $(SRCDIR)/font/glyph_cache.asm \
    $(SRCDIR)/font/kern.asm \
    $(SRCDIR)/font/metrics.asm \
    $(SRCDIR)/font/fallback.asm

# Color management (C25)
COLOR_SRCS := \
    $(SRCDIR)/color/srgb.asm \
    $(SRCDIR)/color/icc_parse.asm \
    $(SRCDIR)/color/matrix.asm \
    $(SRCDIR)/color/trc.asm \
    $(SRCDIR)/color/tonemap.asm \
    $(SRCDIR)/color/blend_linear.asm

# Server Core (C5-C8)
SERVER_SRCS := \
    $(SRCDIR)/server/main.asm \
    $(SRCDIR)/server/client/client.asm \
    $(SRCDIR)/server/client/client_registry.asm \
    $(SRCDIR)/server/client/auth.asm \
    $(SRCDIR)/server/buffer/buffer.asm \
    $(SRCDIR)/server/buffer/buffer_pool.asm \
    $(SRCDIR)/server/fence/fence.asm \
    $(SRCDIR)/server/fence/fence_full.asm \
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
    $(SRCDIR)/render/sw_transform.asm \
    $(SRCDIR)/render/gpu_render.asm \
    $(SRCDIR)/render/gpu_blit.asm \
    $(SRCDIR)/render/gpu_cmdring.asm

# GPU (C24)
GPU_SRCS := \
    $(SRCDIR)/gpu/gpu_iface.asm \
    $(SRCDIR)/gpu/gpu_ring.asm \
    $(SRCDIR)/gpu/gpu_fence.asm \
    $(SRCDIR)/gpu/gpu_mem.asm \
    $(SRCDIR)/gpu/family/gfx9.asm

# Backend (C9)
BACKEND_SRCS := \
    $(SRCDIR)/backend/backend_dispatch.asm \
    $(SRCDIR)/backend/headless/headless_full.asm \
    $(SRCDIR)/backend/fb_linear/fb_linear_full.asm \
    $(SRCDIR)/backend/remote_backend.asm \
    $(SRCDIR)/backend/native/native_pci.asm \
    $(SRCDIR)/backend/native/native_edid.asm \
    $(SRCDIR)/backend/native/native_ddc.asm \
    $(SRCDIR)/backend/native/native_full.asm

# Codec (C26/C27)
CODEC_SRCS := \
    $(SRCDIR)/codec/deflate.asm \
    $(SRCDIR)/codec/lz.asm \
    $(SRCDIR)/codec/rle.asm \
    $(SRCDIR)/codec/tile_diff.asm \
    $(SRCDIR)/codec/delta.asm \
    $(SRCDIR)/codec/adaptive.asm

# Remote display (C26/C27)
REMOTE_SRCS := \
    $(SRCDIR)/remote/virtual_output.asm \
    $(SRCDIR)/remote/rfb_server.asm \
    $(SRCDIR)/remote/rfb_handshake.asm \
    $(SRCDIR)/remote/rfb_tls.asm \
    $(SRCDIR)/remote/rfb_auth.asm \
    $(SRCDIR)/remote/rfb_encode_raw.asm \
    $(SRCDIR)/remote/rfb_encode_zlib.asm \
    $(SRCDIR)/remote/rfb_input.asm \
    $(SRCDIR)/remote/rfb_clipboard.asm \
    $(SRCDIR)/remote/crp_server.asm \
    $(SRCDIR)/remote/crp_codec.asm \
    $(SRCDIR)/remote/crp_session.asm \
    $(SRCDIR)/remote/crp_share.asm

# Native DCN Family (C10)
DCN_SRCS := \
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
    $(SRCDIR)/input/source_ut.asm \
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
    $(SRCDIR)/input/cursor_theme.asm \
    $(SRCDIR)/input/data_source.asm \
    $(SRCDIR)/input/surface_events.asm

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
    $(SRCDIR)/shell/icons.asm \
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

# Sessions (C18)
SESSION_SRCS := \
    $(SRCDIR)/session/seat_session.asm \
    $(SRCDIR)/session/multiseat.asm \
    $(SRCDIR)/session/user_session.asm \
    $(SRCDIR)/session/lock.asm \
    $(SRCDIR)/session/idle.asm \
    $(SRCDIR)/session/kiosk.asm \
    $(SRCDIR)/session/power.asm

# Governance (C19)
GOVERNANCE_SRCS := \
    $(SRCDIR)/governance/quota.asm \
    $(SRCDIR)/governance/ratelimit.asm \
    $(SRCDIR)/governance/watchdog.asm \
    $(SRCDIR)/governance/containment.asm \
    $(SRCDIR)/governance/scheduler.asm \
    $(SRCDIR)/governance/accounting.asm

# Observability (C20)
OBS_SRCS := \
    $(SRCDIR)/obs/trace.asm \
    $(SRCDIR)/obs/timeline.asm \
    $(SRCDIR)/obs/protolog.asm \
    $(SRCDIR)/obs/record.asm \
    $(SRCDIR)/obs/replay.asm \
    $(SRCDIR)/obs/metrics.asm \
    $(SRCDIR)/obs/stats.asm \
    $(SRCDIR)/obs/debug_iface.asm \
    $(SRCDIR)/obs/faultdump.asm

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
ALL_SRCS    := $(UT_SRCS) $(CORE_SRCS) $(GFX_SRCS) $(PROTO_SRCS) $(IMG_SRCS) $(COLOR_SRCS) $(FONT_SRCS) $(SERVER_SRCS) $(RENDER_SRCS) $(GPU_SRCS) $(BACKEND_SRCS) $(DCN_SRCS) $(OUTPUT_SRCS) $(INPUT_SRCS) $(SHELL_SRCS) $(POLICY_SRCS) $(DATA_SRCS) $(SECURITY_SRCS) $(SESSION_SRCS) $(GOVERNANCE_SRCS) $(OBS_SRCS) $(CODEC_SRCS) $(REMOTE_SRCS) $(TEXT_SRCS) $(A11Y_SRCS)

# Object Files
ALL_OBJS    := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(filter $(SRCDIR)/%,$(ALL_SRCS))) $(GFX_OBJS)
UT_OBJS := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(UT_SRCS))

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
CLIENT_SRCS := \
    $(SRCDIR)/client/conn.asm \
    $(SRCDIR)/client/client.asm \
    $(SRCDIR)/client/objects.asm \
    $(SRCDIR)/client/buffer_pool.asm \
    $(SRCDIR)/client/surface_helpers.asm \
    $(SRCDIR)/client/buffer_helpers.asm \
    $(SRCDIR)/client/events.asm \
    $(SRCDIR)/client/event_loop.asm \
    $(SRCDIR)/client/input_helpers.asm \
    $(SRCDIR)/client/shell_helpers.asm \
    $(SRCDIR)/client/clipboard_helpers.asm \
    $(SRCDIR)/client/present_helpers.asm
CLIENT_OBJS := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(CLIENT_SRCS))
CLIENT_RUNTIME_OBJS := \
    $(OBJDIR)/core/arena.o \
    $(OBJDIR)/core/memops.o \
    $(OBJDIR)/core/ring.o

client: $(LIBDIR)/canvas_client.o

$(LIBDIR)/canvas_client.o: $(CLIENT_OBJS)
	@mkdir -p $(LIBDIR)
	$(LD) -r -o $@ $^
	@echo "  LIB    $@"

# Tools (cwpgen, canvasctl, etc.)
TOOLS := cwpgen canvasctl canvas_info canvas_inspect canvas_record canvas_replay canvas_bench cwplint
TOOL_IMGS := $(addprefix $(IMAGEDIR)/,$(addsuffix .img,$(TOOLS)))

tools: $(TOOL_IMGS)

$(TOOL_IMGS): $(IMAGEDIR)/%.img: $(OBJDIR)/tools/%.o $(ALL_OBJS)
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e tool_main -o $@ $^
	@echo "  IMG    $@"

# Reference Clients
CLIENTS := demo_windows demo_alpha demo_subsurfaces input_test clipboard_test dnd_test ime_test a11y_test panel wallpaper lockscreen bench_latency bench_throughput stress_clients
CLIENT_IMGS := $(addprefix $(IMAGEDIR)/,$(addsuffix .img,$(CLIENTS)))

clients: $(CLIENT_IMGS)

$(CLIENT_IMGS): $(IMAGEDIR)/%.img: $(OBJDIR)/clients/%.o $(LIBDIR)/canvas_client.o $(UT_OBJS) $(CLIENT_RUNTIME_OBJS)
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e client_main -o $@ $^
	@echo "  IMG    $@"

# ---------------------------------------------------------------------------
# Compilation Rules
# ---------------------------------------------------------------------------

$(OBJDIR)/%.o: $(SRCDIR)/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<
	@echo "  ASM    $<"

# the umath unit %includes lib/umath sources: rebuild it when they change
$(OBJDIR)/ugfx/core/umath_unit.o: $(wildcard ../umath/geom/*.asm ../umath/math_fn/*.asm ../umath/scalar/*.asm)

# the built-in UI icons are embedded with incbin
$(OBJDIR)/shell/icons.o: assets/icons/ui.uic

# rebuild assets/icons/ui.uic from assets/icons/ui/*.svg (development machine: python3)
.PHONY: ui-icons
ui-icons:
	python3 ../ugfx/tools/svg2uic.py assets/icons/ui.uic assets/icons/ui

$(OBJDIR)/ugfx/%.o: $(UGFX_DIR)/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I ../../ -o $@ $<
	@echo "  ASM    $<"

# ---------------------------------------------------------------------------
# Linker Script
# ---------------------------------------------------------------------------

linker.ld:
	@printf '%s\n' \
		'ENTRY(canvasd_init)' \
		'SECTIONS' \
		'{' \
		'    . = 0x200000;' \
		'    .text : { *(.text*) }' \
		'    .rodata : { *(.rodata*) }' \
		'    .data : { *(.data*) }' \
		'    .bss : { *(.bss*) *(COMMON) }' \
		'    /DISCARD/ : { *(.note.*) *(.comment*) }' \
		'}' > $@

# ---------------------------------------------------------------------------
# Test Targets
# ---------------------------------------------------------------------------

UNIT_SRCS := \
    tests/unit/test_arena.asm \
    tests/unit/test_str.asm \
    tests/unit/test_ring.asm \
    tests/unit/test_handle.asm \
    tests/unit/test_region.asm \
    tests/unit/test_map.asm \
    tests/unit/test_quota.asm \
    tests/unit/test_record_replay.asm \
    tests/unit/test_jpeg.asm \
    tests/unit/test_icc.asm \
    tests/unit/test_tile_diff.asm \
    tests/unit/test_rfb.asm \
    tests/unit/test_inflate.asm \
    tests/unit/test_png.asm \
    tests/unit/test_webp.asm \
    tests/unit/test_ttf.asm
UNIT_OBJS := $(patsubst tests/%.asm,$(OBJDIR)/tests/%.o,$(UNIT_SRCS))

# Test runner image
$(IMAGEDIR)/test_runner.img: $(OBJDIR)/tests/test_runner.o $(UNIT_OBJS) $(UT_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GFX_OBJS) $(PROTO_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(IMG_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(COLOR_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(FONT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GPU_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(BACKEND_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DCN_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(INPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SHELL_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(POLICY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DATA_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(TEXT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(A11Y_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SECURITY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SESSION_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GOVERNANCE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OBS_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(CODEC_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(REMOTE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $(filter-out linker.ld,$^)
	@echo "  IMG    $@"

# Golden test image
$(IMAGEDIR)/golden_test.img: $(OBJDIR)/tests/golden/golden_test.o $(UT_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GFX_OBJS) $(PROTO_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(IMG_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(COLOR_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(FONT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GPU_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(BACKEND_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DCN_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(INPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SHELL_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(POLICY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DATA_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(TEXT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(A11Y_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SECURITY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SESSION_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GOVERNANCE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OBS_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(CODEC_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(REMOTE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $(filter-out linker.ld,$^)
	@echo "  IMG    $@"

# Fuzz targets (C31)
FUZZ_SRCS := \
    tests/fuzz/fuzz_wire.asm \
    tests/fuzz/fuzz_objects.asm \
    tests/fuzz/fuzz_keymap_config.asm \
    tests/fuzz/fuzz_media.asm

# Soak tests (C31)
SOAK_SRCS := \
    tests/soak/soak_churn.asm \
    tests/soak/soak_hotplug.asm \
    tests/soak/soak_quota.asm

# Bench harness (C32)
BENCH_SRCS := \
    tests/bench/bench_idle.asm \
    tests/bench/bench_latency.asm \
    tests/bench/bench_compose.asm \
    tests/bench/bench_memory.asm

# Conformance suite (C33)
CTS_SRCS := \
    tests/cts/cts_core.asm \
    tests/cts/cts_surface.asm \
    tests/cts/cts_sync.asm \
    tests/cts/cts_present.asm \
    tests/cts/cts_output.asm \
    tests/cts/cts_input.asm \
    tests/cts/cts_shell.asm \
    tests/cts/cts_data.asm \
    tests/cts/cts_text.asm \
    tests/cts/cts_security.asm \
    tests/cts/cts_governance.asm
CTS_OBJS := $(patsubst tests/%.asm,$(OBJDIR)/tests/%.o,$(CTS_SRCS))
SOAK_OBJS := $(patsubst tests/%.asm,$(OBJDIR)/tests/%.o,$(SOAK_SRCS))
BENCH_OBJS := $(patsubst tests/%.asm,$(OBJDIR)/tests/%.o,$(BENCH_SRCS))
FUZZ_EXTRA_OBJS := $(patsubst tests/%.asm,$(OBJDIR)/tests/%.o,$(FUZZ_SRCS))

# Fuzz runner image
$(IMAGEDIR)/fuzz_runner.img: $(OBJDIR)/tests/fuzz/fuzz_driver.o $(FUZZ_EXTRA_OBJS) $(UT_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(PROTO_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(IMG_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(COLOR_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(FONT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GPU_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(BACKEND_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DCN_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(INPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SHELL_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(POLICY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DATA_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(TEXT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(A11Y_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SECURITY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SESSION_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GOVERNANCE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OBS_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(CODEC_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(REMOTE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $(filter-out linker.ld,$^)
	@echo "  IMG    $@"

# Replay test image
$(IMAGEDIR)/replay_test.img: $(OBJDIR)/tests/replay/replay_test.o $(UT_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(PROTO_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GPU_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(BACKEND_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DCN_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(INPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SHELL_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(POLICY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(DATA_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(TEXT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(A11Y_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SECURITY_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SESSION_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(GOVERNANCE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OBS_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(CODEC_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(REMOTE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $(filter-out linker.ld,$^)
	@echo "  IMG    $@"

# Test target
.PHONY: test
test: $(IMAGEDIR)/test_runner.img $(IMAGEDIR)/golden_test.img $(IMAGEDIR)/fuzz_runner.img $(IMAGEDIR)/replay_test.img
	@echo "All test images built"
	@echo "Run on Utkarsha to execute tests"

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

$(OBJDIR)/tests/soak/%.o: tests/soak/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/bench/%.o: tests/bench/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/cts/%.o: tests/cts/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

# ---------------------------------------------------------------------------
# Host Tests (development machine only; never part of an OS image)
#   tests/host/ut_host.asm stands in for the ut_* bindings, so unit suites and
#   decoders run as ordinary processes. --gc-sections drops unused modules.
# ---------------------------------------------------------------------------

HOSTDIR       := $(BUILDDIR)/host
HOST_SUITES   := webp
HOST_LIB_OBJS := $(filter-out $(UT_OBJS) $(OBJDIR)/server/main.o,$(ALL_OBJS))
HOST_LDFLAGS  := -nostdlib -static --gc-sections -e _start
HOST_TESTS    := $(addprefix $(HOSTDIR)/test_,$(HOST_SUITES))

$(HOSTDIR)/%.o: tests/host/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(HOSTDIR)/runner_%.o: tests/host/host_runner.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -D HOST_SUITE=test_$*_suite -o $@ $<

$(HOSTDIR)/test_%: $(HOSTDIR)/runner_%.o $(OBJDIR)/tests/unit/test_%.o $(HOSTDIR)/ut_host.o $(HOST_LIB_OBJS)
	$(LD) $(HOST_LDFLAGS) -o $@ $^

$(HOSTDIR)/host_decode: $(HOSTDIR)/host_decode.o $(HOSTDIR)/ut_host.o $(HOST_LIB_OBJS)
	$(LD) $(HOST_LDFLAGS) -o $@ $^

$(HOSTDIR)/host_ui: $(HOSTDIR)/host_ui.o $(HOSTDIR)/ut_host.o $(HOST_LIB_OBJS)
	$(LD) $(HOST_LDFLAGS) -o $@ $^

.PHONY: host host-check
host: $(HOST_TESTS) $(HOSTDIR)/host_decode $(HOSTDIR)/host_ui

host-check: host
	@set -e; for t in $(HOST_TESTS); do $$t; done
	$(MAKE) -C ../ugfx host
	python3 tests/host/svg_decode_check.py $(HOSTDIR)/host_decode ../ugfx/$(BUILDDIR)/host_ctx
	python3 tests/host/ui_icons_check.py $(HOSTDIR)/host_ui ../ugfx/$(BUILDDIR)/host_ctx
	python3 tests/host/compare_images.py $(HOSTDIR)/host_decode

.PHONY: fuzz
fuzz: $(IMAGEDIR)/fuzz_runner.img
	@echo "Running fuzz tests..."

# Soak test image (C31)
$(IMAGEDIR)/soak_test.img: $(OBJDIR)/tests/soak_runner.o $(SOAK_OBJS) $(UT_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(OUTPUT_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e soak_runner_init -o $@ $^
	@echo "  IMG    $@"

.PHONY: soak
soak: $(IMAGEDIR)/soak_test.img
	@echo "Running 24h soak test..."

# Bench runner image (C32)
$(IMAGEDIR)/bench_runner.img: $(OBJDIR)/tests/bench_runner.o $(BENCH_OBJS) $(UT_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(SERVER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) $(RENDER_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e bench_runner_init -o $@ $^
	@echo "  IMG    $@"

.PHONY: bench
bench: $(IMAGEDIR)/bench_runner.img
	@echo "Running benchmarks..."

# CTS runner image (C33)
$(IMAGEDIR)/cts_runner.img: $(OBJDIR)/tests/cts_runner.o $(CTS_OBJS) $(CLIENT_OBJS) $(UT_OBJS) $(CORE_SRCS:$(SRCDIR)/%.asm=$(OBJDIR)/%.o) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e cts_runner_init -o $@ $^
	@echo "  IMG    $@"

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
	@echo "  host         Build host test binaries (development machine)"
	@echo "  host-check   Run host unit suites and decoder conformance"
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
