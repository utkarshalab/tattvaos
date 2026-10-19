; ============================================================================
; RFB Handshake — Version + TLS-Only Security Handshake
; No legacy VNC authentication (TLS client cert / token instead)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"
extern rfb_auth

; struct offsets (hoisted above use)
%define RFB_VERSION_LEN   12
%define RFB_SEC_TLS       18  ; VeNCrypt-style TLS tunnel (our own subset)

section .text


; ---------------------------------------------------------------------------
; rfb_handshake
;   IN: rdi = RfbClient*
; ---------------------------------------------------------------------------
global rfb_handshake
rfb_handshake:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + RfbClient_conn]
    ; 1. send server version
    mov rdi, r12
    mov rsi, rfb_version_str
    mov rdx, RFB_VERSION_LEN
    call tv_tls_write
    cmp rax, RFB_VERSION_LEN
    jne .fail
    ; 2. read client version
    sub rsp, 16
    mov rdi, r12
    mov rsi, rsp
    mov rdx, RFB_VERSION_LEN
    call tv_tls_read
    cmp rax, RFB_VERSION_LEN
    jne .fail2
    ; accept 3.3/3.7/3.8
    mov rdi, rsp
    call rfb_check_version
    test rax, rax
    jz .fail2
    ; 3. security: exactly one type — TLS already established, then token auth
    sub rsp, 8
    mov byte [rsp + 0], 1  ; num types
    mov byte [rsp + 1], RFB_SEC_TLS
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 2
    call tv_tls_write
    add rsp, 8
    cmp rax, 2
    jne .fail2
    ; read client choice
    sub rsp, 8
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 1
    call tv_tls_read
    cmp rax, 1
    jne .fail3
    cmp byte [rsp], RFB_SEC_TLS
    jne .fail3
    add rsp, 8
    ; 4. token auth (server sends challenge request, client answers)
    mov rdi, rbx
    call rfb_auth
    test rax, rax
    jnz .fail2
    ; 5. ClientInit + ServerInit exchange
    mov rdi, rbx
    call rfb_client_init
    test rax, rax
    jnz .fail2
    mov rdi, rbx
    call rfb_server_init_msg
    add rsp, 16
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.fail3:
    add rsp, 8
.fail2:
    add rsp, 16
.fail:
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; rfb_check_version
; ---------------------------------------------------------------------------
global rfb_check_version
rfb_check_version:
    PROLOGUE
    ASSERT_PTR rdi
    ; "RFB 003.00x\n"
    cmp dword [rdi], 0x20424652  ; "RFB "
    jne .no
    cmp word [rdi + 4], 0x3030   ; "00"
    jne .no
    movzx eax, byte [rdi + 10]
    cmp al, '3'
    je .yes
    cmp al, '7'
    je .yes
    cmp al, '8'
    je .yes
.no:
    xor rax, rax
    leave
    ret
.yes:
    mov rax, 1
    leave
    ret

; ---------------------------------------------------------------------------
; rfb_client_init — read shared flag (1 byte)
; ---------------------------------------------------------------------------
global rfb_client_init
rfb_client_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + RfbClient_conn]
    sub rsp, 8
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 1
    call tv_tls_read
    cmp rax, 1
    jne .fail
    mov al, [rsp]
    mov [rbx + RfbClient.shared], al
    add rsp, 8
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    add rsp, 8
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; rfb_server_init_msg — framebuffer size, format, name
; ---------------------------------------------------------------------------
global rfb_server_init_msg
rfb_server_init_msg:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    ASSERT_PTR rbx
    mov r12, [rbx + RfbClient_conn]
    sub rsp, 32
    ; width/height from virtual output
    mov rax, [rbx + RfbClient.server]
    mov rax, [rax + RfbServer.voutput]
    mov rax, [rax + VirtualOutput.fb]
    movzx edx, word [rax + PixBuf.width]
    xchg dl, dh
    mov [rsp + 0], dx
    movzx edx, word [rax + PixBuf.height]
    xchg dl, dh
    mov [rsp + 2], dx
    ; pixel format: 32bpp, depth 24, bigendian 0, truecolor 1
    mov byte [rsp + 4], 32
    mov byte [rsp + 5], 24
    mov byte [rsp + 6], 0
    mov byte [rsp + 7], 1
    mov word [rsp + 8], 0x00FF  ; red max BE
    mov word [rsp + 10], 0x00FF
    mov word [rsp + 12], 0x00FF
    mov byte [rsp + 14], 16     ; red shift
    mov byte [rsp + 15], 8
    mov byte [rsp + 16], 0
    mov byte [rsp + 17], 0
    mov byte [rsp + 18], 0
    mov byte [rsp + 19], 0
    mov byte [rsp + 20], 0
    ; name length + name
    mov dword [rsp + 20], 6 | (0 << 24)  ; BE 6 -> store carefully
    mov dword [rsp + 20], 0x06000000
    mov dword [rsp + 24], 0x76747461  ; "tatt"
    mov word [rsp + 28], 0x6176      ; "va"
    mov rdi, r12
    mov rsi, rsp
    mov rdx, 30
    call tv_tls_write
    add rsp, 32
    cmp rax, 30
    jne .fail
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12
    ret

section .rodata
rfb_version_str: db "RFB 003.008", 10

section .data
global rfb_handshake_version
rfb_handshake_version: dq 0x010000
