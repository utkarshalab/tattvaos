; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/res.asm
; =============================================================================
; Resource templates (_CRS, _PRS): the descriptors a device's buffer holds,
; decoded one at a time into a fixed 56-byte record.
;
;   aml_get_crs(node, value*)            the device's _CRS buffer
;   aml_res_next(buf, len, &offset, res*) the next descriptor: 1, 0 at the
;                                         end, or a negative error
;
; aml_res_next needs nothing from the interpreter, so drivers can decode a
; template while AML runs elsewhere. Every descriptor is checked against
; the buffer and its own minimum length; offsets inside GPIO and serial
; bus descriptors are checked against the descriptor.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_RES_ASM
%define LIB_IO_ACPI_AML_RES_ASM

; ---- the decoded record ------------------------------------------------------
%define AML_RES_IRQ         1   ; base = lowest IRQ, count, extra = mask or u32*
%define AML_RES_DMA         2   ; base = lowest channel, extra = mask
%define AML_RES_IO          3   ; base = minimum, len = length, extra = maximum
%define AML_RES_FIXED_IO    4   ; base, len
%define AML_RES_MEM24       5   ; base = minimum, len = length, extra = maximum
%define AML_RES_MEM32       6   ; base = minimum, len = length, extra = maximum
%define AML_RES_FIXED_MEM32 7   ; base, len
%define AML_RES_ADDRESS     8   ; sub = 0 memory, 1 I/O, 2 bus numbers;
                                ; base = minimum, len = length,
                                ; extra = translation offset
%define AML_RES_EXT_IRQ     9   ; base = first IRQ, count, extra = u32* list
%define AML_RES_GPIO_INT    10  ; base = first pin, count, extra = u16* pins,
                                ; len = int flags | debounce << 16 |
                                ;       pin config << 32
%define AML_RES_GPIO_IO     11  ; as GPIO_INT, len low 16 = I/O flags
%define AML_RES_I2C         12  ; base = target address, len = speed (Hz)
%define AML_RES_SPI         13  ; base = chip select, len = speed (Hz),
                                ; extra = bits | phase << 8 | polarity << 16
%define AML_RES_UART        14  ; len = baud, extra = rx fifo | tx fifo << 16
                                ;       | parity << 32 | lines << 40
%define AML_RES_CSI2        15
%define AML_RES_REGISTER    16  ; sub = space, base = address, len = bit width,
                                ; extra = bit offset | access size << 8
%define AML_RES_FIXED_DMA   17  ; base = request line, len = channel,
                                ; extra = transfer width
%define AML_RES_VENDOR      18
%define AML_RES_PIN         19  ; pin function / config / group: sub = type
%define AML_RES_CLOCK       20
%define AML_RES_START_DEP   21
%define AML_RES_END_DEP     22

; flags for interrupts (IRQ, Extended IRQ, GPIO interrupt)
%define AML_RES_EDGE        (1 << 0)
%define AML_RES_ACTIVE_LOW  (1 << 1)
%define AML_RES_SHARED      (1 << 2)
%define AML_RES_WAKE        (1 << 3)
%define AML_RES_BOTH_EDGES  (1 << 4)    ; GPIO: active on both edges
; flags for memory and serial buses
%define AML_RES_WRITABLE    (1 << 0)    ; memory
%define AML_RES_10BIT       (1 << 0)    ; I2C: 10-bit addressing

struc aml_res
    .kind:      resb 1          ; AML_RES_*
    .flags:     resb 1
    .sub:       resb 1
    .pad:       resb 1
    .count:     resd 1
    .base:      resq 1
    .len:       resq 1
    .extra:     resq 1
    .source:    resq 1          ; resource source name (NUL-terminated), or 0
    .raw:       resq 1          ; the descriptor itself
    .raw_len:   resd 1          ; its length, header included
    .pad2:      resd 1
endstruc                        ; 56 bytes

section .text

