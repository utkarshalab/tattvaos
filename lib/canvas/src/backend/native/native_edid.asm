; ============================================================================
; EDID Parser — Extended Display Identification Data
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"

; struct offsets (hoisted above use)
%define EDID_BLOCKS  1
%define EDID_SIZE    128
%define Edid_sizeof  128

extern arena_alloc

section .text


struc Edid
    .header:          resb 8
    .manufacturer:    resw 1
    .product:         resw 1
    .serial:          resd 1
    .week:            resb 1
    .year:            resb 1
    .version:         resb 1
    .revision:        resb 1
    .input_type:      resb 1
    .max_hsize:       resb 1
    .max_vsize:       resb 1
    .gamma:           resb 1
    .features:        resb 1
    .red_x:           resb 1
    .red_y:           resb 1
    .green_x:         resb 1
    .green_y:         resb 1
    .blue_x:          resb 1
    .blue_y:          resb 1
    .white_x:         resb 1
    .white_y:         resb 1
    .est_timings:     resb 3
    .std_timings:     resb 16
    .detailed:        resb 72
    .extensions:      resb 1
    .checksum:        resb 1
endstruc

; ---------------------------------------------------------------------------
; edid_parse
;   Parse EDID data
;   IN:  rdi = edid_data (128 bytes), rsi = Edid*
;   OUT: rax = 0 OK, negative error
; ---------------------------------------------------------------------------
global edid_parse
edid_parse:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Verify header (0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00)
    mov rax, 0x00FFFFFFFFFFFF00
    cmp qword [rbx], rax
    jne .bad_header

    ; Verify checksum
    xor rax, rax
    mov rcx, EDID_SIZE
    mov rsi, rbx
.checksum_loop:
    add al, [rsi]
    inc rsi
    dec rcx
    jnz .checksum_loop
    test al, al
    jnz .bad_checksum

    ; Copy header
    mov rax, [rbx + 8]
    mov [r12 + Edid.manufacturer], ax
    mov rax, [rbx + 10]
    mov [r12 + Edid.product], ax
    mov eax, [rbx + 12]
    mov [r12 + Edid.serial], eax

    mov al, [rbx + 16]
    mov [r12 + Edid.week], al
    mov al, [rbx + 17]
    mov [r12 + Edid.year], al
    mov al, [rbx + 18]
    mov [r12 + Edid.version], al
    mov al, [rbx + 19]
    mov [r12 + Edid.revision], al

    ; Parse detailed timings (offset 54, 72, 90, 108)
    mov r13, rbx
    add r13, 54
    mov r14, 4
.timing_loop:
    call edid_parse_detailed_timing
    add r13, 18
    dec r14
    jnz .timing_loop

    ; Parse extensions
    mov al, [rbx + 126]
    mov [r12 + Edid.extensions], al

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.bad_header:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.bad_checksum:
    mov rax, -(EIO)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; edid_parse_detailed_timing
;   IN:  r13 = timing data (18 bytes)
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
edid_parse_detailed_timing:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, r13

    ; Check if timing descriptor (not monitor descriptor)
    mov al, [rbx]
    mov ah, [rbx + 1]
    test ax, ax
    jz .monitor_desc

    ; Pixel clock (little endian, 10kHz units)
    mov ax, [rbx]
    mov [r12 + Mode.pixel_clock], eax
    shl eax, 14  ; convert to Hz (10kHz * 100000 = Hz, but we store 10kHz)
    mov [r12 + Mode.pixel_clock], eax

    ; Horizontal active
    mov al, [rbx + 2]
    mov ah, [rbx + 4]
    and ah, 0xF0
    shr ah, 4
    mov [r12 + Mode.hactive], ax

    ; Horizontal blanking
    mov al, [rbx + 3]
    mov ah, [rbx + 4]
    and ah, 0x0F
    mov [r12 + Mode.hblank], ax

    ; Vertical active
    mov al, [rbx + 5]
    mov ah, [rbx + 7]
    and ah, 0xF0
    shr ah, 4
    mov [r12 + Mode.vactive], ax

    ; Vertical blanking
    mov al, [rbx + 6]
    mov ah, [rbx + 7]
    and ah, 0x0F
    mov [r12 + Mode.vblank], ax

    ; Sync offsets/widths
    mov al, [rbx + 8]
    mov ah, [rbx + 10]
    and ah, 0xF0
    shr ah, 4
    mov [r12 + Mode.hsync_offset], ax

    mov al, [rbx + 9]
    mov ah, [rbx + 10]
    and ah, 0x0F
    mov [r12 + Mode.hsync_width], ax

    mov al, [rbx + 11]
    mov ah, [rbx + 10]
    and ah, 0xC0
    shr ah, 6
    mov [r12 + Mode.vsync_offset], ax

    mov al, [rbx + 11]
    and al, 0x30
    shr al, 4
    mov [r12 + Mode.vsync_width], al

    ; Image size
    mov ax, [rbx + 12]
    mov [r12 + Mode.width_mm], ax
    mov ax, [rbx + 14]
    mov [r12 + Mode.height_mm], ax

    ; Border
    mov al, [rbx + 16]
    mov [r12 + Mode.hborder], al
    mov al, [rbx + 17]
    mov [r12 + Mode.vborder], al

    ; Flags
    mov al, [rbx + 17]
    mov [r12 + Mode.flags], al

    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

