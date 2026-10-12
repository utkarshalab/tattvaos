; ============================================================================
; Debug Interface — Privileged Live Inspection (cw_debug)
; Scene dump, client list, stats, trace control
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

; ---------------------------------------------------------------------------
; debug_iface_init
; ---------------------------------------------------------------------------
global debug_iface_init
debug_iface_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov qword [rbx + Server.debug], 0
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; debug_check
;   Gate cw_debug: requires CAP_DEBUG via gate_check
; ---------------------------------------------------------------------------
global debug_check
debug_check:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    mov rdx, CAP_DEBUG
    call gate_check
    ret

; ---------------------------------------------------------------------------
; debug_scene_dump
;   Dump scene graph summary into buffer
;   IN: rdi=server*, rsi=out_buf, rdx=out_len
;   OUT: rax = bytes written
; ---------------------------------------------------------------------------
global debug_scene_dump
debug_scene_dump:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; header: "canvas scene v1\n"
    mov r14, scene_hdr
    mov rdi, r12
    mov rsi, r14
    call str_copy
    ; TODO: walk surfaces/outputs and append lines
    mov rax, 17
    ret

; ---------------------------------------------------------------------------
; debug_client_list
;   List clients: id, caps, surfaces, memory
; ---------------------------------------------------------------------------
global debug_client_list
debug_client_list:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    ; TODO: iterate registry, format lines
    xor rax, rax
    ret

; ---------------------------------------------------------------------------
; debug_trace_control
;   Enable/disable trace categories + clear
; ---------------------------------------------------------------------------
global debug_trace_control
debug_trace_control:
    PROLOGUE_SAVE rbx
    mov rbx, rdi
    ASSERT_PTR rbx
    cmp rsi, 0
    je .clear
    cmp rsi, 1
    je .set_mask
    jmp .invalid
.set_mask:
    mov rdi, rbx
    mov rsi, rdx
    call trace_set_mask
    ret
.clear:
    mov rdi, rbx
    call trace_clear
    ret
.invalid:
    RETURN_ERROR EINVAL

; ---------------------------------------------------------------------------
; debug_metrics_dump
; ---------------------------------------------------------------------------
global debug_metrics_dump
debug_metrics_dump:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, rbx
    mov rsi, r12
    call metrics_snapshot
    ret

section .rodata
scene_hdr: db "canvas scene v1", 10, 0

section .data
global debug_iface_version
debug_iface_version: dq 0x010000
