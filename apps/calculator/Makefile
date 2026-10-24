NASM ?= nasm
LD ?= ld
BUILD ?= build
CORE := calc scientific float_format session cli math
OBJS := $(addprefix $(BUILD)/,$(addsuffix .o,$(CORE)))
MATH_DEPS := $(wildcard ../../lib/umath/math_fn/*.asm ../../lib/umath/scalar/*.asm ../../lib/umath/cpuid/*.asm)

.PHONY: all test
all: $(BUILD)/calc

$(BUILD):
	mkdir -p "$@"

$(BUILD)/%.o: src/%.asm src/session.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@

$(BUILD)/math.o: $(MATH_DEPS)

$(BUILD)/calc: $(OBJS) $(BUILD)/host.o
	$(LD) -z noexecstack -o $@ $^

$(BUILD)/command_host.o: tests/command_host.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@

$(BUILD)/command-test: $(OBJS) $(BUILD)/command.o $(BUILD)/command_host.o
	$(LD) -z noexecstack -o $@ $^

$(BUILD)/probe.o: tests/probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@

$(BUILD)/scientific.so: $(OBJS) $(BUILD)/probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -z text -o $@ $^

$(BUILD)/abi.o: tests/abi.asm src/session.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@

$(BUILD)/abi-test: $(OBJS) $(BUILD)/abi.o
	$(LD) -z noexecstack -o $@ $^

test: $(BUILD)/calc $(BUILD)/command-test $(BUILD)/scientific.so $(BUILD)/abi-test
	python3 tests/test_calc.py $(BUILD)/calc
	python3 tests/test_command.py $(BUILD)/command-test
	python3 tests/test_scientific.py $(BUILD)/scientific.so
	python3 tests/test_session.py $(BUILD)/scientific.so $(BUILD)/calc
	$(BUILD)/abi-test
