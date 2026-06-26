; =============================================================================
; str/encoding/engine.asm
; Transcoder engine — convert between any two encodings via a UTF-8 pivot.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   (each codec module registers decode/encode callbacks)
;
; -----------------------------------------------------------------------------
; The engine converts FROM any supported encoding TO any other by pivoting
; through Unicode codepoints:
;
;   source bytes --[decoder]--> codepoint stream --[encoder]--> dest bytes
;
; Every codec provides two callbacks:
;   decode_one(const uint8_t *src, uint64_t src_len, uint32_t *out_cp)
;     → returns number of source bytes consumed, or negative error
;   encode_one(uint32_t cp, uint8_t *dst, uint64_t dst_cap)
;     → returns number of dest bytes written, or negative error
;
; A codec is described by an EncCodec struct holding these callbacks plus
; metadata (name, max bytes per char, whether stateful).
;
; The engine itself is encoding-agnostic — it just drives the two callbacks.
;
; EncCodec struct (48 bytes):
;   decode_one   dq   — decoder callback
;   encode_one   dq   — encoder callback
;   name         dq   — pointer to name string
;   max_bytes    dq   — max bytes per character
;   flags        dq   — ENC_FLAG_*
;   state_init   dq   — optional state initializer (for stateful codecs)
;
; Functions:
;   str_transcode         — convert src in encoding A → dst in encoding B
;   str_decode_to_utf8    — convert any encoding → UTF-8
;   str_encode_from_utf8  — convert UTF-8 → any encoding
;   str_codec_by_name     — look up a codec by name
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

; EncCodec struct
struc EncCodec
    .decode_one resq 1      ; fn(src, src_len, *out_cp) → bytes consumed
    .encode_one resq 1      ; fn(cp, dst, dst_cap) → bytes written
    .name       resq 1      ; codec name string
    .max_bytes  resq 1      ; max bytes per character
    .flags      resq 1
    .state_init resq 1
endstruc

ENCCODEC_SIZE   equ 48

; Codec flags
ENC_FLAG_STATEFUL   equ 0x01    ; codec maintains state (ISO-2022)
ENC_FLAG_ASCII_SUPERSET equ 0x02 ; ASCII bytes map to themselves

; UTF-8 codec callbacks (from utf8/ module)
extern str_utf8_decode
extern str_utf8_encode_unchecked
extern str_utf8_encode_buf_size

section .text

; -----------------------------------------------------------------------------
; str_transcode
;
; Convert a byte string from source encoding to destination encoding.
;
; Signature:
;   int64_t str_transcode(const EncCodec *src_codec, const uint8_t *src,
;                          uint64_t src_len,
;                          const EncCodec *dst_codec, uint8_t *dst,
;                          uint64_t dst_cap, uint64_t *out_len)
;
; Arguments:
;   RDI  — source codec
;   RSI  — source bytes
;   RDX  — source length
;   RCX  — destination codec
;   R8   — destination buffer
;   R9   — destination capacity
;   [rsp+8] — out_len pointer
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_ENCODING   invalid source byte sequence
;   RAX  = STR_ERR_BUF_TOO_SMALL
; -----------------------------------------------------------------------------

STR_FUNC str_transcode

    guard_null rdi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL
    guard_null r8,  STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src codec
    mov     r12, rsi            ; src ptr
    mov     r13, rdx            ; src len
    mov     r14, rcx            ; dst codec
    mov     r15, r8             ; dst ptr

    ; load remaining args from stack
    ; after 5 pushes (40 bytes) + return addr (8) + saved rbp (8):
    ; original [rsp+8] (out_len) is now at [rsp + 40 + 16 + 8]
    mov     rax, [rbp + 16]     ; out_len (first stack arg)
    push    rax                 ; save out_len
    push    r9                  ; save dst_cap

    xor     r10, r10            ; src offset
    xor     r11, r11            ; dst offset

.tc_loop:
    cmp     r10, r13
    jae     .tc_done

    ; decode one codepoint from source
    lea     rdi, [r12 + r10]
    mov     rsi, r13
    sub     rsi, r10            ; remaining src len

    sub     rsp, 16
    and     rsp, -16
    lea     rdx, [rsp]          ; out_cp
    push    r10
    push    r11
    call    [rbx + EncCodec.decode_one]
    pop     r11
    pop     r10

    test    rax, rax
    js      .tc_decode_err      ; negative = error

    mov     rcx, rax            ; bytes consumed
    mov     r8d, [rsp]          ; decoded codepoint
    mov     rsp, rbp
    sub     rsp, 16             ; restore our 2 pushes (out_len, dst_cap)

    add     r10, rcx            ; advance source

    ; encode the codepoint into destination
    mov     edi, r8d            ; cp
    mov     rsi, r15
    add     rsi, r11            ; dst + offset
    mov     rdx, [rsp + 0]      ; dst_cap
    sub     rdx, r11            ; remaining dst cap

    push    r10
    push    r11
    call    [r14 + EncCodec.encode_one]
    pop     r11
    pop     r10

    test    rax, rax
    js      .tc_encode_err

    add     r11, rax            ; advance dst
    jmp     .tc_loop

