; =============================================================================
; Utkarsha OS — lib/input/ps2/kbd.asm
; =============================================================================
; The PS/2 keyboard: reset and set-up, scan code set 1 decoding (the
; controller translates from set 2), and the lock-key LEDs.
;
; Keycodes are the numbers canvas reads (lib/canvas/src/input/keymap_us.asm):
; set 1 make codes for the base keys, and 96 and up for the keys behind an
; 0xE0 prefix (Right Ctrl 97, arrows 103-108, Super 125 and 126, ...).
;
; Canvas repeats held keys itself, so the keyboard's own repeats are
; dropped here: a key reports one press and one release.
;
; LEDs follow the lock keys pressed on this keyboard. The LED command needs
; two acknowledged bytes; the interrupt handler sends the second byte when
; the first is acknowledged, and ps2_kbd_service (on the input fiber) starts
; the exchange and gives up on one that is never acknowledged.
; =============================================================================

%ifndef LIB_INPUT_PS2_KBD_ASM
%define LIB_INPUT_PS2_KBD_ASM

%define KBD_ACK             0xFA
%define KBD_RESEND          0xFE
%define KBD_BAT_OK          0xAA
%define KBD_CMD_LEDS        0xED
%define KBD_CMD_SCANSET     0xF0
%define KBD_CMD_ENABLE      0xF4
%define KBD_CMD_RESET       0xFF

%define KBD_LED_SCROLL      (1 << 0)
%define KBD_LED_NUM         (1 << 1)
%define KBD_LED_CAPS        (1 << 2)

%define KBD_IDLE            0
%define KBD_WAIT_CMD_ACK    1       ; sent 0xED, waiting for its ACK
%define KBD_WAIT_ARG_ACK    2       ; sent the LED byte, waiting for its ACK

%define KBD_CMD_TRIES       3
%define KBD_LED_TIMEOUT_NS  50000000    ; 50 ms
%define KBD_LED_TIMEOUT_POLLS 100000    ; the same without a clock

section .rodata
; set 1 make code → keycode; 0 = no key
ps2_set1_keys:
    db   0,   1,   2,   3,   4,   5,   6,   7    ; 0x00
    db   8,   9,  10,  11,  12,  13,  14,  15    ; 0x08
    db  16,  17,  18,  19,  20,  21,  22,  23    ; 0x10
    db  24,  25,  26,  27,  28,  29,  30,  31    ; 0x18
    db  32,  33,  34,  35,  36,  37,  38,  39    ; 0x20
    db  40,  41,  42,  43,  44,  45,  46,  47    ; 0x28
    db  48,  49,  50,  51,  52,  53,  54,  55    ; 0x30
    db  56,  57,  58,  59,  60,  61,  62,  63    ; 0x38
    db  64,  65,  66,  67,  68,  69,  70,  71    ; 0x40
    db  72,  73,  74,  75,  76,  77,  78,  79    ; 0x48
    db  80,  81,  82,  83,  99,   0,  86,  87    ; 0x50
    db  88,   0,   0,   0,   0,   0,   0,   0    ; 0x58
    db   0,   0,   0,   0,   0,   0,   0,   0    ; 0x60
    db   0,   0,   0,   0,   0,   0,   0,   0    ; 0x68
    db  93,   0,   0,  89,   0,   0,   0,   0    ; 0x70
    db   0,  92,   0,  94,   0, 124, 121,   0    ; 0x78

; 0xE0 + make code → keycode
ps2_set1_e0_keys:
    db   0,   0,   0,   0,   0,   0,   0,   0    ; 0x00
    db   0,   0,   0,   0,   0,   0,   0,   0    ; 0x08
    db 165,   0,   0,   0,   0,   0,   0,   0    ; 0x10 previous track
    db   0, 163,   0,   0,  96,  97,   0,   0    ; 0x18 next, keypad enter, right ctrl
    db 113, 140, 164,   0, 166,   0,   0,   0    ; 0x20 mute, calculator, play, stop
    db   0,   0,   0,   0,   0,   0, 114,   0    ; 0x28 volume down
    db 115,   0, 172,   0,   0,  98,   0,  99    ; 0x30 volume up, home page, keypad /, print screen
    db 100,   0,   0,   0,   0,   0,   0,   0    ; 0x38 right alt
    db   0,   0,   0,   0,   0,   0, 119, 102    ; 0x40 ctrl+break, home
    db 103, 104,   0, 105,   0, 106,   0, 107    ; 0x48 up, page up, left, right, end
    db 108, 109, 110, 111,   0,   0,   0,   0    ; 0x50 down, page down, insert, delete
    db   0,   0,   0, 125, 126, 127, 116, 142    ; 0x58 super, super, menu, power, sleep
    db   0,   0,   0, 143,   0, 217, 156, 173    ; 0x60 wake, search, bookmarks, refresh
    db 128, 159, 158, 157, 155, 226,   0,   0    ; 0x68 stop, forward, back, computer, mail, media
    db   0,   0,   0,   0,   0,   0,   0,   0    ; 0x70
    db   0,   0,   0,   0,   0,   0,   0,   0    ; 0x78

