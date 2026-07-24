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
                          $(KERNEL_DIR)/../crypto/usign/pqc/dilithium.asm \
                          $(KERNEL_DIR)/../crypto/usign/formats/raw.asm \
                          $(KERNEL_DIR)/../crypto/usign/formats/pem.asm \
                          $(KERNEL_DIR)/../crypto/usign/formats/pkcs7.asm \
                          $(KERNEL_DIR)/../crypto/usign/formats/upk_sig.asm \
                          $(KERNEL_DIR)/../crypto/usign/usign.asm

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
