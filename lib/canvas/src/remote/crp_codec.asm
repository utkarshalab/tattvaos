; ============================================================================
; CRP Codec — Per-Tile Encode/Decode Dispatch (raw/RLE/deflate/delta)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

%define CRP_ENC_RAW       0
%define CRP_ENC_RLE       1
%define CRP_ENC_DEFLATE   2
%define CRP_ENC_DELTA     3

; ---------------------------------------------------------------------------
; crp_encode_tile
;   IN: rdi=arena, rsi=cur_pixels, rdx=prev_pixels, rcx=pixels,
;       r8=dst, r9=dst_cap, stack enc
;   OUT: rax = bytes written
; ---------------------------------------------------------------------------
global crp_encode_tile
crp_encode_tile:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r15
    mov eax, [rsp + 64]
    cmp eax, CRP_ENC_RLE
    je .rle
    cmp eax, CRP_ENC_DEFLATE
    je .deflate
    cmp eax, CRP_ENC_DELTA
    je .delta
    ; raw
    mov rax, r14
    shl rax, 2
    cmp rax, r9
    ja .full
    mov rdi, r15
    mov rsi, r12
    mov rdx, rax
    call memcopy
    ret
.rle:
    mov rdi, r12
    mov rsi, r14
    shl rsi, 2
    mov rdx, r15
    mov rcx, r9
    call rle_encode
    ret
.deflate:
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r14
    shl rdx, 2
    mov rcx, r15
    mov r8, r9
    mov r9, 1
    call deflate_compress
    ret
.delta:
    test r13, r13
    jz .rle
    mov rdi, r15
    mov rsi, r9
    mov rdx, r12
    mov rcx, r13
    mov r8, r14
    call delta_encode_tile
    ret
.full:
    RETURN_ERROR ENOSPC

; ---------------------------------------------------------------------------
; crp_decode_tile
;   IN: rdi=enc, rsi=src, rdx=src_len, rcx=prev_or_0, r8=out, r9=pixels
; ---------------------------------------------------------------------------
global crp_decode_tile
crp_decode_tile:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    mov rax, r9
    cmp ebx, CRP_ENC_RLE
    je .rle
    cmp ebx, CRP_ENC_DEFLATE
    je .deflate
    cmp ebx, CRP_ENC_DELTA
    je .delta
    ; raw
    mov rcx, r9
    shl rcx, 2
    cmp r13, rcx
    jne .fail
    mov rdi, r15
    mov rsi, r12
    mov rdx, rcx
    call memcopy
    xor rax, rax
    ret
.rle:
    mov rdi, r12
    mov rsi, r13
    mov rdx, r15
    mov rcx, r9
    shl rcx, 2
    call rle_decode
    test rax, rax
    js .fail
    xor rax, rax
    ret
.deflate:
    ; TODO: inflate into out
    RETURN_ERROR ENOSYS
.delta:
    test r14, r14
    jz .fail
    mov rdi, r14
    mov rsi, r12
    mov rdx, r13
    mov rcx, r15
    mov r8, r9
    call delta_decode_tile
    ret
.fail:
    RETURN_ERROR EREMOTE_CODEC

section .data
global crp_codec_version
crp_codec_version: dq 0x010000
