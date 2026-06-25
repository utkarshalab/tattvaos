; =============================================================================
; str/parse/version.asm
; Parse semantic version strings (semver 2.0.0).
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   convert/int.asm  (str_parse_u64)
;
; -----------------------------------------------------------------------------
; Semver format: MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]
;
;   "1.2.3"                    → major=1, minor=2, patch=3
;   "1.0.0-alpha"              → prerelease="alpha"
;   "1.0.0-alpha.1"            → prerelease="alpha.1"
;   "1.0.0+build.42"           → build="build.42"
;   "1.0.0-beta+exp.sha.5114f" → both
;
; Version struct layout (48 bytes):
;   uint64_t major
;   uint64_t minor
;   uint64_t patch
;   StrSlice prerelease   (16 bytes: ptr + len)
;   StrSlice build_meta   (16 bytes: ptr + len)
;
; Functions:
;   str_parse_version       — parse into Version struct
;   str_version_cmp         — compare two versions
;   str_version_to_str      — format version back to string
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_parse_u64

; Version struct offsets
struc Version
    .major      resq 1
    .minor      resq 1
    .patch      resq 1
    .prerelease resq 2          ; StrSlice (ptr + len)
    .build      resq 2          ; StrSlice (ptr + len)
endstruc

VERSION_SIZE    equ 48

section .text

; -----------------------------------------------------------------------------
; str_parse_version
;
; Parse a semver string into a Version struct.
;
; Signature:
;   int64_t str_parse_version(const StrSlice *src, Version *out)
;
; Arguments:
;   RDI  — source StrSlice
;   RSI  — pointer to Version struct (48 bytes)
;
; Returns:
;   RAX  = STR_OK
;   RAX  = STR_ERR_NULL
;   RAX  = STR_ERR_PARSE   invalid semver format
; -----------------------------------------------------------------------------

STR_FUNC str_parse_version

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, [rdi + StrSlice.ptr]
    mov     r12, [rdi + StrSlice.len]
    mov     r13, rsi            ; out Version
    xor     r15, r15            ; index

    ; zero out Version struct
    xor     eax, eax
    mov     [r13 + Version.major], rax
    mov     [r13 + Version.minor], rax
    mov     [r13 + Version.patch], rax
    mov     [r13 + Version.prerelease], rax
    mov     [r13 + Version.prerelease + 8], rax
    mov     [r13 + Version.build], rax
    mov     [r13 + Version.build + 8], rax

    ; parse MAJOR
    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    lea     rax, [rbx + r15]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r12
    sub     rax, r15
    mov     [rsp + StrSlice.len], rax

    mov     rdi, rsp
    lea     rsi, [rsp + STRSLICE_SIZE]
    lea     rdx, [rsp + STRSLICE_SIZE + 8]
    call    str_parse_u64
    test    rax, rax
    jnz     .ver_parse_err

    mov     rax, [rsp + STRSLICE_SIZE]
    mov     [r13 + Version.major], rax
    mov     r10, [rsp + STRSLICE_SIZE + 8]    ; consumed
    add     r15, r10

    mov     rsp, rbp
    sub     rsp, 0

    ; expect '.'
    cmp     r15, r12
    jae     .ver_parse_err
    cmp     byte [rbx + r15], '.'
    jne     .ver_parse_err
    inc     r15

    ; parse MINOR
    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    lea     rax, [rbx + r15]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r12
    sub     rax, r15
    mov     [rsp + StrSlice.len], rax

    mov     rdi, rsp
    lea     rsi, [rsp + STRSLICE_SIZE]
    lea     rdx, [rsp + STRSLICE_SIZE + 8]
    call    str_parse_u64
    test    rax, rax
    jnz     .ver_parse_err

    mov     rax, [rsp + STRSLICE_SIZE]
    mov     [r13 + Version.minor], rax
    mov     r10, [rsp + STRSLICE_SIZE + 8]
    add     r15, r10

    mov     rsp, rbp
    sub     rsp, 0

    ; expect '.'
    cmp     r15, r12
    jae     .ver_parse_err
    cmp     byte [rbx + r15], '.'
    jne     .ver_parse_err
    inc     r15

    ; parse PATCH
    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    lea     rax, [rbx + r15]
    mov     [rsp + StrSlice.ptr], rax
    mov     rax, r12
    sub     rax, r15
    mov     [rsp + StrSlice.len], rax

    mov     rdi, rsp
    lea     rsi, [rsp + STRSLICE_SIZE]
    lea     rdx, [rsp + STRSLICE_SIZE + 8]
    call    str_parse_u64
    test    rax, rax
    jnz     .ver_parse_err

    mov     rax, [rsp + STRSLICE_SIZE]
    mov     [r13 + Version.patch], rax
    mov     r10, [rsp + STRSLICE_SIZE + 8]
    add     r15, r10

    mov     rsp, rbp
    sub     rsp, 0

    ; optional: prerelease (-) or build (+)
    cmp     r15, r12
    jae     .ver_done

    movzx   eax, byte [rbx + r15]

    cmp     al, '-'
    je      .ver_prerelease

    cmp     al, '+'
    je      .ver_build_only

    jmp     .ver_done

