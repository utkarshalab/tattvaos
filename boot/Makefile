# =============================================================================
# Tattva OS Boot & Kernel Build Makefile
# Target: x86-64 Flat Binary Image + bootable raw disk
# =============================================================================
#
# The kernel is ONE translation unit: nasm assembles kernel/entry.asm and every
# other file arrives through %include. So the prerequisite lists below exist
# purely for rebuild tracking — they are never assembled individually.
#
# They are globbed, not enumerated. A hand-written list silently rots the
# moment a subsystem is reorganised: the unet/core split into l2/l3/l4/sys left
# ten dead paths here and the build failed on a missing prerequisite rather
# than on anything real. Globs survive that.
#
# The boot stages are three separate translation units, each with its own ORG:
#   stage1.bin  ORG 0x7C00, exactly 512 bytes, the MBR
#   stage2.bin  ORG 0x8000, real mode, loaded by stage1
#   kernel.bin  ORG 0x100000, long mode, streamed to 1MB by stage2
#
# Disk layout written by the img target:
#   LBA 0        stage1.bin
#   LBA 1..64    stage2.bin, zero-padded to STAGE2_SECTORS
#   LBA 65..     kernel.bin  (KERNEL_LBA in config.asm)

ASM = nasm
KERNEL_DIR = .
ROOT = $(KERNEL_DIR)/..

# Every source that can reach the kernel translation unit. Tests are excluded:
# they have their own harnesses and are not part of the kernel image.
SRC_DIRS = kernel lib crypto storage security unet

KERNEL_SRCS := $(shell find $(addprefix $(ROOT)/,$(SRC_DIRS)) \
                          \( -name '*.asm' -o -name '*.inc' \) \
                          -not -path '*/tests/*' 2>/dev/null) \
               $(KERNEL_DIR)/boot_info.inc

BOOT_SRCS := $(shell find $(KERNEL_DIR)/stage1 $(KERNEL_DIR)/stage2 \
                          $(KERNEL_DIR)/survive $(KERNEL_DIR)/tpm \
                          $(KERNEL_DIR)/tests \
                          -name '*.asm' 2>/dev/null) \
             $(KERNEL_DIR)/config.asm $(KERNEL_DIR)/boot_info.inc

UEFI_SRCS := $(shell find $(KERNEL_DIR)/uefi $(KERNEL_DIR)/tpm \
                          -name '*.asm' 2>/dev/null) \
             $(KERNEL_DIR)/nvram.asm $(KERNEL_DIR)/config.asm \
             $(KERNEL_DIR)/boot_info.inc
UEFI_EFI = BOOTX64.EFI
OVMF_STRICT_CODE ?= /usr/share/OVMF/OVMF_CODE_4M.secboot.strictnx.fd
OVMF_STRICT_VARS ?= /usr/share/OVMF/OVMF_VARS_4M.fd

# The single kernel translation unit; everything else is %include'd into it.
ENTRY = $(ROOT)/kernel/entry.asm

# stage2 pulls its includes by bare filename from a dozen subdirectories, so
# every one of them has to be on the include path.
BOOT_INC = -I $(KERNEL_DIR)/ \
           -I $(KERNEL_DIR)/stage1/ \
           -I $(KERNEL_DIR)/stage2/ \
           -I $(KERNEL_DIR)/stage2/a20/ \
           -I $(KERNEL_DIR)/stage2/cpu/ \
           -I $(KERNEL_DIR)/stage2/fs/ \
           -I $(KERNEL_DIR)/stage2/gdt/ \
           -I $(KERNEL_DIR)/stage2/hw/ \
           -I $(KERNEL_DIR)/stage2/hw/uart/ \
           -I $(KERNEL_DIR)/stage2/idt/ \
           -I $(KERNEL_DIR)/stage2/memory/ \
           -I $(KERNEL_DIR)/stage2/paging/

# Must match config.asm. A mismatch here is not caught by the assembler: the
# image would simply place the kernel where stage2 does not look for it.
STAGE2_SECTORS = 64
KERNEL_LBA     = 65

IMG = $(KERNEL_DIR)/tattva.img

