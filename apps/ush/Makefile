NASM ?= nasm
LD ?= ld
BUILD ?= build
CORE := main io/frontend parser/tokenizer parser/chain exec/dispatcher exec/cmd_registry_init exec/builtins/core exec/builtins/files exec/builtins/filetools exec/builtins/system exec/builtins/uedit env/environment line/history line/editor
CORE_OBJS := ../uedit/build/uedit-native.o $(BUILD)/uxfs-volume.o $(addprefix $(BUILD)/,$(addsuffix .o,$(CORE)))
CALC := calc scientific float_format session cli math
CALC_OBJS := $(addprefix $(BUILD)/calculator/,$(addsuffix .o,$(CALC)))
CALC_DEPS := $(wildcard ../calculator/src/*.asm ../calculator/src/*.inc ../../lib/umath/math_fn/*.asm ../../lib/umath/scalar/*.asm ../../lib/umath/cpuid/*.asm)
HEADERS := $(wildcard inc/*.inc ../../storage/uxfs/volume.inc ../uedit/inc/*.inc)

.PHONY: all native test run
all: $(BUILD)/ush native
native: $(BUILD)/ush-native.o

../uedit/build/uedit-native.o: $(wildcard ../uedit/src/*.asm ../uedit/inc/*.inc) ../uedit/Makefile $(wildcard ../../lib/str/utf8/decode.asm ../../lib/str/utf8/encode.asm ../../lib/str/unicode/tables/category_table.asm ../../lib/str/unicode/tables/eaw_table.asm ../../lib/str/arch/common/*.inc)
	$(MAKE) -C ../uedit native

$(BUILD)/uxfs-volume.o: ../../storage/uxfs/volume.asm ../../storage/uxfs/volume.inc
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@

$(BUILD)/%.o: src/%.asm $(HEADERS)
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@

$(BUILD)/calculator/%.o: ../calculator/src/%.asm $(CALC_DEPS)
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ../calculator/ -I ../../ $< -o $@

$(BUILD)/ush: $(CORE_OBJS) $(CALC_OBJS) $(BUILD)/host.o $(BUILD)/host_disk.o $(BUILD)/host_platform.o
	$(LD) -z noexecstack -o $@ $^

$(BUILD)/ush-native.o: $(CORE_OBJS) $(CALC_OBJS) $(BUILD)/io/uart.o $(BUILD)/io/ata.o
	$(LD) -r -z noexecstack -o $@ $^

run: $(BUILD)/ush
	./$(BUILD)/ush

$(BUILD)/native-test.o: tests/host/native.asm $(HEADERS)
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@

$(BUILD)/native-test: $(BUILD)/native-test.o $(BUILD)/ush-native.o
	$(LD) -z noexecstack -o $@ $^

$(BUILD)/platform-test.o: tests/host/platform.asm $(HEADERS)
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@

$(BUILD)/platform-test: $(BUILD)/platform-test.o $(BUILD)/ush-native.o
	$(LD) -z noexecstack -o $@ $^

$(BUILD)/uxfs-volume.so: $(BUILD)/uxfs-volume.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $<

test: all $(BUILD)/native-test $(BUILD)/platform-test $(BUILD)/uxfs-volume.so
	$(MAKE) -C ../uedit test
	python3 ../uedit/tests/test_terminal.py $(BUILD)/ush
	python3 tests/host/test_ush.py $(BUILD)/ush
	python3 tests/host/test_editor.py $(BUILD)/ush
	python3 tests/host/test_files.py $(BUILD)/ush
	python3 tests/host/test_tools.py $(BUILD)/ush
	python3 tests/host/test_volume.py $(BUILD)/uxfs-volume.so
	./$(BUILD)/native-test
	./$(BUILD)/platform-test
