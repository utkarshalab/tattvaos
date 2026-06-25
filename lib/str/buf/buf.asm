; =============================================================================
; str/buf/buf.asm
; Generic growable byte buffer backed by heap allocation.
;
; Part of Utkarsha Labs / Tattva OS — str library
; Arch: x86_64 | Assembler: NASM
;
; Depends on:
;   arch/common/types.inc
;   arch/common/error.inc
;   arch/common/macros.inc
;   mem/alloc.asm  (str_alloc, str_free, str_realloc)
;   core/copy.asm  (str_copy_bytes)
;
; -----------------------------------------------------------------------------
; StrBuf — owned, growable byte buffer.
; Layout (from types.inc):
;   ptr  dq  — pointer to heap allocation
;   len  dq  — current byte length (written bytes)
;   cap  dq  — total allocated capacity in bytes
;
; Growth strategy: double capacity when full, with a minimum of 64 bytes.
;
; Functions:
;   str_buf_init        — initialize empty StrBuf (no allocation)
;   str_buf_with_cap    — initialize with pre-allocated capacity
;   str_buf_free        — free backing memory
;   str_buf_push        — append bytes
;   str_buf_push_byte   — append single byte
;   str_buf_push_slice  — append a StrSlice
;   str_buf_reserve     — ensure capacity
;   str_buf_clear       — reset length to 0 (keep allocation)
;   str_buf_as_slice    — get StrSlice view (non-owning)
;   str_buf_truncate    — set length to min(len, n)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

extern str_alloc
extern str_free
extern str_realloc
extern str_copy_bytes

BUF_MIN_CAP     equ 64

section .text

; -----------------------------------------------------------------------------
; str_buf_init
;
; Initialize an empty StrBuf (no heap allocation yet).
;
; Signature:
;   int64_t str_buf_init(StrBuf *buf)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_init

    guard_null rdi, STR_ERR_NULL

    mov     qword [rdi + StrBuf.ptr], 0
    mov     qword [rdi + StrBuf.len], 0
    mov     qword [rdi + StrBuf.cap], 0

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_buf_init

; -----------------------------------------------------------------------------
; str_buf_with_cap
;
; Initialize a StrBuf with pre-allocated capacity.
;
; Signature:
;   int64_t str_buf_with_cap(StrBuf *buf, uint64_t cap)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_with_cap

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi            ; cap

    ; allocate
    mov     rdi, r12
    call    str_alloc
    test    rax, rax
    jz      .wc_oom

    mov     [rbx + StrBuf.ptr], rax
    mov     qword [rbx + StrBuf.len], 0
    mov     [rbx + StrBuf.cap], r12

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.wc_oom:
    pop_regs r12, rbx
    mov     rax, STR_ERR_ALLOC
    pop     rbp
    ret

STR_ENDFUNC str_buf_with_cap

; -----------------------------------------------------------------------------
; str_buf_free
;
; Free the backing memory and zero out the StrBuf.
;
; Signature:
;   int64_t str_buf_free(StrBuf *buf)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_free

    guard_null rdi, STR_ERR_NULL

    mov     rsi, [rdi + StrBuf.cap]
    mov     rdi, [rdi + StrBuf.ptr]

    test    rdi, rdi
    jz      .bf_skip_free

    call    str_free

