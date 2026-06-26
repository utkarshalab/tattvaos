; =============================================================================
; str/path/normalize.asm
; Normalize a filesystem path — resolve . and .., collapse //.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;
; -----------------------------------------------------------------------------
; Path normalization rules:
;   1. Collapse multiple slashes:  /home//raj///code → /home/raj/code
;   2. Remove . segments:          /home/./raj → /home/raj
;   3. Resolve .. segments:        /home/raj/../code → /home/code
;   4. Preserve trailing slash:    /home/raj/ → /home/raj/
;   5. Root stays:                 / stays /, /.. stays /
;   6. Relative paths:             a/b/../c → a/c
;   7. Leading ..:                 ../a stays ../a  (can't resolve past root)
;
; Algorithm: stack-based segment processing.
;   - Split on /
;   - Push each segment onto a stack
;   - "." → skip
;   - ".." → pop (if stack non-empty and top isn't "..")
;   - Reconstruct path from stack
;
; Functions:
;   str_path_normalize     — normalize a path in-place to dst
;   str_path_is_normalized — check if already normalized
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

PATH_SEP    equ '/'

; Max path segments for stack processing
MAX_SEGMENTS    equ 256

section .text

; -----------------------------------------------------------------------------
; str_path_normalize
;
; Normalize a path: resolve . and .., collapse //.
;
; Signature:
;   int64_t str_path_normalize(const StrSlice *path, uint8_t *dst,
;                               uint64_t dst_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

STR_FUNC str_path_normalize

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; dst
    mov     r14, rdx            ; cap
    mov     r15, rcx            ; out_len

    ; allocate segment stack on function stack
    ; each segment: (ptr_offset, len) as two uint64s
    ; MAX_SEGMENTS * 16 bytes
    sub     rsp, MAX_SEGMENTS * 16 + 16
    and     rsp, -16

    ; r8 = is_absolute (starts with /)
    xor     r8d, r8d
    test    r12, r12
    jz      .pn_reconstruct

    movzx   eax, byte [rbx]
    cmp     al, PATH_SEP
    jne     .pn_parse
    mov     r8d, 1

.pn_parse:
    ; parse segments separated by /
    xor     r9, r9              ; src index
    xor     r10, r10            ; stack depth

.pn_next_seg:
    ; skip slashes
.pn_skip_sep:
    cmp     r9, r12
    jae     .pn_reconstruct

    movzx   eax, byte [rbx + r9]
    cmp     al, PATH_SEP
    jne     .pn_seg_start
    inc     r9
    jmp     .pn_skip_sep

.pn_seg_start:
    ; find end of segment
    mov     r11, r9             ; segment start

.pn_seg_scan:
    cmp     r9, r12
    jae     .pn_process_seg

    movzx   eax, byte [rbx + r9]
    cmp     al, PATH_SEP
    je      .pn_process_seg
    inc     r9
    jmp     .pn_seg_scan

.pn_process_seg:
    ; segment = rbx[r11..r9), length = r9 - r11
    mov     rcx, r9
    sub     rcx, r11            ; seg_len

    ; check for "."
    cmp     rcx, 1
    jne     .pn_chk_dotdot
    movzx   eax, byte [rbx + r11]
    cmp     al, '.'
    je      .pn_next_seg        ; skip "."

.pn_chk_dotdot:
    ; check for ".."
    cmp     rcx, 2
    jne     .pn_push
    movzx   eax, byte [rbx + r11]
    cmp     al, '.'
    jne     .pn_push
    movzx   eax, byte [rbx + r11 + 1]
    cmp     al, '.'
    jne     .pn_push

    ; ".." — pop if possible
    test    r10, r10
    jz      .pn_dotdot_keep     ; stack empty

    ; check if top is ".." (can't pop past ..)
    mov     rax, r10
    dec     rax
    mov     rdx, [rsp + rax * 16 + 8]   ; top seg len
    cmp     rdx, 2
    jne     .pn_pop

    mov     rdx, [rsp + rax * 16]        ; top seg offset
    movzx   ecx, byte [rbx + rdx]
    cmp     cl, '.'
    jne     .pn_pop
    movzx   ecx, byte [rbx + rdx + 1]
    cmp     cl, '.'
    je      .pn_dotdot_keep     ; top is also ".." → can't pop

.pn_pop:
    ; pop: just ignore .., skip the top entry
    test    r8d, r8d            ; absolute path?
    jz      .pn_pop_relative

    ; absolute: always pop (can't go above root)
    dec     r10
    jmp     .pn_next_seg

.pn_pop_relative:
    dec     r10
    jmp     .pn_next_seg

.pn_dotdot_keep:
    ; relative path with no parent to pop → keep ".." on stack
    test    r8d, r8d
    jnz     .pn_next_seg        ; absolute: /.. → just / (discard)

    ; push ".." segment
    jmp     .pn_push

.pn_push:
    cmp     r10, MAX_SEGMENTS
    jae     .pn_next_seg        ; overflow protection

    mov     [rsp + r10 * 16], r11       ; segment offset
    mov     rcx, r9
    sub     rcx, r11
    mov     [rsp + r10 * 16 + 8], rcx   ; segment length
    inc     r10
    jmp     .pn_next_seg

.pn_reconstruct:
    ; reconstruct path from stack
    xor     r9, r9              ; dst offset

    ; write leading / if absolute
    test    r8d, r8d
    jz      .pn_write_segs

    cmp     r9, r14
    jae     .pn_overflow
    mov     byte [r13 + r9], PATH_SEP
    inc     r9

.pn_write_segs:
    xor     r11, r11            ; stack index

.pn_write_loop:
    cmp     r11, r10
    jae     .pn_write_trailing

    ; separator between segments (not before first)
    test    r11, r11
    jz      .pn_write_seg

    cmp     r9, r14
    jae     .pn_overflow
    mov     byte [r13 + r9], PATH_SEP
    inc     r9

.pn_write_seg:
    mov     rax, [rsp + r11 * 16]       ; seg offset
    mov     rcx, [rsp + r11 * 16 + 8]   ; seg len

.pn_copy_seg:
    test    rcx, rcx
    jz      .pn_seg_done

    cmp     r9, r14
    jae     .pn_overflow

    movzx   edx, byte [rbx + rax]
    mov     [r13 + r9], dl
    inc     rax
    inc     r9
    dec     rcx
    jmp     .pn_copy_seg

.pn_seg_done:
    inc     r11
    jmp     .pn_write_loop

.pn_write_trailing:
    ; check if original ended with / (preserve trailing slash)
    test    r12, r12
    jz      .pn_done

    movzx   eax, byte [rbx + r12 - 1]
    cmp     al, PATH_SEP
    jne     .pn_done

    ; don't add if result is just "/" already
    cmp     r9, 1
    jbe     .pn_done

    cmp     r9, r14
    jae     .pn_overflow
    mov     byte [r13 + r9], PATH_SEP
    inc     r9

.pn_done:
    ; handle empty result for relative paths
    test    r9, r9
    jnz     .pn_write_len

    ; empty → "."
    cmp     r14, 1
    jb      .pn_overflow
    mov     byte [r13], '.'
    mov     r9, 1

.pn_write_len:
    mov     rsp, rbp

    test    r15, r15
    jz      .pn_ok
    mov     [r15], r9

.pn_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pn_overflow:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_BUF_TOO_SMALL
    pop     rbp
    ret

STR_ENDFUNC str_path_normalize

; -----------------------------------------------------------------------------
; str_path_is_normalized
;
; Check if a path is already in normalized form.
;
; Signature:
;   int64_t str_path_is_normalized(const StrSlice *path)
;
; Returns: RAX = 1 normalized, 0 not
; -----------------------------------------------------------------------------

STR_FUNC str_path_is_normalized

    guard_null rdi, STR_ERR_NULL

    mov     rsi, [rdi + StrSlice.ptr]
    mov     rcx, [rdi + StrSlice.len]

    test    rcx, rcx
    jz      .pin_yes            ; empty is normalized

    xor     r8d, r8d            ; prev_was_sep = 0

    xor     r9, r9              ; index

.pin_loop:
    cmp     r9, rcx
    jae     .pin_yes

    movzx   eax, byte [rsi + r9]

    ; check for //
    cmp     al, PATH_SEP
    jne     .pin_not_sep

    test    r8d, r8d
    jnz     .pin_no             ; consecutive slashes
    mov     r8d, 1
    inc     r9
    jmp     .pin_loop

.pin_not_sep:
    ; check for /. or /.. segments
    test    r8d, r8d
    jz      .pin_advance        ; not after a separator

    cmp     al, '.'
    jne     .pin_advance

    ; could be /. or /..
    lea     rdx, [r9 + 1]
    cmp     rdx, rcx
    jae     .pin_no             ; trailing /. → not normalized

    movzx   edx, byte [rsi + r9 + 1]
    cmp     dl, PATH_SEP
    je      .pin_no             ; /./ → not normalized
    cmp     dl, '.'
    jne     .pin_advance

    ; check for /..
    lea     rdx, [r9 + 2]
    cmp     rdx, rcx
    jae     .pin_no             ; trailing /.. → not normalized
    movzx   edx, byte [rsi + r9 + 2]
    cmp     dl, PATH_SEP
    je      .pin_no             ; /../ → not normalized

.pin_advance:
    xor     r8d, r8d
    inc     r9
    jmp     .pin_loop

.pin_yes:
    mov     eax, 1
    pop     rbp
    ret

.pin_no:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_is_normalized