.ver_prerelease:
    inc     r15
    ; read until '+' or end
    mov     r14, r15            ; start of prerelease

.ver_pre_scan:
    cmp     r15, r12
    jae     .ver_pre_end

    movzx   eax, byte [rbx + r15]
    cmp     al, '+'
    je      .ver_pre_end

    inc     r15
    jmp     .ver_pre_scan

.ver_pre_end:
    ; prerelease = [r14, r15)
    lea     rax, [rbx + r14]
    mov     [r13 + Version.prerelease], rax
    mov     rax, r15
    sub     rax, r14
    mov     [r13 + Version.prerelease + 8], rax

    cmp     r15, r12
    jae     .ver_done

    movzx   eax, byte [rbx + r15]
    cmp     al, '+'
    jne     .ver_done

.ver_build_only:
    inc     r15
    ; rest of string is build metadata
    lea     rax, [rbx + r15]
    mov     [r13 + Version.build], rax
    mov     rax, r12
    sub     rax, r15
    mov     [r13 + Version.build + 8], rax

.ver_done:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ver_parse_err:
    mov     rsp, rbp
    pop_regs r15, r14, r13, r12, rbx
    mov     rax, STR_ERR_PARSE
    pop     rbp
    ret

STR_ENDFUNC str_parse_version

; -----------------------------------------------------------------------------
; str_version_cmp
;
; Compare two Version structs.
; Prerelease versions have LOWER precedence than release versions.
;
; Signature:
;   int64_t str_version_cmp(const Version *a, const Version *b)
;
; Returns:
;   RAX < 0   a < b
;   RAX = 0   a == b
;   RAX > 0   a > b
; -----------------------------------------------------------------------------

STR_FUNC str_version_cmp

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    ; compare major
    mov     rax, [rdi + Version.major]
    mov     rcx, [rsi + Version.major]
    cmp     rax, rcx
    jne     .vc_diff

    ; compare minor
    mov     rax, [rdi + Version.minor]
    mov     rcx, [rsi + Version.minor]
    cmp     rax, rcx
    jne     .vc_diff

    ; compare patch
    mov     rax, [rdi + Version.patch]
    mov     rcx, [rsi + Version.patch]
    cmp     rax, rcx
    jne     .vc_diff

    ; compare prerelease:
    ; no prerelease > has prerelease
    mov     rax, [rdi + Version.prerelease + 8]  ; a.pre.len
    mov     rcx, [rsi + Version.prerelease + 8]  ; b.pre.len

    test    rax, rax
    jnz     .vc_a_has_pre

    ; a has no prerelease
    test    rcx, rcx
    jz      .vc_equal           ; both no prerelease → equal
    mov     rax, 1              ; a > b (a is release, b is prerelease)
    pop     rbp
    ret

.vc_a_has_pre:
    test    rcx, rcx
    jnz     .vc_compare_pre
    mov     rax, -1             ; a < b (a is prerelease, b is release)
    pop     rbp
    ret