; -----------------------------------------------------------------------------
; aml_get_crs — a device's current resources
; Input:  RDI = device node, RSI = destination value* (a buffer)
; Output: EAX = 0; -AML_ENOTFOUND without _CRS; -AML_ETYPE when it is not a
;         buffer; or an error from running it
; -----------------------------------------------------------------------------
global aml_get_crs
aml_get_crs:
    push rbx
    push r12
    push r15
    mov rbx, rdi
    mov r12, rsi
    AML_BEGIN
    call aml_top_frame
    test rax, rax
    jz .oom
    mov r15, rax
    mov rdi, rbx
    mov esi, AML_SEG('_','C','R','S')
    mov rdx, r12
    call aml_eval_child
    cmp eax, AML_NO_CHILD
    je .missing
    test eax, eax
    jnz .out
    cmp byte [r12 + aml_value.type], AML_T_BUFFER
    jne .type
    xor eax, eax
    jmp .out
.missing:
    mov eax, -AML_ENOTFOUND
    jmp .out
.type:
    mov eax, -AML_ETYPE
    jmp .out
.oom:
    mov eax, -AML_ENOMEM
.out:
    pop r15
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_res_next — decode the descriptor at *offset and move past it
; Input:  RDI = template bytes, ESI = template length, RDX = u32* offset,
;         RCX = aml_res* to fill
; Output: EAX = 1 with a descriptor; 0 at the end tag or the end of the
;         buffer; -AML_EBADCODE for a malformed descriptor
; -----------------------------------------------------------------------------
global aml_res_next
aml_res_next:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; buffer
    mov r13d, esi                       ; its length
    mov r14, rdx                        ; offset*
    mov r15, rcx                        ; record
    ; clear the record
    mov rdi, r15
    xor eax, eax
    mov ecx, aml_res_size / 8
    rep stosq
    mov ebx, [r14]                      ; offset
    cmp ebx, r13d
    jae .end
    lea rsi, [r12 + rbx]                ; the descriptor
    mov [r15 + aml_res.raw], rsi
    movzx eax, byte [rsi]
    test al, 0x80
    jnz .large
    ; ---- small: type in bits 6-3, length in bits 2-0 ----
    mov ecx, eax
    and ecx, 7
    lea edx, [rcx + 1]                  ; descriptor length
    lea r8d, [rbx + rdx]
    cmp r8d, r13d
    ja .bad
    mov [r15 + aml_res.raw_len], edx
    mov [r14], r8d                      ; past it
    shr eax, 3
    and eax, 0x0F
    lea rsi, [rsi + 1]                  ; data
    cmp eax, 0x0F
    je .end
    cmp eax, 0x04
    je .irq
    cmp eax, 0x05
    je .dma
    cmp eax, 0x06
    je .start_dep
    cmp eax, 0x07
    je .end_dep
    cmp eax, 0x08
    je .io
    cmp eax, 0x09
    je .fixed_io
    cmp eax, 0x0A
    je .fixed_dma
    cmp eax, 0x0E
    je .vendor
    jmp .bad

.irq:
    ; mask (2), optional flags (1)
    cmp ecx, 2
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_IRQ
    movzx eax, word [rsi]
    mov [r15 + aml_res.extra], rax
    popcnt edx, eax
    mov [r15 + aml_res.count], edx
    test eax, eax
    jz .irq_flags
    bsf edx, eax
    mov [r15 + aml_res.base], rdx
.irq_flags:
    mov al, AML_RES_EDGE                ; no flags byte: edge, active high
    cmp ecx, 3
    jb .irq_set
    movzx edx, byte [rsi + 2]
    xor eax, eax
    test dl, 1
    jz .irq_low
    or al, AML_RES_EDGE
.irq_low:
    test dl, 8
    jz .irq_shared
    or al, AML_RES_ACTIVE_LOW
.irq_shared:
    test dl, 0x10
    jz .irq_wake
    or al, AML_RES_SHARED
.irq_wake:
    test dl, 0x20
    jz .irq_set
    or al, AML_RES_WAKE
.irq_set:
    mov [r15 + aml_res.flags], al
    jmp .ok

