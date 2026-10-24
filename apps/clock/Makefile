NASM ?= nasm
LD ?= ld
AR ?= ar
BUILD ?= build
OBJECTS := $(BUILD)/clock.o $(BUILD)/alarms.o
NATIVE_OBJECTS := $(BUILD)/native.o
.PHONY: all native test test-api test-wired
all: native
native: $(BUILD)/clock-native.o $(BUILD)/libclock.a
$(BUILD)/%.o: src/%.asm inc/clock.inc
	mkdir -p $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/libclock.a: $(OBJECTS) $(NATIVE_OBJECTS)
	$(AR) rcs $@ $^
$(BUILD)/clock-native.o: $(OBJECTS) $(NATIVE_OBJECTS)
	$(LD) -r -z noexecstack -o $@ $^
$(BUILD)/clock.so: $(OBJECTS)
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
test: native $(BUILD)/clock.so $(BUILD)/api-test $(BUILD)/wired.so
	python3 tests/test_clock.py $(BUILD)/clock.so
	./$(BUILD)/api-test
	python3 tests/test_wired.py $(BUILD)/wired.so

# Both static archives compose without pulling duplicate shared-library helpers.
../calender/build/libcalender.a: $(wildcard ../calender/src/*.asm ../calender/inc/*.inc) ../calender/Makefile ../../lib/cal/gregorian.asm ../../lib/cal/civil.asm ../../lib/cal/civil.inc ../../lib/cal/cal.inc ../../lib/time/time.inc $(wildcard ../../lib/io/macro/*.asm ../../lib/str/arch/common/*.inc) ../../lib/str/utf8/decode.asm
	$(MAKE) -C ../calender native
$(BUILD)/api-test.o: tests/test_api.asm inc/api.inc inc/clock.inc ../calender/inc/api.inc ../calender/inc/calender.inc
	mkdir -p $(BUILD)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@
$(BUILD)/api-test: $(BUILD)/api-test.o $(BUILD)/libclock.a ../calender/build/libcalender.a Makefile
	$(LD) -z noexecstack -o $@ $(BUILD)/api-test.o $(BUILD)/libclock.a ../calender/build/libcalender.a

test-api: $(BUILD)/api-test
	./$(BUILD)/api-test

# Host wire tests link actual lib/time service + monotonic/RTC algorithms.
$(BUILD)/time-native-test.o: ../../lib/time/native.asm ../../lib/time/time.inc
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@
$(BUILD)/rtc-native-test.o: ../../lib/time/rtc_native.asm ../../lib/cal/civil.inc ../../lib/time/time.inc
	$(NASM) -w+error -f elf64 -D TIME_NATIVE_TEST=1 -I ../../ $< -o $@
$(BUILD)/mono-test.o: ../../lib/time/mono.asm ../../lib/time/time.inc
	$(NASM) -w+error -f elf64 -D TIME_MONO_STANDALONE=1 -I ../../ $< -o $@
$(BUILD)/time-provider.o: ../../lib/time/tests/native_provider.asm
	$(NASM) -w+error -f elf64 $< -o $@
../calender/build/now.o: ../calender/src/now.asm ../calender/inc/calender.inc
	$(MAKE) -C ../calender native
WIRE_OBJECTS = $(BUILD)/time-native-test.o $(BUILD)/rtc-native-test.o $(BUILD)/mono-test.o $(BUILD)/time-provider.o $(BUILD)/native.o ../calender/build/now.o
$(BUILD)/wired.so: $(WIRE_OBJECTS) $(BUILD)/libclock.a ../calender/build/libcalender.a
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $(WIRE_OBJECTS) $(BUILD)/libclock.a ../calender/build/libcalender.a
test-wired: $(BUILD)/wired.so
	python3 tests/test_wired.py $(BUILD)/wired.so
