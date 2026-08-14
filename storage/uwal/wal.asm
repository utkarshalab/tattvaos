; =============================================================================
; Tattva OS — storage/uwal/wal.asm
; =============================================================================
; UWAL Core — Append Path, LSN Assignment & Record Framing.
;
; Implements:
;   - Log initialisation and superblock formatting (`uwal_init`, `uwal_format`)
;   - Record append with monotonic LSN assignment (`uwal_append`)
;   - Transaction commit and abort markers (`uwal_commit`, `uwal_abort`)
;   - Record integrity via CRC32C (`uwal_rec_checksum`, `uwal_rec_verify`)
;
; The write-ahead rule: a record describing a change must be durable BEFORE
; the change itself is written to its home location. Recovery can then redo
; anything the log knows about, and anything the log does not know about
; provably never reached the data. Reversing that order makes the log useless —
; a crash can leave data modified with no record explaining how to undo it.
;
; LSNs are strictly increasing and never reused. They order records across the
; whole log, including across segment wraps, so recovery can distinguish a live
; tail from a stale record left behind in a recycled segment whose checksum
; still happens to validate.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM, SSE4.2)
; =============================================================================

%include "storage/uwal/uwal.inc"

section .data
align 64

global uwal_super
uwal_super:             times uwal_super_t_size db 0

global uwal_head_lsn
uwal_head_lsn:          dq 1        ; LSN 0 is reserved as "no record"

uwal_prev_lsn:          dq 0        ; LSN of the last appended record
uwal_next_txn:          dq 1        ; Transaction id allocator
uwal_initialised:       dq 0
uwal_appends:           dq 0        ; Records appended
uwal_bytes_written:     dq 0

; Staging buffer for one record header plus payload before it is handed to
; the segment writer.
uwal_stage:             times UWAL_REC_HEADER_SIZE + UWAL_MAX_PAYLOAD db 0

section .text

global uwal_init
global uwal_format
global uwal_append
global uwal_commit
global uwal_abort
global uwal_begin_txn
global uwal_rec_checksum
global uwal_rec_verify
global uwal_crc32c
global uwal_stats

; -----------------------------------------------------------------------------
; uwal_crc32c
;
; CRC32C (Castagnoli) via the SSE4.2 instruction, eight bytes at a time.
;
; Inputs:
;   RDI = Buffer pointer
;   RSI = Length in bytes
;
; Returns:
;   EAX = CRC32C
; -----------------------------------------------------------------------------
align 32
uwal_crc32c:
    push rbx

    mov rbx, rdi
    mov rcx, rsi
    mov eax, 0xFFFFFFFF

.cq_loop:
    cmp rcx, 8
    jb .cq_tail
    crc32 rax, qword [rbx]
    add rbx, 8
    sub rcx, 8
    jmp .cq_loop

.cq_tail:
    test rcx, rcx
    jz .cq_done
    crc32 eax, byte [rbx]
    inc rbx
    dec rcx
    jmp .cq_tail

.cq_done:
    not eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_rec_checksum
;
; Computes the checksum over a record: the header with its own checksum field
; zeroed, then the payload. Zeroing the field first is what makes the value
; reproducible on the verify side.
;
; Inputs:
;   RDI = Pointer to a uwal_rec_t header immediately followed by its payload
;
; Returns:
;   EAX = CRC32C over header + payload
; -----------------------------------------------------------------------------
align 32
uwal_rec_checksum:
    push rbx
    push r12
    push r13

    mov rbx, rdi

    ; Save and clear the stored checksum so it does not cover itself.
    mov r12d, dword [rbx + uwal_rec_t.checksum]
    mov dword [rbx + uwal_rec_t.checksum], 0

    mov r13d, dword [rbx + uwal_rec_t.payload_len]

    mov rdi, rbx
    mov rsi, UWAL_REC_HEADER_SIZE
    add rsi, r13
    call uwal_crc32c

    ; Restore whatever was there so this stays a pure read for the verify path.
    mov dword [rbx + uwal_rec_t.checksum], r12d

    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_rec_verify