.vc_compare_pre:
    ; lexicographic compare of prerelease strings
    mov     r8, [rdi + Version.prerelease]     ; a.pre.ptr
    mov     r9, [rsi + Version.prerelease]     ; b.pre.ptr
    ; min_len
    mov     r10, rax
    cmp     r10, rcx
    jbe     .vc_got_min
    mov     r10, rcx
.vc_got_min:
    xor     r11, r11
.vc_pre_cmp:
    cmp     r11, r10
    jae     .vc_pre_by_len
    movzx   edx, byte [r8 + r11]
    movzx   r12d, byte [r9 + r11]
    cmp     dl, r12b
    jne     .vc_pre_diff
    inc     r11
    jmp     .vc_pre_cmp
.vc_pre_diff:
    movsx   rax, dl
    movsx   rcx, r12b
    sub     rax, rcx
    pop     rbp
    ret
.vc_pre_by_len:
    ; same prefix — longer is greater
    sub     rax, rcx
    pop     rbp
    ret

.vc_equal:
    xor     eax, eax
    pop     rbp
    ret

.vc_diff:
    ; return a[field] - b[field] sign
    jb      .vc_lt
    mov     eax, 1
    pop     rbp
    ret
.vc_lt:
    mov     rax, -1
    pop     rbp
    ret

STR_ENDFUNC str_version_cmp

; -----------------------------------------------------------------------------
; str_version_to_str
;
; Format a Version struct back to semver string.
;
; Signature:
;   int64_t str_version_to_str(const Version *ver, uint8_t *buf,
;                               uint64_t buf_cap, uint64_t *out_len)
; -----------------------------------------------------------------------------

extern str_u64_to_str
extern str_copy_bytes

STR_FUNC str_version_to_str

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13, r14, r15

    mov     rbx, rdi            ; ver
    mov     r12, rsi            ; buf
    mov     r13, rdx            ; cap
    mov     r14, rcx            ; out_len
    xor     r15, r15            ; write offset

    ; write MAJOR
    sub     rsp, 24
    and     rsp, -8

    mov     rdi, [rbx + Version.major]
    lea     rsi, [r12 + r15]
    mov     rdx, r13
    lea     rcx, [rsp]
    call    str_u64_to_str
    mov     r10, [rsp]
    add     r15, r10

    ; '.'
    mov     byte [r12 + r15], '.'
    inc     r15

    ; MINOR
    mov     rdi, [rbx + Version.minor]
    lea     rsi, [r12 + r15]
    mov     rdx, r13
    lea     rcx, [rsp]
    call    str_u64_to_str
    mov     r10, [rsp]
    add     r15, r10

    ; '.'
    mov     byte [r12 + r15], '.'
    inc     r15

    ; PATCH
    mov     rdi, [rbx + Version.patch]
    lea     rsi, [r12 + r15]
    mov     rdx, r13
    lea     rcx, [rsp]
    call    str_u64_to_str
    mov     r10, [rsp]
    add     r15, r10

    mov     rsp, rbp
    sub     rsp, 0

    ; optional prerelease
    mov     r10, [rbx + Version.prerelease + 8]
    test    r10, r10
    jz      .vts_build

    mov     byte [r12 + r15], '-'
    inc     r15

    mov     rdi, [rbx + Version.prerelease]
    lea     rsi, [r12 + r15]     ; wrong — should copy to r12+r15
    mov     rdi, r12
    add     rdi, r15
    mov     rsi, [rbx + Version.prerelease]
    mov     rdx, r10
    call    str_copy_bytes
    add     r15, r10

.vts_build:
    mov     r10, [rbx + Version.build + 8]
    test    r10, r10
    jz      .vts_done

    mov     byte [r12 + r15], '+'
    inc     r15

    mov     rdi, r12
    add     rdi, r15
    mov     rsi, [rbx + Version.build]
    mov     rdx, r10
    call    str_copy_bytes
    add     r15, r10

.vts_done:
    test    r14, r14
    jz      .vts_ok
    mov     [r14], r15

.vts_ok:
    pop_regs r15, r14, r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_version_to_str