; ============================================================================
; Client Lifecycle — Connection, Handshake, Teardown
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/caps.inc"
%include "inc/channel.inc"
%include "inc/handle.inc"
%include "inc/struct_offsets.inc"
%include "inc/log.inc"

extern arena_alloc
extern arena_init
extern client_registry_init
extern client_registry_add
extern client_registry_remove
extern client_registry_find
extern handle_table_init
extern channel_init
extern auth_handshake
extern surface_destroy_client
extern window_list_forget
extern regions_destroy_client
extern fence_destroy_client
extern timeline_destroy_client
extern clipboard_client_gone
extern output_client_gone
extern seat_client_gone
extern buffer_destroy_client

%define CLIENT_CONNECTING   1
%define CLIENT_ACTIVE       2
%define CLIENT_THROTTLED    3
%define CLIENT_DEAD         4

%define CLIENT_REGION_BYTES (1024 * 1024)  ; channels take most of it
%define CLIENT_OBJECTS      4096

section .text

; ---------------------------------------------------------------------------
; client_init
;   Initialize client subsystem
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0 OK
; ---------------------------------------------------------------------------
global client_init
client_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12

    mov rdi, r12
    mov rsi, 16
    call arena_alloc
    test rax, rax
    jz .init_oom
    mov r13, rax
    mov rdi, r13
    mov rsi, r12
    call client_registry_init
    test rax, rax
    js .init_out
    mov [rbx + Server.client_registry], r13
    mov qword [rbx + Server.next_client_id], 1
    mov qword [rbx + Server.arena], r12
    xor rax, rax
.init_out:
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.init_oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; client_accept
;   Accept new client connection. A client owns one memory region holding its
;   arena, Client, object table, channels and registry node, so that a
;   disconnect frees everything at once whatever order clients leave in.
;   IN:  rdi = server*, rsi = ChannelPair* (filled in for the client's end),
;        rdx = capabilities wanted
;   OUT: rax = client_id, negative error
;
; client_accept gives the client the standard trust profile, which grants no
; privileged capability. client_accept_trusted, for canvasd's own clients
; (the greeter, a taskbar), gives it the trusted one, until profiles come
; from the trust store (SEC-02).
; ---------------------------------------------------------------------------
global client_accept
client_accept:
    mov ecx, TRUST_STANDARD
    jmp accept_as

global client_accept_trusted
client_accept_trusted:
    mov ecx, TRUST_TRUSTED

; As client_accept; rcx = the trust profile
%define ACCEPT_FRAME ((((ChannelPair_size + 24 + 56) + 15) & ~15) - 56)
accept_as:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, ACCEPT_FRAME               ; the pair, caps wanted, trust;
                                        ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov [rsp + ChannelPair_size], rdx
    mov [rsp + ChannelPair_size + 8], rcx
    ASSERT_PTR rbx
    ASSERT_PTR r12

    ; The client's region, starting with its arena
    mov edi, CLIENT_REGION_BYTES
    xor esi, esi
    call ut_mem_alloc
    test rax, rax
    js .out
    mov r13, rax                        ; arena*
    mov r15, r8                         ; region handle
    mov rdi, r13
    lea rsi, [r13 + Arena_size]
    mov edx, CLIENT_REGION_BYTES - Arena_size
    call arena_init

    mov rdi, r13
    mov esi, Client_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r14, rax                        ; client*
    mov rdi, rax
    xor eax, eax
    mov ecx, Client_size
    rep stosb

    mov rax, [rbx + Server.next_client_id]
    inc qword [rbx + Server.next_client_id]
    mov [r14 + Client.id], rax
    mov rax, [rsp + ChannelPair_size + 8]
    mov [r14 + Client.trust_profile], rax
    mov [r14 + Client.arena], r13
    mov [r14 + Client.region], r15
    mov byte [r14 + Client.state], CLIENT_CONNECTING

    ; Object table
    mov rdi, r13
    mov esi, HandleTable_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r14 + Client.obj_table], rax
    mov rdi, rax
    mov rsi, r13
    mov edx, CLIENT_OBJECTS
    call handle_table_init
    test rax, rax
    js .fail

    ; Channels: the server writes what the client reads
    mov rdi, rsp
    mov rsi, r13
    xor edx, edx
    xor ecx, ecx
    call channel_init
    test rax, rax
    js .fail
    mov rax, [rsp + ChannelPair.server_to_client]
    mov [r14 + Client.rx_ring], rax
    mov rax, [rsp + ChannelPair.client_to_server]
    mov [r14 + Client.tx_ring], rax
    mov rax, [rsp + ChannelPair.server_to_client_handles]
    mov [r14 + Client.handle_rx], rax
    mov rax, [rsp + ChannelPair.client_to_server_handles]
    mov [r14 + Client.handle_tx], rax
    mov rax, [rbx + Server.loop_task]   ; whom its sends wake
    mov [rsp + ChannelPair.wake_task], rax
    mov qword [rsp + ChannelPair.wakes], 0
    mov rdi, r12                        ; up to state: state and region are
    mov rsi, rsp                        ; the caller's (canvas_connect's)
    mov ecx, ChannelPair.state
    rep movsb

    mov rdi, [rbx + Server.client_registry]
    mov rsi, [r14 + Client.id]
    mov rdx, r14
    mov rcx, r13
    call client_registry_add
    test rax, rax
    js .fail

    ; Grant capabilities; the client reads them first
    mov rdi, r14
    mov rsi, [rsp + ChannelPair_size]
    call auth_handshake
    test rax, rax
    js .unlink

    mov byte [r14 + Client.state], CLIENT_ACTIVE
    mov [r14 + Client.server], rbx
    mov rax, [rbx + Server.client_list]
    mov [r14 + Client.next_client], rax
    mov [rbx + Server.client_list], r14
    mov edi, LOG_CAT_CLIENT
    lea rsi, [rel log_connected]
    mov edx, log_connected_len
    call log_info
    mov rax, [r14 + Client.id]