ps2_kbd_name:       db "PS/2 keyboard", 0

section .bss
alignb 8
kbd_down:           resb 32             ; one bit per keycode held down
kbd_led_sent_at:    resq 1
global ps2_kbd_dev
ps2_kbd_dev:        resd 1              ; device ID, 0 before ps2_init
kbd_prefix:         resd 1              ; 1 after 0xE0
kbd_e1_left:        resd 1              ; bytes left of the Pause sequence
global ps2_kbd_locks
ps2_kbd_locks:      resd 1              ; KBD_LED_* as on the keyboard
kbd_led_pending:    resd 1
global ps2_kbd_cmd_state
ps2_kbd_cmd_state:  resd 1              ; KBD_IDLE, KBD_WAIT_*
kbd_led_polls:      resd 1
global ps2_kbd_unknown
ps2_kbd_unknown:    resd 1              ; codes with no keycode
global ps2_kbd_overruns
ps2_kbd_overruns:   resd 1
global ps2_kbd_resends
ps2_kbd_resends:    resd 1
global ps2_kbd_led_timeouts
ps2_kbd_led_timeouts: resd 1

section .text

; -----------------------------------------------------------------------------
; kbd_command — send one byte to the keyboard and wait for its ACK
;               (start-up only, before the interrupt is on)
; Input:  EDI = byte
; Output: CF = 1 when it is never acknowledged
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
kbd_command:
    push rbx
    push r12
    sub rsp, 8
    mov ebx, edi
    mov r12d, KBD_CMD_TRIES
.try:
    mov edi, ebx
    call i8042_write_data
    jc .fail
    mov esi, I8042_SPIN
    call i8042_read
    jc .fail
    cmp al, KBD_ACK
    je .ok
    cmp al, KBD_RESEND
    jne .fail
    dec r12d
    jnz .try
.fail:
    stc
    jmp .out
.ok:
    clc
.out:
    lea rsp, [rsp + 8]                  ; keeps CF
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ps2_kbd_state_reset — forget held keys, prefixes, locks and LED work
; Clobbers: RAX, RCX, RDI
; -----------------------------------------------------------------------------
global ps2_kbd_state_reset
ps2_kbd_state_reset:
    lea rdi, [rel kbd_down]
    mov ecx, 32
    xor eax, eax
    rep stosb
    mov [rel kbd_prefix], eax
    mov [rel kbd_e1_left], eax
    mov [rel ps2_kbd_locks], eax
    mov [rel kbd_led_pending], eax
    mov [rel ps2_kbd_cmd_state], eax
    mov [rel kbd_led_polls], eax
    mov [rel ps2_kbd_unknown], eax
    mov [rel ps2_kbd_overruns], eax
    mov [rel ps2_kbd_resends], eax
    mov [rel ps2_kbd_led_timeouts], eax
    mov [rel kbd_led_sent_at], rax
    ret

; -----------------------------------------------------------------------------
; ps2_init — bring up the controller and the keyboard; add the keyboard to
;            the device list. The interrupt stays off: see i8042_irq_enable.
; Output: EAX = 0, or a negative INPUT_E* error
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global ps2_init
ps2_init:
    push rbx
    mov dword [rel ps2_kbd_dev], 0
    call ps2_kbd_state_reset
    call i8042_init
    test eax, eax
    jnz .out

    ; Reset: ACK, then the self-test result, which can take a while
    mov edi, KBD_CMD_RESET
    call kbd_command
    jc .absent
    mov esi, I8042_SPIN * 5
    call i8042_read
    jc .absent
    cmp al, KBD_BAT_OK
    jne .absent

    ; Set 2 (the controller translates it), LEDs off. A keyboard that
    ; refuses either still works with its defaults.
    mov edi, KBD_CMD_SCANSET
    call kbd_command
    jc .leds
    mov edi, 2
    call kbd_command
.leds:
    mov edi, KBD_CMD_LEDS
    call kbd_command
    jc .enable
    xor edi, edi
    call kbd_command
.enable:
    mov edi, KBD_CMD_ENABLE
    call kbd_command
    jc .absent

    lea rdi, [rel ps2_kbd_name]
    mov esi, INPUT_BUS_PS2
    mov edx, INPUT_CAP_KEYBOARD
    xor ecx, ecx
    call input_dev_add
    test eax, eax
    js .out
    mov [rel ps2_kbd_dev], eax
    xor eax, eax
    jmp .out
.absent:
    mov eax, -INPUT_ENODEV
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ps2_kbd_byte — one byte from the keyboard (interrupt context)
; Input:  EDI = byte
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global ps2_kbd_byte
ps2_kbd_byte:
    push rbx
    movzx ebx, dil

    ; Replies to an LED exchange. Outside one, 0xFA and 0xFE are ordinary
    ; (unused) break codes.
    mov eax, [rel ps2_kbd_cmd_state]
    test eax, eax
    jz .scan
    cmp bl, KBD_ACK
    je .ack
    cmp bl, KBD_RESEND
    jne .scan
    inc dword [rel ps2_kbd_resends]
    cmp eax, KBD_WAIT_CMD_ACK
    jne .send_arg
    mov edi, KBD_CMD_LEDS
    call i8042_write_data
    jmp .out