.monitor_desc:
    ; Monitor descriptor (serial, name, etc.) - skip for now
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; edid_find_preferred_mode
;   Decode the first valid detailed timing descriptor (EDID's preferred mode)
;   into a native Mode owned by the backend arena.
;   IN: rdi=raw EDID block, rsi=output
;   OUT: rax=Mode*, or 0 when no detailed timing is advertised
; ---------------------------------------------------------------------------
global edid_find_preferred_mode
edid_find_preferred_mode:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    lea r13, [rbx + 54]
    mov r14d, 4
.find_dtd:
    cmp word [r13], 0
    jne .decode_dtd
    add r13, 18
    dec r14d
    jnz .find_dtd
    xor eax, eax
    jmp .preferred_out
.decode_dtd:
    mov rax, [r12 + Output.backend]
    test rax, rax
    jz .no_mode
    mov rdi, [rax + Backend.arena]
    test rdi, rdi
    jz .no_mode
    mov rsi, Mode_SIZE
    call arena_alloc
    test rax, rax
    jz .no_mode
    mov r15, rax
    mov rdi, r15
    mov rcx, Mode_SIZE / 8
    xor eax, eax
    rep stosq

    ; Active and blanking dimensions.
    movzx eax, byte [r13 + 2]
    movzx ecx, byte [r13 + 4]
    and ecx, 0xF0
    shl ecx, 4
    or eax, ecx
    mov [r15 + Mode.width], rax
    mov r8d, eax
    movzx eax, byte [r13 + 3]
    movzx ecx, byte [r13 + 4]
    and ecx, 0x0F
    shl ecx, 8
    or eax, ecx
    add eax, r8d
    mov [r15 + Mode.htotal], rax

    movzx eax, byte [r13 + 5]
    movzx ecx, byte [r13 + 7]
    and ecx, 0xF0
    shl ecx, 4
    or eax, ecx
    mov [r15 + Mode.height], rax
    mov r9d, eax
    movzx eax, byte [r13 + 6]
    movzx ecx, byte [r13 + 7]
    and ecx, 0x0F
    shl ecx, 8
    or eax, ecx
    add eax, r9d
    mov [r15 + Mode.vtotal], rax

    ; Sync start/end positions, including DTD high bits.
    movzx eax, byte [r13 + 8]
    movzx ecx, byte [r13 + 11]
    and ecx, 0xC0
    shl ecx, 2
    or eax, ecx
    add eax, r8d
    mov [r15 + Mode.hsync_start], rax
    mov r10d, eax
    movzx eax, byte [r13 + 9]
    movzx ecx, byte [r13 + 11]
    and ecx, 0x30
    shl ecx, 4
    or eax, ecx
    add eax, r10d
    mov [r15 + Mode.hsync_end], rax

    movzx eax, byte [r13 + 10]
    shr eax, 4
    movzx ecx, byte [r13 + 11]
    and ecx, 0x0C
    shl ecx, 2
    or eax, ecx
    add eax, r9d
    mov [r15 + Mode.vsync_start], rax
    mov r10d, eax
    movzx eax, byte [r13 + 10]
    and eax, 0x0F
    movzx ecx, byte [r13 + 11]
    and ecx, 0x03
    shl ecx, 4
    or eax, ecx
    add eax, r10d
    mov [r15 + Mode.vsync_end], rax

    movzx eax, word [r13]
    imul rax, 10000
    mov [r15 + Mode.pixel_clock], rax
    movzx eax, byte [r13 + 17]
    xor ecx, ecx
    test eax, 2
    jz .no_hpos
    or ecx, MODE_FLAG_HSYNC_POSITIVE
.no_hpos:
    test eax, 4
    jz .no_vpos
    or ecx, MODE_FLAG_VSYNC_POSITIVE
.no_vpos:
    test eax, 0x80
    jz .not_interlaced
    or ecx, MODE_FLAG_INTERLACED
.not_interlaced:
    mov [r15 + Mode.flags], rcx
    mov [r12 + Output.current_mode], r15
    mov rax, r15
    jmp .preferred_out
.no_mode:
    xor eax, eax
.preferred_out:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global edid_version
edid_version: dq 0x010000