.out:
    add rsp, ACCEPT_FRAME
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.unlink:
    mov r13, rax
    mov rdi, [rbx + Server.client_registry]
    mov rsi, [r14 + Client.id]
    call client_registry_remove
    mov rax, r13
    jmp .fail
.oom:
    mov rax, -(ENOMEM)
.fail:
    mov r13, rax
    mov rdi, r15
    call ut_mem_free
    mov rax, r13
    jmp .out

; ---------------------------------------------------------------------------
; client_disconnect
;   Clean up client on disconnect: everything it owned goes with its region
;   IN:  rdi = server*, rsi = client_id
;   OUT: rax = 0 OK, -ESRCH
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
    call client_registry_find
    test rax, rax
    jz .not_found
    mov r13, rax

    ; Mark state
    mov byte [r13 + Client.state], CLIENT_DEAD

    ; Off the list the event loop walks
    lea rcx, [rbx + Server.client_list]
.find:
    mov rax, [rcx]
    test rax, rax
    jz .unlisted
    cmp rax, r13
    je .unlist
    lea rcx, [rax + Client.next_client]
    jmp .find
.unlist:
    mov rax, [r13 + Client.next_client]
    mov [rcx], rax
.unlisted:

    ; What the server tables know of it, and the window list
    mov rdi, rbx
    mov rsi, r13
    call window_list_forget
    mov rdi, rbx
    mov rsi, r13
    call regions_destroy_client
    mov rdi, rbx
    mov rsi, r13
    call fence_destroy_client
    mov rdi, rbx
    mov rsi, r13
    call timeline_destroy_client
    mov rdi, rbx
    mov rsi, r13
    call clipboard_client_gone
    mov rdi, rbx
    mov rsi, r13
    call output_client_gone
    mov rdi, rbx
    mov rsi, r13
    call seat_client_gone
    mov rdi, rbx
    mov rsi, r13
    call surface_destroy_client
    mov rdi, rbx
    mov rsi, r13
    call buffer_destroy_client

    ; Unlink first: the registry node lives in the region
    mov rdi, [rbx + Server.client_registry]
    mov rsi, r12
    call client_registry_remove

    mov rdi, [r13 + Client.region]
    call ut_mem_free

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
    ASSERT_PTR rdi
    mov rdi, [rdi + Server.client_registry]
    test rdi, rdi
    jnz client_registry_find
    xor eax, eax
    ret

section .rodata
log_connected:  db "a client connected"
log_connected_len: equ $ - log_connected

section .data
global client_version
client_version: dq 0x010100