# QEMU. Serial goes to the terminal because that is the only output path the
# kernel has before it brings up a framebuffer, and -display none keeps the
# window from stealing focus on every run. -no-reboot turns a triple fault into
# an exit instead of an endless reboot loop that scrolls the real error away.
#
# -cpu max: kernel/arch/x86_64/cpu.asm hard-requires AVX2/FMA3 (the crypto and
# math paths are written against them) and refuses to boot without them. The
# default qemu64 model advertises none of that, so it isn't a stand-in for
# "no CPU flags" — it's a specific 2006-era feature set the kernel has never
# targeted. -cpu max asks for everything the accelerator in use can expose:
# under KVM that is the host's real feature set, under TCG it's QEMU's widest
# emulated set, either of which actually has AVX2/FMA3 on hardware from the
# last decade.
ACCEL      := $(shell test -e /dev/kvm -a -r /dev/kvm -a -w /dev/kvm && echo kvm || echo tcg)
QEMU       = qemu-system-x86_64
QEMU_MEM   = 512
# -netdev user + -device e1000: gives the e1000 driver in unet/drivers/
# something to actually probe. `user` mode needs no host-side setup (no tap,
# no root) and hands the guest 10.0.2.15/24 with a gateway at 10.0.2.2 —
# unet_init's static config (see unet/unet.asm) is hardcoded to match.
QEMU_FLAGS = -accel $(ACCEL) \
             -cpu max \
             -drive file=$(IMG),format=raw,if=ide \
             -m $(QEMU_MEM) \
             -netdev user,id=n0 \
             -device e1000,netdev=n0 \
             -serial stdio \
             -display none \
             -no-reboot -no-shutdown

all: kernel.bin

# -----------------------------------------------------------------------------
# Kernel
# -----------------------------------------------------------------------------
kernel.bin: $(KERNEL_SRCS)
	@set -eu; TMP="$@.$$$$.tmp"; trap 'rm -f "$$TMP"' EXIT HUP INT TERM; \
	$(ASM) -f bin -I $(ROOT)/ $(ENTRY) -o "$$TMP"; \
	test -s "$$TMP"; \
	sh $(KERNEL_DIR)/ulf_stamp.sh "$$TMP"; \
	mv -f "$$TMP" "$@"; \
	trap - EXIT HUP INT TERM

# -----------------------------------------------------------------------------
# UEFI application
# -----------------------------------------------------------------------------
$(UEFI_EFI): $(UEFI_SRCS)
	@set -eu; TMP_OBJ="$@.$$$$.obj"; TMP_EFI="$@.$$$$.tmp"; \
	trap 'rm -f "$$TMP_OBJ" "$$TMP_EFI"' EXIT HUP INT TERM; \
	$(ASM) -f win64 -Wall -Werror -w-reloc-rel-dword \
	    -I $(KERNEL_DIR)/uefi/ -I $(KERNEL_DIR)/ \
	    $(KERNEL_DIR)/uefi/entry.asm -o "$$TMP_OBJ"; \
	x86_64-w64-mingw32-ld -mi386pep -nostdlib --subsystem 10 \
	    -e efi_main --dynamicbase --nxcompat \
	    --file-alignment 512 --section-alignment 4096 \
	    -o "$$TMP_EFI" "$$TMP_OBJ"; \
	test -s "$$TMP_EFI"; \
	mv -f "$$TMP_EFI" "$@"; \
	rm -f "$$TMP_OBJ"; \
	trap - EXIT HUP INT TERM

uefi: $(UEFI_EFI)

# Assemble to ELF instead: keeps symbol names in the error output and lets
# `nm` show what a section actually contains. Useful when triaging the image.
elf: $(KERNEL_SRCS)
	$(ASM) -f elf64 -I $(ROOT)/ $(ENTRY) -o $(KERNEL_DIR)/kernel.o

# -----------------------------------------------------------------------------
# Boot stages
# -----------------------------------------------------------------------------
stage1.bin: $(BOOT_SRCS)
	@set -eu; TMP="$@.$$$$.tmp"; trap 'rm -f "$$TMP"' EXIT HUP INT TERM; \
	$(ASM) -f bin $(BOOT_INC) $(KERNEL_DIR)/stage1/entry.asm -o "$$TMP"; \
	SZ=`wc -c < "$$TMP"`; \
	if [ "$$SZ" -ne 512 ]; then \
	    echo "stage1: $$SZ bytes, must be exactly 512 (the MBR)" >&2; exit 1; \
	fi; \
	mv -f "$$TMP" "$@"; \
	trap - EXIT HUP INT TERM

stage2.bin: $(BOOT_SRCS)
	@set -eu; TMP="$@.$$$$.tmp"; trap 'rm -f "$$TMP"' EXIT HUP INT TERM; \
	$(ASM) -f bin $(BOOT_INC) $(KERNEL_DIR)/stage2/entry.asm -o "$$TMP"; \
	SZ=`wc -c < "$$TMP"`; MAX=`expr $(STAGE2_SECTORS) \* 512`; \
	if [ "$$SZ" -gt "$$MAX" ]; then \
	    echo "stage2: $$SZ bytes exceeds the $$MAX stage1 loads" >&2; exit 1; \
	fi; \
	mv -f "$$TMP" "$@"; \
	trap - EXIT HUP INT TERM; \
	echo "stage2: $$SZ / $$MAX bytes used"

