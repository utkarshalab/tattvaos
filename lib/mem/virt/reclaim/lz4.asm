; =============================================================================
; Tattva OS — lib/mem/virt/lz4.asm
; =============================================================================
; LZ4 Block Compression and Decompression algorithms.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_LZ4_ASM
%define LIB_MEM_VIRT_LZ4_ASM

[BITS 64]

section .text

; -----------------------------------------------------------------------------
; lz4_compress — compresses a 4096-byte page into a buffer using LZ4 algorithm
; Input:
;   RDI = src (4KB page to compress)
;   RSI = dest (destination buffer)
;   RDX = max_len (limit size, typically 2048)
; Output:
;   RAX = compressed size on success, or 0 on overflow/failure
; -----------------------------------------------------------------------------
global lz4_compress
lz4_compress:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp

    mov r12, rdi                    ; R12 = src
    mov r13, rsi                    ; R13 = dest
    mov r14, rdx                    ; R14 = max_len

    sub rsp, 4096                   ; Allocate 4KB hash table (1024 dwords)
    mov rdi, rsp
    mov rcx, 1024
    xor rax, rax
    rep stosd                       ; Clear hash table to 0 (meaning empty slot)

    ; Initialize pointers
    mov r8, r12                     ; r8 = ip (input pointer)
    lea r9, [r12 + 4096]            ; r9 = ip_end
    mov r10, r13                    ; r10 = op (output pointer)
    lea r11, [r13 + r14]            ; r11 = op_end
    mov r15, r12                    ; r15 = anchor (literal block start)

.loop:
    ; Check if we are near the end of input (LZ4 needs 12 bytes remaining to match)
    lea rcx, [r8 + 12]
    cmp rcx, r9
    jae .write_last_literals

    ; Compute 4-byte hash: (val * 2654435761) >> 16 & 1023
    mov eax, [r8]
    mov rdx, 2654435761
    imul rax, rdx
    shr rax, 16
    and rax, 1023                   ; rax = hash index

    ; Get candidate position from hash table (1-based index)
    mov edx, [rsp + rax * 4]
    
    ; Update hash table with current position (1-based index)
    mov ecx, r8d
    sub ecx, r12d
    inc ecx
    mov [rsp + rax * 4], ecx

    test edx, edx
    jz .no_match

    dec edx                         ; candidate 0-based index
    mov rbx, r12
    add rbx, rdx                    ; rbx = candidate pointer

    ; Verify match distance is within limit (<= 65535) and not self-pointing
    mov rsi, r8
    sub rsi, rbx                    ; rsi = distance
    cmp rsi, 65535
    ja .no_match
    test rsi, rsi
    jz .no_match

    ; Check if first 4 bytes match
    mov edx, [rbx]
    cmp [r8], edx
    jne .no_match

    ; Find match length
    mov rdi, 4                      ; minimum match length is 4
.match_len:
    mov rdx, r8
    add rdx, rdi
    lea rdx, [rdx + 5]              ; LZ4 spec: last 5 bytes must be literals
    cmp rdx, r9
    jae .match_done
    mov al, [rbx + rdi]
    cmp [r8 + rdi], al
    jne .match_done
    inc rdi
    jmp .match_len
.match_done:
    ; Match length is in rdi.
    ; L = r8 - r15 (literal length)
    ; M = rdi - 4 (match length - 4)
    ; Distance = rsi

    mov rdx, r8
    sub rdx, r15                    ; rdx = L

    mov rax, rdi
    sub rax, 4                      ; rax = M

    ; Construct Token byte: (min(L, 15) << 4) | min(M, 15)
    mov rbp, rdx
    cmp rbp, 15
    jb .token_L_ok
    mov rbp, 15
.token_L_ok:
    shl rbp, 4

    mov rcx, rax
    cmp rcx, 15
    jb .token_M_ok
    mov rcx, 15
.token_M_ok:
    or rbp, rcx                     ; rbp = token byte

    ; Check space for token
    cmp r10, r11
    jae .failed

    mov [r10], bpl
    inc r10

    ; Write literal length extension if L >= 15
    cmp rdx, 15
    jb .write_literals
    
    mov rbp, rdx
    sub rbp, 15
.lit_ext_loop:
    cmp r10, r11
    jae .failed
    cmp rbp, 255
    jb .lit_ext_done
    mov byte [r10], 255
    inc r10
    sub rbp, 255
    jmp .lit_ext_loop
.lit_ext_done:
    mov [r10], bpl
    inc r10

.write_literals:
    ; Copy L literals from r15 to r10
    test rdx, rdx
    jz .write_offset

    mov rcx, r10
    add rcx, rdx
    cmp rcx, r11
    ja .failed                      ; exceeds max compressed length

.copy_lit_loop:
    mov al, [r15]
    mov [r10], al
    inc r15
    inc r10
    dec rdx
    jnz .copy_lit_loop

.write_offset:
    ; Write 16-bit offset (rsi)
    mov rcx, r10
    add rcx, 2
    cmp rcx, r11
    ja .failed

    mov [r10], sil
    mov rbx, rsi
    shr rbx, 8
    mov [r10 + 1], bl
    add r10, 2

    ; Write match length extension if M >= 15
    cmp rax, 15
    jb .match_written
    
    mov rbp, rax
    sub rbp, 15
.match_ext_loop:
    cmp r10, r11
    jae .failed
    cmp rbp, 255
    jb .match_ext_done
    mov byte [r10], 255
    inc r10
    sub rbp, 255
    jmp .match_ext_loop
