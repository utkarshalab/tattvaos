; =============================================================================
; lib/io/block/bdev.asm
; Uniform block device read/write synchronization layer.
;
; Part of Utkarsha Labs / Tattva OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BLOCK_BDEV_ASM
%define IO_BLOCK_BDEV_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

; =============================================================================
; bdev_read — Synchronous read sectors from a block device
; In : RDI = -> device_t object
;      RSI = Starting LBA (logical block address)
;      RDX = Count of blocks
;      RCX = -> Destination buffer
; Out: RAX = 0 on success, or a negative error band code on failure
; =============================================================================
IO_FUNC bdev_read
    guard_null rdi
    guard_null rcx

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; Check if synchronous read fallback exists
    mov     rax, [rdi + device_t.read]
    test    rax, rax
    jz      .try_async

    ; Call synchronous read directly: read(dev, lba, count, buf)
    call    rax
    jmp     .done

.try_async:
    ; Synchronous read not available, check for asynchronous submit
    mov     rax, [rdi + device_t.submit]
    test    rax, rax
    jz      .err_badarg

    ; Allocate io_request_t on stack to perform block read
    ; Stack size of io_request_t is 104 bytes. Align RSP.
    sub     rsp, 128                ; Stack buffer aligned (multiple of 16)
    mov     rbx, rsp                ; RBX = -> stack io_request_t

    ; Clear stack request block
    mov     rdi, rbx
    xor     rax, rax
    mov     rcx, 16                 ; 128 / 8 = 16 qwords
    rep     stosq

    ; Populate io_request_t
    pop     rdi                     ; Restore original RDI (dev) to push/access
    push    rdi
    mov     [rbx + io_request_t.device], rdi
    mov     qword [rbx + io_request_t.opcode], IO_OP_READ
    mov     [rbx + io_request_t.lba], rsi
    mov     [rbx + io_request_t.nblocks], rdx
    mov     qword [rbx + io_request_t.state], IO_REQ_INIT

    ; We simulate direct transfer (non-SG for simple bdev helper, or stub SG)
    ; In this bring-up, we reuse the destination buffer pointer directly:
    ; We can pass buffer address directly in priv or iov fields.
    ; To keep it simple, we wrap it in a stack iovec:
    lea     rax, [rbx + 96]         ; Allocate one iovec_t in remaining stack space
    mov     [rax + iovec_t.base], rcx
    mov     [rax + iovec_t.len], rdx ; size in blocks
    ; Get sector size
    mov     rsi, [rdi + device_t.sector_size]
    imul    [rax + iovec_t.len], rsi ; convert to bytes
    mov     [rbx + io_request_t.iov], rax
    mov     qword [rbx + io_request_t.iov_cnt], 1

    ; Submit the request: submit(dev, req)
    mov     rdi, [rbx + io_request_t.device]
    mov     rsi, rbx                ; RSI = &req
    mov     rax, [rdi + device_t.submit]
    call    rax

    test    rax, rax
    jnz     .cleanup_err            ; Submission failed

.spin_wait:
    ; Spin-wait for completion (polling state)
    mov     rax, [rbx + io_request_t.state]
    cmp     rax, IO_REQ_COMPLETE
    je      .complete
    cmp     rax, IO_REQ_ERROR
    je      .err_status
    cmp     rax, IO_REQ_CANCELLED
    je      .err_cancel
    
    pause                           ; CPU yield hint
    jmp     .spin_wait

.complete:
    xor     rax, rax
    jmp     .cleanup

.err_status:
    mov     rax, [rbx + io_request_t.status]
    jmp     .cleanup

.err_cancel:
    mov     rax, IO_ERR_CANCEL
    jmp     .cleanup

.cleanup_err:
    ; RAX already has submission error status
.cleanup:
    add     rsp, 128
    jmp     .done

.err_badarg:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC bdev_read

; =============================================================================
; bdev_write — Synchronous write sectors to a block device
; In : RDI = -> device_t object
;      RSI = Starting LBA
;      RDX = Count of blocks
;      RCX = -> Source buffer
; Out: RAX = 0 on success, or a negative error band code on failure
; =============================================================================
IO_FUNC bdev_write
    guard_null rdi
    guard_null rcx

    push    rbx
    push    rcx
    push    rdx
    push    rsi
    push    rdi

    ; Check if synchronous write fallback exists
    mov     rax, [rdi + device_t.write]
    test    rax, rax
    jz      .try_async

    ; Call synchronous write directly
    call    rax
    jmp     .done

.try_async:
    ; Synchronous write not available, check for asynchronous submit
    mov     rax, [rdi + device_t.submit]
    test    rax, rax
    jz      .err_badarg

    ; Allocate stack request block
    sub     rsp, 128
    mov     rbx, rsp

    mov     rdi, rbx
    xor     rax, rax
    mov     rcx, 16
    rep     stosq

    pop     rdi
    push    rdi
    mov     [rbx + io_request_t.device], rdi
    mov     qword [rbx + io_request_t.opcode], IO_OP_WRITE
    mov     [rbx + io_request_t.lba], rsi
    mov     [rbx + io_request_t.nblocks], rdx
    mov     qword [rbx + io_request_t.state], IO_REQ_INIT

    lea     rax, [rbx + 96]
    mov     [rax + iovec_t.base], rcx
    mov     [rax + iovec_t.len], rdx
    mov     rsi, [rdi + device_t.sector_size]
    imul    [rax + iovec_t.len], rsi
    mov     [rbx + io_request_t.iov], rax
    mov     qword [rbx + io_request_t.iov_cnt], 1

    ; Submit write request
    mov     rdi, [rbx + io_request_t.device]
    mov     rsi, rbx
    mov     rax, [rdi + device_t.submit]
    call    rax

    test    rax, rax
    jnz     .cleanup_err

.spin_wait:
    mov     rax, [rbx + io_request_t.state]
    cmp     rax, IO_REQ_COMPLETE
    je      .complete
    cmp     rax, IO_REQ_ERROR
    je      .err_status
    cmp     rax, IO_REQ_CANCELLED
    je      .err_cancel
    
    pause
    jmp     .spin_wait

.complete:
    xor     rax, rax
    jmp     .cleanup

.err_status:
    mov     rax, [rbx + io_request_t.status]
    jmp     .cleanup

.err_cancel:
    mov     rax, IO_ERR_CANCEL
    jmp     .cleanup

.cleanup_err:
.cleanup:
    add     rsp, 128
    jmp     .done

.err_badarg:
    mov     rax, IO_ERR_BADARG

.done:
    pop     rdi
    pop     rsi
    pop     rdx
    pop     rcx
    pop     rbx
IO_ENDFUNC bdev_write

%endif ; IO_BLOCK_BDEV_ASM
