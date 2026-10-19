; ============================================================================
; JPEG Huffman — Canonical Huffman Table Build + Symbol Decode
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

extern jpeg_bits_get

; struct offsets (hoisted above use)
%define HuffTable_SIZE 1556

section .text

struc HuffTable
    .counts:        resb 16
    .symbols:       resb 256
    .max_syms:      resd 1
    .codes:         resd 256
    .sizes:         resb 256
endstruc
%if HuffTable_size != HuffTable_SIZE
    %error "HuffTable_SIZE does not match the structure layout"
%endif

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
    ; Validate the prefix tree before materializing codes. `left` is the
    ; number of unused codewords at the current bit length.
    mov eax, 1
    xor ecx, ecx
.validate_lengths:
    shl eax, 1
    movzx edx, byte [r12 + rcx]
    sub eax, edx
    js .fail                         ; oversubscribed tree
    inc ecx
    cmp ecx, 16
    jb .validate_lengths
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
    ; A table may be redefined by a later DHT segment. Clear lookup metadata
    ; so symbols absent from the replacement cannot retain stale codes.
    lea rdi, [rbx + HuffTable.codes]
    xor eax, eax
    mov ecx, (256 * 4 + 256) / 8
    rep stosq
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
    jz .next_len
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
.next_len:
    ; Canonical JPEG codes are left-shifted after every code length.
    shl r15d, 1
    jmp .gen_len
.done:
    cmp r12d, r14d
    jne .fail
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

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
    movzx ecx, byte [rdi + rdx]
    cmp byte [rbx + HuffTable.sizes + rcx], r14b
    jne .next
    cmp dword [rbx + HuffTable.codes + rcx * 4], r13d
    je .found
.next:
    inc edx
    jmp .search
.found:
    mov eax, ecx
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.fail:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; jpeg_huff_decode_stream
;   Decode directly from the stuffing-aware entropy reader.
;   IN: rdi=HuffTable*, rsi=JpegBitReader*
; ---------------------------------------------------------------------------
global jpeg_huff_decode_stream
jpeg_huff_decode_stream:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    xor r13d, r13d
    mov r14d, 1
.stream_length:
    cmp r14d, 16
    ja .stream_fail
    mov rdi, r12
    mov esi, 1
    call jpeg_bits_get
    test rax, rax
    js .stream_out
    shl r13d, 1
    or r13d, eax
    lea r15, [rbx + HuffTable.symbols]
    mov r8d, [rbx + HuffTable.max_syms]
    xor edx, edx
.stream_search:
    cmp edx, r8d
    jae .stream_next_length
    movzx ecx, byte [r15 + rdx]
    cmp byte [rbx + HuffTable.sizes + rcx], r14b
    jne .stream_next_symbol
    cmp dword [rbx + HuffTable.codes + rcx * 4], r13d
    je .stream_found
.stream_next_symbol:
    inc edx
    jmp .stream_search
.stream_next_length:
    inc r14d
    jmp .stream_length
.stream_found:
    mov eax, ecx
    jmp .stream_out
.stream_fail:
    mov rax, -EINVAL
.stream_out:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global jpeg_huff_version
jpeg_huff_version: dq 0x010000