.dma:
    cmp ecx, 2
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_DMA
    movzx eax, byte [rsi]
    mov [r15 + aml_res.extra], rax
    popcnt edx, eax
    mov [r15 + aml_res.count], edx
    test eax, eax
    jz .dma_flags
    bsf edx, eax
    mov [r15 + aml_res.base], rdx
.dma_flags:
    mov al, [rsi + 1]
    mov [r15 + aml_res.sub], al
    jmp .ok

.start_dep:
    mov byte [r15 + aml_res.kind], AML_RES_START_DEP
    jmp .ok
.end_dep:
    mov byte [r15 + aml_res.kind], AML_RES_END_DEP
    jmp .ok

.io:
    ; information, minimum (2), maximum (2), alignment, length
    cmp ecx, 7
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_IO
    mov al, [rsi]
    mov [r15 + aml_res.sub], al         ; bit 0: 16-bit decode
    movzx eax, word [rsi + 1]
    mov [r15 + aml_res.base], rax
    movzx eax, word [rsi + 3]
    mov [r15 + aml_res.extra], rax
    movzx eax, byte [rsi + 6]
    mov [r15 + aml_res.len], rax
    jmp .ok

.fixed_io:
    cmp ecx, 3
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_FIXED_IO
    movzx eax, word [rsi]
    and eax, 0x3FF                      ; ten address bits
    mov [r15 + aml_res.base], rax
    movzx eax, byte [rsi + 2]
    mov [r15 + aml_res.len], rax
    jmp .ok

.fixed_dma:
    cmp ecx, 5
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_FIXED_DMA
    movzx eax, word [rsi]
    mov [r15 + aml_res.base], rax
    movzx eax, word [rsi + 2]
    mov [r15 + aml_res.len], rax
    movzx eax, byte [rsi + 4]
    mov [r15 + aml_res.extra], rax
    jmp .ok

.vendor:
    mov byte [r15 + aml_res.kind], AML_RES_VENDOR
    mov [r15 + aml_res.count], ecx
    jmp .ok

    ; ---- large: type in bits 6-0, a 16-bit length ----
.large:
    lea r8d, [rbx + 3]
    cmp r8d, r13d
    ja .bad
    movzx ecx, word [rsi + 1]           ; data length
    lea edx, [rcx + 3]
    lea r8d, [rbx + rdx]
    cmp r8d, r13d
    ja .bad
    mov [r15 + aml_res.raw_len], edx
    mov [r14], r8d
    and eax, 0x7F
    mov r9, rsi                         ; descriptor start (for offsets)
    lea rsi, [rsi + 3]                  ; data
    cmp eax, 0x01
    je .mem24
    cmp eax, 0x02
    je .register
    cmp eax, 0x04
    je .vendor
    cmp eax, 0x05
    je .mem32
    cmp eax, 0x06
    je .fixed_mem32
    cmp eax, 0x07
    je .dword_addr
    cmp eax, 0x08
    je .word_addr
    cmp eax, 0x09
    je .ext_irq
    cmp eax, 0x0A
    je .qword_addr
    cmp eax, 0x0B
    je .ext_addr
    cmp eax, 0x0C
    je .gpio
    cmp eax, 0x0E
    je .serial
    cmp eax, 0x0D
    je .pin
    cmp eax, 0x0F
    jb .bad
    cmp eax, 0x12
    jbe .pin
    cmp eax, 0x13
    je .clock
    jmp .bad

.mem24:
    ; information, minimum, maximum, alignment, length: 16-bit, in 256s
    cmp ecx, 9
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_MEM24
    movzx eax, byte [rsi]
    and eax, 1
    mov [r15 + aml_res.flags], al
    movzx eax, word [rsi + 1]
    shl rax, 8
    mov [r15 + aml_res.base], rax
    movzx eax, word [rsi + 3]
    shl rax, 8
    mov [r15 + aml_res.extra], rax
    movzx eax, word [rsi + 7]
    shl rax, 8
    mov [r15 + aml_res.len], rax
    jmp .ok

