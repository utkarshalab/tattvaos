; =============================================================================
; Tattva OS — storage/uwal/fsync.asm
; =============================================================================
; UWAL Durability Layer — Device Barriers, Group Commit & Block Transport.
;
; Implements:
;   - Durability barrier honouring the configured sync mode (`uwal_sync`)
;   - Group commit batching (`uwal_group_commit_join`, `uwal_group_commit_run`)
;   - Block transport to the log region (`uwal_device_read/write`)
;
; A write returning does not mean it is durable. It usually means the device
; accepted it into a volatile write cache that a power loss will discard. Only
; an explicit cache flush, or a Force Unit Access write that bypasses the cache
; entirely, makes it survive. This is where most "we used a WAL and still lost
; data" stories come from.
;
; The barrier is also the log's throughput ceiling: a device flush costs
; hundreds of microseconds, so one flush per transaction caps the system at a
; few thousand commits per second regardless of how fast the CPU is.
;
; Group commit is the standard answer. Transactions arriving while a flush is
; already in progress wait for the NEXT one instead of issuing their own, so N
; concurrent commits cost one flush rather than N. Throughput rises with
; concurrency while each individual commit still waits for a real barrier
; before being told it succeeded.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uwal/uwal.inc"

section .data
align 64

uwal_sync_mode:         dq UWAL_SYNC_FLUSH
uwal_flush_count:       dq 0        ; Barriers actually issued
uwal_flush_joined:      dq 0        ; Commits that rode an existing barrier
uwal_flush_epoch:       dq 0        ; Increments once per completed barrier
uwal_flush_active:      dq 0        ; Non-zero while a barrier is in flight

; Base LBA of the log region, cached from the superblock.
uwal_dev_base_lba:      dq 0
; NVMe controller the log lives on. Bound at init; every transport call needs
; it because the driver takes the controller as its first argument.
global uwal_dev_ctrl
uwal_dev_ctrl:          dq 0
uwal_dev_reads:         dq 0
uwal_dev_writes:        dq 0

section .text

global uwal_sync
global uwal_set_sync_mode
global uwal_group_commit_join
global uwal_group_commit_run
global uwal_device_read
global uwal_device_write
global uwal_device_flush
global uwal_sync_stats

; -----------------------------------------------------------------------------
; uwal_set_sync_mode
;
; Selects the durability/throughput trade.
;
; UWAL_SYNC_NONE is legitimate only where losing recent commits is acceptable —
; a rebuildable cache, say. For anything claiming durability it is wrong, and
; it is fast precisely because it is not doing the work.
;
; Inputs:
;   EDI = UWAL_SYNC_*
;
; Returns:
;   EAX = 0 on success, UWAL_ERR_INVAL on an unknown mode
; -----------------------------------------------------------------------------
align 32
uwal_set_sync_mode:
    cmp edi, UWAL_SYNC_BARRIER
    ja .sm_inval

    mov [uwal_sync_mode], rdi
    xor eax, eax
    ret

.sm_inval:
    mov eax, UWAL_ERR_INVAL
    ret

; -----------------------------------------------------------------------------
; uwal_device_flush
;
; Issues the device cache flush. This is the expensive primitive everything
; else here exists to economise on.
;
; Returns:
;   EAX = 0 on success, UWAL_ERR_IO on device failure
; -----------------------------------------------------------------------------
align 32
uwal_device_flush:
    push rbx

    ; Order our own stores before asking the device to flush; without this the
    ; flush can be issued before the data it is supposed to cover is visible.
    sfence

    ; NVMe FLUSH (opcode 0x00) against the log namespace.
    mov rdi, [uwal_dev_ctrl]
    test rdi, rdi
    jz .df_fail                     ; No controller bound: cannot claim durability
    call uxfs_nvme_flush
    test eax, eax
    js .df_fail

    inc qword [uwal_flush_count]
    xor eax, eax
    pop rbx
    ret

.df_fail:
    mov eax, UWAL_ERR_IO
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_sync
;
; Durability barrier. On success every record appended before the call is
; guaranteed to survive power loss.
;
; Returns:
;   EAX = 0 on success, UWAL_ERR_IO on device failure
; -----------------------------------------------------------------------------
align 32
uwal_sync:
    push rbx

    mov rax, [uwal_sync_mode]

    cmp rax, UWAL_SYNC_NONE
    je .sy_none

    cmp rax, UWAL_SYNC_FUA
    je .sy_fua

    ; FLUSH and BARRIER both need a real device flush; BARRIER additionally
    ; orders it against subsequent writes.
    call uwal_device_flush
    test eax, eax
    jnz .sy_fail

    mov rax, [uwal_sync_mode]
    cmp rax, UWAL_SYNC_BARRIER
    jne .sy_done
    sfence

.sy_done:
    inc qword [uwal_flush_epoch]
    xor eax, eax
    pop rbx
    ret

.sy_fua:
    ; Writes already bypassed the cache; only store ordering remains.
    sfence
    inc qword [uwal_flush_epoch]
    xor eax, eax
    pop rbx
    ret

.sy_none:
    ; Buffered: report success without durability. Documented, not accidental.
    xor eax, eax
    pop rbx
    ret

