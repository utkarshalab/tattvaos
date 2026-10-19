# =============================================================================
# File     : apps/ish/Makefile
# Project  : Tattva OS — Ishana Shell
# Author   : Utkarsha Lab
# License  : Apache-2.0
# Description: Build the ish shell as a standalone ELF/flat binary image.
# =============================================================================

ARCH        := x86_64
BITS        := 64
NASM        := nasm
LD          := ld

# Include paths:
#   -I inc/         -> apps/ish/inc/ (shell headers)
#   -I src/         -> apps/ish/src/ (shell sources)
#   -I ../../       -> repo root (tattvaos/lib/, tattvaos/kernel/, etc.)
NASMFLAGS   := -f elf64 -g -F dwarf \
               -D __TATTVA__ \
               -I inc/ \
               -I src/ \
               -I ../../

LDFLAGS     := -nostdlib -static -z max-page-size=0x1000 \
               -T linker.ld \
               --build-id=none

SRCDIR      := src
OBJDIR      := build/obj
IMAGEDIR    := build/img

# Core shell sources
CORE_SRCS := \
    $(SRCDIR)/main.asm \
    $(SRCDIR)/io/frontend.asm \
    $(SRCDIR)/io/uart.asm \
    $(SRCDIR)/line/readline.asm \
    $(SRCDIR)/parser/tokenizer.asm \
    $(SRCDIR)/exec/dispatcher.asm \
    $(SRCDIR)/exec/cmd_registry_init.asm

# Builtin commands
BUILTIN_SRCS := \
    $(SRCDIR)/exec/builtins/echo.asm \
    $(SRCDIR)/exec/builtins/cd.asm \
    $(SRCDIR)/exec/builtins/pwd.asm \
    $(SRCDIR)/exec/builtins/exit.asm \
    $(SRCDIR)/exec/builtins/help.asm \
    $(SRCDIR)/exec/builtins/export.asm \
    $(SRCDIR)/exec/builtins/unset.asm \
    $(SRCDIR)/exec/builtins/set.asm \
    $(SRCDIR)/exec/builtins/read.asm \
    $(SRCDIR)/exec/builtins/history.asm \
    $(SRCDIR)/exec/builtins/source.asm \
    $(SRCDIR)/exec/builtins/alias.asm \
    $(SRCDIR)/exec/builtins/unalias.asm \
    $(SRCDIR)/exec/builtins/jobs.asm \
    $(SRCDIR)/exec/builtins/fg.asm \
    $(SRCDIR)/exec/builtins/bg.asm \
    $(SRCDIR)/exec/builtins/kill.asm \
    $(SRCDIR)/exec/builtins/reboot.asm \
    $(SRCDIR)/exec/builtins/shutdown.asm \
    $(SRCDIR)/exec/builtins/uname.asm \
    $(SRCDIR)/exec/builtins/whoami.asm \
    $(SRCDIR)/exec/builtins/id.asm \
    $(SRCDIR)/exec/builtins/date.asm \
    $(SRCDIR)/exec/builtins/ps.asm

# Job control & environment
JOB_SRCS := \
    $(SRCDIR)/job/job_control.asm \
    $(SRCDIR)/env/environment.asm \
    $(SRCDIR)/env/config.asm

# Utilities
UTIL_SRCS := \
    $(SRCDIR)/util/argv.asm \
    $(SRCDIR)/util/strutil.asm

ALL_SRCS    := $(CORE_SRCS) $(BUILTIN_SRCS) $(JOB_SRCS) $(UTIL_SRCS)
ALL_OBJS    := $(patsubst $(SRCDIR)/%.asm,$(OBJDIR)/%.o,$(ALL_SRCS))

.PHONY: all clean run help

all: $(IMAGEDIR)/ish.img

$(IMAGEDIR)/ish.img: $(ALL_OBJS) linker.ld
	@mkdir -p $(IMAGEDIR)
	$(LD) $(LDFLAGS) -o $@ $(ALL_OBJS)
	@echo "ISH IMG  $@"

$(OBJDIR)/%.o: $(SRCDIR)/%.asm
	@mkdir -p $(dir $@)
	$(NASM) $(NASMFLAGS) -o $@ $<
	@echo "NASM     $<"

run: $(IMAGEDIR)/ish.img
	qemu-system-x86_64 -nographic -serial stdio -drive file=$<,format=raw -m 512

clean:
	rm -rf build

help:
	@echo "Ishana Shell Build Targets"
	@echo "  all    - Build ish.img (default)"
	@echo "  run    - Build and run under QEMU with serial console"
	@echo "  clean  - Remove build artifacts"
	@echo "  help   - Show this help"