.register:
    ; space, bit width, bit offset, access size, address (8)
    cmp ecx, 12
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_REGISTER
    mov al, [rsi]
    mov [r15 + aml_res.sub], al
    movzx eax, byte [rsi + 1]
    mov [r15 + aml_res.len], rax
    movzx eax, byte [rsi + 2]
    movzx edx, byte [rsi + 3]
    shl edx, 8
    or eax, edx
    mov [r15 + aml_res.extra], rax
    mov rax, [rsi + 4]
    mov [r15 + aml_res.base], rax
    jmp .ok

.mem32:
    ; information, minimum, maximum, alignment, length: 32-bit
    cmp ecx, 17
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_MEM32
    movzx eax, byte [rsi]
    and eax, 1
    mov [r15 + aml_res.flags], al
    mov eax, [rsi + 1]
    mov [r15 + aml_res.base], rax
    mov eax, [rsi + 5]
    mov [r15 + aml_res.extra], rax
    mov eax, [rsi + 13]
    mov [r15 + aml_res.len], rax
    jmp .ok

.fixed_mem32:
    cmp ecx, 9
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_FIXED_MEM32
    movzx eax, byte [rsi]
    and eax, 1
    mov [r15 + aml_res.flags], al
    mov eax, [rsi + 1]
    mov [r15 + aml_res.base], rax
    mov eax, [rsi + 5]
    mov [r15 + aml_res.len], rax
    jmp .ok

    ; Address descriptors: type, general flags, type flags, then five
    ; fields (granularity, minimum, maximum, translation, length) of 2, 4
    ; or 8 bytes, then an optional resource source.
.word_addr:
    mov r10d, 2
    jmp .address
.dword_addr:
    mov r10d, 4
    jmp .address
.qword_addr:
    mov r10d, 8
.address:
    lea eax, [r10 * 5 + 3]              ; fixed part
    cmp ecx, eax
    jb .bad
    mov r11d, eax                       ; where the source starts
    mov byte [r15 + aml_res.kind], AML_RES_ADDRESS
    mov al, [rsi]
    mov [r15 + aml_res.sub], al
    lea rdi, [rsi + 3]                  ; granularity
    mov edx, r10d
    lea rax, [rdi + rdx]                ; minimum
    call aml_res_field
    mov [r15 + aml_res.base], rax
    lea rax, [rdi + rdx * 2]
    lea rax, [rax + rdx]                ; translation (4th)
    call aml_res_field
    mov [r15 + aml_res.extra], rax
    lea rax, [rdi + rdx * 4]            ; length (5th)
    call aml_res_field
    mov [r15 + aml_res.len], rax
    jmp .source_after

.ext_addr:
    ; type, flags, flags, revision, reserved, then six 8-byte fields
    cmp ecx, 53
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_ADDRESS
    mov al, [rsi]
    mov [r15 + aml_res.sub], al
    mov rax, [rsi + 13]
    mov [r15 + aml_res.base], rax
    mov rax, [rsi + 29]
    mov [r15 + aml_res.extra], rax
    mov rax, [rsi + 37]
    mov [r15 + aml_res.len], rax
    jmp .ok

.ext_irq:
    ; flags, count, count × u32, optional resource source
    cmp ecx, 2
    jb .bad
    movzx eax, byte [rsi + 1]
    test eax, eax
    jz .bad
    lea r11d, [rax * 4 + 2]
    cmp ecx, r11d
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_EXT_IRQ
    mov [r15 + aml_res.count], eax
    lea rax, [rsi + 2]
    mov [r15 + aml_res.extra], rax
    mov eax, [rsi + 2]
    mov [r15 + aml_res.base], rax
    movzx edx, byte [rsi]
    xor eax, eax
    test dl, 2
    jz .xirq_low
    or al, AML_RES_EDGE
.xirq_low:
    test dl, 4
    jz .xirq_shared
    or al, AML_RES_ACTIVE_LOW
.xirq_shared:
    test dl, 8
    jz .xirq_wake
    or al, AML_RES_SHARED
