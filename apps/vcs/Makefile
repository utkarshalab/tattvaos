NASM ?= nasm
LD ?= ld
AR ?= ar
BUILD ?= build
OBJECTS := $(BUILD)/cli.o $(BUILD)/diff.o $(BUILD)/repo_diff.o $(BUILD)/blame.o $(BUILD)/integrate.o $(BUILD)/rebase.o $(BUILD)/pick.o $(BUILD)/sync.o $(BUILD)/protocol.o $(BUILD)/client.o $(BUILD)/server.o $(BUILD)/stream.o $(BUILD)/plan.o $(BUILD)/policy.o $(BUILD)/bundle.o $(BUILD)/remote.o $(BUILD)/bridge.o $(BUILD)/pack.o $(BUILD)/tree.o $(BUILD)/commit.o $(BUILD)/history_plan.o $(BUILD)/history_pack.o $(BUILD)/upload_pack.o $(BUILD)/upload_protocol.o $(BUILD)/upload_request.o $(BUILD)/upload_server.o $(BUILD)/repository.o $(BUILD)/object_store.o $(BUILD)/object_index.o $(BUILD)/chunk_pipeline.o $(BUILD)/file_object.o $(BUILD)/tree_object.o $(BUILD)/ownership.o $(BUILD)/publication.o $(BUILD)/history.o $(BUILD)/refs.o $(BUILD)/worktree.o $(BUILD)/stage.o $(BUILD)/stash.o $(BUILD)/bisect.o $(BUILD)/identity.o $(BUILD)/signing.o $(BUILD)/scalar.o $(BUILD)/sha256.o $(BUILD)/sha512.o $(BUILD)/ed25519.o
.PHONY: all native test
all: native
native: $(BUILD)/vcs-native.o $(BUILD)/libvcs.a
$(BUILD):
	mkdir -p $@
$(BUILD)/cli.o: src/cli/cli.asm include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@
$(BUILD)/diff.o: src/merge/diff.asm include/diff.inc include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@
$(BUILD)/repo_diff.o: src/merge/repo_diff.asm include/diff.inc include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/blame.o: src/merge/blame.asm include/diff.inc include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/integrate.o: src/merge/integrate.asm include/vcs.inc include/repository.inc include/diff.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/rebase.o: src/merge/rebase.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/pick.o: src/merge/pick.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/sync.o: src/sync/sync.asm include/vcs.inc include/wire.inc ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/protocol.o: src/sync/protocol.asm include/vcs.inc include/sync_protocol.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/client.o: src/sync/client.asm include/vcs.inc include/wire.inc include/sync_protocol.inc include/client.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/server.o: src/sync/server.asm include/vcs.inc include/wire.inc include/sync_protocol.inc include/server.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/stream.o: src/sync/stream.asm include/vcs.inc include/wire.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/plan.o: src/sync/plan.asm include/vcs.inc include/repository.inc include/bundle.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/policy.o: src/sync/policy.asm include/vcs.inc include/sync_protocol.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/bundle.o: src/sync/bundle.asm include/vcs.inc include/repository.inc include/bundle.inc include/wire.inc ../../lib/storage/uxfs/volume.inc ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/remote.o: src/sync/remote.asm include/vcs.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/bridge.o: src/bridge/bridge.asm include/vcs.inc include/wire.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/pack.o: src/bridge/pack.asm include/vcs.inc include/git_pack.inc ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/tree.o: src/bridge/tree.asm include/vcs.inc include/repository.inc include/git_tree.inc include/git_pack.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/commit.o: src/bridge/commit.asm include/vcs.inc include/git_commit.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/history_plan.o: src/bridge/history_plan.asm include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/history_pack.o: src/bridge/history_pack.asm include/vcs.inc include/repository.inc include/git_pack.inc include/git_tree.inc include/git_commit.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/upload_pack.o: src/bridge/upload_pack.asm include/vcs.inc include/repository.inc include/git_pack.inc include/git_tree.inc include/git_commit.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/upload_protocol.o: src/bridge/upload_protocol.asm include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/upload_request.o: src/bridge/upload_request.asm include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/upload_server.o: src/bridge/upload_server.asm include/vcs.inc include/wire.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/repository.o: src/store/repository.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/object_store.o: src/store/object_store.asm include/vcs.inc include/object_store.inc ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/object_index.o: src/store/object_index.asm include/vcs.inc include/object_index.inc ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/chunk_pipeline.o: src/store/chunk_pipeline.asm include/vcs.inc include/chunk.inc include/object_store.inc include/chunk_pipeline.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/file_object.o: src/store/file_object.asm include/vcs.inc include/object_store.inc include/chunk_pipeline.inc include/file_object.inc ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/tree_object.o: src/store/tree_object.asm include/vcs.inc include/object_store.inc include/chunk_pipeline.inc include/file_object.inc include/tree_object.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/ownership.o: src/store/ownership.asm include/vcs.inc include/chunk_pipeline.inc include/file_object.inc include/tree_object.inc include/ownership.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/publication.o: src/store/publication.asm include/vcs.inc include/object_store.inc include/ownership.inc include/publication.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/history.o: src/store/history.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/refs.o: src/store/refs.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/worktree.o: src/store/worktree.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/stage.o: src/store/stage.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/stash.o: src/store/stash.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/bisect.o: src/store/bisect.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/identity.o: src/store/identity.asm include/vcs.inc include/repository.inc ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/signing.o: src/policy/signing.asm include/vcs.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ -I ../../ $< -o $@
$(BUILD)/scalar.o: src/kernels/scalar/scalar.asm include/vcs.inc include/chunk.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@
$(BUILD)/sha256.o: ../../lib/crypto/uhash/sha256/sha256.asm ../../lib/crypto/uhash/sha256/sha256.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@
$(BUILD)/sha512.o: ../../lib/crypto/uhash/sha512/sha512.asm ../../lib/crypto/uhash/sha512/sha512.inc | $(BUILD)
	$(NASM) -w+error -dSHA512_DEFAULT_REL -f elf64 -I ../../ $< -o $@
