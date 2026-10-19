; ============================================================================
; Canvas ABI — x86-64 NASM calling convention for Tattva OS
; No libc, no standard ABI, our own pure assembly convention
; ============================================================================

%ifndef __ABI_INC__
%define __ABI_INC__

; ---------------------------------------------------------------------------
; Register Assignment (Tattva Syscall Convention)
; ---------------------------------------------------------------------------
; Syscall number:  rax
; Args:            rdi, rsi, rdx, rcx, r8, r9, r10, r11  (up to 8 args)
; Return:          rax (u64), rdx (u64 for 128-bit)
; Error:           negative rax = -Errno (see errors.inc)
;
; Callee-saved:    rbx, rbp, r12-r15, rsp (16-byte aligned at call)
; Volatile:        rax, rcx, rdx, rsi, rdi, r8-r11, xmm0-15, ymm0-15, zmm0-31
; Red zone:        NOT used (interrupt handlers clobber)
; Shadow space:    32 bytes reserved by caller (rsp+8..rsp+40)

; ---------------------------------------------------------------------------
; Syscall Numbers (Tattva OS)
; ---------------------------------------------------------------------------
%define SYS_MEM_ALLOC       0
%define SYS_MEM_FREE        1
%define SYS_TIME_NOW_NS     2
%define SYS_LOG_WRITE       3
%define SYS_ENTROPY_GET     4
%define SYS_WAIT_WAIT       5
%define SYS_THREAD_WAKE     6
%define SYS_THREAD_SLEEP    7
%define SYS_EXIT            60

; ---------------------------------------------------------------------------
; Function Prologue / Epilogue Macros
; ---------------------------------------------------------------------------

%macro PROLOGUE 0
    push rbp
    mov  rbp, rsp
%endmacro

%macro EPILOGUE 0
    leave
    ret
%endmacro

%macro PROLOGUE_SAVE 1-*
    push rbp
    mov  rbp, rsp
    %rep %0
        push %1
        %rotate 1
    %endrep
%endmacro

%macro EPILOGUE_RESTORE 1-*
    %rep %0
        %rotate -1
        pop %1
    %endrep
    leave
    ret
%endmacro

; ---------------------------------------------------------------------------
; Stack Frame Helpers
; ---------------------------------------------------------------------------

%macro LOCALS 1
    sub rsp, %1
    and rsp, ~15          ; keep 16-byte aligned
%endmacro

%macro LOCAL_END 0
    leave
    ret
%endmacro

; ---------------------------------------------------------------------------
; Syscall Wrapper Macro
; ---------------------------------------------------------------------------
; Usage: SYSCALL nr, arg1, arg2, arg3, arg4, arg5, arg6
; Returns rax (error if negative)

%macro SYSCALL 1-8
    %if %0 > 1
        %rotate 1
        %rep %0 - 1
            %if %0 == 2
                mov rdi, %1
            %elif %0 == 3
                mov rsi, %1
            %elif %0 == 4
                mov rdx, %1
            %elif %0 == 5
                mov rcx, %1
            %elif %0 == 6
                mov r8, %1
            %elif %0 == 6
                mov r9, %1
            %elif %0 == 8
                mov r10, %1
            %endif
            %rotate 1
        %endrep
        %rotate -1
    %endif
    mov rax, %1
    syscall
%endmacro

; ---------------------------------------------------------------------------
; Fast Path: Inline Syscalls (for hot paths)
; ---------------------------------------------------------------------------

%macro TV_MEM_ALLOC 2       ; size, flags -> rax=vaddr, rdx=paddr, r8=handle
    mov rdi, %1
    mov rsi, %2
    mov rax, SYS_MEM_ALLOC
    syscall
%endmacro

%macro TV_TIME_NOW_NS 0     ; -> rax=ns
    mov rax, SYS_TIME_NOW_NS
    syscall
%endmacro

%macro TV_LOG_WRITE 2       ; buf, len -> rax=written
    mov rdi, %1
    mov rsi, %2
    mov rax, SYS_LOG_WRITE
    syscall
%endmacro

%macro TV_ENTROPY_GET 2     ; buf, len -> rax=0/err
    mov rdi, %1
    mov rsi, %2
    mov rax, SYS_ENTROPY_GET
    syscall
%endmacro

%macro TV_WAIT_WAIT 2       ; waitset, deadline_ns -> rax=mask
    mov rdi, %1
    mov rsi, %2
    mov rax, SYS_WAIT_WAIT
    syscall
%endmacro

%endif ; __ABI_INC__