.tc_done:
    mov     rcx, [rsp + 8]      ; out_len
    add     rsp, 16             ; pop out_len, dst_cap

    test    rcx, rcx
    jz      .tc_ok
    mov     [rcx], r11

.tc_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.tc_decode_err:
    mov     rsp, rbp
    sub     rsp, 16
    add     rsp, 16
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.tc_encode_err:
    add     rsp, 16
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_transcode

; -----------------------------------------------------------------------------
; str_decode_to_utf8
;
; Convert bytes in any encoding to UTF-8.
; Convenience wrapper: transcode(src_codec → utf8_codec).
;
; Signature:
;   int64_t str_decode_to_utf8(const EncCodec *src_codec, const uint8_t *src,
;                               uint64_t src_len, uint8_t *dst,
;                               uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_decode_to_utf8

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rcx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src codec
    mov     r12, rsi            ; src
    mov     r13, rdx            ; src len
    mov     r14, rcx            ; dst
    mov     r15, r8             ; dst cap
    push    r9                  ; out_len

    xor     r10, r10            ; src offset
    xor     r11, r11            ; dst offset

.du_loop:
    cmp     r10, r13
    jae     .du_done

    ; decode one cp from source
    lea     rdi, [r12 + r10]
    mov     rsi, r13
    sub     rsi, r10

    sub     rsp, 16
    and     rsp, -16
    lea     rdx, [rsp]
    push    r10
    push    r11
    call    [rbx + EncCodec.decode_one]
    pop     r11
    pop     r10

    test    rax, rax
    js      .du_err

    mov     rcx, rax            ; consumed
    mov     r8d, [rsp]          ; cp
    mov     rsp, rbp
    sub     rsp, 8              ; keep out_len on stack

    add     r10, rcx

    ; encode as UTF-8
    mov     edi, r8d
    mov     rsi, r14
    add     rsi, r11

    ; bounds check: need up to 4 bytes
    lea     rax, [r11 + 4]
    cmp     rax, r15
    ja      .du_overflow

    push    r10
    push    r11
    call    str_utf8_encode_unchecked
    pop     r11
    pop     r10

    add     r11, rax
    jmp     .du_loop

.du_done:
    pop     rcx                 ; out_len
    test    rcx, rcx
    jz      .du_ok
    mov     [rcx], r11

.du_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.du_err:
    mov     rsp, rbp
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.du_overflow:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_decode_to_utf8

; -----------------------------------------------------------------------------
; str_encode_from_utf8
;
; Convert UTF-8 bytes to any encoding.
;
; Signature:
;   int64_t str_encode_from_utf8(const uint8_t *src, uint64_t src_len,
;                                 const EncCodec *dst_codec, uint8_t *dst,
;                                 uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_encode_from_utf8

    guard_null rdi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; src (utf8)
    mov     r12, rsi            ; src len
    mov     r13, rdx            ; dst codec
    mov     r14, rcx            ; dst
    mov     r15, r8             ; dst cap
    push    r9                  ; out_len

    xor     r10, r10            ; src offset
    xor     r11, r11            ; dst offset

.eu_loop:
    cmp     r10, r12
    jae     .eu_done

    ; decode one UTF-8 codepoint
    lea     rdi, [rbx + r10]
    mov     rsi, r12
    sub     rsi, r10

    sub     rsp, 16
    and     rsp, -16
    lea     rdx, [rsp]
    push    r10
    push    r11
    call    str_utf8_decode
    pop     r11
    pop     r10

    test    rax, rax
    js      .eu_err

    mov     rcx, rax            ; consumed
    mov     r8d, [rsp]          ; cp
    mov     rsp, rbp
    sub     rsp, 8

    add     r10, rcx

    ; encode via dest codec
    mov     edi, r8d
    mov     rsi, r14
    add     rsi, r11
    mov     rdx, r15
    sub     rdx, r11

    push    r10
    push    r11
    call    [r13 + EncCodec.encode_one]
    pop     r11
    pop     r10

    test    rax, rax
    js      .eu_overflow

    add     r11, rax
    jmp     .eu_loop

.eu_done:
    pop     rcx
    test    rcx, rcx
    jz      .eu_ok
    mov     [rcx], r11

.eu_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.eu_err:
    mov     rsp, rbp
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_ENCODING
    pop     rbp
    ret

.eu_overflow:
    add     rsp, 8
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_encode_from_utf8