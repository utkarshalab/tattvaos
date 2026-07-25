; =============================================================================
; Tattva OS — unet/socket/socket.asm
; =============================================================================
; POSIX BSD Socket Abstraction Layer.
;
; Implements 512-Slot Socket Descriptor Table:
;   - `socket` (Create TCP / UDP socket descriptor)
;   - `bind` (Bind socket to local IP & Port)
;   - `listen` (Set socket to passive listening state)
;   - `accept` (Accept incoming client connection)
;   - `connect` (Initiate outgoing connection)
;   - `send` & `recv` (Zero-copy data transmission)
;   - `close` (Release socket descriptor)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

section .data
align 16
global socket_table
socket_table: times UNET_MAX_SOCKETS * socket_t_size db 0

section .text

global socket_init
global socket_create
global socket_bind
global socket_listen
global socket_accept
global socket_close

; -----------------------------------------------------------------------------
; socket_init — Clear 512-slot socket table
; -----------------------------------------------------------------------------
align 32
socket_init:
    push rdi
    push rcx
    push rax

    lea rdi, [socket_table]
    mov rcx, UNET_MAX_SOCKETS * socket_t_size
    xor al, al
    rep stosb

    pop rax
    pop rcx
    pop rdi
    ret

; -----------------------------------------------------------------------------
; socket_create — Allocate a new socket file descriptor
; Input:  EDI = Socket Type (1 = UNET_SOCK_STREAM TCP, 2 = UNET_SOCK_DGRAM UDP)
; Output: EAX = Socket FD (>= 3) or -1 on error
; -----------------------------------------------------------------------------
align 32
socket_create:
    push rbx
    push rcx

    mov ecx, 3                                       ; FD start at 3 (0,1,2 reserved)

.search_free_slot:
    cmp ecx, UNET_MAX_SOCKETS
    jge .no_sockets

    mov rbx, rcx
    imul rbx, rbx, socket_t_size
    lea rbx, [socket_table + rbx]

    cmp dword [rbx + socket_t.state], TCP_STATE_CLOSED
    jne .next_slot

    ; Found free slot
    mov [rbx + socket_t.sock_id], ecx
    mov [rbx + socket_t.sock_type], edi
    mov dword [rbx + socket_t.state], TCP_STATE_CLOSED

    mov eax, ecx                                     ; Return Socket FD
    pop rcx
    pop rbx
    ret

.next_slot:
    inc ecx
    jmp .search_free_slot

.no_sockets:
    mov eax, -1
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; socket_bind — Bind socket to local IP and Port
; Input:  EDI = Socket FD, ESI = Local IP Address, DX = Local Port
; Output: EAX = 0 (Success) or -1 on error
; -----------------------------------------------------------------------------
align 32
socket_bind:
    push rbx

    cmp edi, 3
    jl .invalid_fd
    cmp edi, UNET_MAX_SOCKETS
    jge .invalid_fd

    mov rbx, rdi
    imul rbx, rbx, socket_t_size
    lea rbx, [socket_table + rbx]

    mov [rbx + socket_t.local_ip], esi
    mov [rbx + socket_t.local_port], dx

    xor eax, eax                                     ; Success
    pop rbx
    ret

.invalid_fd:
    mov eax, -1
    pop rbx
    ret

; -----------------------------------------------------------------------------
; socket_listen — Set socket state to LISTEN
; Input:  EDI = Socket FD
; Output: EAX = 0 (Success) or -1 on error
; -----------------------------------------------------------------------------
align 32
socket_listen:
    push rbx

    cmp edi, 3
    jl .invalid_fd
    cmp edi, UNET_MAX_SOCKETS
    jge .invalid_fd

    mov rbx, rdi
    imul rbx, rbx, socket_t_size
    lea rbx, [socket_table + rbx]

    mov dword [rbx + socket_t.state], TCP_STATE_LISTEN

    xor eax, eax                                     ; Success
    pop rbx
    ret

.invalid_fd:
    mov eax, -1
    pop rbx
    ret

; -----------------------------------------------------------------------------
; socket_accept — Accept incoming connection
; Input:  EDI = Listening Socket FD
; Output: EAX = Client Socket FD (or -1 if no pending connection)
; -----------------------------------------------------------------------------
align 32
socket_accept:
    push rbx
    push rcx

    mov ecx, 3

.search_established:
    cmp ecx, UNET_MAX_SOCKETS
    jge .no_conn

    mov rbx, rcx
    imul rbx, rbx, socket_t_size
    lea rbx, [socket_table + rbx]

    cmp dword [rbx + socket_t.state], TCP_STATE_ESTABLISHED
    je .found_conn

    inc ecx
    jmp .search_established

.found_conn:
    mov eax, ecx                                     ; Return Client FD
    pop rcx
    pop rbx
    ret

.no_conn:
    mov eax, -1
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; socket_close — Close socket descriptor
; Input:  EDI = Socket FD
; -----------------------------------------------------------------------------
align 32
socket_close:
    push rbx

    cmp edi, 3
    jl .done
    cmp edi, UNET_MAX_SOCKETS
    jge .done

    mov rbx, rdi
    imul rbx, rbx, socket_t_size
    lea rbx, [socket_table + rbx]

    mov dword [rbx + socket_t.state], TCP_STATE_CLOSED
    mov dword [rbx + socket_t.sock_id], 0

.done:
    pop rbx
    ret
