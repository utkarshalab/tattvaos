; ============================================================================
; Displays — Screens Plugged In and Taken Out
; ============================================================================
; The kernel tells of a display plugged in or taken out through the function
; given to ut_display_register_callback (KERNEL_NEEDS.md, step 5): rdi = an
; 8-byte record, a u32 type (1 added, 2 removed) and a u32 framebuffer index
; as ut_fb_info counts them, rsi = the server. displays_event only copies the
; record into a small ring; displays_step, between turns, acts on what is
; there: an added framebuffer becomes an output to the right of the layout
; (fb_linear_add_output, server_place_output), shown in its own display
; memory; the output of a removed one goes (server_remove_output), unless it
; is the last. Taskbars follow at the next taskbar_step_all.
;
; Only a server started on a framebuffer (the fb_linear backend) takes new
; ones; a headless one has no display memory to show them in. Without the
; kernel's export (-ENOSYS) nothing is ever reported, and nothing changes.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern fb_linear_add_output
extern fb_linear_flip
extern server_place_output
extern server_remove_output
extern server_wake

%define DISPLAY_ADDED       1
%define DISPLAY_REMOVED     2
%define DISPLAY_RING        16          ; reports held between turns

section .text

; ---------------------------------------------------------------------------
; displays_start
;   Ask the kernel to tell of displays coming and going
;   IN:  rdi = server*
;   OUT: rax = 0, or the kernel's negative error (-ENOSYS without it)
; ---------------------------------------------------------------------------
global displays_start
displays_start:
    sub rsp, 8
    mov rsi, rdi
    lea rdi, [rel displays_event]
    call ut_display_register_callback
    add rsp, 8
    ret

; ---------------------------------------------------------------------------
; displays_event
;   The kernel's call: the record kept for displays_step; with the ring
;   full it is counted and lost
;   IN:  rdi = the 8-byte record, rsi = the server
; ---------------------------------------------------------------------------
global displays_event
displays_event:
    mov eax, [rel ring_tail]
    mov ecx, eax
    sub ecx, [rel ring_head]
    cmp ecx, DISPLAY_RING
    jae .full
    and eax, DISPLAY_RING - 1
    lea rcx, [rel ring]
    mov rdx, [rdi]
    mov [rcx + rax * 8], rdx
    inc dword [rel ring_tail]
    mov rdi, rsi                        ; the loop woken to act on it
    jmp server_wake
.full:
    inc dword [rel dropped]
    ret

; ---------------------------------------------------------------------------
; displays_step
;   Every report held: a display added gets an output, a display removed
;   loses its own; between turns
;   IN:  rdi = server*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global displays_step
displays_step:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, FB_INFO_BYTES              ; what ut_fb_info fills; aligned
    mov rbx, rdi
.next:
    mov eax, [rel ring_head]
    cmp eax, [rel ring_tail]
    je .done
    and eax, DISPLAY_RING - 1
    lea rcx, [rel ring]
    mov r12d, [rcx + rax * 8]           ; the type
    mov r13d, [rcx + rax * 8 + 4]       ; the framebuffer's index
    inc dword [rel ring_head]
    cmp r12d, DISPLAY_ADDED
    je .added
    cmp r12d, DISPLAY_REMOVED
    jne .next
    mov rsi, [rbx + Server.outputs]     ; its output, if it has one
.find:
    test rsi, rsi
    jz .next
    cmp qword [rsi + Output.scanout], 0
    je .other
    cmp [rsi + Output.fb_index], r13d
    je .remove
.other:
    mov rsi, [rsi + Output.next]
    jmp .find
.remove:
    mov rdi, rbx                        ; the last one stays (-EBUSY)
    call server_remove_output
    jmp .next
.added:
    mov rax, [rbx + Server.backend]     ; only on a framebuffer
    lea rcx, [rel fb_linear_flip]
    cmp [rax + Backend.flip], rcx
    jne .next
    mov rsi, [rbx + Server.outputs]     ; not one shown already
.shown:
    test rsi, rsi
    jz .ask
    cmp qword [rsi + Output.scanout], 0
    je .not_it
    cmp [rsi + Output.fb_index], r13d
    je .next
.not_it:
    mov rsi, [rsi + Output.next]
    jmp .shown
.ask:
    mov dword [rsp + FB_INFO_FLAGS], 0  ; for a kernel that does not say
    mov rdi, rsp
    mov esi, r13d
    call ut_fb_info
    test rax, rax
    js .next
    mov rdi, [rbx + Server.backend]
    mov rsi, rsp
    mov edx, r13d
    call fb_linear_add_output
    test rax, rax
    jz .next
    mov rdi, rbx
    mov rsi, rax
    call server_place_output
    jmp .next
.done:
    xor eax, eax
    add rsp, FB_INFO_BYTES
    EPILOGUE_RESTORE rbx, r12, r13

section .bss
alignb 8
ring:           resq DISPLAY_RING       ; type, index
ring_head:      resd 1
ring_tail:      resd 1
dropped:        resd 1

section .data
global displays_version
displays_version: dq 0x010000
