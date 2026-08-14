; =============================================================================
; Tattva OS — storage/uwal/uwal.asm
; =============================================================================
; Master UWAL (Unikernel Write-Ahead Log) Subsystem Dispatcher.
;
; Single-pass NASM included subsystem handler linking every UWAL sub-module:
;   - Core:      record framing, LSN assignment, transaction markers
;   - Segments:  ring allocation, sealing, checkpoint-driven reclamation
;   - Recovery:  two-pass tail discovery and committed-transaction replay
;   - Fsync:     device barriers, group commit, block transport
;
; UWAL is a general-purpose durable log serving udb and any other client that
; needs crash consistency. It is deliberately separate from the filesystem
; metadata journal in storage/uxfs/journal: each stack owns its own log and
; addresses the block device directly, which is what "no redundant block
; layers" in storage/README.md requires. Stacking a database log on a
; filesystem log would journal every commit twice.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "storage/uwal/uwal.inc"

; -----------------------------------------------------------------------------
; Durability Layer — included first: everything above it issues barriers.
; -----------------------------------------------------------------------------
%include "storage/uwal/fsync.asm"

; -----------------------------------------------------------------------------
; Segment Ring
; -----------------------------------------------------------------------------
%include "storage/uwal/segment.asm"

; -----------------------------------------------------------------------------
; Core Append Path
; -----------------------------------------------------------------------------
%include "storage/uwal/wal.asm"

; -----------------------------------------------------------------------------
; Crash Recovery
; -----------------------------------------------------------------------------
%include "storage/uwal/recovery.asm"

section .text

global uwal_subsystem_init
global uwal_shutdown

; -----------------------------------------------------------------------------
; uwal_subsystem_init
;
; Brings the log online end to end: formats or validates the superblock, lays
; out the segment ring, and replays anything the previous run left uncommitted.
;
; Inputs:
;   RDI = Pointer to the uxfs_nvme_ctrl_t the log lives on
;   RSI = Base LBA of the log region
;   EDX = Segment count
;   ECX = UWAL_SYNC_* durability mode
;
; Returns:
;   EAX = UWAL_OK, or a negative UWAL_ERR_*
; -----------------------------------------------------------------------------
align 32
uwal_subsystem_init:
    push rbx
    push r12
    push r13
    push r14

    mov r14, rdi                    ; Controller
    mov rbx, rsi                    ; Base LBA
    mov r12d, edx                   ; Segment count
    mov r13d, ecx                   ; Sync mode

    test r14, r14
    jz .init_inval                  ; Without a controller nothing is durable

    mov edi, r13d
    call uwal_set_sync_mode
    test eax, eax
    jnz .init_return

    ; Cache the transport bindings before anything can issue I/O.
    mov [uwal_dev_ctrl], r14
    mov [uwal_dev_base_lba], rbx

    mov rdi, rbx
    mov esi, r12d
    call uwal_init
    jmp .init_return

.init_inval:
    mov eax, UWAL_ERR_INVAL

.init_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_shutdown
;
; Flushes outstanding records and checkpoints through the current head, so a
; clean shutdown leaves nothing for the next boot to replay.
;
; Returns:
;   EAX = UWAL_OK, or a negative UWAL_ERR_*
; -----------------------------------------------------------------------------
align 32
uwal_shutdown:
    push rbx

    call uwal_group_commit_run
    test eax, eax
    js .sd_fail

    ; Checkpoint at the last assigned LSN: everything is durable by now.
    mov rdi, [uwal_head_lsn]
    dec rdi
    call uwal_checkpoint
    test rax, rax
    js .sd_fail

    xor eax, eax
    pop rbx
    ret

.sd_fail:
    mov eax, UWAL_ERR_IO
    pop rbx
    ret