;
; Validates a record's sentinel, length and checksum.
;
; A record that fails here is not necessarily corruption: the tail of a log is
; routinely a partially-written record from the crash that stopped the system.
; Recovery treats the first failure as the end of the log, which is why the
; checksum must cover the payload — a header-only checksum would accept a
; record whose payload never landed.
;
; Inputs:
;   RDI = Pointer to a candidate record
;
; Returns:
;   EAX = UWAL_OK, UWAL_ERR_CORRUPT on a bad sentinel, or UWAL_ERR_TORN
; -----------------------------------------------------------------------------
align 32
uwal_rec_verify:
    push rbx
    push r12

    mov rbx, rdi

    cmp word [rbx + uwal_rec_t.magic], UWAL_REC_MAGIC
    jne .rv_corrupt

    mov eax, dword [rbx + uwal_rec_t.payload_len]
    cmp eax, UWAL_MAX_PAYLOAD
    ja .rv_corrupt                  ; Implausible length: header is garbage

    movzx eax, byte [rbx + uwal_rec_t.type]
    test eax, eax
    jz .rv_corrupt
    cmp eax, UWAL_REC_SEGMENT_END
    ja .rv_corrupt

    mov r12d, dword [rbx + uwal_rec_t.checksum]

    mov rdi, rbx
    call uwal_rec_checksum

    cmp eax, r12d
    jne .rv_torn

    xor eax, eax
    pop r12
    pop rbx
    ret

.rv_torn:
    mov eax, UWAL_ERR_TORN
    pop r12
    pop rbx
    ret

.rv_corrupt:
    mov eax, UWAL_ERR_CORRUPT
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_format
;
; Writes a fresh superblock over a log region. Destroys any existing log, so
; callers must be certain recovery has already completed.
;
; Inputs:
;   RDI = Base LBA of the log region
;   ESI = Segment count
;   EDX = UWAL_SYNC_* durability mode
;
; Returns:
;   EAX = UWAL_OK, or UWAL_ERR_INVAL on bad geometry
; -----------------------------------------------------------------------------
align 32
uwal_format:
    push rbx

    test esi, esi
    jz .fm_inval
    cmp esi, UWAL_MAX_SEGMENTS
    ja .fm_inval
    cmp edx, UWAL_SYNC_BARRIER
    ja .fm_inval

    lea rbx, [uwal_super]

    mov rax, UWAL_MAGIC
    mov [rbx + uwal_super_t.magic], rax
    mov dword [rbx + uwal_super_t.version], UWAL_VERSION
    mov dword [rbx + uwal_super_t.block_size], UWAL_BLOCK_SIZE
    mov qword [rbx + uwal_super_t.segment_size], UWAL_SEGMENT_SIZE
    mov dword [rbx + uwal_super_t.segment_count], esi
    mov dword [rbx + uwal_super_t.sync_mode], edx
    mov qword [rbx + uwal_super_t.head_lsn], 1
    mov qword [rbx + uwal_super_t.checkpoint_lsn], 0
    mov [rbx + uwal_super_t.base_lba], rdi

    ; Checksum covers everything ahead of the field itself.
    mov dword [rbx + uwal_super_t.checksum], 0
    mov rdi, rbx
    mov rsi, uwal_super_t.checksum
    call uwal_crc32c
    mov dword [rbx + uwal_super_t.checksum], eax

    mov qword [uwal_head_lsn], 1
    mov qword [uwal_prev_lsn], 0

    xor eax, eax
    pop rbx
    ret

.fm_inval:
    mov eax, UWAL_ERR_INVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_init
