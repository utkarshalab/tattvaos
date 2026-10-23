; ============================================================================
; ICC Parse — ICC v2/v4 Profile Parser (matrix/TRC + header)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/colorm.inc"
%include "inc/canvas_client.inc"

extern arena_alloc

; struct offsets (hoisted above use)
%define IccProfile_SIZE    112
%define ICC_MAGIC_SIZE_OFF   0
%define ICC_TAG_COUNT_OFF    128

section .text

struc IccProfile
    .size:          resd 1
    .version:       resd 1
    .device_class:  resd 1
    .color_space:   resd 1
    .pcs:           resd 1
    .rendering_intent: resd 1
    .matrix_r:      resd 3
    .matrix_g:      resd 3
    .matrix_b:      resd 3
    .trc_r:         resq 1
    .trc_g:         resq 1
    .trc_b:         resq 1
    .has_matrix:    resb 1
    .has_trc:       resb 1
endstruc


; ---------------------------------------------------------------------------
; icc_probe
; ---------------------------------------------------------------------------
global icc_probe
icc_probe:
    PROLOGUE
    ASSERT_PTR rdi
    cmp rsi, 132
    jb .no
    mov eax, [rdi + 0]
    test eax, eax
    jz .no
    ; check 'acsp' at offset 80
    cmp dword [rdi + 80], 0x70736361  ; "acsp" LE
    jne .no
    mov rax, 1
    leave
    ret
.no:
    xor rax, rax
    leave
    ret

; ---------------------------------------------------------------------------
; icc_parse
;   IN: rdi = arena, rsi = data, rdx = len — OUT: rax = IccProfile*
; ---------------------------------------------------------------------------
global icc_parse
icc_parse:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, r12
    mov rsi, r13
    call icc_probe
    test rax, rax
    jz .bad
    mov rdi, rbx
    mov rsi, IccProfile_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax
    mov eax, [r12 + 0]
    xchg al, ah
    rol eax, 16
    xchg al, ah
    mov [r14 + IccProfile.size], eax
    mov eax, [r12 + 4]
    mov [r14 + IccProfile.version], eax
    mov eax, [r12 + 12]
    mov [r14 + IccProfile.device_class], eax
    mov eax, [r12 + 16]
    mov [r14 + IccProfile.color_space], eax
    mov eax, [r12 + 20]
    mov [r14 + IccProfile.pcs], eax
    mov eax, [r12 + 64]
    mov [r14 + IccProfile.rendering_intent], eax
    mov byte [r14 + IccProfile.has_matrix], 0
    mov byte [r14 + IccProfile.has_trc], 0
    ; walk tags
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    call icc_parse_tags
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.bad:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.oom:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; icc_parse_tags
; ---------------------------------------------------------------------------
global icc_parse_tags
icc_parse_tags:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    cmp r13, 132
    jb .done
    mov r14d, [r12 + 128]
    xchg r14b, r14b  ; count is BE; byte-swap below
    mov eax, r14d
    bswap eax
    mov r14d, eax
    cmp r14d, 64
    ja .done
    lea r15, [r12 + 132]
    xor ecx, ecx
.loop:
    cmp ecx, r14d
    jae .done
    mov eax, [r15 + 0]  ; tag sig BE
    mov edx, [r15 + 4]
    bswap edx
    mov esi, [r15 + 8]
    bswap esi
    ; bounds check offset/size
    mov edi, edx
    add edi, esi
    cmp rdi, r13
    ja .next
    cmp eax, 0x7258595A  ; "rXYZ" BE? stored BE in file; compare swapped
    je .mat_r
    cmp eax, 0x6758595A
    je .mat_g
    cmp eax, 0x6258595A
    je .mat_b
    cmp eax, 0x72545243  ; "rTRC"
    je .trc_r
    cmp eax, 0x67545243
    je .trc_g
    cmp eax, 0x62545243
    je .trc_b
    jmp .next
.mat_r:
    mov rdi, rbx
    lea rdi, [rbx + IccProfile.matrix_r]
    mov rsi, r12
    add rsi, rdx
    call icc_read_xyz
    mov byte [rbx + IccProfile.has_matrix], 1
    jmp .next
.mat_g:
    mov rdi, rbx
    lea rdi, [rbx + IccProfile.matrix_g]
    mov rsi, r12
    add rsi, rdx
    call icc_read_xyz
    jmp .next
.mat_b:
    mov rdi, rbx
    lea rdi, [rbx + IccProfile.matrix_b]
    mov rsi, r12
    add rsi, rdx
    call icc_read_xyz
    jmp .next
.trc_r:
    mov rdi, rbx
    lea rdi, [rbx + IccProfile.trc_r]
    mov rsi, r12
    add rsi, rdx
    mov rdx, rsi
    call icc_read_trc
    mov byte [rbx + IccProfile.has_trc], 1
    jmp .next
.trc_g:
    mov rdi, rbx
    lea rdi, [rbx + IccProfile.trc_g]
    mov rsi, r12
    add rsi, rdx
    call icc_read_trc
    jmp .next
.trc_b:
    mov rdi, rbx
    lea rdi, [rbx + IccProfile.trc_b]
    mov rsi, r12
    add rsi, rdx
    call icc_read_trc
    jmp .next
.next:
    add r15, 12
    inc ecx
    jmp .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; icc_read_xyz — s15Fixed16 triple at [rsi+8..]
; ---------------------------------------------------------------------------
global icc_read_xyz
icc_read_xyz:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ; type 'XYZ ' expected; values BE s15.16
    mov eax, [rsi + 8]
    bswap eax
    mov [rbx + 0], eax
    mov eax, [rsi + 12]
    bswap eax
    mov [rbx + 4], eax
    mov eax, [rsi + 16]
    bswap eax
    mov [rbx + 8], eax
    xor rax, rax
    EPILOGUE_RESTORE rbx
    ret

; ---------------------------------------------------------------------------
; icc_read_trc — curveType/paraType; store opaque pointer
; ---------------------------------------------------------------------------
global icc_read_trc
icc_read_trc:
    PROLOGUE
    mov [rdi], rsi
    xor rax, rax
    leave
    ret

section .data
global icc_parse_version
icc_parse_version: dq 0x010000