$(BUILD)/ed25519.o: ../../lib/crypto/usign/ed25519/ed25519.asm ../../lib/crypto/usign/ed25519/ed25519.inc ../../lib/crypto/usign/ed25519/fe25519.asm ../../lib/crypto/usign/ed25519/sc25519.asm ../../lib/crypto/usign/ed25519/ge25519.asm | $(BUILD)
	$(NASM) -w+error -dED25519_NO_KEYGEN -dED25519_EXTERNAL_SHA512 -f elf64 -I ../../ $< -o $@
$(BUILD)/volume.o: ../../lib/storage/uxfs/volume.asm ../../lib/storage/uxfs/volume.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ../../ $< -o $@
$(BUILD)/repository.so: $(BUILD)/repository.o $(BUILD)/history.o $(BUILD)/refs.o $(BUILD)/worktree.o $(BUILD)/stage.o $(BUILD)/stash.o $(BUILD)/bisect.o $(BUILD)/identity.o $(BUILD)/signing.o $(BUILD)/repo_diff.o $(BUILD)/blame.o $(BUILD)/diff.o $(BUILD)/integrate.o $(BUILD)/rebase.o $(BUILD)/pick.o $(BUILD)/protocol.o $(BUILD)/bundle.o $(BUILD)/remote.o $(BUILD)/sha256.o $(BUILD)/sha512.o $(BUILD)/ed25519.o $(BUILD)/volume.o $(BUILD)/remote_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/vcs-native.o: $(OBJECTS)
	$(LD) -r -z noexecstack -o $@ $^
$(BUILD)/libvcs.a: $(OBJECTS)
	$(AR) rcs $@ $^
$(BUILD)/diff.so: $(BUILD)/diff.o $(BUILD)/diff_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/chunk.so: $(BUILD)/scalar.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/object_store.so: $(BUILD)/object_store.o $(BUILD)/sha256.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/object_index.so: $(BUILD)/object_index.o $(BUILD)/sha256.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/chunk_pipeline.so: $(BUILD)/chunk_pipeline.o $(BUILD)/object_store.o $(BUILD)/scalar.o $(BUILD)/sha256.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/file_object.so: $(BUILD)/file_object.o $(BUILD)/object_store.o $(BUILD)/sha256.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/tree_object.so: $(BUILD)/tree_object.o $(BUILD)/object_store.o $(BUILD)/sha256.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/ownership.so: $(BUILD)/ownership.o $(BUILD)/file_object.o $(BUILD)/tree_object.o $(BUILD)/object_store.o $(BUILD)/sha256.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/publication.so: $(BUILD)/publication.o $(BUILD)/ownership.o $(BUILD)/file_object.o $(BUILD)/tree_object.o $(BUILD)/object_store.o $(BUILD)/sha256.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/diff_probe.o: tests/unit/diff_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/protocol.so: $(BUILD)/protocol.o $(BUILD)/protocol_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/protocol_probe.o: tests/unit/protocol_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/policy.so: $(BUILD)/policy.o $(BUILD)/policy_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/policy_probe.o: tests/unit/policy_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/client.so: $(BUILD)/client.o $(BUILD)/client_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/client_probe.o: tests/unit/client_probe.asm include/vcs.inc include/wire.inc include/client.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@
$(BUILD)/server.so: $(BUILD)/server.o $(BUILD)/server_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/server_probe.o: tests/unit/server_probe.asm include/vcs.inc include/wire.inc | $(BUILD)
	$(NASM) -w+error -f elf64 -I ./ $< -o $@
