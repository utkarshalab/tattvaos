; ============================================================================
; Stacking — Surfaces Coming and Going
; ============================================================================
; A surface that shows its first buffer goes on top of its level and takes
; the keyboard, if surfaces at its level take it when they show: windows,
; popups, overlay layers and surfaces with no role do; background, bottom and
; top layers do not, nor on a click. One
; that has the keyboard and stops showing anything, or is destroyed, hands it
; to the topmost surface still showing that would take it; with none left,
; nothing has it. A destroyed surface is told nothing: its client let it go.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern compositor_raise_surface
extern input_focus_surface
extern input_forget_surface

section .text

; ---------------------------------------------------------------------------
; stacking_mapped
;   A surface shows its first buffer
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global stacking_mapped
stacking_mapped:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    call compositor_raise_surface
    cmp qword [r12 + Surface.output], 0
    je .out                             ; minimized: not on show
    mov rdi, r12
    call takes_keyboard_on_show
    test eax, eax
    jz .out
    mov rdi, rbx
    mov rsi, r12
    call input_focus_surface
.out:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; stacking_level
;   IN:  rdi = surface*
;   OUT: rax = its stacking level (LEVEL_*), sign-extended
; ---------------------------------------------------------------------------
global stacking_level
stacking_level:
    xor eax, eax
    mov rcx, [rdi + Surface.window]
    test rcx, rcx
    jz .out
    movsxd rax, dword [rcx + Window.level]
.out:
    ret

; rdi = surface -> eax = 1 if it takes the keyboard when it shows
takes_keyboard_on_show:
    push rdi
    call stacking_level
    pop rdi
    cmp eax, LEVEL_NORMAL
    je .yes
    cmp eax, LEVEL_POPUP
    je .yes
    cmp eax, LEVEL_OVERLAY
    je .yes
    xor eax, eax
    ret
.yes:
    mov eax, 1
    ret

; ---------------------------------------------------------------------------
; stacking_unmapped
;   A surface no longer shows a buffer; it is told it lost the keyboard
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global stacking_unmapped
stacking_unmapped:
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .out
    cmp [rax + InputSeat.keyboard_focus], rsi
    je focus_topmost
.out:
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; stacking_destroyed
;   A surface is going; call before it leaves its output
;   IN:  rdi = server*, rsi = surface*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global stacking_destroyed
stacking_destroyed:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    xor r13d, r13d                      ; had the keyboard
    mov rax, [rbx + Server.input_seat]
    test rax, rax
    jz .forget
    cmp [rax + InputSeat.keyboard_focus], r12
    sete r13b
.forget:
    mov rdi, rbx
    mov rsi, r12
    call input_forget_surface
    test r13d, r13d
    jz .out
    mov rdi, rbx
    mov rsi, r12
    call focus_topmost
.out:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; stacking_focus_any
;   With nothing holding the keyboard, the topmost surface that would take
;   it on show takes it
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global stacking_focus_any
stacking_focus_any:
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .out
    cmp qword [rax + InputSeat.keyboard_focus], 0
    jne .out
    mov rdx, [rdi + Server.outputs]
    xor esi, esi
    jmp focus_topmost_on
.out:
    xor eax, eax
    ret

; The keyboard to the topmost surface on the screen, on any output, that
; shows a buffer and would take it, other than rsi; to none if there is none
; or rsi is off the screen.
; rdi = server*, rsi = surface* -> rax = 0
focus_topmost:
    mov rdx, [rsi + Surface.output]
; The same with rdx an output (0: no screen, none), skipping rsi (0: nothing)
focus_topmost_on:
    test rdx, rdx
    jz .none
    mov rax, [rdi + Server.stack]
    xor ecx, ecx
.walk:
    test rax, rax
    jz .found
    cmp rax, rsi
    je .next
    cmp qword [rax + Surface.current + SurfaceState.buffer], 0
    je .next
    push rax
    push rcx
    push rsi
    push rdi
    mov rdi, rax
    call takes_keyboard_on_show
    mov edx, eax
    pop rdi
    pop rsi
    pop rcx
    pop rax
    test edx, edx
    jz .next
    mov rcx, rax                        ; bottom to top: the last one wins
.next:
    mov rax, [rax + Surface.z_order_next]
    jmp .walk
.found:
    mov rsi, rcx
    jmp input_focus_surface
.none:
    xor esi, esi
    jmp input_focus_surface
