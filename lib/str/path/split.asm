%ifndef GUARD_LIB_STR_PATH_SPLIT_ASM
%define GUARD_LIB_STR_PATH_SPLIT_ASM
; =============================================================================
; str/path/split.asm
; Split a path into dirname, basename, extension, stem.
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
; Path component extraction:
;   "/home/raj/code.asm"
;     dirname   = "/home/raj"
;     basename  = "code.asm"
;     stem      = "code"
;     extension = "asm"
;
;   "file.tar.gz"
;     dirname   = ""
;     basename  = "file.tar.gz"
;     stem      = "file.tar"
;     extension = "gz"
;
; All outputs are StrSlice views into the original buffer — no allocation.
;
; Functions:
;   str_path_dirname     — everything before the last /
;   str_path_basename    — everything after the last /
;   str_path_extension   — after the last . in basename
;   str_path_stem        — basename without extension
;   str_path_split       — dirname + basename in one call
;   str_path_parent      — parent directory (dirname with trailing / stripped)
; =============================================================================

%include "arch/common/types.inc"
%include "arch/common/error.inc"
%include "arch/common/macros.inc"

PATH_SEP    equ '/'
DOT         equ '.'

section .text

; Internal: find last separator position.
; RDI = ptr, RSI = len
; Returns RAX = index of last '/', or -1 if none.
_find_last_sep:
    mov     rax, rsi
    dec     rax                 ; start from end

.fls_loop:
    test    rax, rax
    js      .fls_none

    movzx   ecx, byte [rdi + rax]
    cmp     cl, PATH_SEP
    je      .fls_found
    dec     rax
    jmp     .fls_loop

.fls_none:
    mov     rax, -1
.fls_found:
    ret

; Internal: find last dot in range [start, end).
; RDI = ptr, RSI = start index, RDX = end index
; Returns RAX = index of last '.', or -1 if none.
_find_last_dot:
    mov     rax, rdx
    dec     rax

.fld_loop:
    cmp     rax, rsi
    jb      .fld_none

    movzx   ecx, byte [rdi + rax]
    cmp     cl, DOT
    je      .fld_found
    dec     rax
    jmp     .fld_loop

.fld_none:
    mov     rax, -1
.fld_found:
    ret