$(BUILD)/stream.so: $(BUILD)/stream.o $(BUILD)/stream_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/stream_probe.o: tests/unit/stream_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/sync.so: $(BUILD)/sync.o $(BUILD)/sync_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/sync_probe.o: tests/unit/sync_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/bundle_frame.so: $(BUILD)/bundle.o $(BUILD)/bundle_frame_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/bundle_frame_probe.o: tests/unit/bundle_frame_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/plan.so: $(BUILD)/plan.o $(BUILD)/plan_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/plan_probe.o: tests/unit/plan_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/remote_probe.o: tests/unit/remote_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/upload_request.so: $(BUILD)/upload_request.o $(BUILD)/upload_request_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/upload_request_probe.o: tests/unit/upload_request_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/upload_protocol.so: $(BUILD)/upload_protocol.o $(BUILD)/upload_protocol_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/upload_protocol_probe.o: tests/unit/upload_protocol_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/upload_server.so: $(BUILD)/upload_server.o $(BUILD)/upload_server_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/upload_server_probe.o: tests/unit/upload_server_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/bridge_codec.so: $(BUILD)/bridge.o $(BUILD)/bridge_codec_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/bridge_codec_probe.o: tests/unit/bridge_codec_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/bridge_export.so: $(BUILD)/bridge.o $(BUILD)/bridge_export_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/bridge_export_probe.o: tests/unit/bridge_export_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/bridge_import.so: $(BUILD)/bridge.o $(BUILD)/bridge_import_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/bridge_import_probe.o: tests/unit/bridge_import_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/bridge_serve.so: $(BUILD)/bridge.o $(BUILD)/bridge_serve_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/bridge_serve_probe.o: tests/unit/bridge_serve_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/smart_bridge.so: $(BUILD)/bridge.o $(BUILD)/upload_request.o $(BUILD)/upload_protocol.o $(BUILD)/history_pack.o $(BUILD)/history_plan.o $(BUILD)/tree.o $(BUILD)/commit.o $(BUILD)/pack.o $(BUILD)/sha256.o $(BUILD)/smart_bridge_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/smart_bridge_probe.o: tests/unit/smart_bridge_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/smart_server.so: $(BUILD)/upload_server.o $(BUILD)/bridge.o $(BUILD)/upload_request.o $(BUILD)/upload_protocol.o $(BUILD)/history_pack.o $(BUILD)/history_plan.o $(BUILD)/tree.o $(BUILD)/commit.o $(BUILD)/pack.o $(BUILD)/sha256.o $(BUILD)/smart_bridge_probe.o $(BUILD)/smart_server_transport_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/smart_server_transport_probe.o: tests/unit/smart_server_transport_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/upload_pack.so: $(BUILD)/upload_pack.o $(BUILD)/upload_pack_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/upload_pack_probe.o: tests/unit/upload_pack_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/pack.so: $(BUILD)/pack.o $(BUILD)/sha256.o $(BUILD)/pack_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/pack_probe.o: tests/unit/pack_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/commit.so: $(BUILD)/commit.o $(BUILD)/pack.o $(BUILD)/sha256.o $(BUILD)/commit_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/commit_probe.o: tests/unit/commit_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/tree.so: $(BUILD)/tree.o $(BUILD)/pack.o $(BUILD)/sha256.o $(BUILD)/tree_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/tree_probe.o: tests/unit/tree_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/history_plan.so: $(BUILD)/history_plan.o $(BUILD)/history_plan_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/history_plan_probe.o: tests/unit/history_plan_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
$(BUILD)/history_pack.so: $(BUILD)/history_pack.o $(BUILD)/history_plan.o $(BUILD)/tree.o $(BUILD)/commit.o $(BUILD)/pack.o $(BUILD)/sha256.o $(BUILD)/history_pack_probe.o
	$(LD) -shared -Bsymbolic -z noexecstack -o $@ $^
