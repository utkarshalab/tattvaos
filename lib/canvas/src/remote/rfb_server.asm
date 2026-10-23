; ============================================================================
; RFB Server — TLS-Wrapped VNC-Compatible Server (no legacy VNC auth)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
extern arena_alloc
extern rfb_client_update
extern rfb_handshake
extern ut_tls_accept
extern ut_tls_close
extern ut_tls_listen

%define RFB_PORT_DEFAULT  5900
%define RFB_VERSION_STR   "RFB 003.008\n"

section .text

; ---------------------------------------------------------------------------
; rfb_server_init
; ---------------------------------------------------------------------------
global rfb_server_init
rfb_server_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, RfbServer_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov rbx, rax
    mov qword [rbx + RfbServer.server], rdi
    mov qword [rbx + RfbServer.listener], 0
    mov dword [rbx + RfbServer.port], RFB_PORT_DEFAULT
    mov qword [rbx + RfbServer.clients], 0
    mov qword [rbx + RfbServer.client_count], 0
    mov qword [rbx + RfbServer.voutput], r13
    mov byte [rbx + RfbServer.running], 0
    mov qword [rdi + Server.rfb], rbx
    mov rax, rbx
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; rfb_server_listen
;   IN: rdi = rfb*, rsi = port, rdx = cert_pem, rcx = cert_len, r8 = key
; ---------------------------------------------------------------------------
global rfb_server_listen
rfb_server_listen:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov dword [rbx + RfbServer.port], r12d
    call ut_tls_listen
    test rax, rax
    js .fail
    mov [rbx + RfbServer.listener], rax
    mov byte [rbx + RfbServer.running], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rfb_server_accept
;   Accept one client, run handshake
; ---------------------------------------------------------------------------
global rfb_server_accept
rfb_server_accept:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    cmp byte [rbx + RfbServer.running], 0
    je .not_running
    mov rdi, [rbx + RfbServer.listener]
    mov rsi, 0  ; infinite
    call ut_tls_accept
    test rax, rax
    js .accept_fail
    mov r12, rax
    ; allocate client
    mov rdi, [rbx + RfbServer.server]
    mov rdi, [rdi + Server.arena]
    mov rsi, RfbClient_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov qword [rax + RfbClient.server], rbx
    mov qword [rax + RfbClient.conn], r12
    mov dword [rax + RfbClient.width], 0
    mov dword [rax + RfbClient.height], 0
    mov byte [rax + RfbClient.shared], 0
    mov qword [rax + RfbClient.encodings], 0
    mov dword [rax + RfbClient.enc_count], 0
    ; link
    mov rdx, [rbx + RfbServer.clients]
    mov [rax + RfbClient.next], rdx
    mov [rbx + RfbServer.clients], rax
    inc qword [rbx + RfbServer.client_count]
    ; handshake
    mov rdi, rax
    call rfb_handshake
    test rax, rax
    jnz .hs_fail
    mov rax, r12
    EPILOGUE_RESTORE rbx, r12
    ret
.not_running:
    mov rax, -(ENOTCONN)
    EPILOGUE_RESTORE rbx, r12
    ret
.accept_fail:
    mov rax, -(ECONNREFUSED)
    EPILOGUE_RESTORE rbx, r12
    ret
.oom:
    mov rdi, r12
    call ut_tls_close
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12
    ret
.hs_fail:
    mov rdi, r12
    call ut_tls_close
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rfb_server_broadcast Damage — send dirty tiles to all clients
; ---------------------------------------------------------------------------
global rfb_server_update
rfb_server_update:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + RfbServer.clients]
    test r12, r12
    jz .done
.loop:
    mov rdi, r12
    call rfb_client_update
    mov r12, [r12 + RfbClient.next]
    test r12, r12
    jnz .loop
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

section .data
global rfb_server_version
rfb_server_version: dq 0x010000
