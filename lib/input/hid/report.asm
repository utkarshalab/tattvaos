; =============================================================================
; Utkarsha OS — lib/input/hid/report.asm — keyboards and mice in report
; protocol
; =============================================================================
; For keyboards and mice whose reports are not (only) the boot ones: what
; their report descriptor says, kept small, for every HID transport.
;
;   hid_rmap_prepare(desc, map)   the input fields of Keyboard and Keypad
;                       collections (keys: modifiers, arrays, n-key bitmaps)
;                       and of Mouse and Pointer collections (buttons, X, Y,
;                       wheel, horizontal scroll), and where the keyboard's
;                       LED output report is. EAX = HID_RMAP_KEYBOARD |
;                       HID_RMAP_POINTER for what it found.
;   hid_rmap_keyboard(map, report, len, out)  a keyboard report as the
;                       8-byte boot report (modifiers, 0, six keys; more
;                       than six held: ErrorRollOver), so the boot handling,
;                       LEDs and the new-keyboard check work unchanged.
;                       EAX = 1 when the report was the keyboard's.
;   hid_rmap_pointer(map, report, len)    motion, wheel, horizontal scroll
;                       and up to 8 buttons as events. EAX = 1 when it was
;                       the pointer's.
; A report cut short is ignored.
; =============================================================================

%ifndef LIB_INPUT_HID_REPORT_ASM
%define LIB_INPUT_HID_REPORT_ASM

%define HID_RMAP_FIELDS     12
%define HID_RMAP_USAGES     96
%define HID_RMAP_KEYBOARD   1
%define HID_RMAP_POINTER    2

%define HID_APP_POINTER     0x00010001
%define HID_APP_MOUSE       0x00010002
%define HID_APP_KEYBOARD    0x00010006
%define HID_APP_KEYPAD      0x00010007

struc hid_rmap
    .dev:           resd 1          ; lib/input device ID (pointer events)
    .uses_ids:      resd 1
    .nfields:       resd 1
    .nusages:       resd 1
    .has:           resd 1          ; HID_RMAP_*
    .led_id:        resd 1          ; the LED output report's ID
    .has_led:       resd 1
    .buttons:       resd 1          ; pointer buttons down
    .fields:        resb HID_RMAP_FIELDS * hid_field_size
    .usages:        resd HID_RMAP_USAGES
    .role:          resb HID_RMAP_FIELDS    ; HID_RMAP_KEYBOARD or _POINTER
    .kbd_ids:       resb 32         ; report IDs with keyboard fields (bits)
    .ptr_ids:       resb 32         ; ... with pointer fields
endstruc

section .text

; hid_rmap_usage — the usage at index ECX of field RSI in map RBX (list or
; range), EAX = usage or 0 past the end
hid_rmap_usage:
    movzx eax, word [rsi + hid_field.usage_count]
    test eax, eax
    jz .range
    cmp ecx, eax
    jb .listed
    xor eax, eax
    ret
.listed:
    movzx eax, word [rsi + hid_field.usage_list]
    add eax, ecx
    mov eax, [rbx + hid_rmap.usages + rax * 4]
    ret
.range:
    mov eax, [rsi + hid_field.usage_min]
    add eax, ecx
    cmp eax, [rsi + hid_field.usage_max]
    jbe .out
    xor eax, eax
.out:
    ret

; hid_rmap_page — EAX = the usage page of field RSI's first usage (desc RDI)
hid_rmap_page:
    movzx eax, word [rsi + hid_field.usage_count]
    test eax, eax
    jz .range
    movzx eax, word [rsi + hid_field.usage_list]
    mov eax, [rdi + hid_desc.usages + rax * 4]
    shr eax, 16
    ret
.range:
    mov eax, [rsi + hid_field.usage_min]
    shr eax, 16
    ret

