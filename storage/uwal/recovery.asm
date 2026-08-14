; =============================================================================
; Tattva OS — storage/uwal/recovery.asm
; =============================================================================
; UWAL Crash Recovery — Tail Discovery, Transaction Resolution & Replay.
;
; Implements:
;   - Replay handler registration per stream (`uwal_register_handler`)
;   - Two-pass recovery over the log (`uwal_recover`)
;   - Checkpoint publication (`uwal_checkpoint`)
;
; Recovery is two passes, and the order matters.
;
; PASS ONE scans from the checkpoint to the end of the log and records which
; transactions reached a commit marker. Nothing is applied yet.
;
; PASS TWO rescans and replays only records belonging to committed
; transactions. Anything without a commit is discarded — it was in flight when
; the machine stopped and was never promised to anyone.
;
; A single-pass recovery cannot do this. Reaching a data record, it has no way
; to know whether the commit lies ahead, so it must either apply changes it may
; have to undo, or defer everything and effectively become two passes anyway.
;
; The scan stops at the first record that fails verification. That is not
; failure handling — it is the normal case. The tail of a crashed log is almost
; always a partially-written record, and the checksum is exactly what makes it
; distinguishable from a complete one.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uwal/uwal.inc"

%define UWAL_MAX_HANDLERS            8
%define UWAL_MAX_TXNS                4096    ; Committed-transaction table size
%define UWAL_TXN_MASK                (UWAL_MAX_TXNS - 1)

; -----------------------------------------------------------------------------
; A registered replay handler. One physical log fans out to several clients.
; -----------------------------------------------------------------------------
struc uwal_handler_t
    .stream:            resd 1      ; Stream this handler owns
    .active:            resd 1
    .callback:          resq 1      ; fn(record*, payload*, len) -> 0 on success
endstruc

section .data
align 64

uwal_handlers:          times UWAL_MAX_HANDLERS * uwal_handler_t_size db 0

; Open-addressed set of transaction ids seen to commit during pass one.
uwal_committed:         times UWAL_MAX_TXNS db 0
uwal_committed_ids:     times UWAL_MAX_TXNS * 8 db 0

uwal_replay_count:      dq 0        ; Records replayed
uwal_discard_count:     dq 0        ; Records dropped as uncommitted
uwal_recover_runs:      dq 0

; Staging for one record read back from the device.
uwal_rec_buf:           times UWAL_REC_HEADER_SIZE + UWAL_MAX_PAYLOAD db 0

section .text

global uwal_register_handler
global uwal_recover
global uwal_checkpoint
global uwal_txn_mark_committed
global uwal_txn_is_committed
global uwal_recovery_stats

; -----------------------------------------------------------------------------
; uwal_txn_slot
;
; Hashes a transaction id to a slot. Fibonacci hashing again: ids are allocated
; sequentially, so the low bits alone would cluster.
;
; Inputs:
;   RDI = Transaction id
;
; Returns:
;   RAX = Slot index
; -----------------------------------------------------------------------------
align 32
uwal_txn_slot:
    mov rax, rdi
    mov rcx, 0x9E3779B97F4A7C15
    imul rax, rcx
    shr rax, 52
    and rax, UWAL_TXN_MASK
    ret

; -----------------------------------------------------------------------------
; uwal_txn_mark_committed
;
; Records that a transaction reached a commit marker.
;
; Inputs:
;   RDI = Transaction id
;
; Returns:
;   EAX = 0 on success, UWAL_ERR_NOSPC when the table is saturated
; -----------------------------------------------------------------------------
align 32
uwal_txn_mark_committed:
    push rbx
    push r12
    push r13

    mov r13, rdi
    test r13, r13
    jz .tm_inval                    ; Transaction id 0 is never valid

    call uwal_txn_slot
    mov r12, rax
    mov rbx, UWAL_MAX_TXNS

.tm_probe:
    lea rax, [uwal_committed]
    cmp byte [rax + r12], 0
    je .tm_claim

    ; Already recorded: a duplicate commit marker is harmless.
    lea rax, [uwal_committed_ids]
    mov rcx, [rax + r12 * 8]
    cmp rcx, r13
    je .tm_done

    inc r12
    and r12, UWAL_TXN_MASK
    dec rbx
    jnz .tm_probe

    mov eax, UWAL_ERR_NOSPC
    jmp .tm_return

.tm_claim:
    lea rax, [uwal_committed]
    mov byte [rax + r12], 1
    lea rax, [uwal_committed_ids]
    mov [rax + r12 * 8], r13

.tm_done:
    xor eax, eax
    jmp .tm_return

