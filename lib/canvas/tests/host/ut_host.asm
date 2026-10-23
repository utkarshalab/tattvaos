; ============================================================================
; Host Test Shim — ut_host.asm
; Implements the ut_* service bindings over host process syscalls so unit
; tests and decoders can run on a development machine. Test builds only;
; never linked into canvasd or client images.
; ============================================================================

%define PANIC_IMPL 1
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

%define HOST_SYS_WRITE          1
%define HOST_SYS_MMAP           9
%define HOST_SYS_MUNMAP         11
%define HOST_SYS_CLOCK_GETTIME  228
%define HOST_SYS_EXIT_GROUP     231
%define HOST_SYS_GETRANDOM      318
%define HOST_CLOCK_MONOTONIC    1
%define HOST_STDOUT             1

section .text

; ---------------------------------------------------------------------------
; host_write
;   IN: rdi = buffer, rsi = length — OUT: rax = bytes written or -errno
; ---------------------------------------------------------------------------
host_write:
    mov rdx, rsi
    mov rsi, rdi
    mov edi, HOST_STDOUT
    mov eax, HOST_SYS_WRITE
    syscall
    ret

; ---------------------------------------------------------------------------
; ut_log_write
;   IN: rdi = buffer, rsi = length — OUT: rax = bytes written
; ---------------------------------------------------------------------------
global ut_log_write
ut_log_write:
    PROLOGUE
    call host_write
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_log_printf
;   Limited printf: %s %d %u %x %p %c %%; 'l' length prefixes are ignored
;   IN: rdi = format, rsi, rdx, rcx, r8, r9, then stack = args
;   OUT: rax = bytes written
; ---------------------------------------------------------------------------
global ut_log_printf
ut_log_printf:
    ; Spill register args so all arguments are addressable as one array.
    pop r11                     ; return address
    push r9
    push r8
    push rcx
    push rdx
    push rsi
    push r11
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 40                 ; [rsp] = 32-byte number scratch
    mov rbx, rdi                ; format cursor
    lea r12, [rbp + 16]         ; next argument slot
    xor r13, r13                ; bytes written
.loop:
    mov r14, rbx                ; start of literal run
.scan:
    movzx eax, byte [rbx]
    test al, al
    jz .flush_end
    cmp al, '%'
    je .flush_spec
    inc rbx
    jmp .scan
.flush_spec:
    call .emit_run
    inc rbx                     ; skip '%'
.len_prefix:
    movzx eax, byte [rbx]
    cmp al, 'l'
    jne .spec
    inc rbx
    jmp .len_prefix
.spec:
    inc rbx
    cmp al, 's'
    je .fmt_s
    cmp al, 'd'
    je .fmt_d
    cmp al, 'u'
    je .fmt_u
    cmp al, 'x'
    je .fmt_x
    cmp al, 'p'
    je .fmt_p
    cmp al, 'c'
    je .fmt_c
    test al, al
    jz .done
    ; '%%' and unknown specifiers print the character itself
    mov [rsp], al
    mov rdi, rsp
    mov esi, 1
    call .emit
    jmp .loop
.fmt_s:
    mov rdi, [r12]
    add r12, 8
    test rdi, rdi
    jnz .s_len
    lea rdi, [rel null_str]
.s_len:
    xor esi, esi
.s_scan:
    cmp byte [rdi + rsi], 0
    je .s_out
    inc rsi
    jmp .s_scan
.s_out:
    call .emit
    jmp .loop
.fmt_c:
    mov rax, [r12]
    add r12, 8
    mov [rsp], al
    mov rdi, rsp
    mov esi, 1
    call .emit
    jmp .loop
.fmt_d:
    mov rax, [r12]
    add r12, 8
    test rax, rax
    jns .dec
    neg rax
    mov r15, rax
    mov byte [rsp], '-'
    mov rdi, rsp
    mov esi, 1
    call .emit
    mov rax, r15
    jmp .dec
.fmt_u:
    mov rax, [r12]
    add r12, 8
.dec:
    lea rdi, [rsp + 32]
    mov ecx, 10
.dec_loop:
    xor edx, edx
    div rcx
    add dl, '0'
    dec rdi
    mov [rdi], dl
    test rax, rax
    jnz .dec_loop
    lea rsi, [rsp + 32]
    sub rsi, rdi
    call .emit
    jmp .loop
.fmt_p:
    mov word [rsp], '0x'
    mov rdi, rsp
    mov esi, 2
    call .emit
.fmt_x:
    mov rax, [r12]
    add r12, 8
    lea rdi, [rsp + 32]
.hex_loop:
    mov edx, eax
    and edx, 15
    lea rcx, [rel hex_digits]
    mov dl, [rcx + rdx]
    dec rdi
    mov [rdi], dl
    shr rax, 4
    jnz .hex_loop
    lea rsi, [rsp + 32]
    sub rsi, rdi
    call .emit
    jmp .loop
.flush_end:
    call .emit_run
.done:
    mov rax, r13
    add rsp, 40
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    leave
    pop r11                     ; return address
    add rsp, 40                 ; drop spilled register args
    jmp r11