$(BUILD)/history_pack_probe.o: tests/unit/history_pack_probe.asm | $(BUILD)
	$(NASM) -w+error -f elf64 $< -o $@
test: native $(BUILD)/diff.so $(BUILD)/chunk.so $(BUILD)/object_store.so $(BUILD)/object_index.so $(BUILD)/chunk_pipeline.so $(BUILD)/file_object.so $(BUILD)/tree_object.so $(BUILD)/ownership.so $(BUILD)/publication.so $(BUILD)/protocol.so $(BUILD)/policy.so $(BUILD)/client.so $(BUILD)/server.so $(BUILD)/stream.so $(BUILD)/sync.so $(BUILD)/bundle_frame.so $(BUILD)/plan.so $(BUILD)/upload_request.so $(BUILD)/upload_protocol.so $(BUILD)/upload_server.so $(BUILD)/bridge_codec.so $(BUILD)/bridge_export.so $(BUILD)/bridge_import.so $(BUILD)/bridge_serve.so $(BUILD)/smart_bridge.so $(BUILD)/smart_server.so $(BUILD)/upload_pack.so $(BUILD)/pack.so $(BUILD)/commit.so $(BUILD)/tree.so $(BUILD)/history_plan.so $(BUILD)/history_pack.so $(BUILD)/repository.so
	sh scripts/test-cli.sh
	python3 tests/unit/test_diff.py $(BUILD)/diff.so
	python3 tests/differential/test_chunking.py $(BUILD)/chunk.so
	python3 tests/unit/test_object_store.py $(BUILD)/object_store.so
	python3 tests/unit/test_object_index.py $(BUILD)/object_index.so
	python3 tests/unit/test_chunk_pipeline.py $(BUILD)/chunk_pipeline.so
	python3 tests/unit/test_file_object.py $(BUILD)/file_object.so
	python3 tests/unit/test_tree_object.py $(BUILD)/tree_object.so
	python3 tests/unit/test_ownership.py $(BUILD)/ownership.so
	python3 tests/unit/test_tree_ownership.py $(BUILD)/ownership.so
	python3 tests/unit/test_publication.py $(BUILD)/publication.so
	python3 tests/unit/test_protocol.py $(BUILD)/protocol.so
	python3 tests/unit/test_policy.py $(BUILD)/policy.so
	python3 tests/unit/test_client.py $(BUILD)/client.so
	python3 tests/unit/test_server.py $(BUILD)/server.so
	python3 tests/unit/test_stream.py $(BUILD)/stream.so
	python3 tests/unit/test_sync.py $(BUILD)/sync.so
	python3 tests/unit/test_bundle_frame.py $(BUILD)/bundle_frame.so
	python3 tests/unit/test_plan.py $(BUILD)/plan.so
	python3 tests/unit/test_remote.py $(BUILD)/repository.so
	python3 tests/unit/test_upload_request.py $(BUILD)/upload_request.so
	python3 tests/unit/test_upload_protocol.py $(BUILD)/upload_protocol.so
	python3 tests/unit/test_upload_server.py $(BUILD)/upload_server.so
	python3 tests/unit/test_bridge_codec.py $(BUILD)/bridge_codec.so
	python3 tests/unit/test_bridge_export.py $(BUILD)/bridge_export.so
	python3 tests/differential/test_git_bridge.py $(BUILD)/bridge_export.so
	python3 tests/unit/test_bridge_import.py $(BUILD)/bridge_import.so
	python3 tests/differential/test_git_import.py $(BUILD)/bridge_import.so
	python3 tests/unit/test_bridge_serve.py $(BUILD)/bridge_serve.so
	python3 tests/unit/test_smart_bridge.py $(BUILD)/smart_bridge.so
	python3 tests/differential/test_git_pack.py $(BUILD)/smart_bridge.so
	python3 tests/unit/test_smart_server.py $(BUILD)/smart_server.so
	python3 tests/unit/test_upload_pack.py $(BUILD)/upload_pack.so
	python3 tests/unit/test_pack.py $(BUILD)/pack.so
	python3 tests/unit/test_commit.py $(BUILD)/commit.so
	python3 tests/unit/test_tree.py $(BUILD)/tree.so
	python3 tests/unit/test_history_plan.py $(BUILD)/history_plan.so
	python3 tests/unit/test_history_pack.py $(BUILD)/history_pack.so
	python3 tests/unit/test_repository.py $(BUILD)/repository.so
	python3 tests/unit/test_history.py $(BUILD)/repository.so
