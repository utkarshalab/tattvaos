# =============================================================================
# Tattva OS Kernel Build Makefile
# Target: x86-64 Flat Binary Image
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

ASM = nasm
KERNEL_DIR = .
ROOT = $(KERNEL_DIR)/..

# Every source that can reach the translation unit. Tests are excluded: they
# have their own harnesses and are not part of the kernel image.
SRC_DIRS = kernel lib crypto storage security unet

KERNEL_SRCS := $(shell find $(addprefix $(ROOT)/,$(SRC_DIRS)) \
                          \( -name '*.asm' -o -name '*.inc' \) \
                          -not -path '*/tests/*' 2>/dev/null)

# The single translation unit; everything else is %include'd into it.
ENTRY = $(ROOT)/kernel/entry.asm

all: kernel.bin

kernel.bin: $(KERNEL_SRCS)
	$(ASM) -f bin -I $(ROOT)/ $(ENTRY) -o $(KERNEL_DIR)/kernel.bin
	@# Patch the ULF size field (offset +4, 4 bytes little-endian) with the real
	@# image length. The assembler cannot compute it: kernel_end sits in .text,
	@# and .data/.rodata are emitted after it, so the label under-reported a
	@# 9.3 MiB image as 274 KB. A loader trusting that would copy the code and
	@# none of its data.
	@#
	@# Done in shell, not Python: this is an assembly-native OS and the kernel
	@# build should not require an interpreter. The inner printf renders the
	@# four bytes as octal escapes; the outer one emits them.
	@SZ=`wc -c < $(KERNEL_DIR)/kernel.bin`; \
	B0=`expr $$SZ % 256`; B1=`expr $$SZ / 256 % 256`; \
	B2=`expr $$SZ / 65536 % 256`; B3=`expr $$SZ / 16777216 % 256`; \
	printf "`printf '\\%03o\\%03o\\%03o\\%03o' $$B0 $$B1 $$B2 $$B3`" \
	  | dd of=$(KERNEL_DIR)/kernel.bin bs=1 seek=4 conv=notrunc status=none; \
	echo "ulf: image size $$SZ bytes written to header"

# Assemble to ELF instead: keeps symbol names in the error output and lets
# `nm` show what a section actually contains. Useful when triaging the image.
elf: $(KERNEL_SRCS)
	$(ASM) -f elf64 -I $(ROOT)/ $(ENTRY) -o $(KERNEL_DIR)/kernel.o

clean:
	rm -f $(KERNEL_DIR)/kernel.bin $(KERNEL_DIR)/kernel.o

.PHONY: all elf clean
