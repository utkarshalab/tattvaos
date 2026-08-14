%ifndef GUARD_STORAGE_UWAL_SEGMENT_ASM
%define GUARD_STORAGE_UWAL_SEGMENT_ASM
; =============================================================================
; Tattva OS — storage/uwal/segment.asm
; =============================================================================
; UWAL Segment Ring — Allocation, Sealing & Reclamation.
;
; Implements:
;   - Segment ring initialisation (`uwal_segment_init`)
;   - Append with automatic roll to the next segment (`uwal_segment_write`)
;   - Sealing and checkpoint-driven reclamation (`uwal_segment_seal`,
;     `uwal_segment_reclaim`)
;
; The log is a ring of fixed-size segments rather than one growing file.
; Segments make reclamation cheap: once every record in a segment predates the
; checkpoint, the whole segment is reusable in one step, with no compaction and
; no rewriting of live records.
;
; A segment is never partially overwritten. Records are appended until the next
; one will not fit, then the segment is sealed and the writer rolls forward.
; This means a torn write can only ever occur at the tail of the active
; segment, which bounds what recovery has to reason about.
;
; Reclaiming a segment that still holds uncheckpointed records would destroy
; the only copy of changes not yet applied to their home location, so
; reclamation refuses unless the checkpoint has passed the segment's last LSN.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uwal/uwal.inc"

section .data
align 64

global uwal_segments
uwal_segments:          times UWAL_MAX_SEGMENTS * uwal_segment_t_size db 0

uwal_seg_count:         dq 0
uwal_seg_active:        dq 0        ; Index of the segment being appended to
uwal_seg_base_lba:      dq 0
uwal_seg_rolls:         dq 0        ; Segment transitions performed

section .text

global uwal_segment_init
global uwal_segment_write
global uwal_segment_seal
global uwal_segment_reclaim
global uwal_segment_active
global uwal_segment_space

; -----------------------------------------------------------------------------
; uwal_segment_init
;
; Lays out the segment ring over a contiguous log region.
;
; Inputs:
;   RDI = Base LBA of the log region
;   ESI = Segment count
;
; Returns:
;   EAX = UWAL_OK, or UWAL_ERR_INVAL on bad geometry
; -----------------------------------------------------------------------------
align 32
uwal_segment_init:
    push rbx
    push r12
    push r13
    push r14

    test esi, esi
    jz .si_inval
    cmp esi, UWAL_MAX_SEGMENTS
    ja .si_inval

    mov [uwal_seg_base_lba], rdi
    mov r13d, esi
    mov [uwal_seg_count], r13

    lea rbx, [uwal_segments]
    mov r12, rdi                    ; Running LBA
    xor r14d, r14d                  ; Segment index

    ; Blocks per segment, used to step the LBA cursor.
    mov rax, UWAL_SEGMENT_SIZE
    shr rax, 12                     ; / UWAL_BLOCK_SIZE
    mov rcx, rax

.si_loop:
    cmp r14d, r13d
    jae .si_done

    mov [rbx + uwal_segment_t.base_lba], r12
    mov qword [rbx + uwal_segment_t.write_offset], 0
    mov qword [rbx + uwal_segment_t.first_lsn], 0
    mov qword [rbx + uwal_segment_t.last_lsn], 0
    mov dword [rbx + uwal_segment_t.state], UWAL_SEG_FREE

    add r12, rcx                    ; Next segment's base LBA
    add rbx, uwal_segment_t_size
    inc r14d
    jmp .si_loop

.si_done:
    ; Segment 0 opens as the active one.
    lea rbx, [uwal_segments]
    mov dword [rbx + uwal_segment_t.state], UWAL_SEG_ACTIVE
    mov qword [uwal_seg_active], 0

    xor eax, eax
    jmp .si_return

.si_inval:
    mov eax, UWAL_ERR_INVAL

.si_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_segment_active
;
; Returns:
;   RAX = Pointer to the active segment descriptor
; -----------------------------------------------------------------------------
align 32
uwal_segment_active:
    mov rax, [uwal_seg_active]
    imul rax, rax, uwal_segment_t_size
    lea rax, [uwal_segments + rax]
    ret

; -----------------------------------------------------------------------------
; uwal_segment_space
;
; Returns:
;   RAX = Bytes still available in the active segment
; -----------------------------------------------------------------------------
align 32
uwal_segment_space:
    call uwal_segment_active
    mov rcx, [rax + uwal_segment_t.write_offset]
    mov rax, UWAL_SEGMENT_SIZE
    sub rax, rcx
    ret

; -----------------------------------------------------------------------------
; uwal_segment_seal
;
; Closes the active segment and opens the next free one.
;
; Sealing is what keeps torn writes confined to a single known location: only
; the tail of the active segment can ever be partially written.
;
; Returns:
;   EAX = UWAL_OK, or UWAL_ERR_NOSPC when no free segment remains
; -----------------------------------------------------------------------------
align 32
uwal_segment_seal:
    push rbx
    push r12
    push r13

    call uwal_segment_active
    mov rbx, rax
    mov dword [rbx + uwal_segment_t.state], UWAL_SEG_SEALED

    ; Walk the ring for a reusable segment.
    mov r12, [uwal_seg_active]
    mov r13, [uwal_seg_count]
    mov rcx, r13                    ; Search budget