.tm_inval:
    mov eax, UWAL_ERR_INVAL

.tm_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_txn_is_committed
;
; Inputs:
;   RDI = Transaction id
;
; Returns:
;   EAX = 1 when the transaction committed, 0 otherwise
; -----------------------------------------------------------------------------
align 32
uwal_txn_is_committed:
    push rbx
    push r12
    push r13

    mov r13, rdi
    call uwal_txn_slot
    mov r12, rax
    mov rbx, UWAL_MAX_TXNS

.ti_probe:
    lea rax, [uwal_committed]
    cmp byte [rax + r12], 0
    je .ti_no                       ; Empty slot ends the probe

    lea rax, [uwal_committed_ids]
    mov rcx, [rax + r12 * 8]
    cmp rcx, r13
    je .ti_yes

    inc r12
    and r12, UWAL_TXN_MASK
    dec rbx
    jnz .ti_probe

.ti_no:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    ret

.ti_yes:
    mov eax, 1
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_register_handler
;
; Binds a replay callback to a stream.
;
; Inputs:
;   EDI = Stream id
;   RSI = Callback: fn(record*, payload*, payload_len) -> 0 on success
;
; Returns:
;   EAX = 0 on success, UWAL_ERR_NOSPC when the table is full
; -----------------------------------------------------------------------------
align 32
uwal_register_handler:
    push rbx
    push r12

    test rsi, rsi
    jz .rh_inval

    lea rbx, [uwal_handlers]
    mov r12, UWAL_MAX_HANDLERS

.rh_scan:
    cmp dword [rbx + uwal_handler_t.active], 0
    je .rh_claim

    ; Re-registering a stream replaces its handler.
    cmp dword [rbx + uwal_handler_t.stream], edi
    je .rh_claim

    add rbx, uwal_handler_t_size
    dec r12
    jnz .rh_scan

    mov eax, UWAL_ERR_NOSPC
    pop r12
    pop rbx
    ret

.rh_claim:
    mov dword [rbx + uwal_handler_t.stream], edi
    mov [rbx + uwal_handler_t.callback], rsi
    mov dword [rbx + uwal_handler_t.active], 1

    xor eax, eax
    pop r12
    pop rbx
    ret

.rh_inval:
    mov eax, UWAL_ERR_INVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_find_handler
;
; Inputs:
;   EDI = Stream id
;
; Returns:
;   RAX = Handler descriptor pointer, or 0 when the stream is unclaimed
; -----------------------------------------------------------------------------
align 32
uwal_find_handler:
    push rbx
    push r12

    lea rbx, [uwal_handlers]
    mov r12, UWAL_MAX_HANDLERS

.fh_scan:
    cmp dword [rbx + uwal_handler_t.active], 0
    je .fh_next
    cmp dword [rbx + uwal_handler_t.stream], edi
    je .fh_found

.fh_next:
    add rbx, uwal_handler_t_size
    dec r12
    jnz .fh_scan

    xor eax, eax
    pop r12
    pop rbx
    ret

.fh_found:
    mov rax, rbx
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_scan_pass
;
; Walks the log from the checkpoint to the first unverifiable record.
;
; Inputs:
;   EDI = 0 for pass one (collect commits), 1 for pass two (replay)
;
; Returns:
;   RAX = Highest LSN successfully verified
; -----------------------------------------------------------------------------
align 32
uwal_scan_pass:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r15d, edi                   ; Pass number
    xor r14, r14                    ; Segment byte cursor
    xor r13, r13                    ; Highest verified LSN

    lea rbx, [uwal_super]
    mov r12, [rbx + uwal_super_t.checkpoint_lsn]

.sp_loop:
    ; Pull the next record header plus payload into staging.
    mov rdi, r14
    lea rsi, [uwal_rec_buf]
    mov edx, UWAL_REC_HEADER_SIZE + UWAL_MAX_PAYLOAD
    call uwal_device_read
    test eax, eax
    js .sp_done                     ; Ran off the end of the log region

    lea rdi, [uwal_rec_buf]
    call uwal_rec_verify
    test eax, eax
    jnz .sp_done                    ; Torn or absent: this is the tail

    lea rbx, [uwal_rec_buf]
    mov rax, [rbx + uwal_rec_t.lsn]

    ; A record older than the checkpoint is already applied; skip it.
    cmp rax, r12
    jb .sp_advance

    mov r13, rax                    ; Track the furthest good LSN

    movzx eax, byte [rbx + uwal_rec_t.type]

    test r15d, r15d
    jnz .sp_replay

    ; --- Pass one: note commit markers only --------------------------------
    cmp eax, UWAL_REC_COMMIT
    jne .sp_advance

    mov rdi, [rbx + uwal_rec_t.txn_id]
    call uwal_txn_mark_committed
    jmp .sp_advance

