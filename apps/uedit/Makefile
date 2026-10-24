NASM ?= nasm
LD ?= ld
BUILD ?= build
STR_SRCS := utf8/decode.asm utf8/encode.asm unicode/tables/category_table.asm unicode/tables/eaw_table.asm
STR_HEADERS := $(wildcard ../../lib/str/arch/common/*.inc)
OBJECTS := $(BUILD)/core.o $(BUILD)/text.o $(BUILD)/actions.o $(BUILD)/terminal.o $(addprefix $(BUILD)/str/,$(STR_SRCS:.asm=.o))

.PHONY: all native test test-terminal run
all: native
native: $(BUILD)/uedit-native.o

$(BUILD)/str/%.o: ../../lib/str/%.asm $(STR_HEADERS)
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ../../ -I ../../lib/str/ $< -o $@

$(BUILD)/%.o: src/%.asm inc/uedit.inc
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@

$(BUILD)/uedit-native.o: $(OBJECTS)
	$(LD) -r -z noexecstack -o $@ $^

$(BUILD)/uedit.so: $(OBJECTS)
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^

test: native $(BUILD)/uedit.so
	python3 tests/test_uedit.py $(BUILD)/uedit.so

test-terminal: native
	$(MAKE) -C ../ush all
	python3 tests/test_terminal.py ../ush/build/ush

# The callable native app uses Ush's terminal/storage frontend for development.
run: native
	$(MAKE) -C ../ush all
	../ush/build/ush $(if $(DISK),--disk $(DISK),)
