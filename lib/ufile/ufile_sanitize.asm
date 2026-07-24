; =============================================================================
; Tattva OS — lib/ufile/ufile_sanitize.asm
; =============================================================================
; Hardened Security & TOCTOU Shadow Copy Protection Routines for ufile.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

[BITS 64]

%include "ufile.inc"

section .text

; -----------------------------------------------------------------------------
; ufile_shadow_copy — Copy 512-byte header into CPU-local shadow buffer
; Input:  RDI = Source untrusted header buffer
;         RSI = Source length (in bytes)
; Output: RAX = Pointer to immutable shadow copy buffer
; -----------------------------------------------------------------------------
ufile_shadow_copy:
    push rbx
    push rcx
    push rsi
    push rdi

    mov rbx, rdi                    ; RBX = src
    mov rdi, shadow_scratch_buf
    mov rcx, 64                     ; 64 qwords = 512 bytes
    
    ; Copy min(RSI, 512) bytes
    cmp rsi, 512
    jbe .do_copy
    mov rsi, 512
.do_copy:
    shr rsi, 3                      ; Convert to qwords
    jz .zero_fill
    mov rcx, rsi
    rep movsq

.zero_fill:
    mov rax, shadow_scratch_buf

    pop rdi
    pop rsi
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ufile_bounds_check — Verify pointer offset bounds (offset + size <= max_len)
; Input:  RDI = Current Offset
;         RSI = Access Size
;         RDX = Maximum Buffer Length
; Output: RAX = 1 if valid bounds, 0 if out-of-bounds violation
; -----------------------------------------------------------------------------
ufile_bounds_check:
    mov rax, rdi
    add rax, rsi
    jc .out_of_bounds               ; Carry flag set = 64-bit overflow

    cmp rax, rdx
    ja .out_of_bounds

    mov rax, 1                      ; Valid!
    ret

.out_of_bounds:
    xor rax, rax
    ret

; -----------------------------------------------------------------------------
; ufile_safe_mul — Overflow-checked 64-bit multiplication
; Input:  RAX = Value A
;         RDI = Value B
; Output: RAX = Product (A * B), RDX = 1 if safe, 0 if overflowed
; -----------------------------------------------------------------------------
ufile_safe_mul:
    mul rdi
    jo .overflow                    ; Overflow flag set

    mov rdx, 1                      ; Safe!
    ret

.overflow:
    xor rdx, rdx
    ret

; -----------------------------------------------------------------------------
; ufile_sanitize_string — Sanitize ASCII string & enforce null-termination
; Input:  RDI = Source string pointer
;         RSI = Destination buffer pointer (min 32 bytes)
;         RDX = Max string length to read (up to 31)
; Output: RAX = Length of sanitized string
; -----------------------------------------------------------------------------
ufile_sanitize_string:
    push rbx
    push rcx
    push rdi
    push rsi

    xor rcx, rcx                    ; Byte count

.copy_loop:
    cmp rcx, rdx
    jae .null_term
    cmp rcx, 31                     ; Cap at 31 chars + null
    jae .null_term

    mov al, [rdi + rcx]
    test al, al
    jz .null_term

    ; Check printable ASCII (0x20 .. 0x7E)
    cmp al, 0x20
    jb .replace_char
    cmp al, 0x7E
    jbe .store_char

.replace_char:
    mov al, '?'                     ; Replace unprintable control chars with '?'

.store_char:
    mov [rsi + rcx], al
    inc rcx
    jmp .copy_loop

.null_term:
    mov byte [rsi + rcx], 0         ; Forcibly null-terminate string
    mov rax, rcx                    ; Return string length

    pop rsi
    pop rdi
    pop rcx
    pop rbx
    ret

section .data
align 64
shadow_scratch_buf: times 512 db 0
