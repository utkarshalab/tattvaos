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

# Build mode: make (debug) or make release (MODE=release)
#   debug    DEBUG_BUILD=1, PARANOID_CHECKS=1: assertions and checks on; build/
#   release  DEBUG_BUILD=0, PARANOID_CHECKS=0: checks compiled out; build/release/
# Both treat every assembler warning as an error.
MODE        ?= debug
ifeq ($(MODE),release)
MODE_FLAGS  := -D DEBUG_BUILD=0 -D PARANOID_CHECKS=0 -D TRAP_ON_PANIC=0
MODE_DIR    := /release
else ifeq ($(MODE),debug)
MODE_FLAGS  := -D DEBUG_BUILD=1 -D PARANOID_CHECKS=1 -D TRAP_ON_PANIC=1
MODE_DIR    :=
else
$(error MODE must be debug or release, not '$(MODE)')
endif

# NASM Flags
NASMFLAGS   := -f elf64 -g -F dwarf -Werror \
               -D __UT__ \
               $(MODE_FLAGS) \
               -I inc/ \
               -I src/ \
               -I ../ugfx/include/ \
               -I ../ufont/include/ -I ../ufont/layout/

# Linker Flags (Utkarsha image format)
LDFLAGS     := -nostdlib -static -z max-page-size=0x1000 \
               -T linker.ld \
               --build-id=none

# Directories
SRCDIR      := src
INCDIR      := inc
BUILDDIR    := build$(MODE_DIR)