; -----------------------------------------------------------------------------
; str_path_dirname
;
; Extract the directory portion of a path.
;
; Signature:
;   int64_t str_path_dirname(const StrSlice *path, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_path_dirname

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, [rbx + StrSlice.len]
    call    _find_last_sep
    ; rax = last sep index, or -1

    cmp     rax, -1
    je      .pd_empty

    ; dirname = path[0..rax)  (exclude the trailing /)
    ; but "/" → dirname is "/"
    test    rax, rax
    jz      .pd_root

    mov     rcx, [rbx + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     [r12 + StrSlice.len], rax

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pd_root:
    ; path starts with / and first / is at index 0 → dirname = "/"
    mov     rcx, [rbx + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     qword [r12 + StrSlice.len], 1

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pd_empty:
    ; no separator → dirname is empty
    mov     rcx, [rbx + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     qword [r12 + StrSlice.len], 0

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_dirname

; -----------------------------------------------------------------------------
; str_path_basename
;
; Extract the filename portion (after the last /).
;
; Signature:
;   int64_t str_path_basename(const StrSlice *path, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_path_basename

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    mov     rdi, [rbx + StrSlice.ptr]
    mov     rsi, [rbx + StrSlice.len]
    call    _find_last_sep

    cmp     rax, -1
    je      .pb_whole           ; no sep → whole thing is basename

    ; basename = path[rax+1 ..]
    inc     rax
    mov     rcx, [rbx + StrSlice.ptr]
    add     rcx, rax
    mov     [r12 + StrSlice.ptr], rcx

    mov     rdx, [rbx + StrSlice.len]
    sub     rdx, rax
    mov     [r12 + StrSlice.len], rdx

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pb_whole:
    mov     rcx, [rbx + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     rcx, [rbx + StrSlice.len]
    mov     [r12 + StrSlice.len], rcx

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_basename

; -----------------------------------------------------------------------------
; str_path_extension
;
; Extract the extension (after the last . in basename, without the dot).
; Hidden files (.gitignore) have no extension (the leading dot is the name).
;
; Signature:
;   int64_t str_path_extension(const StrSlice *path, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_path_extension

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi

    ; first get basename
    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_path_basename

    ; now find last dot in basename
    mov     rdi, [rsp + StrSlice.ptr]
    mov     r13, [rsp + StrSlice.len]

    ; find last '.' but skip leading dot (hidden files)
    ; start search from index 1 if basename starts with .
    xor     rsi, rsi            ; start = 0
    test    r13, r13
    jz      .pe_none

    movzx   eax, byte [rdi]
    cmp     al, DOT
    jne     .pe_search
    mov     rsi, 1              ; skip leading dot

.pe_search:
    mov     rdx, r13            ; end
    call    _find_last_dot

    cmp     rax, -1
    je      .pe_none

    ; extension = basename[dot+1 ..]
    inc     rax
    mov     rcx, [rsp + StrSlice.ptr]
    add     rcx, rax
    mov     [r12 + StrSlice.ptr], rcx

    mov     rdx, r13
    sub     rdx, rax
    mov     [r12 + StrSlice.len], rdx

    mov     rsp, rbp
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pe_none:
    mov     rcx, [rsp + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     qword [r12 + StrSlice.len], 0

    mov     rsp, rbp
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_extension

; -----------------------------------------------------------------------------
; str_path_stem
;
; Basename without the extension (and without the dot).
;
; Signature:
;   int64_t str_path_stem(const StrSlice *path, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_path_stem

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi

    sub     rsp, STRSLICE_SIZE + 16
    and     rsp, -16

    mov     rdi, rbx
    lea     rsi, [rsp]
    call    str_path_basename

    mov     rdi, [rsp + StrSlice.ptr]
    mov     r13, [rsp + StrSlice.len]

    ; find last dot (skip leading dot for hidden files)
    xor     rsi, rsi
    test    r13, r13
    jz      .ps_whole

    movzx   eax, byte [rdi]
    cmp     al, DOT
    jne     .ps_search
    mov     rsi, 1

.ps_search:
    mov     rdx, r13
    call    _find_last_dot

    cmp     rax, -1
    je      .ps_whole

    ; stem = basename[0..dot)
    mov     rcx, [rsp + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     [r12 + StrSlice.len], rax

    mov     rsp, rbp
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.ps_whole:
    ; no dot → stem is the whole basename
    mov     rcx, [rsp + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     [r12 + StrSlice.len], r13

    mov     rsp, rbp
    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_stem

; -----------------------------------------------------------------------------
; str_path_split
;
; Split path into dirname + basename in one call.
;
; Signature:
;   int64_t str_path_split(const StrSlice *path,
;                           StrSlice *out_dir, StrSlice *out_base)
; -----------------------------------------------------------------------------

STR_FUNC str_path_split

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL
    guard_null rdx, STR_ERR_NULL

    push_regs rbx, r12, r13

    mov     rbx, rdi
    mov     r12, rsi
    mov     r13, rdx

    mov     rdi, rbx
    mov     rsi, r12
    call    str_path_dirname

    mov     rdi, rbx
    mov     rsi, r13
    call    str_path_basename

    pop_regs r13, r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_split

; -----------------------------------------------------------------------------
; str_path_parent
;
; Get parent directory — like dirname but strips trailing slash too.
; "/home/raj/"  → "/home"
; "/home/raj"   → "/home"
;
; Signature:
;   int64_t str_path_parent(const StrSlice *path, StrSlice *out)
; -----------------------------------------------------------------------------

STR_FUNC str_path_parent

    guard_null rdi, STR_ERR_NULL
    guard_null rsi, STR_ERR_NULL

    push_regs rbx, r12

    mov     rbx, rdi
    mov     r12, rsi

    ; strip trailing slashes first
    mov     rdi, [rbx + StrSlice.ptr]
    mov     rcx, [rbx + StrSlice.len]

.pp_strip:
    test    rcx, rcx
    jz      .pp_empty

    movzx   eax, byte [rdi + rcx - 1]
    cmp     al, PATH_SEP
    jne     .pp_find_sep

    ; don't strip the root /
    cmp     rcx, 1
    je      .pp_root

    dec     rcx
    jmp     .pp_strip

.pp_find_sep:
    ; find last / in the stripped range
    mov     rsi, rcx            ; len
    call    _find_last_sep

    cmp     rax, -1
    je      .pp_empty

    test    rax, rax
    jz      .pp_root

    mov     rcx, [rbx + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     [r12 + StrSlice.len], rax

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pp_root:
    mov     rcx, [rbx + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     qword [r12 + StrSlice.len], 1

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

.pp_empty:
    mov     rcx, [rbx + StrSlice.ptr]
    mov     [r12 + StrSlice.ptr], rcx
    mov     qword [r12 + StrSlice.len], 0

    pop_regs r12, rbx
    xor     eax, eax
    pop     rbp
    ret

STR_ENDFUNC str_path_parent
%endif ; GUARD_LIB_STR_PATH_SPLIT_ASM
