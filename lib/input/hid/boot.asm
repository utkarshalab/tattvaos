; =============================================================================
; Utkarsha OS — lib/input/hid/boot.asm — HID keyboards and mice, boot reports
; =============================================================================
; Shared by every HID transport (USB now; Bluetooth later):
;
;   hid_usage_key       keyboard usage (page 7) → keycode, 256 bytes
;   hid_boot_keyboard(state, report, len)   the 8-byte boot report → key
;                       events against the last one; EAX = 1 when a lock key
;                       (Caps, Num, Scroll) was pressed, so the transport
;                       sets the LEDs from state.locks
;   hid_boot_mouse(state, report, len)      buttons, X, Y and the wheel
;
; The boot report: modifier bits, a reserved byte, up to six keys held. A
; report of ErrorRollOver (usage 1) means too many keys for the device to
; tell apart: it is ignored, and the keys stay as they were.
; =============================================================================

%ifndef LIB_INPUT_HID_BOOT_ASM
%define LIB_INPUT_HID_BOOT_ASM

%define HID_LED_NUM         (1 << 0)
%define HID_LED_CAPS        (1 << 1)
%define HID_LED_SCROLL      (1 << 2)

struc hid_boot
    .prev:          resb 8          ; the last report (keyboard)
    .dev:           resd 1          ; lib/input device ID
    .buttons:       resd 1          ; mouse buttons down
    .locks:         resd 1          ; HID_LED_* (keyboard)
    .pad:           resd 1
endstruc

section .bss
alignb 4
global hid_boot_unknown
hid_boot_unknown:   resd 1          ; usages with no keycode
global hid_boot_rollover
hid_boot_rollover:  resd 1          ; ErrorRollOver reports

section .rodata
; usage → keycode (0: none)
global hid_usage_key
hid_usage_key:
    db 0, 0, 0, 0                                               ; 00-03
    db 30, 48, 46, 32, 18, 33, 34, 35, 23, 36, 37, 38, 50       ; a-m
    db 49, 24, 25, 16, 19, 31, 20, 22, 47, 17, 45, 21, 44       ; n-z
    db 2, 3, 4, 5, 6, 7, 8, 9, 10, 11                           ; 1-0
    db 28, 1, 14, 15, 57, 12, 13, 26, 27, 43, 43, 39, 40        ; 28-34
    db 41, 51, 52, 53                                           ; 35-38
    db 58, 59, 60, 61, 62, 63, 64, 65, 66, 67, 68, 87, 88       ; caps, F1-F12
    db 99, 70, 119, 110, 102, 104, 111, 107, 109                ; 46-4E
    db 106, 105, 108, 103                                       ; arrows
    db 69, 98, 55, 74, 78, 96, 79, 80, 81, 75, 76, 77, 71       ; keypad
    db 72, 73, 82, 83                                           ; 60-63
    db 86, 127, 116, 117                                        ; 64-67
    db 183, 184, 185, 186, 187, 188, 189, 190, 191, 192, 193, 194 ; F13-F24
    db 134, 138, 130, 132, 128, 129, 131, 137, 133, 135, 136    ; 74-7E
    db 113, 115, 114                                            ; mute, volume
    db 0, 0, 0, 121, 0, 89, 93, 124, 92, 94, 95, 0, 0, 0        ; 82-8F
    db 122, 123, 90, 91, 85                                     ; 90-94
    times 0xE0 - 0x95 db 0
    db 29, 42, 56, 125, 97, 54, 100, 126                        ; modifiers
    times 0x100 - 0xE8 db 0             ; 256 bytes: the tests check entries

section .text

; hid_boot_post — EDI type, ESI code, EDX value; RBX = state
hid_boot_post:
    mov ecx, [rbx + hid_boot.dev]
    jmp input_post_safe

; hid_boot_has — whether byte AL is among the key bytes at RSI (R8D of them)
; Output: ZF = 1 (je) when it is
hid_boot_has:
    xor ecx, ecx
.next:
    cmp ecx, r8d
    jae .no
    cmp [rsi + rcx], al
    je .out
    inc ecx
    jmp .next
.no:
    test esp, esp                       ; ZF = 0
.out:
    ret

; hid_boot_key — post usage AL as key EDX (1 down, 0 up), when it has a code
hid_boot_key:
    movzx eax, al
    lea rcx, [rel hid_usage_key]
    movzx esi, byte [rcx + rax]
    test esi, esi
    jnz .post
    inc dword [rel hid_boot_unknown]
    ret