;
; Brings the log online: validates the superblock, initialises the segment ring
; and replays anything the last shutdown left behind.
;
; Inputs:
;   RDI = Base LBA of the log region
;   ESI = Segment count
;
; Returns:
;   EAX = UWAL_OK, UWAL_ERR_CORRUPT on a bad superblock, or a recovery error
; -----------------------------------------------------------------------------
align 32
uwal_init:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13d, esi

    lea rbx, [uwal_super]

    ; A zeroed or mismatched magic means the region was never formatted.
    mov rax, [rbx + uwal_super_t.magic]
    mov rcx, UWAL_MAGIC
    cmp rax, rcx
    jne .ui_unformatted

    cmp dword [rbx + uwal_super_t.version], UWAL_VERSION
    ja .ui_corrupt                  ; Written by a newer implementation

    ; Verify the superblock checksum before trusting any field in it.
    mov r13d, dword [rbx + uwal_super_t.checksum]
    mov dword [rbx + uwal_super_t.checksum], 0
    mov rdi, rbx
    mov rsi, uwal_super_t.checksum
    call uwal_crc32c
    mov dword [rbx + uwal_super_t.checksum], r13d
    cmp eax, r13d
    jne .ui_corrupt

    mov rdi, r12
    mov esi, dword [rbx + uwal_super_t.segment_count]
    call uwal_segment_init
    test eax, eax
    jnz .ui_return

    ; Replay whatever the previous run did not checkpoint.
    call uwal_recover
    test eax, eax
    jnz .ui_return

    mov qword [uwal_initialised], 1
    xor eax, eax
    jmp .ui_return

.ui_unformatted:
    ; Fresh region: format it rather than failing.
    mov rdi, r12
    mov esi, r13d
    mov edx, UWAL_SYNC_FLUSH
    call uwal_format
    test eax, eax
    jnz .ui_return

    mov rdi, r12
    mov esi, r13d
    call uwal_segment_init
    test eax, eax
    jnz .ui_return

    mov qword [uwal_initialised], 1
    xor eax, eax
    jmp .ui_return

.ui_corrupt:
    mov eax, UWAL_ERR_CORRUPT

.ui_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_begin_txn
;
; Allocates a transaction id. Records sharing an id are committed or discarded
; as a unit by recovery.
;
; Returns:
;   RAX = Fresh transaction id
; -----------------------------------------------------------------------------
align 32
uwal_begin_txn:
    mov rax, 1
    lock xadd [uwal_next_txn], rax  ; Atomic: ids must be unique under SMP
    ret

; -----------------------------------------------------------------------------
; uwal_append
;
; Frames a record, checksums it and hands it to the segment writer.
;
; Inputs:
;   RDI = Payload pointer (may be 0 when payload_len is 0)
;   ESI = Payload length
;   EDX = Record type (UWAL_REC_*)
;   ECX = Stream id
;   R8  = Transaction id
;
; Returns:
;   RAX = Assigned LSN, or a negative UWAL_ERR_*
; -----------------------------------------------------------------------------
align 32
uwal_append:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi                    ; Payload
    mov r12d, esi                   ; Payload length
    mov r13d, edx                   ; Type
    mov r14d, ecx                   ; Stream
    mov r15, r8                     ; Transaction id

    cmp qword [uwal_initialised], 0
    je .ap_inval

    cmp r12d, UWAL_MAX_PAYLOAD
    ja .ap_inval
    test r12d, r12d
    jz .ap_no_payload
    test rbx, rbx
    jz .ap_inval                    ; Length without a buffer

.ap_no_payload:
    ; Assign an LSN atomically: two CPUs appending concurrently must never
    ; receive the same sequence number.
    mov rax, 1
    lock xadd [uwal_head_lsn], rax
    push rax                        ; Keep the assigned LSN

    lea rdi, [uwal_stage]

    mov word  [rdi + uwal_rec_t.magic], UWAL_REC_MAGIC
    mov byte  [rdi + uwal_rec_t.type], r13b
    mov byte  [rdi + uwal_rec_t.stream], r14b
    mov dword [rdi + uwal_rec_t.payload_len], r12d
    mov [rdi + uwal_rec_t.lsn], rax

    mov rcx, [uwal_prev_lsn]
    mov [rdi + uwal_rec_t.prev_lsn], rcx
    mov [rdi + uwal_rec_t.txn_id], r15

    push rdi
    rdtsc
    shl rdx, 32
    or rax, rdx                     ; 64-bit timestamp counter
    pop rdi
    mov [rdi + uwal_rec_t.timestamp], rax

    mov dword [rdi + uwal_rec_t.checksum], 0
    mov dword [rdi + uwal_rec_t.reserved], 0

    ; Copy the payload in behind the header.
    test r12d, r12d
    jz .ap_checksum

    push rdi
    lea rdi, [uwal_stage + UWAL_REC_HEADER_SIZE]
    mov rsi, rbx
    mov ecx, r12d
    rep movsb
    pop rdi

