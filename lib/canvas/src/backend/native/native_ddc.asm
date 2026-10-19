; ============================================================================
; DDC/I2C — Display Data Channel for EDID Reading
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define DDC_ADDR_EDID      0x50
%define DDC_ADDR_EDID_EXT  0x30
%define DDC_SEGMENT_ADDR   0x30

section .text


; ---------------------------------------------------------------------------
; ddc_read_edid
;   Read EDID via DDC/I2C
;   IN:  rdi = backend*, rsi = output*, rdx = edid_buffer (128 bytes)
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global ddc_read_edid
ddc_read_edid:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ASSERT_PTR r13

    ; Get I2C bus for this output
    mov r14, [rbx + Backend.state]
    mov r15, [r14 + Controller.state]
    test r15, r15
    jz .fail

    ; Get I2C bus from output
    mov rax, [r12 + Output.i2c_bus]
    test rax, rax
    jz .no_i2c

    ; Read EDID (128 bytes) from address 0x50
    mov rdi, rax
    mov rsi, DDC_ADDR_EDID
    mov rdx, 0
    mov rcx, 0
    mov r8, r13
    mov r9, 128
    call tv_i2c_read
    test rax, rax
    jnz .fail

    ; Verify EDID checksum
    call edid_verify_checksum
    test rax, rax
    jz .checksum_fail

    ; Check for extensions
    mov al, [r13 + 126]
    test al, al
    jz .done

    ; Read extension blocks
    mov r14, r13
    add r14, 128
    movzx ecx, al
.ext_loop:
    test ecx, ecx
    jz .done

    ; Read extension block
    mov rdi, [r12 + Output.i2c_bus]
    mov rsi, DDC_ADDR_EDID
    mov edx, ecx
    dec edx
    mov r8, r14
    mov r9, 128
    call tv_i2c_read
    test rax, rax
    jnz .fail

    call edid_verify_checksum
    test rax, rax
    jz .checksum_fail

    add r14, 128
    dec ecx
    jmp .ext_loop

.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.no_i2c:
    mov rax, -(ENXIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.checksum_fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.fail:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; edid_verify_checksum
;   Verify EDID block checksum
;   IN:  rdi = edid_buffer (128 bytes)
;   OUT: rax = 1 if valid, 0 if invalid
; ---------------------------------------------------------------------------
edid_verify_checksum:
    PROLOGUE_SAVE rbx, rcx
    mov rbx, rdi
    ASSERT_PTR rbx

    xor rax, rax
    mov rcx, 128
.checksum_loop:
    add al, [rbx]
    inc rbx
    dec rcx
    jnz .checksum_loop

    test al, al
    jnz .invalid
    mov rax, 1
    EPILOGUE_RESTORE rbx, rcx
    ret

.invalid:
    xor rax, rax
    EPILOGUE_RESTORE rbx, rcx
    ret

; ---------------------------------------------------------------------------
; ddc_write
;   Write to DDC/I2C (for MCCS, etc.)
;   IN:  rdi = i2c_bus, rsi = addr, rdx = reg, rcx = data, r8 = len
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global ddc_write
ddc_write:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov r15, r8
    ASSERT_PTR rbx

    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    mov rcx, r14
    mov r8, r15
    call tv_i2c_write
    test rax, rax
    jz .done
    mov rax, -(EIO)
.done:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global ddc_version
ddc_version: dq 0x010000
