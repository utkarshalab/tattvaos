ASM     = nasm
LINKER ?= lld-link
QEMU64  = qemu-system-x86_64
QEMU32  = qemu-system-i386

STAGE1_MAX = 512
KERNEL_DIR = ../kernel

all: boot.img check

# Stage 1
stage1/stage1.bin: stage1/entry.asm
	$(ASM) -f bin stage1/entry.asm \
		-i stage1/ -i . \
		-o stage1/stage1.bin

# Stage 2
stage2/stage2.bin: stage2/entry.asm
	$(ASM) -f bin stage2/entry.asm \
		-i stage2/ -i stage2/a20/ -i stage2/cpu/ \
		-i stage2/gdt/ -i stage2/idt/ -i stage2/paging/ \
		-i stage2/memory/ -i stage2/fs/ -i stage2/hw/uart/ \
		-i stage1/ \
		-i . \
		-o stage2/stage2.bin

# Kernel
$(KERNEL_DIR)/kernel.bin: $(KERNEL_DIR)/entry.asm $(KERNEL_DIR)/entry/start.asm $(KERNEL_DIR)/entry/init.asm $(KERNEL_DIR)/entry/main.asm $(KERNEL_DIR)/drivers/serial/uart.asm $(KERNEL_DIR)/arch/x86_64/interrupts.asm $(KERNEL_DIR)/arch/x86_64/gdt.asm $(KERNEL_DIR)/arch/x86_64/cpu.asm \
                          $(KERNEL_DIR)/../lib/mem/mem.asm $(KERNEL_DIR)/../lib/mem/mem.inc $(KERNEL_DIR)/../lib/mem/phys/map.asm $(KERNEL_DIR)/../lib/mem/phys/bitmap.asm $(KERNEL_DIR)/../lib/mem/phys/phys.asm \
                          $(KERNEL_DIR)/../lib/mem/ops/memcpy.asm $(KERNEL_DIR)/../lib/mem/ops/memset.asm $(KERNEL_DIR)/../lib/mem/ops/memzero.asm $(KERNEL_DIR)/../lib/mem/ops/memcmp.asm $(KERNEL_DIR)/../lib/mem/ops/memmove.asm \
                          $(KERNEL_DIR)/../lib/mem/heap/bump.asm \
                          $(KERNEL_DIR)/../lib/mem/heap/free_list.asm \
                          $(KERNEL_DIR)/../lib/mem/heap/leak_tracker.asm \
                          $(KERNEL_DIR)/../lib/mem/heap/heap.asm \
                          $(KERNEL_DIR)/../lib/mem/heap/defrag.asm \
                          $(KERNEL_DIR)/../lib/mem/slab/slab.asm \
                          $(KERNEL_DIR)/../lib/mem/slab/slab_create.asm \
                          $(KERNEL_DIR)/../lib/mem/slab/slab_alloc.asm \
                          $(KERNEL_DIR)/../lib/mem/slab/slab_free.asm \
                          $(KERNEL_DIR)/../lib/mem/slab/slab_reap.asm \
                          $(KERNEL_DIR)/../lib/mem/buddy/buddy.asm \
                          $(KERNEL_DIR)/../lib/mem/buddy/buddy_init.asm \
                          $(KERNEL_DIR)/../lib/mem/buddy/buddy_alloc.asm \
                          $(KERNEL_DIR)/../lib/mem/buddy/buddy_free.asm \
                          $(KERNEL_DIR)/../lib/mem/arena/arena.asm \
                          $(KERNEL_DIR)/../lib/mem/arena/arena_create.asm \
                          $(KERNEL_DIR)/../lib/mem/arena/arena_alloc.asm \
                          $(KERNEL_DIR)/../lib/mem/arena/arena_reset.asm \
                          $(KERNEL_DIR)/../lib/mem/arena/arena_destroy.asm \
                          $(KERNEL_DIR)/../lib/mem/arena/arena_checkpoint.asm \
                          $(KERNEL_DIR)/../lib/mem/arena/arena_local.asm \
                          $(KERNEL_DIR)/../lib/mem/pool/pool.asm \
                          $(KERNEL_DIR)/../lib/mem/pool/pool_create.asm \
                          $(KERNEL_DIR)/../lib/mem/pool/pool_grow.asm \
                          $(KERNEL_DIR)/../lib/mem/pool/pool_alloc.asm \
                          $(KERNEL_DIR)/../lib/mem/pool/pool_free.asm \
                          $(KERNEL_DIR)/../lib/mem/pool/pool_destroy.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/pgtable.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/virt.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/pgtable_walk.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/pgtable_map.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/pgtable_unmap.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/pgtable_cache.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/pgtable_lock.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/pgtable_split.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/tlb.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/tlb_shootdown.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/paging/thp.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/reclaim/swap_device.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/reclaim/zswap.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/reclaim/swap.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/reclaim/kswapd.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/ept.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/spt.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/vtlb.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/eve.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/pml.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/nested.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/hmm.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/dmabuf.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/gpummu.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/p2pdma.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/hmm_metrics.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/acpi_hotplug.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/rt_safe/uaf.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/rt_safe/stack.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/rt_safe/sched_affinity.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/pf.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/kernel_relocator.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/zone_transition.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/hardware/locality_scorer.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/reclaim/replacement.asm \
                          $(KERNEL_DIR)/../storage/ummapf/mmap.asm \
                          $(KERNEL_DIR)/../lib/mem/virt/rt_safe/ipc.asm \
                          $(KERNEL_DIR)/../lib/mem/numa/numa.asm $(KERNEL_DIR)/../lib/mem/numa/numa_detect.asm \
                          $(KERNEL_DIR)/../lib/hw/ucpu/mtrr.asm \
                          $(KERNEL_DIR)/../lib/hw/ucpu/pat.asm \
                          $(KERNEL_DIR)/drivers/gpu/fb.asm \
                          $(KERNEL_DIR)/../unet/core/link/net_link.asm \
                          $(KERNEL_DIR)/../unet/core/link/net_ring.inc \
                          $(KERNEL_DIR)/../unet/core/link/net_ring.asm \
                          $(KERNEL_DIR)/../unet/core/link/ring.asm \
                          $(KERNEL_DIR)/../unet/core/link/pci.asm \
                          $(KERNEL_DIR)/../unet/core/link/loan.asm \
                          $(KERNEL_DIR)/../unet/core/link/sbuf.asm \
                          $(KERNEL_DIR)/../unet/core/link/recycle.asm \
                          $(KERNEL_DIR)/../unet/core/link/rss.asm \
                          $(KERNEL_DIR)/sched/fiber.inc \
                          $(KERNEL_DIR)/sched/fiber.asm \
                          $(KERNEL_DIR)/sched/fiber_canary.asm \
                          $(KERNEL_DIR)/sched/fiber_pkey.asm \
                          $(KERNEL_DIR)/sched/fiber_guard.inc \
                          $(KERNEL_DIR)/sched/fiber_guard.asm \
                          $(KERNEL_DIR)/sched/fiber_supervisor.asm \
                          $(KERNEL_DIR)/sched/smp_mpmc.asm \
                          $(KERNEL_DIR)/sched/sched.inc \
                          $(KERNEL_DIR)/sched/sched.asm \
                          $(KERNEL_DIR)/../lib/ufile/ufile.inc \
                          $(KERNEL_DIR)/../lib/ufile/ufile_sanitize.asm \
                          $(KERNEL_DIR)/../lib/ufile/ufile_entropy.asm \
                          $(KERNEL_DIR)/../lib/ufile/ufile_hash.asm \
                          $(KERNEL_DIR)/../lib/ufile/ufile_engine.asm \
                          $(KERNEL_DIR)/../lib/ufile/ufile_transpose.asm \
                          $(KERNEL_DIR)/../lib/ufile/signatures/fs_signatures.asm \
                          $(KERNEL_DIR)/../lib/ufile/signatures/ai_signatures.asm \
                          $(KERNEL_DIR)/../lib/ufile/signatures/exec_signatures.asm \
                          $(KERNEL_DIR)/../lib/ufile/ufile.asm \
                          $(KERNEL_DIR)/../crypto/uhash/sha256/sha256.inc \
                          $(KERNEL_DIR)/../crypto/uhash/sha256/sha256.asm \
                          $(KERNEL_DIR)/../crypto/uhash/blake3/blake3.inc \
                          $(KERNEL_DIR)/../crypto/uhash/blake3/blake3.asm \
                          $(KERNEL_DIR)/../crypto/uhash/blake2/blake2b.asm \
                          $(KERNEL_DIR)/../crypto/uhash/blake2/blake2s.asm \
                          $(KERNEL_DIR)/../crypto/uhash/sha512/sha512.inc \
                          $(KERNEL_DIR)/../crypto/uhash/sha512/sha512.asm \
                          $(KERNEL_DIR)/../crypto/uhash/sha3/sha3.asm \
                          $(KERNEL_DIR)/../crypto/uhash/uhash.asm \
                          $(KERNEL_DIR)/../crypto/usign/ed25519/ed25519.inc \
                          $(KERNEL_DIR)/../crypto/usign/ed25519/ed25519.asm \
                          $(KERNEL_DIR)/../crypto/usign/ecdsa/ecdsa_p256.asm \
                          $(KERNEL_DIR)/../crypto/usign/rsa/rsa_pss.asm \
                          $(KERNEL_DIR)/../crypto/usign/formats/raw.asm \
                          $(KERNEL_DIR)/../crypto/usign/formats/pem.asm \
                          $(KERNEL_DIR)/../crypto/usign/formats/pkcs7.asm \
                          $(KERNEL_DIR)/../crypto/usign/formats/upk_sig.asm \
                          $(KERNEL_DIR)/../crypto/usign/usign.asm \
                          $(KERNEL_DIR)/../crypto/ukdf/hkdf/hkdf.inc \
                          $(KERNEL_DIR)/../crypto/ukdf/hkdf/hkdf.asm \
                          $(KERNEL_DIR)/../crypto/ukdf/argon2/argon2.asm \
                          $(KERNEL_DIR)/../crypto/ukdf/pbkdf2/pbkdf2.asm \
                          $(KERNEL_DIR)/../crypto/ukdf/ukdf.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/ucrypt.inc \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_gcm.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_xts.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/chacha20_poly1305.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_cbc.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_ctr.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_ccm.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_kw.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/asymmetric/x25519.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/asymmetric/ecdh_p256.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/asymmetric/rsa_oaep.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/mac/hmac/hmac.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/mac/kmac/kmac.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/mac/cmac/cmac.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/mac/poly1305/poly1305.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/mac/poly1305/poly1305_2way.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_gcm_siv.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/xchacha20_poly1305.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/asymmetric/curve448.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_gcm_4way.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_kw_ad.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/guards/ct_guard.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/guards/s2n_guard.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/guards/memory_barrier_guard.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/guards/wipe.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/ucrypt_post.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_gcm_avx512.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aes_ocb3.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/sm4_gcm.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/aria_gcm.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/symmetric/camellia_gcm.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/asymmetric/ed448.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/asymmetric/bip32_hdkey.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/asymmetric/secp256k1_schnorr.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/mac/vmac/vmac.asm \
                          $(KERNEL_DIR)/../crypto/ucrypt/ucrypt.asm \
                          $(KERNEL_DIR)/../lib/urand/urand.inc \
                          $(KERNEL_DIR)/../lib/urand/sources/rdrand.asm \
                          $(KERNEL_DIR)/../lib/urand/sources/jitter.asm \
                          $(KERNEL_DIR)/../lib/urand/sources/interrupt_entropy.asm \
                          $(KERNEL_DIR)/../lib/urand/health/entropy_health.asm \
                          $(KERNEL_DIR)/../lib/urand/pools/fortuna_pools.asm \
                          $(KERNEL_DIR)/../lib/urand/generators/chacha20_rng.asm \
                          $(KERNEL_DIR)/../lib/urand/generators/aes_ctr_drbg.asm \
                          $(KERNEL_DIR)/../lib/urand/urand_percpu.asm \
                          $(KERNEL_DIR)/../lib/urand/urand_wipe.asm \
                          $(KERNEL_DIR)/../lib/urand/tests/urand_test.asm \
                          $(KERNEL_DIR)/../lib/urand/urand.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509.inc \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_oid.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_asn1.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_sanitize.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_parse.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_ext.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_san_match.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_policy.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_path.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_time.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_crl.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_ocsp.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_aia.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_name_constraints.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_sct.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_fingerprint.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_key_match.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_trust_store.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_self_signed.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_name_norm.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_csr.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_pqc_cert.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509_chain.asm \
                          $(KERNEL_DIR)/../crypto/ux509/ux509.asm \
                          $(KERNEL_DIR)/../crypto/upqc/upqc.inc \
                          $(KERNEL_DIR)/../crypto/upqc/dilithium.asm \
                          $(KERNEL_DIR)/../crypto/upqc/kyber.asm \
                          $(KERNEL_DIR)/../crypto/upqc/falcon.asm \
                          $(KERNEL_DIR)/../crypto/upqc/sphincs.asm \
                          $(KERNEL_DIR)/../crypto/upqc/upqc.asm \
                          $(KERNEL_DIR)/../lib/ucmp/include/ucmp.inc \
                          $(KERNEL_DIR)/../lib/ucmp/arch/common/macros.inc \
                          $(KERNEL_DIR)/../lib/ucmp/arch/common/error.inc \
                          $(KERNEL_DIR)/../lib/ucmp/arch/common/types.inc \
                          $(KERNEL_DIR)/../lib/ucmp/arch/common/bitops.inc \
                          $(KERNEL_DIR)/../lib/ucmp/arch/x86_64/simd/scan.asm \
                          $(KERNEL_DIR)/../lib/ucmp/core/stream.asm \
                          $(KERNEL_DIR)/../lib/ucmp/core/buffer.asm \
                          $(KERNEL_DIR)/../lib/ucmp/core/bitstream.asm \
                          $(KERNEL_DIR)/../lib/ucmp/algo/lz4/lz4.asm \
                          $(KERNEL_DIR)/../lib/ucmp/algo/lz4/lz4_decomp.asm \
                          $(KERNEL_DIR)/../lib/ucmp/algo/snappy/snappy.asm \
                          $(KERNEL_DIR)/../lib/ucmp/algo/zstd/zstd.asm \
                          $(KERNEL_DIR)/../lib/ucmp/algo/deflate/deflate.asm \
                          $(KERNEL_DIR)/../lib/ucmp/algo/deflate/inflate.asm \
                          $(KERNEL_DIR)/../lib/ucmp/algo/zlib/zlib.asm \
                          $(KERNEL_DIR)/../lib/ucmp/algo/gzip/gzip.asm \
                          $(KERNEL_DIR)/../lib/ucmp/checksum/crc32.asm \
                          $(KERNEL_DIR)/../lib/ucmp/mem/arena.asm \
                          $(KERNEL_DIR)/../lib/ucmp/ucmp.asm \
                          $(KERNEL_DIR)/../ufs/ufs.inc \
                          $(KERNEL_DIR)/../ufs/vfs/vfs.asm \
                          $(KERNEL_DIR)/../ufs/vfs/overlayfs.asm \
                          $(KERNEL_DIR)/../ufs/vfs/ufs_clone.asm \
                          $(KERNEL_DIR)/../ufs/vfs/ufs_snapshot.asm \
                          $(KERNEL_DIR)/../ufs/vfs/ufs_pseudofs.asm \
                          $(KERNEL_DIR)/../ufs/vfs/compat/fat32.asm \
                          $(KERNEL_DIR)/../ufs/vfs/compat/ntfs.asm \
                          $(KERNEL_DIR)/../ufs/vfs/compat/ext4_compat.asm \
                          $(KERNEL_DIR)/../ufs/cache/ufs_pagecache.asm \
                          $(KERNEL_DIR)/../ufs/cache/ufs_arc.asm \
                          $(KERNEL_DIR)/../ufs/cache/ufs_dax.asm \
                          $(KERNEL_DIR)/../ufs/cache/ufs_dedup.asm \
                          $(KERNEL_DIR)/../ufs/cache/ufs_tmpfs.asm \
                          $(KERNEL_DIR)/../ufs/crypto/ufs_crypto.asm \
                          $(KERNEL_DIR)/../ufs/crypto/ufs_pqc.asm \
                          $(KERNEL_DIR)/../ufs/crypto/ufs_fscrypt.asm \
                          $(KERNEL_DIR)/../ufs/crypto/ufs_verity.asm \
                          $(KERNEL_DIR)/../ufs/crypto/ufs_vault.asm \
                          $(KERNEL_DIR)/../ufs/btree/ufs_cow_btree.asm \
                          $(KERNEL_DIR)/../ufs/btree/ufs_alloc_groups.asm \
                          $(KERNEL_DIR)/../ufs/extents/ufs_extents.asm \
                          $(KERNEL_DIR)/../ufs/compress/ufs_compress.asm \
                          $(KERNEL_DIR)/../ufs/compress/erofs.asm \
                          $(KERNEL_DIR)/../ufs/cluster/ufs_cluster.asm \
                          $(KERNEL_DIR)/../ufs/cluster/ufs_erasure.asm \
                          $(KERNEL_DIR)/../ufs/limits/ufs_quota.asm \
                          $(KERNEL_DIR)/../ufs/drivers/nvme.asm \
                          $(KERNEL_DIR)/../ufs/drivers/nvme_zns.asm \
                          $(KERNEL_DIR)/../ufs/drivers/usb_storage.asm \
                          $(KERNEL_DIR)/../ufs/drivers/ahci.asm \
                          $(KERNEL_DIR)/../ufs/drivers/sdhci.asm \
                          $(KERNEL_DIR)/../ufs/drivers/virtio_blk.asm \
                          $(KERNEL_DIR)/../ufs/drivers/nvme_of.asm \
                          $(KERNEL_DIR)/../ufs/journal/ufs_journal.asm \
                          $(KERNEL_DIR)/../ufs/tests/ufs_fuzz.asm \
                          $(KERNEL_DIR)/../ufs/ufs.asm

	$(ASM) -f bin $(KERNEL_DIR)/entry.asm \
		-i $(KERNEL_DIR)/ -i $(KERNEL_DIR)/../ \
		-o $(KERNEL_DIR)/kernel.bin
	python3 -c "import struct; f='$(KERNEL_DIR)/kernel.bin'; d=bytearray(open(f,'rb').read()); struct.pack_into('<Q',d,16,0); s=sum(struct.unpack('<Q',d[i:i+8].ljust(8,b'\0'))[0] for i in range(0,len(d),8))&0xFFFFFFFFFFFFFFFF; struct.pack_into('<Q',d,16,s); open(f,'wb').write(d)"