.sy_fail:
    mov eax, UWAL_ERR_IO
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_group_commit_join
;
; Joins an in-flight barrier rather than issuing another.
;
; The epoch counter is the mechanism: a caller samples it, and any barrier that
; completes afterwards necessarily covers the caller's record, because the
; record was already written before the call. Waiting for the epoch to advance
; is therefore sufficient — no separate queue of waiters is needed.
;
; Returns:
;   EAX = 0 once a barrier covering the caller's writes has completed
; -----------------------------------------------------------------------------
align 32
uwal_group_commit_join:
    push rbx
    push r12

    mov r12, [uwal_flush_epoch]     ; Epoch we must see advance past

    cmp qword [uwal_flush_active], 0
    je .gj_lead                     ; Nobody flushing: become the leader

    inc qword [uwal_flush_joined]

.gj_wait:
    pause                           ; Spin hint while the leader flushes
    mov rax, [uwal_flush_epoch]
    cmp rax, r12
    ja .gj_covered
    jmp .gj_wait

.gj_covered:
    xor eax, eax
    pop r12
    pop rbx
    ret

.gj_lead:
    ; Claim leadership; if another CPU beat us to it, fall back to waiting.
    mov rax, 1
    xchg rax, [uwal_flush_active]
    test rax, rax
    jnz .gj_wait

    call uwal_sync
    mov rbx, rax

    mov qword [uwal_flush_active], 0

    mov eax, ebx
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_group_commit_run
;
; Forces a barrier as leader, ignoring any batching. Used by checkpointing,
; where waiting behind another batch would be pointless.
;
; Returns:
;   EAX = 0 on success, UWAL_ERR_IO on device failure
; -----------------------------------------------------------------------------
align 32
uwal_group_commit_run:
    push rbx

    mov qword [uwal_flush_active], 1
    call uwal_sync
    mov rbx, rax
    mov qword [uwal_flush_active], 0

    mov eax, ebx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_device_write
;
; Writes bytes into the log region at a segment-relative offset.
;
; The log addresses the block device directly rather than going through uxfs.
; Routing it through the filesystem would mean every log write also generated
; filesystem metadata journalling — the double-journalling the split between
; uwal and uxfs exists to avoid — and would make uwal depend on the very layer
; that depends on it.
;
; Inputs:
;   RDI = Segment base LBA
;   RSI = Byte offset within the segment
;   RDX = Source buffer
;   ECX = Byte count
;
; Returns:
;   EAX = 0 on success, UWAL_ERR_IO on device failure
; -----------------------------------------------------------------------------
align 32
uwal_device_write:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Segment base LBA
    mov r12, rsi                    ; Offset
    mov r13, rdx                    ; Buffer
    mov r14d, ecx                   ; Length

    test r14d, r14d
    jz .dw_done

    ; Translate the byte offset into an absolute LBA. Records are block-framed
    ; by the segment writer, so an append always starts on a block boundary.
    mov rax, r12
    shr rax, 12                     ; / UWAL_BLOCK_SIZE
    add rax, rbx                    ; Absolute LBA

    ; Round the byte count up to whole blocks: the device transfers sectors.
    mov rdx, r14
    add rdx, UWAL_BLOCK_SIZE - 1
    shr rdx, 12

    mov rdi, [uwal_dev_ctrl]
    test rdi, rdi
    jz .dw_fail
    mov rsi, rax                    ; Starting LBA
    mov rcx, r13                    ; DMA source buffer
    call uxfs_nvme_write_sectors
    test eax, eax
    js .dw_fail

    inc qword [uwal_dev_writes]

.dw_done:
    xor eax, eax
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

.dw_fail:
    mov eax, UWAL_ERR_IO
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_device_read
;
; Reads bytes back from the log region during recovery.
;
; Inputs:
;   RDI = Byte offset within the log region
;   RSI = Destination buffer
;   EDX = Byte count
;
; Returns:
;   EAX = 0 on success, UWAL_ERR_IO past the end of the region
; -----------------------------------------------------------------------------
align 32
uwal_device_read:
    push rbx
    push r12
    push r13

    mov rbx, rdi                    ; Offset
    mov r12, rsi                    ; Destination
    mov r13d, edx                   ; Length

    test r13d, r13d
    jz .dr_done

    ; Refuse to read past the configured log region.
    mov rax, UWAL_SEGMENT_SIZE
    imul rax, [uwal_seg_count]
    cmp rbx, rax
    jae .dr_fail

    mov rax, rbx
    shr rax, 12
    add rax, [uwal_dev_base_lba]

    mov rdx, r13
    add rdx, UWAL_BLOCK_SIZE - 1
    shr rdx, 12                     ; Whole blocks to transfer

    mov rdi, [uwal_dev_ctrl]
    test rdi, rdi
    jz .dr_fail
    mov rsi, rax                    ; Starting LBA
    mov rcx, r12                    ; DMA destination buffer
    call uxfs_nvme_read_sectors
    test eax, eax
    js .dr_fail

    inc qword [uwal_dev_reads]

.dr_done:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.dr_fail:
    mov eax, UWAL_ERR_IO
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_sync_stats
;
; Inputs:
;   RDI = Pointer to five qwords: flushes, joined, epoch, reads, writes
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uwal_sync_stats:
    mov rax, [uwal_flush_count]
    mov [rdi], rax
    mov rax, [uwal_flush_joined]
    mov [rdi + 8], rax
    mov rax, [uwal_flush_epoch]
    mov [rdi + 16], rax
    mov rax, [uwal_dev_reads]
    mov [rdi + 24], rax
    mov rax, [uwal_dev_writes]
    mov [rdi + 32], rax
    xor eax, eax
    ret
