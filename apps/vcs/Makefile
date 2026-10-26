NASM ?= nasm
LD ?= ld
AR ?= ar
BUILD ?= build
OBJECTS := $(BUILD)/cli.o $(BUILD)/diff.o $(BUILD)/repo_diff.o $(BUILD)/integrate.o $(BUILD)/rebase.o $(BUILD)/pick.o $(BUILD)/sync.o $(BUILD)/bridge.o $(BUILD)/repository.o $(BUILD)/history.o $(BUILD)/refs.o $(BUILD)/worktree.o $(BUILD)/stage.o $(BUILD)/identity.o $(BUILD)/signing.o $(BUILD)/sha256.o $(BUILD)/sha512.o $(BUILD)/ed25519.o
.PHONY: all native test
all: native
native: $(BUILD)/vcs-native.o $(BUILD)/libvcs.a
$(BUILD):
	mkdir -p $@
$(BUILD)/cli.o: src/cli/cli.asm include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@
$(BUILD)/diff.o: src/merge/diff.asm include/diff.inc include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@
$(BUILD)/repo_diff.o: src/merge/repo_diff.asm include/diff.inc include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/integrate.o: src/merge/integrate.asm include/vcs.inc include/repository.inc include/diff.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/rebase.o: src/merge/rebase.asm include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/pick.o: src/merge/pick.asm include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/sync.o: src/sync/sync.asm include/vcs.inc include/wire.inc ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/bridge.o: src/bridge/bridge.asm include/vcs.inc include/wire.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/repository.o: src/store/repository.asm include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/history.o: src/store/history.asm include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/refs.o: src/store/refs.asm include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/worktree.o: src/store/worktree.asm include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/stage.o: src/store/stage.asm include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/identity.o: src/store/identity.asm include/vcs.inc include/repository.inc ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/signing.o: src/policy/signing.asm include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/sha256.o: ../../lib/crypto/uhash/sha256/sha256.asm ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@
$(BUILD)/sha512.o: ../../lib/crypto/uhash/sha512/sha512.asm ../../lib/crypto/uhash/sha512/sha512.inc | $(BUILD)
	$(NASM) -w+error -dSHA512_DEFAULT_REL -f elf64 -I ../../ $< -o $@
$(BUILD)/ed25519.o: ../../lib/crypto/usign/ed25519/ed25519.asm ../../lib/crypto/usign/ed25519/ed25519.inc ../../lib/crypto/usign/ed25519/fe25519.asm ../../lib/crypto/usign/ed25519/sc25519.asm ../../lib/crypto/usign/ed25519/ge25519.asm | $(BUILD)
	$(NASM) -w+error -dED25519_NO_KEYGEN -dED25519_EXTERNAL_SHA512 -f elf64 -I ../../ $< -o $@
$(BUILD)/volume.o: ../../storage/uxfs/volume.asm ../../storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@
$(BUILD)/repository.so: $(BUILD)/repository.o $(BUILD)/history.o $(BUILD)/refs.o $(BUILD)/worktree.o $(BUILD)/stage.o $(BUILD)/identity.o $(BUILD)/signing.o $(BUILD)/repo_diff.o $(BUILD)/diff.o $(BUILD)/integrate.o $(BUILD)/rebase.o $(BUILD)/pick.o $(BUILD)/sha256.o $(BUILD)/sha512.o $(BUILD)/ed25519.o $(BUILD)/volume.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/vcs-native.o: $(OBJECTS)
	$(LD) -r -z noexecstack -o $@ $^
$(BUILD)/libvcs.a: $(OBJECTS)
	$(AR) rcs $@ $^
$(BUILD)/diff.so: $(BUILD)/diff.o $(BUILD)/diff_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/diff_probe.o: tests/unit/diff_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
test: native $(BUILD)/diff.so $(BUILD)/repository.so
	sh scripts/test-cli.sh
	python3 tests/unit/test_diff.py $(BUILD)/diff.so
	python3 tests/unit/test_repository.py $(BUILD)/repository.so
	python3 tests/unit/test_history.py $(BUILD)/repository.so