.match_ext_done:
    mov [r10], bpl
    inc r10

.match_written:
    ; Update anchor = r8 + rdi (where rdi was match length)
    ; Update r8 = anchor
    add r8, rdi                     ; ip = ip + match_len
    mov r15, r8                     ; anchor = ip
    jmp .loop

.no_match:
    inc r8                          ; ip++
    jmp .loop

.write_last_literals:
    ; Copy remaining input bytes as literals
    mov rdx, r9
    sub rdx, r15                    ; rdx = L

    ; Write last token (M is 0, so token = (min(L, 15) << 4) | 0)
    mov rbp, rdx
    cmp rbp, 15
    jb .last_token_ok
    mov rbp, 15
.last_token_ok:
    shl rbp, 4

    cmp r10, r11
    jae .failed
    mov [r10], bpl
    inc r10

    ; Write literal length extension if L >= 15
    cmp rdx, 15
    jb .copy_last_literals

    mov rbp, rdx
    sub rbp, 15
.last_lit_ext_loop:
    cmp r10, r11
    jae .failed
    cmp rbp, 255
    jb .last_lit_ext_done
    mov byte [r10], 255
    inc r10
    sub rbp, 255
    jmp .last_lit_ext_loop
.last_lit_ext_done:
    mov [r10], bpl
    inc r10

.copy_last_literals:
    test rdx, rdx
    jz .done_success

    mov rcx, r10
    add rcx, rdx
    cmp rcx, r11
    ja .failed

.last_lit_copy_loop:
    mov al, [r15]
    mov [r10], al
    inc r15
    inc r10
    dec rdx
    jnz .last_lit_copy_loop

.done_success:
    mov rax, r10
    sub rax, r13                    ; rax = compressed size
    jmp .exit

.failed:
    xor rax, rax                    ; return 0

.exit:
    add rsp, 4096                   ; Free hash table
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; lz4_decompress — decompresses a block of LZ4 data into a 4096-byte page
; Input:
;   RDI = src (compressed buffer)
;   RSI = dest (destination page)
;   RDX = compressed_len
; Output:
;   RAX = decompressed size (4096 on success, 0 on failure)
; -----------------------------------------------------------------------------
global lz4_decompress
lz4_decompress:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r8, rdi                     ; R8 = src pointer
    lea r9, [rdi + rdx]             ; R9 = src end
    mov r10, rsi                    ; R10 = dest pointer
    lea r11, [rsi + 4096]           ; R11 = dest end (expects exactly 4096 bytes)

.next_sequence:
    cmp r8, r9
    jae .done_success               ; source consumed, success

    ; Read sequence token
    movzx rax, byte [r8]
    inc r8
    mov rbx, rax
    shr rbx, 4                      ; RBX = L (token >> 4)
    and rax, 15                     ; RAX = M (token & 0x0F)

    ; 1. Process literal length L
    cmp rbx, 15
    jne .copy_literals

.lit_len_loop:
    cmp r8, r9
    jae .failed                     ; truncated literal length extension
    movzx rcx, byte [r8]
    inc r8
    add rbx, rcx
    cmp rcx, 255
    je .lit_len_loop

.copy_literals:
    test rbx, rbx
    jz .process_match

    ; Verify space boundaries
    mov rcx, r10
    add rcx, rbx
    cmp rcx, r11
    ja .failed                      ; literal copy exceeds dest boundary

    mov rcx, r8
    add rcx, rbx
    cmp rcx, r9
    ja .failed                      ; literal copy exceeds src boundary

.copy_lit_loop:
    mov dl, [r8]
    mov [r10], dl
    inc r8
    inc r10
    dec rbx
    jnz .copy_lit_loop

.process_match:
    cmp r8, r9
    jae .done_success               ; end of block reached (no trailing match)

    ; Read 16-bit offset
    mov rcx, r8
    add rcx, 2
    cmp rcx, r9
    ja .failed                      ; truncated offset
    
    movzx r12, word [r8]            ; R12 = offset
    add r8, 2
    test r12, r12
    jz .failed                      ; offset cannot be 0

    ; Process match length M
    cmp rax, 15
    jne .add_minmatch

.match_len_loop:
    cmp r8, r9
    jae .failed                     ; truncated match length extension
    movzx rcx, byte [r8]
    inc r8
    add rax, rcx
    cmp rcx, 255
    je .match_len_loop

.add_minmatch:
    add rax, 4                      ; actual match length = value + 4

    ; Verify match source and destination boundaries
    mov r13, r10
    sub r13, r12                    ; r13 = match source = dest - offset
    cmp r13, rsi
    jb .failed                      ; match source points before start of dest page

    mov rcx, r10
    add rcx, rax
    cmp rcx, r11
    ja .failed                      ; match copy exceeds dest page limit

    ; Copy match (can overlap, copy byte-by-byte)
.copy_match_loop:
    mov dl, [r13]
    mov [r10], dl
    inc r13
    inc r10
    dec rax
    jnz .copy_match_loop

    jmp .next_sequence

.done_success:
    mov rax, r10
    sub rax, rsi                    ; RAX = decompressed size
    cmp rax, 4096
    jne .failed                     ; must decompress to exactly 4096 bytes
    mov rax, 4096
    jmp .exit

.failed:
    xor rax, rax                    ; return 0

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_MEM_VIRT_LZ4_ASM