.ack:
    cmp eax, KBD_WAIT_CMD_ACK
    jne .ack_done
.send_arg:
    mov dword [rel ps2_kbd_cmd_state], KBD_WAIT_ARG_ACK
    mov edi, [rel ps2_kbd_locks]
    call i8042_write_data
    jmp .out
.ack_done:
    mov dword [rel ps2_kbd_cmd_state], KBD_IDLE
    jmp .out

.scan:
    test bl, bl                         ; 0x00 and 0xFF: the keyboard's
    jz .overrun                         ; buffer overflowed
    cmp bl, 0xFF
    je .overrun

    ; Pause sends E1 1D 45 E1 9D C5 and nothing on release
    mov eax, [rel kbd_e1_left]
    test eax, eax
    jz .not_pause
    dec eax
    mov [rel kbd_e1_left], eax
    jnz .out
    mov edi, INPUT_KEY
    mov esi, KEY_PAUSE
    mov edx, 1
    mov ecx, [rel ps2_kbd_dev]
    call input_post
    mov edi, INPUT_KEY
    mov esi, KEY_PAUSE
    xor edx, edx
    mov ecx, [rel ps2_kbd_dev]
    call input_post
    jmp .out
.not_pause:
    cmp bl, 0xE1
    jne .not_e1
    mov dword [rel kbd_e1_left], 5
    jmp .out
.not_e1:
    cmp bl, 0xE0
    jne .code
    mov dword [rel kbd_prefix], 1
    jmp .out

.code:
    mov ecx, ebx
    and ecx, 0x7F                       ; make code
    xor edx, edx
    test bl, 0x80
    setz dl                             ; 1 pressed, 0 released
    xor eax, eax
    xchg eax, [rel kbd_prefix]
    test eax, eax
    jz .base
    cmp ecx, 0x2A                       ; E0 2A and E0 36 are shifts the
    je .out                             ; keyboard adds around some keys
    cmp ecx, 0x36
    je .out
    lea rax, [rel ps2_set1_e0_keys]
    jmp .lookup
.base:
    lea rax, [rel ps2_set1_keys]
.lookup:
    movzx esi, byte [rax + rcx]
    test esi, esi
    jz .unknown

    test edx, edx
    jz .release
    bts [rel kbd_down], esi             ; held already: the keyboard's repeat
    jc .out

    ; Lock keys toggle their LED
    xor eax, eax
    cmp esi, KEY_CAPSLOCK
    jne .num
    mov eax, KBD_LED_CAPS
.num:
    cmp esi, KEY_NUMLOCK
    jne .scroll
    mov eax, KBD_LED_NUM
.scroll:
    cmp esi, KEY_SCROLLLOCK
    jne .post
    mov eax, KBD_LED_SCROLL
.post:
    test eax, eax
    jz .send
    xor [rel ps2_kbd_locks], eax
    mov dword [rel kbd_led_pending], 1
    jmp .send
.release:
    btr [rel kbd_down], esi             ; not held: nothing to release
    jnc .out
.send:
    mov edi, INPUT_KEY
    mov ecx, [rel ps2_kbd_dev]
    call input_post
    jmp .out

.unknown:
    inc dword [rel ps2_kbd_unknown]
    jmp .out
.overrun:
    inc dword [rel ps2_kbd_overruns]
.out:
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ps2_kbd_service — start a pending LED update, or give up on a stuck one
;                   (input fiber, interrupts on)
; Clobbers: the caller-saved registers
; -----------------------------------------------------------------------------
global ps2_kbd_service
ps2_kbd_service:
    push rbx
    cmp dword [rel ps2_kbd_dev], 0
    je .out
    cmp dword [rel ps2_kbd_cmd_state], KBD_IDLE
    jne .waiting
    cmp dword [rel kbd_led_pending], 0
    je .out
    mov dword [rel kbd_led_pending], 0
    mov dword [rel kbd_led_polls], 0
    call input_now
    mov [rel kbd_led_sent_at], rax
    ; state first: the ACK can arrive before i8042_write_data returns
    mov dword [rel ps2_kbd_cmd_state], KBD_WAIT_CMD_ACK
    mov edi, KBD_CMD_LEDS
    call i8042_write_data
    jmp .out
.waiting:
    call input_now
    test rax, rax
    jz .count
    sub rax, [rel kbd_led_sent_at]
    cmp rax, KBD_LED_TIMEOUT_NS
    jb .out
    jmp .give_up
.count:
    inc dword [rel kbd_led_polls]
    cmp dword [rel kbd_led_polls], KBD_LED_TIMEOUT_POLLS
    jb .out
.give_up:
    inc dword [rel ps2_kbd_led_timeouts]
    mov dword [rel ps2_kbd_cmd_state], KBD_IDLE
    mov dword [rel kbd_led_pending], 1  ; try again with the current locks
.out:
    pop rbx
    ret

%endif ; LIB_INPUT_PS2_KBD_ASM