.ap_checksum:
    lea rdi, [uwal_stage]
    call uwal_rec_checksum
    lea rdi, [uwal_stage]
    mov dword [rdi + uwal_rec_t.checksum], eax

    ; Hand the framed record to the segment writer.
    lea rdi, [uwal_stage]
    mov esi, UWAL_REC_HEADER_SIZE
    add esi, r12d
    call uwal_segment_write
    test eax, eax
    js .ap_io

    pop rax                         ; Assigned LSN
    mov [uwal_prev_lsn], rax

    inc qword [uwal_appends]
    mov ecx, UWAL_REC_HEADER_SIZE
    add ecx, r12d
    add [uwal_bytes_written], rcx

    jmp .ap_return

.ap_io:
    pop rcx                         ; Discard the LSN
    mov rax, UWAL_ERR_IO
    jmp .ap_return

.ap_inval:
    mov rax, UWAL_ERR_INVAL

.ap_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_commit
;
; Appends a commit marker and forces it durable.
;
; The flush is the entire point: a commit record still sitting in a device
; write cache has not committed anything. Only once the barrier returns may the
; caller report success to whoever asked for the transaction.
;
; Inputs:
;   RDI = Transaction id
;
; Returns:
;   RAX = LSN of the commit record, or a negative UWAL_ERR_*
; -----------------------------------------------------------------------------
align 32
uwal_commit:
    push rbx

    mov rbx, rdi                    ; Transaction id

    xor rdi, rdi                    ; Commit markers carry no payload
    xor esi, esi
    mov edx, UWAL_REC_COMMIT
    mov ecx, UWAL_STREAM_UDB
    mov r8, rbx
    call uwal_append
    test rax, rax
    js .cm_return

    push rax
    call uwal_sync                  ; Durability barrier before reporting done
    pop rax
    test eax, eax
    js .cm_fail

.cm_return:
    pop rbx
    ret

.cm_fail:
    mov rax, UWAL_ERR_IO
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_abort
;
; Appends an abort marker. No flush: an abort that is lost to a crash is
; harmless, because recovery discards any transaction lacking a commit record
; anyway. Forcing a barrier here would cost durability latency for nothing.
;
; Inputs:
;   RDI = Transaction id
;
; Returns:
;   RAX = LSN of the abort record, or a negative UWAL_ERR_*
; -----------------------------------------------------------------------------
align 32
uwal_abort:
    push rbx

    mov rbx, rdi

    xor rdi, rdi
    xor esi, esi
    mov edx, UWAL_REC_ABORT
    mov ecx, UWAL_STREAM_UDB
    mov r8, rbx
    call uwal_append

    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_stats
;
; Inputs:
;   RDI = Pointer to four qwords: head LSN, appends, bytes written, checkpoint
;
; Returns:
;   EAX = 0
; -----------------------------------------------------------------------------
align 32
uwal_stats:
    mov rax, [uwal_head_lsn]
    mov [rdi], rax
    mov rax, [uwal_appends]
    mov [rdi + 8], rax
    mov rax, [uwal_bytes_written]
    mov [rdi + 16], rax
    lea rcx, [uwal_super]
    mov rax, [rcx + uwal_super_t.checkpoint_lsn]
    mov [rdi + 24], rax
    xor eax, eax
    ret
