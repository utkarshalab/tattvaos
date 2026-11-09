; ============================================================================
; Pointer Settings — Per Device: Scroll Speed, Natural Scroll, Buttons
; ============================================================================
; PTR-03, PTR-05. Each pointing device may have its own settings; any other
; uses the default ones. A device's settings: flags (POINTER_NATURAL: the
; scroll direction reversed; POINTER_LEFT_HANDED: left and right buttons
; swapped), a scroll speed in 120ths (120: as the device reports), and a
; button map (button n pressed acts as map[n]; set by
; server_set_button_map, left-handed swapping 0 and 1 over it). Up to
; POINTER_DEVICES devices have their own; past that the default holds.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

section .text

; ---------------------------------------------------------------------------
; server_set_pointer
;   IN:  rdi = server*, esi = device, or -1 for the default; edx = flags
;        (POINTER_*); ecx = scroll speed in 120ths (0: 120)
;   OUT: rax = 0, -ENOSPC with POINTER_DEVICES devices set already
; ---------------------------------------------------------------------------
global server_set_pointer
server_set_pointer:
    push rbx
    push rdx
    push rcx
    call settings_for
    pop rcx
    pop rdx
    test rax, rax
    jz .full
    mov [rax + PointerDevice.flags], edx
    test ecx, ecx
    jnz .speed
    mov ecx, 120
.speed:
    mov [rax + PointerDevice.scroll], ecx
    xor eax, eax
    pop rbx
    ret
.full:
    mov rax, -(ENOSPC)
    pop rbx
    ret

; ---------------------------------------------------------------------------
; server_set_button_map
;   IN:  rdi = server*, esi = device or -1; rdx = 32 bytes, the button each
;        button acts as (0 to 31; 0xFF: itself)
;   OUT: rax = 0, -ENOSPC as server_set_pointer, -EINVAL for a button past 31
; ---------------------------------------------------------------------------
global server_set_button_map
server_set_button_map:
    push rbx
    push rdx
    push rdx                            ; 16-byte aligned
    call settings_for
    pop rdx
    pop rdx
    test rax, rax
    jz .full
    xor ecx, ecx
.check:
    movzx r8d, byte [rdx + rcx]
    cmp r8d, 0xFF
    je .ok
    cmp r8d, 31
    ja .bad
.ok:
    inc ecx
    cmp ecx, 32
    jb .check
    xor ecx, ecx
.copy:
    mov r8b, [rdx + rcx]
    mov [rax + PointerDevice.map + rcx], r8b
    inc ecx
    cmp ecx, 32
    jb .copy
    xor eax, eax
    pop rbx
    ret
.bad:
    mov rax, -(EINVAL)
    pop rbx
    ret
.full:
    mov rax, -(ENOSPC)
    pop rbx
    ret

; ---------------------------------------------------------------------------
; pointer_settings
;   A device's settings: its own, else the default
;   IN:  rdi = server*, esi = device
;   OUT: rax = PointerDevice*
; ---------------------------------------------------------------------------
global pointer_settings
pointer_settings:
    lea rax, [rdi + Server.pointer_devices]
    xor ecx, ecx
.find:
    cmp dword [rax + PointerDevice.used], 0
    je .next
    cmp [rax + PointerDevice.device], esi
    je .out
.next:
    add rax, PointerDevice_size
    inc ecx
    cmp ecx, POINTER_DEVICES
    jb .find
    lea rax, [rdi + Server.pointer_default]
.out:
    ret

; ---------------------------------------------------------------------------
; pointer_button
;   The button a press of button esi on device edx acts as
;   IN:  rdi = server*, esi = button (0 to 31), edx = device
;   OUT: eax = the button
; ---------------------------------------------------------------------------
global pointer_button
pointer_button:
    push rsi
    mov esi, edx
    call pointer_settings
    pop rsi
    mov ecx, esi                        ; itself, unless mapped
    cmp byte [rax + PointerDevice.ready], 0
    je .mapped                          ; never set: every button itself
    movzx edx, byte [rax + PointerDevice.map + rsi]
    cmp edx, 0xFF
    je .mapped
    mov ecx, edx
.mapped:
    test dword [rax + PointerDevice.flags], POINTER_LEFT_HANDED
    jz .done
    cmp ecx, 1                          ; left-handed: left and right swap
    ja .done
    xor ecx, 1
.done:
    mov eax, ecx
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = server, esi = device or -1 -> rax = its PointerDevice (made, from the
; default, the first time), 0 with none free; rbx used
settings_for:
    lea rbx, [rdi + Server.pointer_default]
    cmp esi, -1
    je .made
    lea rax, [rdi + Server.pointer_devices]
    xor ecx, ecx
    xor r8d, r8d                        ; a free one
.find:
    cmp dword [rax + PointerDevice.used], 0
    je .free
    cmp [rax + PointerDevice.device], esi
    je .have
    jmp .next
.free:
    test r8, r8
    jnz .next
    mov r8, rax
.next:
    add rax, PointerDevice_size
    inc ecx
    cmp ecx, POINTER_DEVICES
    jb .find
    xor eax, eax
    test r8, r8
    jz .out
    call ready_default                  ; a copy of the default
    mov rax, r8
    push rdi
    push rsi
    mov rdi, rax
    mov rsi, rbx
    mov ecx, PointerDevice_size
    rep movsb
    pop rsi
    pop rdi
    mov [rax + PointerDevice.device], esi
    mov dword [rax + PointerDevice.used], 1
.have:
    ret
.made:
    call ready_default
    mov rax, rbx
.out:
    ret

; rbx = the default PointerDevice: filled the first time (speed 120, every
; button itself)
ready_default:
    cmp byte [rbx + PointerDevice.ready], 0
    jne .done
    mov dword [rbx + PointerDevice.scroll], 120
    mov dword [rbx + PointerDevice.flags], 0
    push rcx
    xor ecx, ecx
.map:
    mov byte [rbx + PointerDevice.map + rcx], 0xFF
    inc ecx
    cmp ecx, 32
    jb .map
    pop rcx
    mov byte [rbx + PointerDevice.ready], 1
.done:
    ret

section .data
global pointer_settings_version
pointer_settings_version: dq 0x010000