; Emit the literal run [r14, rbx).
.emit_run:
    mov rdi, r14
    mov rsi, rbx
    sub rsi, r14
    jz .emit_none
; Emit rdi/rsi and add to the byte count.
.emit:
    push rdi                    ; keep 16-byte alignment for the syscall path
    call host_write
    pop rdi
    test rax, rax
    js .emit_none
    add r13, rax
.emit_none:
    ret

; ---------------------------------------------------------------------------
; Log level and flush are no-ops on the host
; ---------------------------------------------------------------------------
global ut_log_set_level
ut_log_set_level:
    xor eax, eax
    ret

global ut_log_get_level
ut_log_get_level:
    mov eax, 5
    ret

global ut_log_flush
ut_log_flush:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; ut_mem_alloc
;   IN: rdi = size, rsi = flags (ignored)
;   OUT: rax = address or negative error, rdx = address, r8 = region handle
;   The handle is the address; the size is stored in a header page so
;   ut_mem_free can unmap the whole region.
; ---------------------------------------------------------------------------
global ut_mem_alloc
ut_mem_alloc:
    PROLOGUE_SAVE rbx
    lea rbx, [rdi + 4095 + 4096]
    and rbx, -4096
    xor edi, edi
    mov rsi, rbx
    mov edx, 3                  ; PROT_READ | PROT_WRITE
    mov r10d, 0x22              ; MAP_PRIVATE | MAP_ANONYMOUS
    mov r8, -1
    xor r9d, r9d
    mov eax, HOST_SYS_MMAP
    syscall
    test rax, rax
    js .fail
    mov [rax], rbx              ; header: mapping size
    add rax, 4096
    mov rdx, rax
    mov r8, rax
    EPILOGUE_RESTORE rbx
.fail:
    mov rax, -(ENOMEM)
    xor edx, edx
    xor r8d, r8d
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; ut_mem_free
;   IN: rdi = region handle from ut_mem_alloc — OUT: rax = 0 or -errno
; ---------------------------------------------------------------------------
global ut_mem_free
ut_mem_free:
    test rdi, rdi
    jz .null
    sub rdi, 4096
    mov rsi, [rdi]
    mov eax, HOST_SYS_MUNMAP
    syscall
    ret
.null:
    mov rax, -(EINVAL)
    ret

; ---------------------------------------------------------------------------
; ut_time_now_ns
;   OUT: rax = monotonic nanoseconds
; ---------------------------------------------------------------------------
global ut_time_now_ns
ut_time_now_ns:
    PROLOGUE
    sub rsp, 16
    mov edi, HOST_CLOCK_MONOTONIC
    mov rsi, rsp
    mov eax, HOST_SYS_CLOCK_GETTIME
    syscall
    mov rax, [rsp]
    imul rax, rax, 1000000000
    add rax, [rsp + 8]
    EPILOGUE

; ---------------------------------------------------------------------------
; ut_entropy_get
;   IN: rdi = buffer, rsi = length — OUT: rax = 0 or -errno
; ---------------------------------------------------------------------------
global ut_entropy_get
ut_entropy_get:
    xor edx, edx
    mov eax, HOST_SYS_GETRANDOM
    syscall
    test rax, rax
    js .done
    xor eax, eax
.done:
    ret

; ---------------------------------------------------------------------------
; ut_task_exit
;   IN: rdi = exit code — does not return
; ---------------------------------------------------------------------------
global ut_task_exit
ut_task_exit:
    mov eax, HOST_SYS_EXIT_GROUP
    syscall
    hlt

; ---------------------------------------------------------------------------
; Panic hooks used by macros.inc assertions: print and exit with status 134
; ---------------------------------------------------------------------------
%macro HOST_PANIC 2
global %1
%1:
    and rsp, -16
    lea rdi, [rel %2]
    mov esi, %2_len
    call host_write
    mov edi, 134
    jmp ut_task_exit
%endmacro

HOST_PANIC panic_assert_failed, panic_msg_assert
HOST_PANIC panic_null_ptr, panic_msg_null
HOST_PANIC panic_unaligned, panic_msg_unaligned
HOST_PANIC panic_bounds, panic_msg_bounds
HOST_PANIC panic_oom, panic_msg_oom
HOST_PANIC panic_unreachable, panic_msg_unreachable

section .rodata

hex_digits:             db "0123456789abcdef"
null_str:               db "(null)", 0
panic_msg_assert:       db "PANIC: assertion failed", 10
panic_msg_assert_len    equ $ - panic_msg_assert
panic_msg_null:         db "PANIC: null pointer", 10
panic_msg_null_len      equ $ - panic_msg_null
panic_msg_unaligned:    db "PANIC: unaligned access", 10
panic_msg_unaligned_len equ $ - panic_msg_unaligned
panic_msg_bounds:       db "PANIC: out of bounds", 10
panic_msg_bounds_len    equ $ - panic_msg_bounds
panic_msg_oom:          db "PANIC: out of memory", 10
panic_msg_oom_len       equ $ - panic_msg_oom
panic_msg_unreachable:  db "PANIC: unreachable", 10
panic_msg_unreachable_len equ $ - panic_msg_unreachable
