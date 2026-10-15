ROOT := ..
BUILD := build
ASM := nasm
CC := gcc

.PHONY: all test clean

all: $(BUILD)/test_timer_wheel

$(BUILD):
	mkdir -p $@

$(BUILD)/timer_wheel.o: $(ROOT)/lib/time/timer_wheel.asm $(ROOT)/lib/time/time.inc | $(BUILD)
	$(ASM) -f elf64 -g -F dwarf -I$(ROOT)/ -o $@ $<

$(BUILD)/test_timer_wheel: tests/test_timer_wheel.c $(BUILD)/timer_wheel.o
	$(CC) -std=c11 -Wall -Wextra -Werror -O2 -no-pie -Wl,-z,noexecstack -o $@ $^

test: $(BUILD)/test_timer_wheel
	./$(BUILD)/test_timer_wheel

clean:
	rm -rf $(BUILD)
