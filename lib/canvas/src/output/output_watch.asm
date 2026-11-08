; ============================================================================
; Output Watch — What Clients Learn of the Outputs (cw_output)
; ============================================================================
; The first step of decision 0012: a client can learn each output's place,
; logical size and scale. cw_output.list answers with an output event for
; each output and then done, and keeps the client told: output again for one
; added, back from mirroring or with a new scale, removed for one taken away
; or made a mirror. A mirror is no part of the layout and is not listed.
; Scales go out in 120ths (120 is 1, 180 is 1.5). Places and sizes are in
; the layout's logical units: an output's size is its pixel size divided by
; its scale (output/output_scale).
;
; Each output gets an id the first time it is told of (Output.id, from
; Server.output_seq); up to OUTPUT_WATCHERS clients watch.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"

extern sync_event

section .text

; ---------------------------------------------------------------------------
; output_list
;   Every output to the client, then done; it is told of changes from now
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0, -ENOSPC with OUTPUT_WATCHERS watching already
; ---------------------------------------------------------------------------
global output_list
output_list:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    xor ecx, ecx                        ; watching already, or a free place
    mov edx, -1
.find:
    mov rax, [rbx + Server.output_watchers + rcx * 8]
    cmp rax, r12
    je .watching
    test rax, rax
    jnz .next
    cmp edx, -1
    jne .next
    mov edx, ecx
.next:
    inc ecx
    cmp ecx, OUTPUT_WATCHERS
    jb .find
    mov rax, -(ENOSPC)
    cmp edx, -1
    je .out
    mov [rbx + Server.output_watchers + rdx * 8], r12
.watching:
    mov r13, [rbx + Server.outputs]
.output:
    test r13, r13
    jz .done
    cmp qword [r13 + Output.mirror_of], 0
    jne .skip
    mov rdi, rbx
    mov rsi, r12
    mov rdx, r13
    call tell_output
.skip:
    mov r13, [r13 + Output.next]
    jmp .output
.done:
    mov rdi, r12                        ; and that is all of them
    mov esi, CWP_OBJ_OUTPUT
    mov edx, OUTPUT_EV_DONE
    xor ecx, ecx
    xor r8d, r8d
    call sync_event
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; output_announce
;   An output added, back from mirroring, or changed: to every watcher
;   IN:  rdi = server*, rsi = Output*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global output_announce
output_announce:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    cmp qword [r12 + Output.mirror_of], 0
    jne .done
    xor r13d, r13d
.watcher:
    mov rsi, [rbx + Server.output_watchers + r13 * 8]
    test rsi, rsi
    jz .next
    mov rdi, rbx
    mov rdx, r12
    call tell_output
.next:
    inc r13d
    cmp r13d, OUTPUT_WATCHERS
    jb .watcher
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; output_withdraw
;   An output taken away or made a mirror: removed(id) to every watcher
;   IN:  rdi = server*, rsi = Output*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global output_withdraw
output_withdraw:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov rdi, rsi
    call id_of
    mov [rsp], eax
    xor r13d, r13d
.watcher:
    mov rdi, [rbx + Server.output_watchers + r13 * 8]
    test rdi, rdi
    jz .next
    mov esi, CWP_OBJ_OUTPUT
    mov edx, OUTPUT_EV_REMOVED
    mov rcx, rsp
    mov r8d, 4
    call sync_event
.next:
    inc r13d
    cmp r13d, OUTPUT_WATCHERS
    jb .watcher
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; output_client_gone
;   A client going watches no more
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global output_client_gone
output_client_gone:
    xor ecx, ecx
.next:
    cmp [rdi + Server.output_watchers + rcx * 8], rsi
    jne .other
    mov qword [rdi + Server.output_watchers + rcx * 8], 0
.other:
    inc ecx
    cmp ecx, OUTPUT_WATCHERS
    jb .next
    xor eax, eax
    ret

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; rdi = server, rsi = client, rdx = Output*: output(id, x, y, width, height,
; scale in 120ths) to it
tell_output:
    push rbx
    sub rsp, 32                         ; the event; 16-byte aligned
    mov rbx, rsi
    mov rdi, rdx
    call id_of
    mov [rsp], eax
    mov eax, [rdx + Output.x]
    mov [rsp + 4], eax
    mov eax, [rdx + Output.y]
    mov [rsp + 8], eax
    mov eax, [rdx + Output.width]
    mov [rsp + 12], eax
    mov eax, [rdx + Output.height]
    mov [rsp + 16], eax
    mov rax, [rdx + Output.scale]       ; 16.16 to 120ths, rounded; 0 is 1
    test rax, rax
    jnz .scaled
    mov eax, 0x10000
.scaled:
    imul rax, rax, 120
    add rax, 0x8000
    shr rax, 16
    mov [rsp + 20], eax
    mov rdi, rbx
    mov esi, CWP_OBJ_OUTPUT
    mov edx, OUTPUT_EV_OUTPUT
    mov rcx, rsp
    mov r8d, 24
    call sync_event
    add rsp, 32
    pop rbx
    ret

; rdi = Output* -> eax = its id, given the first time; rdx = the Output*
id_of:
    mov rdx, rdi
    mov rax, [rdx + Output.id]
    test rax, rax
    jnz .out
    mov rcx, [rdx + Output.backend]
    mov rcx, [rcx + Backend.server]
    inc qword [rcx + Server.output_seq]
    mov rax, [rcx + Server.output_seq]
    mov [rdx + Output.id], rax
.out:
    ret

section .data
global output_watch_version
output_watch_version: dq 0x010000
