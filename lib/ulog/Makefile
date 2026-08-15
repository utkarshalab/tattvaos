# =============================================================================
# lib/ulog/Makefile
# Standalone build for lib/ulog's own tests/ — mirrors lib/time/Makefile.
# The real kernel image assembles this module via kernel/entry.asm's
# %include chain, as one translation unit; this Makefile exists only to let
# tests/ link against ulog.o in isolation.
# =============================================================================

ASM = nasm
ASMFLAGS = -f elf64 -i ../../ -DULOG_BUILD_LEVEL=0

TARGET = ulog.o
SRC = ulog.asm

.PHONY: all clean test

all: $(TARGET)

$(TARGET): $(SRC)
	$(ASM) $(ASMFLAGS) -o $(TARGET) $(SRC)

test: $(TARGET)
	$(ASM) $(ASMFLAGS) -o tests/run_tests.o tests/run_tests.asm

clean:
	rm -f $(TARGET) tests/run_tests.o
