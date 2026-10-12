; ============================================================================
; Remote Backend — Virtual Outputs Viewed Over RFB/CRP
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

section .text

struc RemoteBackend {
    .voutput:       resq 1
    .rfb:           resq 1
    .crp:           resq 1
}
%define RemoteBackend_size    24

; ---------------------------------------------------------------------------
; remote_backend_init
; ---------------------------------------------------------------------------
global remote_backend_init
remote_backend_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Backend.arena]
    mov rsi, RemoteBackend_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov qword [r13 + RemoteBackend.voutput], 0
    mov qword [r13 + RemoteBackend.rfb], 0
    mov qword [r13 + RemoteBackend.crp], 0
    mov qword [rbx + Backend.state], r13
    ; default 1920x1080 virtual output
    mov rdi, [rbx + Backend.server]
    mov rsi, 1920
    mov rdx, 1080
    call virtual_output_create
    test rax, rax
    jz .oom
    mov [r13 + RemoteBackend.voutput], rax
    xor rax, rax
    ret
.oom:
    RETURN_ERROR ENOMEM

; ---------------------------------------------------------------------------
; remote_backend_flip
;   Composite done elsewhere; just bump seq + broadcast
; ---------------------------------------------------------------------------
global remote_backend_flip
remote_backend_flip:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + Backend.state]
    test r12, r12
    jz .done
    ; broadcast to RFB viewers
    mov rax, [r12 + RemoteBackend.rfb]
    test rax, rax
    jz .check_crp
    mov rdi, rax
    call rfb_server_update
.check_crp:
    mov rax, [r12 + RemoteBackend.crp]
    test rax, rax
    jz .done
    mov rdi, rax
    call crp_share_broadcast
.done:
    xor rax, rax
    ret

global remote_backend_deinit
remote_backend_deinit:
    PROLOGUE
    xor rax, rax
    ret

global remote_backend_modeset
remote_backend_modeset:
    PROLOGUE
    xor rax, rax
    ret

global remote_backend_vblank_wait
remote_backend_vblank_wait:
    PROLOGUE
    mov rdi, 16666667
    call tv_time_sleep_ns
    xor rax, rax
    ret

global remote_backend_hotplug
remote_backend_hotplug:
    PROLOGUE
    xor rax, rax
    ret

global remote_backend_cursor
remote_backend_cursor:
    PROLOGUE
    xor rax, rax
    ret

section .data
global remote_backend_version
remote_backend_version: dq 0x010000