# Disk image layout:
#   Sector 0       = stage1 (MBR, 512 bytes)
#   Sector 1-64    = stage2 (up to 32KB)
#   Sector 65+     = kernel (seek=65 = CHS sector 66)
boot.img: stage1/stage1.bin stage2/stage2.bin $(KERNEL_DIR)/kernel.bin
	dd if=/dev/zero of=boot.img bs=512 count=2880
	dd if=stage1/stage1.bin of=boot.img conv=notrunc
	dd if=stage2/stage2.bin of=boot.img bs=512 seek=1 conv=notrunc
	dd if=$(KERNEL_DIR)/kernel.bin of=boot.img bs=512 seek=65 conv=notrunc

# Enforce 512 byte MBR size — never disable this
check: stage1/stage1.bin
	@size=$$(wc -c < stage1/stage1.bin); \
	if [ $$size -ne $(STAGE1_MAX) ]; then \
		echo "ERROR: stage1 is $$size bytes, must be exactly $(STAGE1_MAX) bytes"; \
		exit 1; \
	fi; \
	echo "stage1 size OK: $$size / $(STAGE1_MAX) bytes"

# Run normally (64-bit)
run: boot.img
	$(QEMU64) -drive format=raw,file=boot.img -serial stdio -no-reboot

# Debug real mode (16-bit — use i386 not x86_64)
debug: boot.img
	$(QEMU32) -drive format=raw,file=boot.img -serial stdio -s -S &
	gdb -ex "set architecture i8086" \
		-ex "target remote :1234" \
		-ex "break *0x7C00" \
		-ex "continue"

# Debug stage2 (32-bit protected mode)
debug32: boot.img
	$(QEMU32) -drive format=raw,file=boot.img -serial stdio -s -S &
	gdb -ex "set architecture i386" \
		-ex "target remote :1234" \
		-ex "break *0x8000" \
		-ex "continue"

# UEFI Path build targets
uefi/entry.obj: uefi/entry.asm uefi/protocol.asm uefi/console.asm uefi/gop.asm uefi/file.asm uefi/memory.asm uefi/handoff.asm
	$(ASM) -f win64 uefi/entry.asm -o uefi/entry.obj -i uefi/ -i .

uefi/BOOTX64.EFI: uefi/entry.obj
	$(LINKER) /subsystem:efi_application /entry:efi_main /out:uefi/BOOTX64.EFI uefi/entry.obj

# Run tests
test: boot.img
	bash tests/run_all.sh

clean:
	rm -f boot.img stage1/stage1.bin stage2/stage2.bin $(KERNEL_DIR)/kernel.bin uefi/entry.obj uefi/BOOTX64.EFI