.post:
    mov edi, INPUT_KEY
    jmp hid_boot_post

; -----------------------------------------------------------------------------
; hid_boot_keyboard
; Input:  RDI = hid_boot state, RSI = report, EDX = its length
; Output: EAX = 1 when a lock key went down (state.locks changed), else 0
; -----------------------------------------------------------------------------
global hid_boot_keyboard
hid_boot_keyboard:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                         ; the report, padded to 8 bytes
    mov rbx, rdi
    xor ebp, ebp                        ; lock pressed
    xor eax, eax
    cmp edx, 3
    jb .out
    mov qword [rsp], 0
    mov ecx, edx
    cmp ecx, 8
    jbe .copy
    mov ecx, 8
.copy:
    mov al, [rsi + rcx - 1]
    mov [rsp + rcx - 1], al
    dec ecx
    jnz .copy
    ; ErrorRollOver anywhere in the keys: ignore it
    mov ecx, 2
.rollover:
    cmp byte [rsp + rcx], 1
    je .phantom
    inc ecx
    cmp ecx, 8
    jb .rollover

    ; keys let go: in the last report, not in this one
    mov r12d, 2
.released:
    mov al, [rbx + hid_boot.prev + r12]
    cmp al, 4
    jb .released_next
    lea rsi, [rsp + 2]
    mov r8d, 6
    call hid_boot_has
    je .released_next
    mov al, [rbx + hid_boot.prev + r12]
    xor edx, edx
    call hid_boot_key
.released_next:
    inc r12d
    cmp r12d, 8
    jb .released

    ; modifiers that changed
    movzx r13d, byte [rbx + hid_boot.prev]
    movzx r14d, byte [rsp]
    xor r12d, r12d
.modifier:
    bt r13d, r12d
    setc r15b
    bt r14d, r12d
    setc al
    cmp al, r15b
    je .modifier_next
    movzx edx, al
    lea eax, [r12d + 0xE0]
    call hid_boot_key
.modifier_next:
    inc r12d
    cmp r12d, 8
    jb .modifier

    ; keys pressed: in this report, not in the last
    mov r12d, 2
.pressed:
    mov al, [rsp + r12]
    cmp al, 4
    jb .pressed_next
    lea rsi, [rbx + hid_boot.prev + 2]
    mov r8d, 6
    call hid_boot_has
    je .pressed_next
    mov al, [rsp + r12]
    mov edx, 1
    call hid_boot_key
    ; the lock keys
    movzx eax, byte [rsp + r12]
    mov ecx, HID_LED_CAPS
    cmp eax, 0x39
    je .lock
    mov ecx, HID_LED_NUM
    cmp eax, 0x53
    je .lock
    mov ecx, HID_LED_SCROLL
    cmp eax, 0x47
    jne .pressed_next
.lock:
    xor [rbx + hid_boot.locks], ecx
    mov ebp, 1
.pressed_next:
    inc r12d
    cmp r12d, 8
    jb .pressed

    mov rax, [rsp]
    mov [rbx + hid_boot.prev], rax
    mov eax, ebp
    jmp .out
.phantom:
    inc dword [rel hid_boot_rollover]
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
; hid_boot_mouse — buttons (bits 0-2: left, right, middle), X, Y, the wheel
; Input:  RDI = hid_boot state, RSI = report, EDX = its length
; -----------------------------------------------------------------------------
global hid_boot_mouse
hid_boot_mouse:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    cmp r13d, 3
    jb .out
    movsx esi, byte [r12 + 1]
    movsx edx, byte [r12 + 2]
    mov eax, esi
    or eax, edx
    jz .wheel
    mov edi, INPUT_MOTION
    call hid_boot_post
.wheel:
    cmp r13d, 4
    jb .buttons
    movsx edx, byte [r12 + 3]
    test edx, edx
    jz .buttons
    neg edx                             ; wheel away from the user: up
    mov edi, INPUT_AXIS
    xor esi, esi
    call hid_boot_post
.buttons:
    movzx r14d, byte [r12]
    and r14d, 7
    xor r15d, r15d
.button:
    mov eax, [rbx + hid_boot.buttons]
    bt eax, r15d
    setc al
    bt r14d, r15d
    setc dl
    cmp al, dl
    je .next
    movzx edx, dl
    mov edi, INPUT_BUTTON
    mov esi, r15d
    call hid_boot_post
.next:
    inc r15d
    cmp r15d, 3
    jb .button
    mov [rbx + hid_boot.buttons], r14d
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_INPUT_HID_BOOT_ASM