.ss_scan:
    inc r12
    cmp r12, r13
    jb .ss_check
    xor r12, r12                    ; Wrap

.ss_check:
    mov rax, r12
    imul rax, rax, uwal_segment_t_size
    lea rax, [uwal_segments + rax]

    mov edx, dword [rax + uwal_segment_t.state]
    cmp edx, UWAL_SEG_FREE
    je .ss_open
    cmp edx, UWAL_SEG_RECLAIMABLE
    je .ss_open

    dec rcx
    jnz .ss_scan

    ; Every segment still holds uncheckpointed records. Appending would
    ; overwrite the only copy of changes not yet applied.
    mov eax, UWAL_ERR_NOSPC
    jmp .ss_return

.ss_open:
    mov qword [rax + uwal_segment_t.write_offset], 0
    mov qword [rax + uwal_segment_t.first_lsn], 0
    mov qword [rax + uwal_segment_t.last_lsn], 0
    mov dword [rax + uwal_segment_t.state], UWAL_SEG_ACTIVE
    mov [uwal_seg_active], r12

    inc qword [uwal_seg_rolls]

    xor eax, eax

.ss_return:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_segment_write
;
; Appends a framed record to the active segment, rolling forward when it will
; not fit.
;
; A record is never split across segments. Splitting would force recovery to
; stitch fragments together before it could even validate a checksum, and a
; crash between the halves would leave a fragment indistinguishable from
; garbage.
;
; Inputs:
;   RDI = Pointer to the framed record
;   ESI = Total record length (header + payload)
;
; Returns:
;   RAX = Byte offset within the segment where the record landed,
;         or a negative UWAL_ERR_*
; -----------------------------------------------------------------------------
align 32
uwal_segment_write:
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi                    ; Record
    mov r12d, esi                   ; Length

    test r12d, r12d
    jz .sw_inval
    cmp r12d, UWAL_SEGMENT_SIZE
    ja .sw_inval                    ; Larger than a whole segment

    call uwal_segment_active
    mov r13, rax

    ; Roll forward if this record will not fit in what remains.
    mov rax, [r13 + uwal_segment_t.write_offset]
    add rax, r12
    cmp rax, UWAL_SEGMENT_SIZE
    jbe .sw_fits

    call uwal_segment_seal
    test eax, eax
    jnz .sw_return                  ; Ring full: propagate ENOSPC

    call uwal_segment_active
    mov r13, rax

.sw_fits:
    mov r14, [r13 + uwal_segment_t.write_offset]

    ; Record the LSN span this segment covers, so reclamation can tell whether
    ; the checkpoint has passed it.
    mov rax, [rbx + uwal_rec_t.lsn]
    cmp qword [r13 + uwal_segment_t.first_lsn], 0
    jne .sw_have_first
    mov [r13 + uwal_segment_t.first_lsn], rax

.sw_have_first:
    mov [r13 + uwal_segment_t.last_lsn], rax

    ; Hand the bytes to the block layer at this segment's LBA plus offset.
    mov rdi, [r13 + uwal_segment_t.base_lba]
    mov rsi, r14
    mov rdx, rbx
    mov ecx, r12d
    call uwal_device_write
    test eax, eax
    js .sw_io

    add r14, r12
    mov [r13 + uwal_segment_t.write_offset], r14

    mov rax, r14
    sub rax, r12                    ; Offset the record was placed at
    jmp .sw_return

.sw_io:
    mov rax, UWAL_ERR_IO
    jmp .sw_return

.sw_inval:
    mov rax, UWAL_ERR_INVAL

.sw_return:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uwal_segment_reclaim
;
; Marks sealed segments reusable once the checkpoint has advanced past every
; record they contain.
;
; The guard is strict: a segment is only reclaimed when checkpoint_lsn is at or
; beyond its last LSN, meaning every change it describes has already reached
; its home location. Reclaiming earlier would discard the only record of work
; that has not yet been applied.
;
; Inputs:
;   RDI = Checkpoint LSN
;
; Returns:
;   RAX = Segments reclaimed
; -----------------------------------------------------------------------------
align 32
uwal_segment_reclaim:
    push rbx
    push r12
    push r13
    push r14

    mov r14, rdi                    ; Checkpoint LSN
    lea rbx, [uwal_segments]
    mov r12, [uwal_seg_count]
    xor r13, r13                    ; Reclaimed count

.sr_loop:
    test r12, r12
    jz .sr_done

    cmp dword [rbx + uwal_segment_t.state], UWAL_SEG_SEALED
    jne .sr_next

    mov rax, [rbx + uwal_segment_t.last_lsn]
    test rax, rax
    jz .sr_free                     ; Sealed but empty: nothing to preserve

    cmp rax, r14
    ja .sr_next                     ; Still holds uncheckpointed records

.sr_free:
    mov dword [rbx + uwal_segment_t.state], UWAL_SEG_RECLAIMABLE
    inc r13

.sr_next:
    add rbx, uwal_segment_t_size
    dec r12
    jmp .sr_loop

.sr_done:
    mov rax, r13
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; GUARD_STORAGE_UWAL_SEGMENT_ASM
