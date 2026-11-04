; ============================================================================
; Stacking — Surfaces Coming and Going
; ============================================================================
; A surface that shows its first buffer goes on top of its output and takes
; the keyboard. One that has the keyboard and stops showing anything, or is
; destroyed, hands it to the topmost surface still showing; with none left,
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
    mov rdi, rbx
    mov rsi, r12
    call input_focus_surface
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

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

; The keyboard to the topmost surface on rsi's output that shows a buffer,
; other than rsi; to none if there is none.
; rdi = server*, rsi = surface* -> rax = 0
focus_topmost:
    mov rax, [rsi + Surface.output]
    test rax, rax
    jz .none
    mov rax, [rax + Output.surfaces]
    xor ecx, ecx
.walk:
    test rax, rax
    jz .found
    cmp rax, rsi
    je .next
    cmp qword [rax + Surface.current + SurfaceState.buffer], 0
    je .next
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
