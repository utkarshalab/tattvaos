; =============================================================================
; lib/io/core/fd.asm
; Global file descriptor table tracking.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_CORE_FD_ASM
%define IO_CORE_FD_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"

section .bss
global io_fd_table
io_fd_table: resb fd_t_size * 256    ; Fixed array of 256 file descriptor entries

section .text

; =============================================================================
; io_fd_init — Zero-initialize the global file descriptor table
; In : None
; Out: None
; =============================================================================
IO_FUNC io_fd_init
    push    rdi
    push    rcx
    push    rax

    lea     rdi, [rel io_fd_table]
    mov     rcx, (fd_t_size * 256) / 8  ; Clear by qwords
    xor     rax, rax
    rep     stosq                       ; Zero out entire table

    pop     rax
    pop     rcx
    pop     rdi
IO_ENDFUNC io_fd_init

global io_fd_alloc
global io_fd_free
global io_fd_get
global io_fd_dup

; =============================================================================
; io_fd_alloc — Allocate a new file descriptor slot for a device
; In : RDI = -> device_t structure
; Out: RAX = Assigned FD number (0-255) or negative error code (IO_ERR_NOMEM)
; =============================================================================
IO_FUNC io_fd_alloc
    guard_null rdi
    push    rbx
    push    rcx
    push    rdx

    mov     rbx, rdi                ; RBX = -> device_t
    lea     rdx, [rel io_fd_table]
    xor     rcx, rcx                ; RCX = index iterator

.scan:
    cmp     rcx, 256
    jae     .err_full

    mov     rax, rcx
    imul    rax, fd_t_size
    lea     rax, [rdx + rax]        ; RAX = -> fd_t slot

    cmp     qword [rax + fd_t.device], 0
    jz      .allocate

    inc     rcx
    jmp     .scan

.allocate:
    mov     [rax + fd_t.device], rbx
    mov     qword [rax + fd_t.offset], 0
    mov     qword [rax + fd_t.flags], 0
    mov     rax, rcx                ; Return allocated FD index
    jmp     .done

.err_full:
    mov     rax, IO_ERR_NOMEM

.done:
    pop     rdx
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC io_fd_alloc

; =============================================================================
; io_fd_free — Deallocate a file descriptor slot
; In : RDI = FD number to release
; Out: RAX = 0 on success, or negative error code (IO_ERR_BADARG)
; =============================================================================
IO_FUNC io_fd_free
    cmp     rdi, 256
    jae     .err_bad_fd

    imul    rdi, fd_t_size
    lea     rax, [rel io_fd_table]
    add     rax, rdi                ; RAX = -> target fd_t slot

    cmp     qword [rax + fd_t.device], 0
    jz      .err_bad_fd             ; Already free or unused

    mov     qword [rax + fd_t.device], 0
    mov     qword [rax + fd_t.offset], 0
    mov     qword [rax + fd_t.flags], 0
    xor     rax, rax                ; Return 0 (Success)
    ret

.err_bad_fd:
    mov     rax, IO_ERR_BADARG
    ret
IO_ENDFUNC io_fd_free

; =============================================================================
; io_fd_get — Resolve FD number to fd_t pointer
; In : RDI = FD number
; Out: RAX = -> fd_t structure, or 0 if invalid/free
; =============================================================================
IO_FUNC io_fd_get
    cmp     rdi, 256
    jae     .invalid

    imul    rdi, fd_t_size
    lea     rax, [rel io_fd_table]
    add     rax, rdi

    cmp     qword [rax + fd_t.device], 0
    jz      .invalid
    ret

.invalid:
    xor     rax, rax                ; Return NULL
    ret
IO_ENDFUNC io_fd_get

; =============================================================================
; io_fd_dup — Duplicate an active file descriptor
; In : RDI = Source FD number
; Out: RAX = New duplicated FD number, or negative error code (IO_ERR_BADARG/NOMEM)
; =============================================================================
IO_FUNC io_fd_dup
    push    rbx
    push    rcx
    push    rsi
    push    rdi

    call    io_fd_get               ; RAX = -> source fd_t
    test    rax, rax
    jz      .err_bad_src
    mov     rbx, rax                ; RBX = -> source fd_t

    ; Allocate a new FD slot using same device
    mov     rdi, [rbx + fd_t.device]
    call    io_fd_alloc
    cmp     rax, 0
    jl      .done                   ; Fails with IO_ERR_NOMEM if table full
    mov     rsi, rax                ; RSI = new FD index

    ; Copy offset and flags
    imul    rax, fd_t_size
    lea     rcx, [rel io_fd_table]
    add     rcx, rax                ; RCX = -> target fd_t slot

    mov     rax, [rbx + fd_t.offset]
    mov     [rcx + fd_t.offset], rax

    mov     rax, [rbx + fd_t.flags]
    mov     [rcx + fd_t.flags], rax

    mov     rax, rsi                ; Return new FD index
    jmp     .done

.err_bad_src:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdi
    pop     rsi
    pop     rcx
    pop     rbx
    ret
IO_ENDFUNC io_fd_dup

%endif ; IO_CORE_FD_ASM
