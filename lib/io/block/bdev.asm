; =============================================================================
; lib/io/block/bdev.asm
; Uniform block device read/write synchronization layer.
;
; Part of Utkarsha Labs / Utkarsha OS
; Arch: x86_64 | Assembler: NASM
; =============================================================================

%ifndef IO_BLOCK_BDEV_ASM
%define IO_BLOCK_BDEV_ASM

%include "lib/io/macro/func.asm"
%include "lib/io/macro/guard.asm"
%include "lib/io/io.inc"
%include "lib/io/error/codes.asm"

section .text

; Stack frame for the asynchronous path: one io_request_t followed by the
; single iovec_t it points at, rounded up to keep RSP 16-byte aligned.
%define BDEV_IOV_OFF    io_request_t_size
%define BDEV_FRAME      ((io_request_t_size + iovec_t_size + 15) & ~15)

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
    mov     r8d, IO_OP_READ
    mov     r9d, device_t.read
    jmp     bdev_rw
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
    mov     r8d, IO_OP_WRITE
    mov     r9d, device_t.write
    jmp     bdev_rw
IO_ENDFUNC bdev_write

; -----------------------------------------------------------------------------
; bdev_rw — shared body of bdev_read / bdev_write
; In : RDI = device, RSI = LBA, RDX = block count, RCX = buffer,
;      R8 = IO_OP_READ / IO_OP_WRITE,
;      R9 = offset of the synchronous handler in device_t (.read / .write)
; Out: RAX = 0 on success, or a negative error band code on failure
;
; Uses the device's synchronous handler when it has one; otherwise builds an
; io_request_t on the stack, submits it, and polls until it finishes.
; -----------------------------------------------------------------------------
bdev_rw:
    push    rbx
    push    r12
    push    r13
    push    r14
    push    r15

    mov     rbx, rdi                ; device
    mov     r12, rsi                ; LBA
    mov     r13, rdx                ; block count
    mov     r14, rcx                ; buffer
    mov     r15, r8                 ; opcode

    mov     rax, [rbx + r9]         ; synchronous handler
    test    rax, rax
    jz      .try_async
    ; handler(dev, lba, count, buf): RDI..RCX still hold the arguments
    call    rax
    jmp     .done

.try_async:
    cmp     qword [rbx + device_t.submit], 0
    je      .err_badarg

    sub     rsp, BDEV_FRAME
    mov     rdi, rsp
    xor     eax, eax
    mov     ecx, BDEV_FRAME / 8
    rep     stosq                   ; zero the request and its iovec

    mov     [rsp + io_request_t.device], rbx
    mov     [rsp + io_request_t.opcode], r15
    mov     [rsp + io_request_t.lba], r12
    mov     [rsp + io_request_t.nblocks], r13
    mov     qword [rsp + io_request_t.state], IO_REQ_INIT

    ; One iovec covering the whole transfer: count * sector_size bytes
    lea     rax, [rsp + BDEV_IOV_OFF]
    mov     [rax + iovec_t.base], r14
    mov     rdx, r13
    imul    rdx, [rbx + device_t.sector_size]
    mov     [rax + iovec_t.len], rdx
    mov     [rsp + io_request_t.iov], rax
    mov     qword [rsp + io_request_t.iov_cnt], 1

    ; submit(dev, req)
    mov     rdi, rbx
    mov     rsi, rsp
    call    [rbx + device_t.submit]
    test    rax, rax
    jnz     .cleanup                ; submission failed: RAX = its error

.spin_wait:
    mov     rax, [rsp + io_request_t.state]
    cmp     rax, IO_REQ_COMPLETE
    je      .complete
    cmp     rax, IO_REQ_ERROR
    je      .err_status
    cmp     rax, IO_REQ_CANCELLED
    je      .err_cancel
    cmp     rax, IO_REQ_TIMEOUT
    je      .err_timeout
    pause                           ; CPU yield hint
    jmp     .spin_wait

.complete:
    xor     eax, eax
    jmp     .cleanup
.err_status:
    mov     rax, [rsp + io_request_t.status]
    jmp     .cleanup
.err_cancel:
    mov     rax, IO_ERR_CANCEL
    jmp     .cleanup
.err_timeout:
    mov     rax, IO_ERR_TIMEOUT

.cleanup:
    add     rsp, BDEV_FRAME
    jmp     .done

.err_badarg:
    mov     rax, IO_ERR_BADARG

.done:
    pop     r15
    pop     r14
    pop     r13
    pop     r12
    pop     rbx
    ret

%endif ; IO_BLOCK_BDEV_ASM
