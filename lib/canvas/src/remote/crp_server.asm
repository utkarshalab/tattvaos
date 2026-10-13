; ============================================================================
; CRP — Canvas Remote Protocol (native, compressed, multi-viewer)
; Frame header + tile stream: tile(x,y,w,h,enc,len,payload)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"

; struct offsets (hoisted above use)
%define CrpServer_size    40
%define CRP_MAGIC        0x50524343  ; "CRCP"
%define CRP_VERSION      1
%define CRP_PORT_DEFAULT 5901
%define CrpFrameHdr_size    24
%define CrpTileHdr_size    12

section .text

struc CrpServer
    .server:         resq 1
    .listener:       resq 1
    .port:           resd 1
    .sessions:       resq 1
    .voutput:        resq 1
    .running:        resb 1
endstruc


struc CrpFrameHdr
    .magic:          resd 1
    .version:        resw 1
    .flags:         resw 1
    .seq:            resq 1
    .tile_count:     resd 1
    .total_bytes:    resd 1
endstruc

struc CrpTileHdr
    .x:             resw 1
    .y:             resw 1
    .w:             resw 1
    .h:             resw 1
    .enc:           resb 1
    .reserved:      resb 1
    .len:           resd 1
endstruc

; ---------------------------------------------------------------------------
; crp_server_init
; ---------------------------------------------------------------------------
global crp_server_init
crp_server_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, CrpServer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + CrpServer.server], rdi
    mov qword [rbx + CrpServer.listener], 0
    mov dword [rbx + CrpServer.port], CRP_PORT_DEFAULT
    mov qword [rbx + CrpServer.sessions], 0
    mov qword [rbx + CrpServer.voutput], r13
    mov byte [rbx + CrpServer.running], 0
    mov qword [rdi + Server.crp], rbx
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; crp_server_listen
; ---------------------------------------------------------------------------
global crp_server_listen
crp_server_listen:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov dword [rbx + CrpServer.port], r12d
    call tv_tls_listen
    test rax, rax
    js .fail
    mov [rbx + CrpServer.listener], rax
    mov byte [rbx + CrpServer.running], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; crp_send_frame
;   IN: rdi = CrpServer*, rsi = session (conn handle in rsi+8 layout)
;   Encodes all dirty tiles with adaptive choice
; ---------------------------------------------------------------------------
global crp_send_frame
crp_send_frame:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r13, [rbx + CrpServer.voutput]
    test r13, r13
    jz .done
    mov rdi, r13
    call virtual_output_damage
    test rax, rax
    jz .done
    ; frame header
    sub rsp, 64
    mov dword [rsp + 0], CRP_MAGIC
    mov word [rsp + 4], CRP_VERSION
    mov word [rsp + 6], 0
    mov rax, [r13 + VirtualOutput.seq]
    inc qword [r13 + VirtualOutput.seq]
    mov [rsp + 8], rax
    mov [rsp + 16], eax  ; tile count placeholder (patched below)
    mov dword [rsp + 20], 0
    mov rdi, [r12 + 8]  ; conn
    mov rsi, rsp
    mov rdx, CrpFrameHdr_size
    call rfb_tls_write_all
    ; TODO: tile loop with adaptive_choose + encoders
    add rsp, 64
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global crp_server_version
crp_server_version: dq 0x010000