; -----------------------------------------------------------------------------
; hid_rmap_prepare
; Input:  RDI = hid_desc* (parsed), RSI = hid_rmap* to fill
; Output: EAX = HID_RMAP_* found
; -----------------------------------------------------------------------------
global hid_rmap_prepare
hid_rmap_prepare:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov rbx, rsi
    mov r14d, [rbx + hid_rmap.dev]
    mov rdi, rbx
    mov ecx, hid_rmap_size
    xor eax, eax
    rep stosb
    mov [rbx + hid_rmap.dev], r14d
    mov eax, [r12 + hid_desc.uses_ids]
    mov [rbx + hid_rmap.uses_ids], eax
    xor r13d, r13d
.field:
    cmp r13d, [r12 + hid_desc.field_count]
    jae .done
    mov eax, r13d
    imul eax, eax, hid_field_size
    lea rsi, [r12 + hid_desc.fields + rax]
    inc r13d
    test word [rsi + hid_field.flags], HID_F_CONST
    jnz .field
    mov eax, [rsi + hid_field.application]
    cmp eax, HID_APP_KEYBOARD
    je .keyboard
    cmp eax, HID_APP_KEYPAD
    je .keyboard
    cmp eax, HID_APP_MOUSE
    je .pointer
    cmp eax, HID_APP_POINTER
    jne .field
.pointer:
    cmp byte [rsi + hid_field.kind], HID_INPUT
    jne .field
    mov rdi, r12
    call hid_rmap_page
    cmp eax, 0x09                       ; buttons
    je .ptr_keep
    cmp eax, 0x01                       ; X, Y, wheel
    je .ptr_rel
    cmp eax, 0x0C                       ; AC Pan
    jne .field
.ptr_rel:
    test word [rsi + hid_field.flags], HID_F_RELATIVE
    jz .field                           ; absolute: a tablet, not a mouse
.ptr_keep:
    mov r15d, HID_RMAP_POINTER
    jmp .keep
.keyboard:
    mov rdi, r12
    call hid_rmap_page
    cmp byte [rsi + hid_field.kind], HID_OUTPUT
    jne .kbd_input
    cmp eax, 0x08                       ; the LEDs
    jne .field
    movzx eax, byte [rsi + hid_field.report_id]
    mov [rbx + hid_rmap.led_id], eax
    mov dword [rbx + hid_rmap.has_led], 1
    jmp .field
.kbd_input:
    cmp byte [rsi + hid_field.kind], HID_INPUT
    jne .field
    cmp eax, 0x07
    jne .field
    mov r15d, HID_RMAP_KEYBOARD
.keep:
    cmp dword [rbx + hid_rmap.nfields], HID_RMAP_FIELDS
    jae .field
    movzx ecx, word [rsi + hid_field.usage_count]
    mov eax, [rbx + hid_rmap.nusages]
    add eax, ecx
    cmp eax, HID_RMAP_USAGES
    ja .field
    mov eax, [rbx + hid_rmap.nfields]
    mov [rbx + hid_rmap.role + rax], r15b
    imul eax, eax, hid_field_size
    lea rdi, [rbx + hid_rmap.fields + rax]
    push rsi
    push rdi
    mov ecx, hid_field_size
    rep movsb
    pop rdi
    pop rsi
    movzx ecx, word [rsi + hid_field.usage_count]
    movzx edx, word [rsi + hid_field.usage_list]
    mov eax, [rbx + hid_rmap.nusages]
    mov [rdi + hid_field.usage_list], ax
.usage:
    test ecx, ecx
    jz .kept
    mov r8d, [r12 + hid_desc.usages + rdx * 4]
    mov r9d, [rbx + hid_rmap.nusages]
    mov [rbx + hid_rmap.usages + r9 * 4], r8d
    inc dword [rbx + hid_rmap.nusages]
    inc edx
    dec ecx
    jmp .usage
.kept:
    inc dword [rbx + hid_rmap.nfields]
    or [rbx + hid_rmap.has], r15d
    movzx eax, byte [rsi + hid_field.report_id]
    cmp r15d, HID_RMAP_KEYBOARD
    jne .ptr_id
    bts [rbx + hid_rmap.kbd_ids], eax
    jmp .field
.ptr_id:
    bts [rbx + hid_rmap.ptr_ids], eax
    jmp .field