.xirq_wake:
    test dl, 0x10
    jz .xirq_set
    or al, AML_RES_WAKE
.xirq_set:
    mov [r15 + aml_res.flags], al
    ; fall into the optional source
.source_after:
    ; a resource source index and a NUL-terminated name may follow the
    ; fixed part (R11D bytes into the data); only when more than the
    ; index byte is present
    lea eax, [r11 + 1]
    cmp ecx, eax
    jbe .ok
    lea rax, [rsi + r11 + 1]
    mov rdi, rax
    lea r8, [rsi + rcx]                 ; end of the descriptor
    call aml_res_string
    jmp .ok

.gpio:
    ; rev, type, general flags (2), int/io flags (2), pin config,
    ; drive strength (2), debounce (2), pin table offset (2), source index,
    ; source name offset (2), vendor offset (2), vendor length (2)
    cmp ecx, 20
    jb .bad
    movzx eax, byte [rsi + 1]
    mov edx, AML_RES_GPIO_INT
    test eax, eax
    jz .gpio_kind
    mov edx, AML_RES_GPIO_IO
.gpio_kind:
    mov [r15 + aml_res.kind], dl
    movzx eax, word [rsi + 4]           ; int / io flags
    movzx edx, word [rsi + 9]           ; debounce timeout
    shl rdx, 16
    or rax, rdx
    movzx edx, byte [rsi + 6]           ; pin configuration
    shl rdx, 32
    or rax, rdx
    mov [r15 + aml_res.len], rax
    cmp byte [r15 + aml_res.kind], AML_RES_GPIO_INT
    jne .gpio_pins
    movzx edx, word [rsi + 4]
    xor eax, eax
    test dl, 1
    jz .gpio_pol
    or al, AML_RES_EDGE
.gpio_pol:
    mov r10d, edx
    shr r10d, 1
    and r10d, 3
    cmp r10d, 1
    jne .gpio_both
    or al, AML_RES_ACTIVE_LOW
.gpio_both:
    cmp r10d, 2
    jne .gpio_shared
    or al, AML_RES_BOTH_EDGES
.gpio_shared:
    test dl, 8
    jz .gpio_wake
    or al, AML_RES_SHARED
.gpio_wake:
    test dl, 0x10
    jz .gpio_flags
    or al, AML_RES_WAKE
.gpio_flags:
    mov [r15 + aml_res.flags], al
.gpio_pins:
    ; pins run from the pin table to the source name, u16 each; offsets
    ; count from the descriptor's first byte
    movzx eax, word [rsi + 11]          ; pin table
    movzx edx, word [rsi + 14]          ; source name
    lea r10d, [rcx + 3]                 ; descriptor length
    cmp eax, edx
    ja .bad
    cmp edx, r10d
    ja .bad
    cmp eax, 23
    jb .bad
    mov r11d, edx
    sub r11d, eax
    shr r11d, 1
    mov [r15 + aml_res.count], r11d
    lea r8, [r9 + rax]
    mov [r15 + aml_res.extra], r8
    test r11d, r11d
    jz .gpio_source
    movzx r8d, word [r8]
    mov [r15 + aml_res.base], r8
.gpio_source:
    cmp edx, r10d
    jae .ok
    lea rdi, [r9 + rdx]
    movzx eax, word [rsi + 16]          ; vendor data offset ends the name
    lea r8, [r9 + r10]
    test eax, eax
    jz .gpio_name
    cmp eax, edx
    jbe .gpio_name
    cmp eax, r10d
    ja .gpio_name
    lea r8, [r9 + rax]
.gpio_name:
    call aml_res_string
    jmp .ok

.serial:
    ; rev, source index, bus type, general flags, type flags (2),
    ; type revision, type data length (2), type data, vendor data,
    ; source name to the end
    cmp ecx, 9
    jb .bad
    movzx edx, word [rsi + 7]           ; type data length
    lea r11d, [rdx + 9]
    cmp ecx, r11d
    jb .bad
    movzx eax, byte [rsi + 2]
    mov [r15 + aml_res.sub], al
    movzx r10d, word [rsi + 4]          ; type flags
    lea rdi, [rsi + 9]                  ; type data
    cmp eax, 1
    je .i2c
    cmp eax, 2
    je .spi
    cmp eax, 3
    je .uart
    cmp eax, 4
    je .csi2
    jmp .bad
