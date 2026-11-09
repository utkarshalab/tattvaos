; ============================================================================
; Clamshell — The Built-in Panel Under a Closed Lid (SES-08)
; ============================================================================
; An output may be the built-in panel (Output.builtin: the kernel says so in
; ut_fb_info's flags, KERNEL_NEEDS.md step 5). With the lid closed it is
; turned off; if another output shows its own part of the layout it is also
; made a mirror of it, so it is no part of the layout and what was on it goes
; there. Opening the lid undoes what closing it did (Output.lid_off). An
; output plugged in while the lid is closed takes the panel's place too.
;
; With the lid closed and no other screen on, clamshell_sleep locks and
; asks the kernel to suspend (ut_power_suspend, a weak import), unless
; server_set_lid_sleep turned that off: then it only locks.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/ut.inc"
%include "inc/log.inc"

extern dpms_set
extern greeter_lock
extern server_mirror_output
extern ut_power_suspend

%define DPMS_ON     0
%define DPMS_OFF    3

section .text

; ---------------------------------------------------------------------------
; clamshell_lid
;   The lid closed (1) or opened (0)
;   IN:  rdi = server*, esi = 1 closed, 0 open
;   OUT: rax = 1 if another output shows the layout with the lid closed
;        (the session need not lock), else 0
; ---------------------------------------------------------------------------
global clamshell_lid
clamshell_lid:
    and esi, 1
    mov [rdi + Server.lid_closed], rsi
    push rdi
    lea rax, [rel log_lid_open]
    lea rcx, [rel log_lid_closed]
    test esi, esi
    cmovnz rax, rcx
    mov edx, log_lid_open_len
    mov ecx, log_lid_closed_len
    cmovnz edx, ecx
    mov edi, LOG_CAT_SESSION
    mov rsi, rax
    call log_info
    pop rdi
    jmp clamshell_update

; ---------------------------------------------------------------------------
; clamshell_update
;   The built-in panel as the lid wants it: after the lid moves and after an
;   output is placed
;   IN:  rdi = server*
;   OUT: rax = 1 if the lid is closed and another output shows the layout,
;        else 0
; ---------------------------------------------------------------------------
global clamshell_update
clamshell_update:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, [rbx + Server.outputs]     ; the built-in panel
.find:
    test r12, r12
    jz .none
    cmp byte [r12 + Output.builtin], 0
    jne .found
    mov r12, [r12 + Output.next]
    jmp .find
.found:
    mov r13, [rbx + Server.outputs]     ; another showing its own part
.other:
    test r13, r13
    jz .looked                          ; none: r13 = 0
    cmp r13, r12
    je .not_it
    cmp qword [r13 + Output.mirror_of], 0
    je .looked
.not_it:
    mov r13, [r13 + Output.next]
    jmp .other
.looked:
    cmp qword [rbx + Server.lid_closed], 0
    je .open
    test byte [r12 + Output.lid_off], LID_DARK
    jnz .dark
    mov rdi, rbx                        ; closed: off
    mov rsi, r12
    mov edx, DPMS_OFF
    call dpms_set
    test rax, rax
    jnz .dark                           ; it would not go off: left as it is
    or byte [r12 + Output.lid_off], LID_DARK
.dark:
    test r13, r13
    jz .none                            ; nothing else to show the layout
    cmp qword [r12 + Output.mirror_of], 0
    jne .elsewhere                      ; shows another's part already
    mov rdi, rbx                        ; out of the layout, its windows
    mov rsi, r12                        ; to the other
    mov rdx, r13
    call server_mirror_output
    test rax, rax
    jnz .none
    or byte [r12 + Output.lid_off], LID_MIRRORED
.elsewhere:
    mov eax, 1
    jmp .out
.open:
    test byte [r12 + Output.lid_off], LID_MIRRORED
    jz .lit
    mov rax, [r12 + Output.mirror_of]   ; still a mirror (its source may
    test rax, rax                       ; have gone, and with it that)
    jz .lit
    mov rdi, rbx                        ; its own part again
    mov rsi, r12
    xor edx, edx
    call server_mirror_output
.lit:
    test byte [r12 + Output.lid_off], LID_DARK
    jz .opened
    mov rdi, rbx
    mov rsi, r12
    mov edx, DPMS_ON
    call dpms_set
.opened:
    mov byte [r12 + Output.lid_off], 0
.none:
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; clamshell_sleep
;   The lid closed with no other screen on: locked, then suspended (unless
;   Server.lid_awake); the kernel returns from ut_power_suspend after resume
;   IN:  rdi = server*
;   OUT: rax = 0, or ut_power_suspend's error (-ENOSYS without it)
; ---------------------------------------------------------------------------
global clamshell_sleep
clamshell_sleep:
    PROLOGUE_SAVE rbx
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov rdi, [rbx + Server.greeter]     ; the login screen up first, so it is
    test rdi, rdi                       ; what shows on waking
    jz .locked
    call greeter_lock
.locked:
    xor eax, eax
    cmp qword [rbx + Server.lid_awake], 0
    jne .out
    inc qword [rbx + Server.suspends]
    call ut_power_suspend
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx

; ---------------------------------------------------------------------------
; server_set_lid_sleep
;   Whether closing the lid with no other screen on suspends (1, as at
;   start) or only locks (0)
;   IN:  rdi = server*, esi = 1 or 0
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global server_set_lid_sleep
server_set_lid_sleep:
    xor eax, eax
    test esi, esi
    sete al
    mov [rdi + Server.lid_awake], rax
    xor eax, eax
    ret

section .rodata
log_lid_closed: db "the lid was closed"
log_lid_closed_len: equ $ - log_lid_closed
log_lid_open:   db "the lid was opened"
log_lid_open_len: equ $ - log_lid_open

section .data
global clamshell_version
clamshell_version: dq 0x010000
