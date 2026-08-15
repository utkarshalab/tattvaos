; =============================================================================
; Tattva OS — lib/ulog/sinks/file_index.asm
; =============================================================================
; A seq -> byte-offset index for the file sink, so a reader (uproc/udbg-style
; tooling later) can seek to a known record instead of scanning the whole
; log file. Append-only, capped, linear-scan lookup — this is a sidecar
; index for an occasional tool to use, not a hot structure.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%ifndef LIB_ULOG_SINKS_FILE_INDEX_ASM
%define LIB_ULOG_SINKS_FILE_INDEX_ASM

[BITS 64]

%define FILE_INDEX_MAX_ENTRIES  4096

struc file_index_entry_t
    .seq       resq 1
    .offset    resq 1
endstruc

section .bss
alignb 8
global ulog_file_index
ulog_file_index: resb (file_index_entry_t_size * FILE_INDEX_MAX_ENTRIES)
global ulog_file_index_count
ulog_file_index_count: resd 1

section .text

; -----------------------------------------------------------------------------
; file_index_note_write — Input: RDI = seq, RSI = offset
; Output: none (silently stops recording once FILE_INDEX_MAX_ENTRIES is hit —
;         the file itself keeps growing; only the index caps out)
; -----------------------------------------------------------------------------
global file_index_note_write
file_index_note_write:
    push rbx
    push rcx

    mov ecx, [ulog_file_index_count]
    cmp ecx, FILE_INDEX_MAX_ENTRIES
    jae .done

    mov rbx, file_index_entry_t_size
    imul rbx, rcx
    add rbx, ulog_file_index
    mov [rbx + file_index_entry_t.seq], rdi
    mov [rbx + file_index_entry_t.offset], rsi

    inc dword [ulog_file_index_count]

.done:
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; file_index_lookup — Input: RDI = seq. Output: RAX = offset, or -1 if unknown
; -----------------------------------------------------------------------------
global file_index_lookup
file_index_lookup:
    push rbx
    push rcx

    xor ecx, ecx
.scan:
    cmp ecx, [ulog_file_index_count]
    jae .not_found

    mov rbx, file_index_entry_t_size
    imul rbx, rcx
    add rbx, ulog_file_index
    cmp [rbx + file_index_entry_t.seq], rdi
    je .found

    inc ecx
    jmp .scan

.found:
    mov rax, [rbx + file_index_entry_t.offset]
    jmp .done

.not_found:
    mov rax, -1

.done:
    pop rcx
    pop rbx
    ret

%endif ; LIB_ULOG_SINKS_FILE_INDEX_ASM
