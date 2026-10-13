; ============================================================================
; Client Lifecycle — Connection, Handshake, Teardown
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/caps.inc"
%include "inc/channel.inc"

; struct offsets (hoisted above use)
%define Server_client_registry   0
%define Server.client_registry 0
%define Server_next_client_id    8
%define Server.next_client_id 8
%define Server_arena             16
%define Server.arena 16
%define Server_size              24
%define Client_id               0
%define Client.id 0
%define Client_trust_profile    8
%define Client.trust_profile 8
%define Client_caps             16
%define Client.caps 16
%define Client_arena            24
%define Client.arena 24
%define Client_obj_table        32
%define Client.obj_table 32
%define Client_tx_ring          40
%define Client.tx_ring 40
%define Client_rx_ring          48
%define Client.rx_ring 48
%define Client_handle_tx        56
%define Client.handle_tx 56
%define Client_handle_rx        64
%define Client.handle_rx 64
%define Client_quota            72
%define Client.quota 72
%define Client_last_ping        104
%define Client.last_ping 104
%define Client_state            112
%define Client.state 112
%define Client_size             256
%define CLIENT_CONNECTING   1
%define CLIENT_ACTIVE       2
%define CLIENT_THROTTLED    3
%define CLIENT_DEAD         4

section .text

; ---------------------------------------------------------------------------
; client_init
;   Initialize client subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global client_init
client_init:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov qword [rbx + Server.client_registry], 0
    mov qword [rbx + Server.next_client_id], 1
    mov qword [rbx + Server.arena], r12
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; client_accept
;   Accept new client connection
;   IN:  rdi = server*, rsi = client_channel_pair*
;   OUT: rax = client_id, negative error
; ---------------------------------------------------------------------------
global client_accept
client_accept:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; Allocate client ID
    mov rax, [rbx + Server.next_client_id]
    inc qword [rbx + Server.next_client_id]
    mov r13, rax        ; client_id

    ; Allocate client struct
    mov rdi, r12
    mov rsi, 256        ; Client struct size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax        ; client*

    ; Initialize client
    mov qword [r14 + Client.id], r13
    mov qword [r14 + Client.trust_profile], TRUST_STANDARD
    mov qword [r14 + Client.caps], 0
    mov qword [r14 + Client.arena], 0
    mov qword [r14 + Client.obj_table], 0
    mov qword [r14 + Client.tx_ring], 0
    mov qword [r14 + Client.rx_ring], 0
    mov qword [r14 + Client.handle_tx], 0
    mov qword [r14 + Client.handle_rx], 0
    mov qword [r14 + Client.quota], 0
    mov qword [r14 + Client.last_ping], 0
    mov byte [r14 + Client.state], CLIENT_CONNECTING

    ; Create per-client arena
    mov rdi, r12
    mov rsi, 64 * 1024    ; 64KB initial
    lea rdx, [r14 + Client.arena]
    call arena_create
    test rax, rax
    jnz .arena_ok

    ; Cleanup on arena failure
    jmp .oom

.arena_ok:
    ; Initialize client object table
    mov rdi, [r14 + Client.arena]
    mov rsi, [r14 + Client.arena]
    mov rdx, 4096
    call handle_table_init
    test rax, rax
    jnz .objtable_ok
    jmp .oom

.objtable_ok:
    mov qword [r14 + Client.obj_table], rax

    ; Initialize channel pair
    mov rdi, [r14 + Client.tx_ring]
    mov rsi, [r14 + Client.arena]
    mov rdx, 256
    mov rcx, 16
    call channel_init
    test rax, rax
    jnz .oom

    ; Add to registry
    ; TODO: Insert into server's client registry (rbtree by client_id)

    ; Send capabilities negotiation
    call client_send_caps

    mov byte [r14 + Client.state], CLIENT_ACTIVE
    mov rax, r13
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

; ---------------------------------------------------------------------------
; client_send_caps
;   Send capabilities to client during handshake
; ---------------------------------------------------------------------------
client_send_caps:
    PROLOGUE_SAVE rbx, r12
    mov rbx, r14
    mov r12, [rbx + Client.tx_ring]
    ; TODO: Send cw_display.capabilities event
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; client_disconnect
;   Clean up client on disconnect
;   IN:  rdi = server*, rsi = client_id
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global client_disconnect
client_disconnect:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx

    ; Find client
    mov rdi, [rbx + Server.client_registry]
    mov rsi, r12
    call rbtree_find
    test rax, rax
    jz .not_found
    mov r13, rax

    ; Mark state
    mov byte [r13 + Client.state], CLIENT_DEAD

    ; Destroy client arena (frees everything)
    mov rdi, [r13 + Client.arena]
    call arena_destroy

    ; Remove from registry
    mov rdi, [rbx + Server.client_registry]
    mov rsi, r12
    call rbtree_remove

    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13
    ret

.not_found:
    mov rax, -(ESRCH)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; client_get
;   Lookup client by ID
;   IN:  rdi = server*, rsi = client_id
;   OUT: rax = client*, 0 if not found
; ---------------------------------------------------------------------------
global client_get
client_get:
    PROLOGUE
    ASSERT_PTR rdi
    mov rax, [rdi + Server.client_registry]
    test rax, rax
    jz .not_found
    call rbtree_find
    leave
    ret
.not_found:
    xor rax, rax
    leave
    ret

section .data




global client_version
client_version: dq 0x010000