# Layouts live in headers: a changed header reassembles everything
HEADERS     := $(wildcard inc/*.inc)
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
    $(SRCDIR)/ut/ut_platform.asm \
    $(SRCDIR)/core/panic.asm

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
    $(UGFX_DIR)/2d/svg.asm \
    $(UGFX_DIR)/2d/filter.asm
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

# Fonts (C22): lib/ufont, assembled into this build like lib/ugfx
UFONT_DIR := ../ufont
FONT_SRCS := \
    $(UFONT_DIR)/sfnt/sfnt.asm \
    $(UFONT_DIR)/sfnt/cff.asm \
    $(UFONT_DIR)/sfnt/woff.asm \
    $(UFONT_DIR)/sfnt/woff2.asm \
    $(UFONT_DIR)/sfnt/brotli.asm \
    $(UFONT_DIR)/sfnt/brotli_tables.asm \
    $(UFONT_DIR)/sfnt/var.asm \
    $(UFONT_DIR)/match/fontset.asm \
    $(UFONT_DIR)/match/standard.asm \
    $(UFONT_DIR)/layout/shape.asm \
    $(UFONT_DIR)/layout/buffer.asm \
    $(UFONT_DIR)/layout/unicode.asm \
    $(UFONT_DIR)/layout/normalize.asm \
    $(UFONT_DIR)/layout/otl.asm \
    $(UFONT_DIR)/layout/map.asm \
    $(UFONT_DIR)/layout/apply.asm \
    $(UFONT_DIR)/layout/gsub.asm \
    $(UFONT_DIR)/layout/gpos.asm \
    $(UFONT_DIR)/layout/indic.asm \
    $(UFONT_DIR)/layout/arabic.asm \
    $(UFONT_DIR)/layout/fallback.asm \
    $(UFONT_DIR)/layout/bidi.asm \
    $(UFONT_DIR)/layout/thai.asm \
    $(UFONT_DIR)/layout/hangul.asm \
    $(UFONT_DIR)/layout/syllabic.asm \
    $(UFONT_DIR)/layout/khmer.asm \
    $(UFONT_DIR)/layout/myanmar.asm \
    $(UFONT_DIR)/layout/use.asm \
    $(UFONT_DIR)/layout/use_table.asm \
    $(UFONT_DIR)/layout/ucd.asm \
    $(UFONT_DIR)/layout/indic_table.asm
FONT_OBJS := $(patsubst $(UFONT_DIR)/%.asm,$(OBJDIR)/ufont/%.o,$(FONT_SRCS))

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
    $(SRCDIR)/server/server_core.asm \
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
    $(SRCDIR)/backend/native/native_full.asm \
    $(SRCDIR)/backend/native/native_planes.asm

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
    $(SRCDIR)/input/source_virtual.asm \
    $(SRCDIR)/input/keymap_us.asm \
    $(SRCDIR)/input/compose.asm \
    $(SRCDIR)/input/accel.asm \
    $(SRCDIR)/input/constraints.asm \
    $(SRCDIR)/input/touch.asm \
    $(SRCDIR)/input/gestures.asm \
    $(SRCDIR)/input/tablet.asm \
    $(SRCDIR)/input/grab.asm \
    $(SRCDIR)/input/cursor.asm \
    $(SRCDIR)/input/cursor_theme.asm \
    $(SRCDIR)/input/data_source.asm \
    $(SRCDIR)/input/surface_events.asm

# Shell (C13)
SHELL_SRCS := \
    $(SRCDIR)/shell/toplevel.asm \
    $(SRCDIR)/shell/configure.asm \
    $(SRCDIR)/shell/decoration.asm \
    $(SRCDIR)/shell/decoration_draw.asm \
    $(SRCDIR)/shell/icons.asm \
    $(SRCDIR)/shell/stacking.asm \
    $(SRCDIR)/shell/window.asm \
    $(SRCDIR)/shell/window_list.asm \
    $(SRCDIR)/shell/titlebar.asm

# Policy (C13)
POLICY_SRCS := \
    $(SRCDIR)/policy/policy_iface.asm

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
    $(SRCDIR)/session/power.asm \
    $(SRCDIR)/session/greeter.asm \
    $(SRCDIR)/session/login.asm

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
    $(SRCDIR)/obs/faultdump.asm \
    $(SRCDIR)/obs/invariants.asm

# Text & A11y (C16)
TEXT_SRCS := \
    $(SRCDIR)/text/text_input.asm \
    $(SRCDIR)/text/preedit.asm \
    $(SRCDIR)/text/ime_bridge.asm \
    $(SRCDIR)/text/ui_text.asm

A11Y_SRCS := \
    $(SRCDIR)/a11y/a11y_tree.asm \
    $(SRCDIR)/a11y/a11y_events.asm \
    $(SRCDIR)/a11y/a11y_reader_hooks.asm \
    $(SRCDIR)/a11y/sticky_keys.asm \
    $(SRCDIR)/a11y/magnifier.asm \
    $(SRCDIR)/a11y/high_contrast.asm

# Client library: linked into canvasd (the greeter) and client images
CLIENT_SRCS := \
    $(SRCDIR)/client/conn.asm \
    $(SRCDIR)/client/wire.asm \
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

# Protocol numbers and dispatch: inc/cwp_ops.inc, inc/cwp_dispatch.inc are
# generated from these
CWP_OPS_PROTOS := proto/canvas-core.cwp proto/canvas-input.cwp proto/canvas-shell.cwp

# Desktop components inside canvasd
DESKTOP_SRCS := \
    $(SRCDIR)/desktop/taskbar.asm

# All Sources
ALL_SRCS    := $(UT_SRCS) $(CORE_SRCS) $(GFX_SRCS) $(PROTO_SRCS) $(IMG_SRCS) $(COLOR_SRCS) $(FONT_SRCS) $(SERVER_SRCS) $(RENDER_SRCS) $(GPU_SRCS) $(BACKEND_SRCS) $(DCN_SRCS) $(OUTPUT_SRCS) $(INPUT_SRCS) $(SHELL_SRCS) $(POLICY_SRCS) $(DATA_SRCS) $(SECURITY_SRCS) $(SESSION_SRCS) $(GOVERNANCE_SRCS) $(OBS_SRCS) $(CODEC_SRCS) $(REMOTE_SRCS) $(TEXT_SRCS) $(A11Y_SRCS) $(CLIENT_SRCS) $(DESKTOP_SRCS)

# Object Files
ALL_OBJS    := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(filter $(SRCDIR)/%,$(ALL_SRCS))) $(GFX_OBJS) $(FONT_OBJS)
UT_OBJS := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(UT_SRCS))

# ---------------------------------------------------------------------------
# Default Target
# ---------------------------------------------------------------------------

.PHONY: all release cwp-ops cwp-check
all: cwp-check layout-check server ubf client tools clients

release:
	$(MAKE) MODE=release all

# inc/cwp_ops.inc and inc/cwp_dispatch.inc from the protocol files;
# cwp-check fails if either is behind
cwp-ops:
	python3 tools/cwpgen.py -o inc/cwp_ops.inc -d inc/cwp_dispatch.inc $(CWP_OPS_PROTOS)

cwp-check:
	@python3 tools/cwpgen.py --check -o inc/cwp_ops.inc -d inc/cwp_dispatch.inc \
	    --handlers src/server/server_core.asm $(CWP_OPS_PROTOS)

# ---------------------------------------------------------------------------
# Layout check: every object's fields live in its one struc. Fails on a
# struct field %define'd outside a struc, on DEFINE_STRUCT_OFFSET, and on a
# struc name defined in more than one file (NASM itself rejects a struc
# label defined twice within one file).
# ---------------------------------------------------------------------------
LAYOUT_DIRS := src inc tests

.PHONY: layout-check
layout-check:
	@! grep -rnE '^\s*%(x?define|assign)\s+[A-Z][A-Za-z0-9]*\.[a-z]' --include='*.asm' --include='*.inc' $(LAYOUT_DIRS) \
	    || { echo "layout-check: struct fields defined outside their struc (above)"; exit 1; }
	@! grep -rn 'DEFINE_STRUCT_OFFSET' --include='*.asm' --include='*.inc' $(LAYOUT_DIRS) \
	    || { echo "layout-check: DEFINE_STRUCT_OFFSET is retired; use a struc"; exit 1; }
	@d=$$(grep -rhoE '^\s*struc\s+\w+' --include='*.asm' --include='*.inc' $(LAYOUT_DIRS) | awk '{print $$2}' | sort | uniq -d); \
	    if [ -n "$$d" ]; then echo "layout-check: struc defined in more than one file: $$d"; exit 1; fi

# ---------------------------------------------------------------------------
# Build Targets
# ---------------------------------------------------------------------------

# Canvas Server Image (canvasd)
server: $(IMAGEDIR)/canvasd.img

$(IMAGEDIR)/canvasd.img: $(ALL_OBJS) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $(ALL_OBJS)
	@echo "  IMG    $@"

# The same program as a UBF: the kernel's exports take the place of src/ut.
# UBF_REQUIRED must resolve at load; every other ut_ name is a weak import
# whose stub returns -ENOSYS until the kernel exports it.
UBF          := $(IMAGEDIR)/canvasd.ubf
UBF_OBJS     := $(filter-out $(UT_OBJS),$(ALL_OBJS)) $(OBJDIR)/core/panic.o
UBF_REQUIRED := ut_mem_alloc,ut_mem_free,ut_time_now_ns,ut_log_write,ut_fb_info,ut_yield

# After UBF is defined: a prerequisite expands where its rule is read
ubf: $(UBF)

$(UBF): $(UBF_OBJS) ubf.ld tools/ubfpack.py
	@mkdir -p $(IMAGEDIR)
	@python3 tools/ubfpack.py -o $@ --script ubf.ld --entry canvasd_init \
	    --require $(UBF_REQUIRED) $(UBF_OBJS)

CLIENT_OBJS := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(CLIENT_SRCS))
CLIENT_RUNTIME_OBJS := \
    $(OBJDIR)/core/arena.o \
    $(OBJDIR)/core/memops.o \
    $(OBJDIR)/core/ring.o \
    $(OBJDIR)/proto/msgbuf.o

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

$(OBJDIR)/%.o: $(SRCDIR)/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<
	@echo "  ASM    $<"

# the umath unit %includes lib/umath sources: rebuild it when they change
$(OBJDIR)/ugfx/core/umath_unit.o: $(wildcard ../umath/geom/*.asm ../umath/math_fn/*.asm ../umath/scalar/*.asm)

# the built-in UI icons are embedded with incbin
$(OBJDIR)/shell/icons.o: assets/icons/ui.uic

# Canvas sources that use ugfx's structures (a UgfxContext on the stack)
$(OBJDIR)/shell/icons.o $(OBJDIR)/img/svg.o: $(UGFX_DIR)/include/ugfx.inc

# rebuild assets/icons/ui.uic from assets/icons/ui/*.svg (development machine: python3)
.PHONY: ui-icons
ui-icons:
	python3 ../ugfx/tools/svg2uic.py assets/icons/ui.uic assets/icons/ui

$(OBJDIR)/ugfx/%.o: $(UGFX_DIR)/%.asm $(UGFX_DIR)/include/ugfx.inc $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I ../../ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/ufont/%.o: $(UFONT_DIR)/%.asm $(UFONT_DIR)/include/ufont.inc $(UFONT_DIR)/layout/shape.inc $(UGFX_DIR)/include/ugfx.inc $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<
	@echo "  ASM    $<"

# linker.ld (tracked, W^X segments) is the one link layout; nothing generates
# or deletes it.

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
    tests/unit/test_vec.asm \
    tests/unit/test_tree.asm \
    tests/unit/test_misc.asm \
    tests/unit/test_gpu.asm \
    tests/unit/test_proto.asm \
    tests/unit/test_client.asm \
    tests/unit/test_surface.asm \
    tests/unit/test_server.asm \
    tests/unit/test_input.asm \
    tests/unit/test_greeter.asm \
    tests/unit/test_window.asm \
    tests/unit/test_taskbar.asm \
    tests/unit/test_ui_text.asm \
    tests/unit/test_clientlib.asm \
    tests/unit/test_fields.asm
UNIT_OBJS := $(patsubst tests/%.asm,$(OBJDIR)/tests/%.o,$(UNIT_SRCS))

# What the test images link: everything the server links but its entry (server/main)
TEST_LIB_OBJS := $(filter-out $(OBJDIR)/server/main.o,$(ALL_OBJS))

# Test runner image
$(IMAGEDIR)/test_runner.img: $(OBJDIR)/tests/test_runner.o $(UNIT_OBJS) $(UT_OBJS) $(TEST_LIB_OBJS) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e test_runner_init -o $@ $(filter-out linker.ld,$^)
	@echo "  IMG    $@"

# Golden test image
$(IMAGEDIR)/golden_test.img: $(OBJDIR)/tests/golden/golden_test.o $(OBJDIR)/tests/unit/test_golden.o $(UT_OBJS) $(TEST_LIB_OBJS) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e golden_test_main -o $@ $(filter-out linker.ld,$^)
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
$(IMAGEDIR)/fuzz_runner.img: $(OBJDIR)/tests/fuzz/fuzz_driver.o $(FUZZ_EXTRA_OBJS) $(UT_OBJS) $(TEST_LIB_OBJS) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e fuzz_driver_main -o $@ $(filter-out linker.ld,$^)
	@echo "  IMG    $@"

# Replay test image
$(IMAGEDIR)/replay_test.img: $(OBJDIR)/tests/replay/replay_test.o $(UT_OBJS) $(TEST_LIB_OBJS) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -e replay_test_main -o $@ $(filter-out linker.ld,$^)
	@echo "  IMG    $@"

# Test target
.PHONY: test
test: $(IMAGEDIR)/test_runner.img $(IMAGEDIR)/golden_test.img $(IMAGEDIR)/fuzz_runner.img $(IMAGEDIR)/replay_test.img
	@echo "All test images built"
	@echo "Run on Utkarsha to execute tests"

# ---------------------------------------------------------------------------
# Test Compilation Rules
# ---------------------------------------------------------------------------

$(OBJDIR)/tests/%.o: tests/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/golden/%.o: tests/golden/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/fuzz/%.o: tests/fuzz/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/replay/%.o: tests/replay/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/input/%.o: tests/input/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/soak/%.o: tests/soak/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/bench/%.o: tests/bench/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

$(OBJDIR)/tests/cts/%.o: tests/cts/%.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -I inc/ -o $@ $<
	@echo "  ASM    $<"

# ---------------------------------------------------------------------------
# Host Tests (development machine only; never part of an OS image)
#   tests/host/ut_host.asm stands in for the ut_* bindings, so unit suites and
#   decoders run as ordinary processes. --gc-sections drops unused modules.
# ---------------------------------------------------------------------------

HOSTDIR       := $(BUILDDIR)/host
HOST_SUITES   := arena str map handle ring vec tree misc gpu proto client surface golden server input greeter window taskbar ui_text clientlib fields region quota tile_diff \
                 inflate icc record_replay rfb webp png jpeg
HOST_LIB_OBJS := $(filter-out $(UT_OBJS) $(OBJDIR)/server/main.o,$(ALL_OBJS))
HOST_LDFLAGS  := -nostdlib -static --gc-sections -e _start
HOST_TESTS    := $(addprefix $(HOSTDIR)/test_,$(HOST_SUITES))

$(HOSTDIR)/%.o: tests/host/%.asm $(UFONT_DIR)/include/ufont.inc $(UGFX_DIR)/include/ugfx.inc $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<

$(HOSTDIR)/runner_%.o: tests/host/host_runner.asm $(HEADERS)
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -D HOST_SUITE=test_$*_suite -o $@ $<

$(HOSTDIR)/test_%: $(HOSTDIR)/runner_%.o $(OBJDIR)/tests/unit/test_%.o $(HOSTDIR)/ut_host.o $(HOST_LIB_OBJS)
	$(LD) $(HOST_LDFLAGS) -o $@ $^

$(HOSTDIR)/host_decode: $(HOSTDIR)/host_decode.o $(HOSTDIR)/ut_host.o $(HOST_LIB_OBJS)
	$(LD) $(HOST_LDFLAGS) -o $@ $^

$(HOSTDIR)/host_ui: $(HOSTDIR)/host_ui.o $(HOSTDIR)/ut_host.o $(HOST_LIB_OBJS)
	$(LD) $(HOST_LDFLAGS) -o $@ $^

$(HOSTDIR)/ubf_run: $(HOSTDIR)/ubf_run.o $(HOSTDIR)/ut_host.o $(HOST_LIB_OBJS)
	$(LD) $(HOST_LDFLAGS) -o $@ $^

.PHONY: host host-check
host: $(HOST_TESTS) $(HOSTDIR)/host_decode $(HOSTDIR)/host_ui

host-check: host
	@set -e; for t in $(HOST_TESTS); do $$t; done
	$(MAKE) -C ../ugfx host
	python3 tests/host/svg_decode_check.py $(HOSTDIR)/host_decode ../ugfx/$(BUILDDIR)/host_ctx
	python3 tests/host/svg_text_check.py $(HOSTDIR)/host_decode ../ugfx/$(BUILDDIR)/host_ctx ../ufont/fonts
	python3 tests/host/ui_icons_check.py $(HOSTDIR)/host_ui ../ugfx/$(BUILDDIR)/host_ctx
	python3 tests/host/compare_images.py $(HOSTDIR)/host_decode

# The UBF passes the loader's checks, then runs to its first frame on what the
# kernel exports.
.PHONY: ubf-check
ubf-check: $(UBF) $(HOSTDIR)/ubf_run
	python3 tests/host/ubf_check.py $(UBF) $(UBF_REQUIRED)
	$(HOSTDIR)/ubf_run $(UBF)

# Every image must keep W^X: no segment both writable and executable.
.PHONY: wx-check
wx-check: all
	@for f in $(IMAGEDIR)/*.img; do \
	    if readelf -lW $$f | awk '$$1 == "LOAD" && $$7 ~ /W/ && $$7 ~ /E/' | grep -q .; then \
	        echo "wx-check: $$f has a writable and executable segment"; exit 1; \
	    fi; \
	done
	@echo "wx-check: every image is W^X"

# No access may be wider than the struc field it names.
.PHONY: field-width-check
field-width-check:
	@python3 tests/host/field_width_check.py .

# UBF programs load above 4 GiB: no object may hold a 32-bit absolute address.
.PHONY: pic-check
pic-check: all
	@for o in $(ALL_OBJS); do \
	    if readelf -rW $$o | awk '/^Relocation section/ { s = $$3 } \
	            /R_X86_64_32/ && s !~ /debug/' | grep -q .; then \
	        echo "pic-check: $$o has a 32-bit absolute reference"; exit 1; \
	    fi; \
	done
	@echo "pic-check: every object is position independent"

# Everything a change must pass: the layout and field checks, all images and
# test images in debug and release, W^X and position independence, the host
# suites and conformance checks, and the UBF in both modes. The fuzz images are
# built here; their suites are still to be written.
.PHONY: check
check: field-width-check all test wx-check pic-check host-check ubf-check release
	$(MAKE) MODE=release ubf-check
	@echo "check: passed"

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

.PHONY: distclean
distclean: clean
	rm -rf build

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
	@echo "  ubf          Pack canvasd as a UBF program"
	@echo "  ubf-check    Validate the UBF and run it to its first frame"
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
	@echo "  check        Everything a change must pass"
	@echo "  release      Build with debug checks compiled out"
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
