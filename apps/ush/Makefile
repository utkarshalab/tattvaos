NASM ?= nasm
LD ?= ld
BUILD ?= build
CORE := main io/frontend parser/tokenizer parser/chain exec/dispatcher exec/cmd_registry_init exec/builtins/core exec/builtins/files exec/builtins/filetools exec/builtins/system exec/builtins/uedit env/environment line/history line/editor
CORE += exec/builtins/vcs
CORE_OBJS := ../vcs/build/diff.o ../vcs/build/repo_diff.o ../uedit/build/uedit-native.o $(BUILD)/uxfs-volume.o $(addprefix $(BUILD)/,$(addsuffix .o,$(CORE)))
CORE_OBJS += ../vcs/build/repository.o ../vcs/build/history.o ../vcs/build/refs.o ../vcs/build/worktree.o ../vcs/build/stage.o ../vcs/build/identity.o ../vcs/build/signing.o ../vcs/build/integrate.o ../vcs/build/rebase.o ../vcs/build/pick.o ../vcs/build/sha256.o ../vcs/build/sha512.o ../vcs/build/ed25519.o
CALC := calc scientific float_format session cli math
CALC_OBJS := $(addprefix $(BUILD)/calculator/,$(addsuffix .o,$(CALC)))
CALC_DEPS := $(wildcard ../calculator/src/*.asm ../calculator/src/*.inc ../../lib/umath/math_fn/*.asm ../../lib/umath/scalar/*.asm ../../lib/umath/cpuid/*.asm)
HEADERS := $(wildcard inc/*.inc ../../storage/uxfs/volume.inc ../uedit/inc/*.inc ../vcs/include/*.inc)

.PHONY: all native test run
all: $(BUILD)/ush native
native: $(BUILD)/ush-native.o

../vcs/build/diff.o: ../vcs/src/merge/diff.asm ../vcs/include/diff.inc ../vcs/include/vcs.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/diff.o
../vcs/build/repo_diff.o: ../vcs/src/merge/repo_diff.asm ../vcs/include/diff.inc ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/repo_diff.o
../vcs/build/repository.o: ../vcs/src/store/repository.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/repository.o
../vcs/build/history.o: ../vcs/src/store/history.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/history.o
../vcs/build/refs.o: ../vcs/src/store/refs.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/refs.o
../vcs/build/worktree.o: ../vcs/src/store/worktree.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/worktree.o
../vcs/build/stage.o: ../vcs/src/store/stage.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/stage.o
../vcs/build/identity.o: ../vcs/src/store/identity.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/identity.o
../vcs/build/signing.o: ../vcs/src/policy/signing.asm ../vcs/include/vcs.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/signing.o
../vcs/build/integrate.o: ../vcs/src/merge/integrate.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../vcs/include/diff.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/integrate.o
../vcs/build/rebase.o: ../vcs/src/merge/rebase.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/rebase.o
../vcs/build/pick.o: ../vcs/src/merge/pick.asm ../vcs/include/vcs.inc ../vcs/include/repository.inc ../../storage/uxfs/volume.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/pick.o
../vcs/build/sha256.o: ../../lib/crypto/uhash/sha256/sha256.asm ../../lib/crypto/uhash/sha256/sha256.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/sha256.o
../vcs/build/sha512.o: ../../lib/crypto/uhash/sha512/sha512.asm ../../lib/crypto/uhash/sha512/sha512.inc ../vcs/Makefile
	$(MAKE) -C ../vcs build/sha512.o
../vcs/build/ed25519.o: ../../lib/crypto/usign/ed25519/ed25519.asm ../vcs/Makefile
	$(MAKE) -C ../vcs build/ed25519.o

../uedit/build/uedit-native.o: $(wildcard ../uedit/src/*.asm ../uedit/inc/*.inc) ../uedit/Makefile $(wildcard ../../lib/str/utf8/decode.asm ../../lib/str/utf8/encode.asm ../../lib/str/unicode/tables/category_table.asm ../../lib/str/unicode/tables/eaw_table.asm ../../lib/str/arch/common/*.inc)
	$(MAKE) -C ../uedit native

$(BUILD)/uxfs-volume.o: ../../storage/uxfs/volume.asm ../../storage/uxfs/volume.inc
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@

$(BUILD)/%.o: src/%.asm $(HEADERS)
	mkdir -p $(dir $@)
	$(NASM) -w+error -f elf64 -I ./ -I ../vcs/ -I ../../ $< -o $@

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
	python3 tests/host/test_vcs.py $(BUILD)/ush
	python3 tests/host/test_vcs_history.py $(BUILD)/ush
	python3 tests/host/test_vcs_merge.py $(BUILD)/ush
	python3 tests/host/test_vcs_rebase.py $(BUILD)/ush
	python3 tests/host/test_vcs_pick.py $(BUILD)/ush
	python3 tests/host/test_vcs_repo_diff.py $(BUILD)/ush
	python3 tests/host/test_volume.py $(BUILD)/uxfs-volume.so
	./$(BUILD)/native-test
	./$(BUILD)/platform-test