.done:
    mov eax, [rbx + hid_rmap.has]
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; hid_rmap_id — RBX = map, R12 = report, R13D = length → EBP = its report
; ID, R12/R13 past it; CF = 1 when there is nothing
hid_rmap_id:
    xor ebp, ebp
    cmp dword [rbx + hid_rmap.uses_ids], 0
    je .ok
    test r13d, r13d
    jz .none
    movzx ebp, byte [r12]
    inc r12
    dec r13d
.ok:
    clc
    ret
.none:
    stc
    ret

; hid_rmap_value — element ECX of field R15 from the report (R12, R13D)
; Output: CF = 1 past the report's end; else RDX = the value
hid_rmap_value:
    push rcx
    mov rdi, r12
    mov esi, r13d
    mov rdx, r15
    call hid_get
    pop rcx
    test eax, eax
    jnz .short
    clc
    ret
.short:
    stc
    ret

; hid_rmap_element — the usage element ECX of field R15 stands for now:
; a variable one when its value is not 0, an array one from its value
; Output: EAX = usage (0: nothing), RDX = the value; CF = 1 cut short
hid_rmap_element:
    push rcx
    sub rsp, 8
    call hid_rmap_value
    jc .short
    test word [r15 + hid_field.flags], HID_F_VARIABLE
    jz .array
    xor eax, eax
    test rdx, rdx
    jz .out
    mov rcx, [rsp + 8]
    mov rsi, r15
    push rdx
    call hid_rmap_usage
    pop rdx
    jmp .out
.array:
    movsxd rax, dword [r15 + hid_field.logical_min]
    mov rcx, rdx
    sub rcx, rax
    js .none
    movsxd r8, dword [r15 + hid_field.logical_max]
    sub r8, rax
    cmp rcx, r8
    jg .none
    mov rsi, r15
    call hid_rmap_usage
    jmp .out
.none:
    xor eax, eax
.out:
    add rsp, 8
    pop rcx
    clc
    ret
.short:
    add rsp, 8
    pop rcx
    stc
    ret

; -----------------------------------------------------------------------------
; hid_rmap_keyboard
; Input:  RDI = hid_rmap*, RSI = report, EDX = length, RCX = 8-byte output
; Output: EAX = 1 when it was a whole keyboard report (output filled)
; -----------------------------------------------------------------------------
global hid_rmap_keyboard
hid_rmap_keyboard:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                         ; [rsp] output, [+8] keys, [+12] rollover
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rsp], rcx
    mov qword [rcx], 0
    mov dword [rsp + 8], 0
    mov dword [rsp + 12], 0
    call hid_rmap_id
    jc .no
    bt [rbx + hid_rmap.kbd_ids], ebp
    jnc .no
    xor r14d, r14d
.field:
    cmp r14d, [rbx + hid_rmap.nfields]
    jae .finish
    mov eax, r14d
    inc r14d
    cmp byte [rbx + hid_rmap.role + rax], HID_RMAP_KEYBOARD
    jne .field
    imul eax, eax, hid_field_size
    lea r15, [rbx + hid_rmap.fields + rax]
    movzx eax, byte [r15 + hid_field.report_id]
    cmp eax, ebp
    jne .field
    xor ecx, ecx
.element:
    movzx eax, word [r15 + hid_field.count]
    cmp ecx, eax
    jae .field
    call hid_rmap_element
    jc .no                              ; cut short: not a whole report
    inc ecx
    mov edx, eax
    shr edx, 16
    cmp edx, 0x07
    jne .element
    movzx eax, ax
    cmp eax, 1
    je .rollover                        ; ErrorRollOver from the device
    cmp eax, 0xE0
    jb .key
    cmp eax, 0xE7
    ja .element
    sub eax, 0xE0
    mov rdx, [rsp]
    bts [rdx], eax                      ; a modifier
    jmp .element
.key:
    cmp eax, 4
    jb .element
    mov edx, [rsp + 8]
    cmp edx, 6
    jae .rollover
    mov r8, [rsp]
    mov [r8 + rdx + 2], al
    inc dword [rsp + 8]
    jmp .element
.rollover:
    mov dword [rsp + 12], 1
    jmp .element