.sp_replay:
    ; --- Pass two: apply committed data records ----------------------------
    cmp eax, UWAL_REC_DATA
    jne .sp_advance                 ; Markers carry nothing to apply

    mov rdi, [rbx + uwal_rec_t.txn_id]
    call uwal_txn_is_committed
    test eax, eax
    jz .sp_discard                  ; In flight at the crash: drop it

    movzx edi, byte [rbx + uwal_rec_t.stream]
    call uwal_find_handler
    test rax, rax
    jz .sp_advance                  ; No client owns this stream

    mov rcx, [rax + uwal_handler_t.callback]
    mov rdi, rbx                            ; Record header
    lea rsi, [rbx + UWAL_REC_HEADER_SIZE]   ; Payload
    mov edx, dword [rbx + uwal_rec_t.payload_len]
    call rcx

    inc qword [uwal_replay_count]
    jmp .sp_advance

.sp_discard:
    inc qword [uwal_discard_count]

.sp_advance:
    lea rbx, [uwal_rec_buf]
    mov eax, dword [rbx + uwal_rec_t.payload_len]
    add eax, UWAL_REC_HEADER_SIZE
    add r14, rax                    ; Step past this record
    jmp .sp_loop

.sp_done:
    mov rax, r13
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_recover
;
; Runs both passes and resumes the log at the discovered tail.
;
; Returns:
;   EAX = UWAL_OK, or a negative UWAL_ERR_*
; -----------------------------------------------------------------------------
align 32
uwal_recover:
    push rbx
    push r12

    ; Clear the committed-transaction set: a stale entry from a previous run
    ; would let an uncommitted transaction be replayed.
    lea rdi, [uwal_committed]
    mov rcx, UWAL_MAX_TXNS
    xor al, al
    rep stosb

    mov qword [uwal_replay_count], 0
    mov qword [uwal_discard_count], 0

    xor edi, edi                    ; Pass one: collect commit markers
    call uwal_scan_pass

    mov edi, 1                      ; Pass two: replay the committed ones
    call uwal_scan_pass
    mov r12, rax                    ; Highest verified LSN

    ; Resume issuing LSNs after the last one that survived verification.
    inc r12
    mov [uwal_head_lsn], r12

    inc qword [uwal_recover_runs]

    xor eax, eax
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_checkpoint
;
; Publishes a checkpoint: every change up to this LSN has reached its home
; location, so recovery may start here and older segments may be reused.
;
; The superblock is flushed before segments are released. If the ordering were
; reversed, a crash in between would leave segments marked reusable while the
; on-disk checkpoint still pointed into them — recovery would then read data
; the log had already given permission to overwrite.
;
; Inputs:
;   RDI = LSN through which all changes are durable at their home location
;
; Returns:
;   RAX = Segments reclaimed, or a negative UWAL_ERR_*
; -----------------------------------------------------------------------------
align 32
uwal_checkpoint:
    push rbx
    push r12

    mov r12, rdi

    lea rbx, [uwal_super]

    ; A checkpoint may never move backwards.
    mov rax, [rbx + uwal_super_t.checkpoint_lsn]
    cmp r12, rax
    jb .cp_inval

    mov rax, [uwal_head_lsn]
    cmp r12, rax
    ja .cp_inval                    ; Beyond anything ever assigned

    mov [rbx + uwal_super_t.checkpoint_lsn], r12

    ; Recompute the superblock checksum over its new contents.
    mov dword [rbx + uwal_super_t.checksum], 0
    mov rdi, rbx
    mov rsi, uwal_super_t.checksum
    call uwal_crc32c
    mov dword [rbx + uwal_super_t.checksum], eax

    ; Superblock durable BEFORE segments become reusable.
    call uwal_sync
    test eax, eax
    js .cp_io

    mov rdi, r12
    call uwal_segment_reclaim

    jmp .cp_return

.cp_io:
    mov rax, UWAL_ERR_IO
    jmp .cp_return

.cp_inval:
    mov rax, UWAL_ERR_INVAL

.cp_return:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_recovery_stats
;
; Inputs:
;   RDI = Pointer to three qwords: replayed, discarded, recovery runs
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uwal_recovery_stats:
    mov rax, [uwal_replay_count]
    mov [rdi], rax
    mov rax, [uwal_discard_count]
    mov [rdi + 8], rax
    mov rax, [uwal_recover_runs]
    mov [rdi + 16], rax
    xor eax, eax
    ret
