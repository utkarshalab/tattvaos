; ============================================================================
; Debug Interface — Privileged Live Inspection (cw_debug)
; Scene dump, client list, stats, trace control
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/caps.inc"
%include "inc/struct_offsets.inc"

extern gate_check
extern metrics_snapshot
extern trace_clear
extern trace_set_mask

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
    EPILOGUE_RESTORE rbx, r12
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
    EPILOGUE_RESTORE rbx, r12
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
    cmp r13, 18
    jb .scene_small
    mov rdi, r12
    mov rsi, scene_hdr
    mov rcx, 17
    rep movsb
    mov r14, 17
    mov rax, [rbx + Server.outputs]
.output_loop:
    test rax, rax
    jz .surface_begin
    cmp r14, r13
    jae .scene_done
    mov byte [r12 + r14], 'O'
    inc r14
    mov rax, [rax + Output.next]
    jmp .output_loop
.surface_begin:
    mov rax, [rbx + Server.surfaces]
.surface_loop:
    test rax, rax
    jz .scene_done
    cmp r14, r13
    jae .scene_done
    mov byte [r12 + r14], 'S'
    inc r14
    mov rax, [rax + Surface.z_order_next]
    jmp .surface_loop
.scene_done:
    cmp r14, r13
    jae .scene_return
    mov byte [r12 + r14], 10
    inc r14
.scene_return:
    mov rax, r14
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.scene_small:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; ---------------------------------------------------------------------------
; debug_client_list
;   List clients: id, caps, surfaces, memory
; ---------------------------------------------------------------------------
global debug_client_list
debug_client_list:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r13, rdx
    test r13, r13
    jz .clients_full
    mov rax, [rbx + Server.client_registry]
    test rax, rax
    jz .clients_empty
    mov rdi, [rax]
    mov rsi, r12
    mov rdx, r13
    call debug_emit_clients
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.clients_empty:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret
.clients_full:
    mov rax, -(ENOSPC)
    EPILOGUE_RESTORE rbx, r12, r13, r14
    ret

; In-order RB-tree dump, one native client id per 17-byte hexadecimal line.
debug_emit_clients:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    xor r14d, r14d
    test rbx, rbx
    jz .emit_done
    mov rdi, [rbx]
    mov rsi, r12
    mov rdx, r13
    call debug_emit_clients
    test rax, rax
    js .emit_out
    mov r14, rax
    mov rax, r13
    sub rax, r14
    cmp rax, 17
    jb .emit_space
    lea rdi, [r12 + r14]
    mov rsi, [rbx + 32]
    call debug_hex64
    add r14, 16
    mov byte [r12 + r14], 10
    inc r14
    mov rdi, [rbx + 8]
    lea rsi, [r12 + r14]
    mov rdx, r13
    sub rdx, r14
    call debug_emit_clients
    test rax, rax
    js .emit_out
    add r14, rax
.emit_done:
    mov rax, r14
.emit_out:
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.emit_space:
    mov rax, -(ENOSPC)
    jmp .emit_out

debug_hex64:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    mov ecx, 16
.hex_loop:
    rol r12, 4
    mov eax, r12d
    and eax, 15
    cmp eax, 10
    jb .hex_digit
    add eax, 'a' - 10
    jmp .hex_store
.hex_digit:
    add eax, '0'
.hex_store:
    mov [rbx], al
    inc rbx
    dec ecx
    jnz .hex_loop
    mov rax, 16
    EPILOGUE_RESTORE rbx, r12
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
    EPILOGUE_RESTORE rbx
    ret
.clear:
    mov rdi, rbx
    call trace_clear
    EPILOGUE_RESTORE rbx
    ret
.invalid:
    mov rax, -(EINVAL)
    EPILOGUE_RESTORE rbx
    ret

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
    EPILOGUE_RESTORE rbx, r12
    ret

section .rodata
scene_hdr: db "canvas scene v1", 10, 0

section .data
global debug_iface_version
debug_iface_version: dq 0x010000