.finish:
    cmp dword [rsp + 12], 0
    je .yes
    mov rdx, [rsp]
    mov eax, 0x01010101
    mov [rdx + 2], eax
    mov word [rdx + 6], 0x0101
.yes:
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 24
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hid_rmap_pointer
; Input:  RDI = hid_rmap*, RSI = report, EDX = length
; Output: EAX = 1 when it was the pointer's report (events posted)
; -----------------------------------------------------------------------------
global hid_rmap_pointer
hid_rmap_pointer:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                 ; [rsp] dx, [+4] dy, [+8] wheel, [+12] pan,
                                ; [+16] buttons
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    call hid_rmap_id
    jc .no
    bt [rbx + hid_rmap.ptr_ids], ebp
    jnc .no
    xor r14d, r14d
.field:
    cmp r14d, [rbx + hid_rmap.nfields]
    jae .post
    mov eax, r14d
    inc r14d
    cmp byte [rbx + hid_rmap.role + rax], HID_RMAP_POINTER
    jne .field
    imul eax, eax, hid_field_size
    lea r15, [rbx + hid_rmap.fields + rax]
    movzx eax, byte [r15 + hid_field.report_id]
    cmp eax, ebp
    jne .field
    xor ecx, ecx
.element:
    movzx eax, word [r15 + hid_field.count]
    cmp ecx, eax
    jae .field
    ; the element's usage whatever its value (variable fields here)
    push rcx
    sub rsp, 8
    call hid_rmap_value
    jc .short
    mov rsi, r15
    mov rcx, [rsp + 8]
    push rdx
    sub rsp, 8
    call hid_rmap_usage
    add rsp, 8
    pop rdx
    add rsp, 8
    pop rcx
    inc ecx
    cmp eax, 0x00010030
    je .x
    cmp eax, 0x00010031
    je .y
    cmp eax, 0x00010038
    je .wheel
    cmp eax, 0x000C0238
    je .pan
    mov r8d, eax
    shr r8d, 16
    cmp r8d, 0x09
    jne .element
    movzx eax, ax
    dec eax
    cmp eax, 8
    jae .element                        ; buttons 1-8 only
    test rdx, rdx
    jz .element
    bts dword [rsp + 16], eax
    jmp .element
.x:
    add [rsp], edx
    jmp .element
.y:
    add [rsp + 4], edx
    jmp .element
.wheel:
    add [rsp + 8], edx
    jmp .element
.pan:
    add [rsp + 12], edx
    jmp .element
.short:
    add rsp, 8
    pop rcx
    jmp .no                             ; cut short: ignored
.post:
    mov esi, [rsp]
    mov edx, [rsp + 4]
    mov eax, esi
    or eax, edx
    jz .wheel_post
    mov edi, INPUT_MOTION
    mov ecx, [rbx + hid_rmap.dev]
    call input_post_safe
.wheel_post:
    mov edx, [rsp + 8]
    test edx, edx
    jz .pan_post
    neg edx                             ; away from the user: up
    mov edi, INPUT_AXIS
    xor esi, esi
    mov ecx, [rbx + hid_rmap.dev]
    call input_post_safe
.pan_post:
    mov edx, [rsp + 12]
    test edx, edx
    jz .buttons
    mov edi, INPUT_AXIS
    mov esi, 1
    mov ecx, [rbx + hid_rmap.dev]
    call input_post_safe
.buttons:
    xor r14d, r14d
.button:
    mov eax, [rbx + hid_rmap.buttons]
    xor eax, [rsp + 16]
    bt eax, r14d
    jnc .button_next
    mov eax, [rsp + 16]
    bt eax, r14d
    setc dl
    movzx edx, dl
    mov edi, INPUT_BUTTON
    mov esi, r14d
    mov ecx, [rbx + hid_rmap.dev]
    call input_post_safe
.button_next:
    inc r14d
    cmp r14d, 8
    jb .button
    mov eax, [rsp + 16]
    mov [rbx + hid_rmap.buttons], eax
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 24
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_INPUT_HID_REPORT_ASM