.i2c:
    cmp edx, 6
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_I2C
    mov eax, [rdi]
    mov [r15 + aml_res.len], rax
    movzx eax, word [rdi + 4]
    mov [r15 + aml_res.base], rax
    mov eax, r10d
    and eax, AML_RES_10BIT
    mov [r15 + aml_res.flags], al
    jmp .serial_source
.spi:
    cmp edx, 9
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_SPI
    mov eax, [rdi]
    mov [r15 + aml_res.len], rax
    movzx eax, byte [rdi + 4]           ; data bits
    movzx r8d, byte [rdi + 5]           ; clock phase
    shl r8d, 8
    or eax, r8d
    movzx r8d, byte [rdi + 6]           ; clock polarity
    shl r8d, 16
    or eax, r8d
    mov [r15 + aml_res.extra], rax
    movzx eax, word [rdi + 7]
    mov [r15 + aml_res.base], rax
    mov eax, r10d
    and eax, 3                          ; wire mode, device polarity
    mov [r15 + aml_res.flags], al
    jmp .serial_source
.uart:
    cmp edx, 10
    jb .bad
    mov byte [r15 + aml_res.kind], AML_RES_UART
    mov eax, [rdi]
    mov [r15 + aml_res.len], rax
    movzx eax, word [rdi + 4]           ; receive FIFO
    movzx r8d, word [rdi + 6]           ; transmit FIFO
    shl r8, 16
    or rax, r8
    movzx r8d, byte [rdi + 8]           ; parity
    shl r8, 32
    or rax, r8
    movzx r8d, byte [rdi + 9]           ; lines in use
    shl r8, 40
    or rax, r8
    mov [r15 + aml_res.extra], rax
    mov [r15 + aml_res.base], r10       ; flow control, stop and data bits
    jmp .serial_source
.csi2:
    mov byte [r15 + aml_res.kind], AML_RES_CSI2
.serial_source:
    ; the source name follows the type data
    lea eax, [r11 + 1]
    cmp ecx, eax
    jb .ok
    lea rdi, [rsi + r11]
    lea r8, [rsi + rcx]
    call aml_res_string
    jmp .ok

.pin:
    mov byte [r15 + aml_res.kind], AML_RES_PIN
    mov [r15 + aml_res.sub], al
    jmp .ok
.clock:
    mov byte [r15 + aml_res.kind], AML_RES_CLOCK
    jmp .ok

.ok:
    mov eax, 1
    jmp .out
.end:
    xor eax, eax
    jmp .out
.bad:
    mov eax, -AML_EBADCODE
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; aml_res_field — a little-endian field of EDX bytes (2, 4 or 8) at RAX
; Output: RAX
; Clobbers: RAX only
; -----------------------------------------------------------------------------
aml_res_field:
    cmp edx, 2
    je .w
    cmp edx, 4
    je .d
    mov rax, [rax]
    ret
.w:
    movzx eax, word [rax]
    ret
.d:
    mov eax, [rax]
    ret

; -----------------------------------------------------------------------------
; aml_res_string — record a resource source name that is NUL-terminated
;                  before R8; a name with no NUL in range is not recorded
; Input:  RDI = start, R8 = end, R15 = the record
; Clobbers: RAX
; -----------------------------------------------------------------------------
aml_res_string:
    mov rax, rdi
.scan:
    cmp rax, r8
    jae .none
    cmp byte [rax], 0
    je .found
    inc rax
    jmp .scan
.found:
    cmp rax, rdi
    je .none                            ; empty name
    mov [r15 + aml_res.source], rdi
.none:
    ret

%endif ; LIB_IO_ACPI_AML_RES_ASM
