; ============================================================================
; JPEG Huffman — Canonical Huffman Table Build + Symbol Decode
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

struc HuffTable {
    .counts:        resb 16
    .symbols:       resb 256
    .max_syms:      resd 1
    .codes:         resd 256
    .sizes:         resb 256
}
%define HuffTable_size    1320

; ---------------------------------------------------------------------------
; jpeg_huff_build
;   IN: rdi = HuffTable*, rsi = counts[16], rdx = symbols, rcx = sym_count
; ---------------------------------------------------------------------------
global jpeg_huff_build
jpeg_huff_build:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13
    cmp r14, 256
    ja .fail
    ; copy counts
    mov rdi, rbx
    mov rsi, r12
    mov rcx, 16
    rep movsb
    ; copy symbols
    lea rdi, [rbx + HuffTable.symbols]
    mov rsi, r13
    mov rcx, r14
    rep movsb
    mov [rbx + HuffTable.max_syms], r14d
    ; build canonical codes
    xor r15d, r15d  ; code
    xor r12d, r12d  ; k index
    xor r13d, r13d  ; length 1..16
.gen_len:
    inc r13d
    cmp r13d, 16
    ja .done
    movzx eax, byte [rbx + r13 - 1]
.len_loop:
    test eax, eax
    jz .gen_len
    cmp r12d, r14d
    jae .fail
    lea rdi, [rbx + HuffTable.symbols]
    movzx edx, byte [rdi + r12]
    mov [rbx + HuffTable.codes + rdx * 4], r15d
    mov [rbx + HuffTable.sizes + rdx], r13b
    inc r12d
    inc r15d
    dec eax
    jmp .len_loop
.done:
    shl r15d, 1
    jmp .gen_len
.fail:
    RETURN_ERROR EINVAL

; ---------------------------------------------------------------------------
; jpeg_huff_decode
;   IN: rdi=HuffTable*, rsi=bitreader* (u64 buf in [rsi], bits left in [rsi+8])
;   OUT: rax = symbol, negative error
; ---------------------------------------------------------------------------
global jpeg_huff_decode
jpeg_huff_decode:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    xor r13d, r13d  ; code
    xor r14d, r14d  ; len
.len:
    inc r14d
    cmp r14d, 16
    ja .fail
    ; get 1 bit
    mov rax, [r12 + 8]
    test rax, rax
    jz .fail
    mov rdx, [r12]
    shl rdx, 1
    mov rcx, rdx
    shr rcx, 63
    mov [r12], rdx
    dec qword [r12 + 8]
    shl r13d, 1
    or r13d, ecx
    ; linear search symbols with this length (tables are small)
    lea rdi, [rbx + HuffTable.symbols]
    mov eax, [rbx + HuffTable.max_syms]
    xor edx, edx
.search:
    cmp edx, eax
    jae .len
    cmp byte [rbx + HuffTable.sizes + rdx], r14b
    jne .next
    cmp dword [rbx + HuffTable.codes + rdx * 4], r13d
    je .found
.next:
    inc edx
    jmp .search
.found:
    movzx eax, byte [rdi + rdx]
    ret
.fail:
    RETURN_ERROR EINVAL

section .data
global jpeg_huff_version
jpeg_huff_version: dq 0x010000