# -----------------------------------------------------------------------------
# Bootable image
# -----------------------------------------------------------------------------
$(IMG): stage1.bin stage2.bin kernel.bin
	@set -eu; TMP="$@.$$$$.tmp"; trap 'rm -f "$$TMP"' EXIT HUP INT TERM; \
	test -s stage1.bin; test -s stage2.bin; test -s kernel.bin; \
	dd if=stage1.bin of="$$TMP" bs=512 seek=0 conv=notrunc status=none; \
	dd if=stage2.bin of="$$TMP" bs=512 seek=1 conv=notrunc status=none; \
	dd if=kernel.bin of="$$TMP" bs=512 seek=$(KERNEL_LBA) conv=notrunc status=none; \
	SZ=`wc -c < "$$TMP"`; PAD=`expr \( $$SZ + 511 \) / 512 \* 512`; \
	if [ "$$PAD" -ne "$$SZ" ]; then dd if=/dev/zero of="$$TMP" bs=1 seek=$$SZ \
	    count=`expr $$PAD - $$SZ` conv=notrunc status=none; fi; \
	mv -f "$$TMP" "$@"; \
	trap - EXIT HUP INT TERM; \
	echo "img: $@ is `wc -c < $@` bytes (`expr \`wc -c < $@\` / 512` sectors)"

img: $(IMG)

# -----------------------------------------------------------------------------
# Run
# -----------------------------------------------------------------------------
run: $(IMG)
	$(QEMU) $(QEMU_FLAGS)

# Same, but stopped at the reset vector waiting for gdb on :1234.
# Attach with:  gdb -ex 'target remote :1234'
debug: $(IMG)
	$(QEMU) $(QEMU_FLAGS) -s -S

# Build-time image validation followed by a boot-to-kernel smoke test.  Keep
# this target beside the image recipe so its paths and QEMU configuration do
# not drift independently from the artifacts it verifies.
test: $(IMG) $(UEFI_EFI)
	@sh $(KERNEL_DIR)/tests/run_all.sh

test-negative: $(IMG)
	@sh $(KERNEL_DIR)/tests/test_boot_negative.sh

# Fast native coverage for the firmware parser and the complete mixed-mode SMP
# translation unit. smp-test adds real OVMF INIT/SIPI/rendezvous boots.
smp-check:
	@sh $(KERNEL_DIR)/tests/test_madt.sh
	@sh $(KERNEL_DIR)/tests/test_smp_asm.sh
	@sh $(KERNEL_DIR)/tests/test_apic_consumers_asm.sh
	@sh $(KERNEL_DIR)/tests/test_pgtable_lock.sh

smp-test: $(IMG) $(UEFI_EFI) smp-check
	@sh $(KERNEL_DIR)/tests/test_smp_qemu.sh

# Native ABI validation plus a complete PE32+ EFI application link check.
uefi-check: $(UEFI_EFI)
	@sh $(KERNEL_DIR)/tests/test_uefi_memory.sh
	@sh $(KERNEL_DIR)/tests/test_uefi_memmap.sh
	@sh $(KERNEL_DIR)/tests/test_uefi_ulf.sh
	@sh $(KERNEL_DIR)/tests/test_uefi_file.sh
	@sh $(KERNEL_DIR)/tests/test_uefi_tpm.sh
	@sh $(KERNEL_DIR)/tests/test_uefi_transition_tables.sh
	@sh $(KERNEL_DIR)/tests/test_uefi_asm.sh

ovmf-test: kernel.bin $(UEFI_EFI)
	@sh $(KERNEL_DIR)/tests/test_ovmf_qemu.sh

ovmf-strictnx-test: kernel.bin $(UEFI_EFI)
	@OVMF_CODE="$(OVMF_STRICT_CODE)" OVMF_VARS="$(OVMF_STRICT_VARS)" \
	    sh $(KERNEL_DIR)/tests/test_ovmf_qemu.sh

clean:
	rm -f $(KERNEL_DIR)/kernel.bin $(KERNEL_DIR)/kernel.o \
	      $(KERNEL_DIR)/stage1.bin $(KERNEL_DIR)/stage2.bin $(IMG) $(UEFI_EFI)

.PHONY: all elf img run debug test test-negative smp-check smp-test uefi \
        uefi-check ovmf-test ovmf-strictnx-test clean