.bf_skip_free:
    ; zero out the struct (caller's rdi is gone — reload from saved)
    ; We need to save the StrBuf ptr before calling str_free
    ; Let's redo with proper save

    pop     rbp
    ret

STR_ENDFUNC str_buf_free

; Corrected str_buf_free:
global str_buf_free
str_buf_free:
    push    rbp
    mov     rbp, rsp

    test    rdi, rdi
    jz      .bf2_null

    push    rbx
    mov     rbx, rdi

    mov     rdi, [rbx + StrBuf.ptr]
    mov     rsi, [rbx + StrBuf.cap]

    test    rdi, rdi
    jz      .bf2_no_free

    call    str_free

.bf2_no_free:
    mov     qword [rbx + StrBuf.ptr], 0
    mov     qword [rbx + StrBuf.len], 0
    mov     qword [rbx + StrBuf.cap], 0

    pop     rbx
    xor     eax, eax
    pop     rbp
    ret

.bf2_null:
    mov     rax, STR_ERR_NULL
    pop     rbp
    ret

; -----------------------------------------------------------------------------
; str_buf_reserve
;
; Ensure the buffer has at least min_cap bytes of capacity.
; Grows by doubling if needed.
;
; Signature:
;   int64_t str_buf_reserve(StrBuf *buf, uint64_t min_cap)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_reserve

    guard_null rdi, STR_ERR_NULL

    ; already have enough capacity?
    mov     rax, [rdi + StrBuf.cap]
    cmp     rax, rsi
    jae     .reserve_ok

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi            ; min_cap

    ; new capacity = max(min_cap, cap * 2, BUF_MIN_CAP)
    mov     r13, [rbx + StrBuf.cap]
    shl     r13, 1              ; cap * 2
    cmp     r13, r12
    jae     .reserve_use_doubled
    mov     r13, r12

.reserve_use_doubled:
    cmp     r13, BUF_MIN_CAP
    jae     .reserve_do_alloc
    mov     r13, BUF_MIN_CAP

.reserve_do_alloc:
    mov     rdi, [rbx + StrBuf.ptr]
    mov     rsi, [rbx + StrBuf.cap]
    mov     rdx, r13
    call    str_realloc
    test    rax, rax
    jz      .reserve_oom

    mov     [rbx + StrBuf.ptr], rax
    mov     [rbx + StrBuf.cap], r13

    pop_regs r13, r12, rbx

.reserve_ok:
    xor     eax, eax
    pop     rbp
    ret

.reserve_oom:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_ALLOC
    pop     rbp
    ret

STR_ENDFUNC str_buf_reserve

; -----------------------------------------------------------------------------
; str_buf_push
;
; Append bytes to the buffer, growing if necessary.
;
; Signature:
;   int64_t str_buf_push(StrBuf *buf, const uint8_t *data, uint64_t len)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    test    rdx, rdx
    jz      .push_ok

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi            ; data
    mov     r13, rdx            ; len

    ; need: buf.len + len <= buf.cap
    mov     rax, [rbx + StrBuf.len]
    add     rax, r13
    jc      .push_overflow

    ; ensure capacity
    mov     rdi, rbx
    mov     rsi, rax
    call    str_buf_reserve
    test    rax, rax
    jnz     .push_err

    ; copy data
    mov     rdi, [rbx + StrBuf.ptr]
    add     rdi, [rbx + StrBuf.len]
    mov     rsi, r12
    mov     rdx, r13
    call    str_copy_bytes
    test    rax, rax
    jnz     .push_err

    ; update len
    add     [rbx + StrBuf.len], r13

    pop_regs r13, r12, rbx

.push_ok:
    xor     eax, eax
    pop     rbp
    ret

.push_overflow:
    pop_regs r13, r12, rbx
    mov     rax, STR_ERR_OVERFLOW
    pop     rbp
    ret

.push_err:
    pop_regs r13, r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_buf_push

; -----------------------------------------------------------------------------
; str_buf_push_byte
;
; Append a single byte, growing if necessary.
;
; Signature:
;   int64_t str_buf_push_byte(StrBuf *buf, uint8_t byte)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_byte

    guard_null rdi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    movzx   r12d, sil

    ; ensure capacity
    mov     rax, [rbx + StrBuf.len]
    inc     rax
    mov     rdi, rbx
    mov     rsi, rax
    call    str_buf_reserve
    test    rax, rax
    jnz     .pb_err

    ; write byte
    mov     rax, [rbx + StrBuf.ptr]
    mov     rcx, [rbx + StrBuf.len]
    mov     [rax + rcx], r12b
    inc     qword [rbx + StrBuf.len]

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pb_err:
    pop_regs r12, rbx
    pop     rbp
    ret

STR_ENDFUNC str_buf_push_byte

; -----------------------------------------------------------------------------
; str_buf_push_slice
;
; Append a StrSlice to the buffer.
;
; Signature:
;   int64_t str_buf_push_slice(StrBuf *buf, const StrSlice *slice)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_push_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rdx, [rsi + StrSlice.len]
    mov     rsi, [rsi + StrSlice.ptr]

    pop     rbp
    jmp     str_buf_push

STR_ENDFUNC str_buf_push_slice

; -----------------------------------------------------------------------------
; str_buf_clear
;
; Reset length to 0, keep allocation.
;
; Signature:
;   int64_t str_buf_clear(StrBuf *buf)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_clear

    guard_null rdi, STR_ERR_NULL

    mov     qword [rdi + StrBuf.len], 0

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_buf_clear

; -----------------------------------------------------------------------------
; str_buf_as_slice
;
; Get a non-owning StrSlice view of the buffer contents.
;
; Signature:
;   int64_t str_buf_as_slice(const StrBuf *buf, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_as_slice

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    mov     rax, [rdi + StrBuf.ptr]
    mov     rcx, [rdi + StrBuf.len]
    mov     [rsi + StrSlice.ptr], rax
    mov     [rsi + StrSlice.len], rcx

    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_buf_as_slice

; -----------------------------------------------------------------------------
; str_buf_truncate
;
; Set len = min(len, n). Does not reallocate.
;
; Signature:
;   int64_t str_buf_truncate(StrBuf *buf, uint64_t n)
; -----------------------------------------------------------------------------

STR_FUNC str_buf_truncate

    guard_null rdi, STR_ERR_NULL

    mov     rax, [rdi + StrBuf.len]
    cmp     rax, rsi
    jbe     .trunc_ok
    mov     [rdi + StrBuf.len], rsi

.trunc_ok:
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_buf_truncate