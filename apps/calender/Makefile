NASM ?= nasm
LD ?= ld
AR ?= ar
BUILD ?= build
OBJECTS := $(BUILD)/date.o $(BUILD)/events.o $(BUILD)/gregorian.o $(BUILD)/civil.o $(BUILD)/utf8.o
NATIVE_OBJECTS := $(BUILD)/now.o
.PHONY: all native test
all: native
native: $(BUILD)/calender-native.o $(BUILD)/libcalender.a
$(BUILD)/%.o: src/%.asm inc/calender.inc
	mkdir -p $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/gregorian.o: ../../lib/cal/gregorian.asm ../../lib/cal/cal.inc ../../lib/time/time.inc ../../lib/io/macro/func.asm ../../lib/io/macro/guard.asm
	mkdir -p $(BUILD)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@
$(BUILD)/civil.o: ../../lib/cal/civil.asm ../../lib/cal/civil.inc
	mkdir -p $(BUILD)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@
$(BUILD)/utf8.o: ../../lib/str/utf8/decode.asm $(wildcard ../../lib/str/arch/common/*.inc)
	mkdir -p $(BUILD)
	$(NASM) -w+error -f elf64 -I ../../ -I ../../lib/str/ $< -o $@
$(BUILD)/libcalender.a: $(OBJECTS) $(NATIVE_OBJECTS)
	$(AR) rcs $@ $^
$(BUILD)/calender-native.o: $(OBJECTS) $(NATIVE_OBJECTS)
	$(LD) -r -z noexecstack -o $@ $^
$(BUILD)/calender.so: $(OBJECTS)
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
test: native $(BUILD)/calender.so
	python3 tests/test_calender.py $(BUILD)/calender.so
