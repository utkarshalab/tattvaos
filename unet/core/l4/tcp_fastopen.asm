%ifndef GUARD_UNET_CORE_L4_TCP_FASTOPEN_ASM
%define GUARD_UNET_CORE_L4_TCP_FASTOPEN_ASM
; =============================================================================
; Tattva OS — unet/core/l4/tcp_fastopen.asm
; =============================================================================
; TCP Fast Open (RFC 7413)
;
; Allows data to be sent in SYN packet, reducing handshake latency.
; Uses TFO cookies for client authentication.
;
; Client flow:
;   1. Initial SYN: Request Fast Open cookie (Fast Open option with empty cookie)
;   2. Server responds with SYN-ACK + cookie
;   3. Subsequent connections: SYN + data + cookie
;
; Server flow:
;   1. Generate/maintain Fast Open key
;   2. Validate cookie on SYN with data
;   3. Accept data immediately if cookie valid
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define TFO_COOKIE_SIZE         16        ; 128-bit cookie
%define TFO_COOKIE_LIFETIME_MS  86400000  ; 24 hours
%define TFO_COOKIE_REQ_OPT      34        ; TCP Fast Open option (cookie request)
%define TFO_COOKIE_OPT          34        ; TCP Fast Open option (with cookie)
%define TFO_OPT_LEN_MIN         2         ; Kind + Length
%define TFO_OPT_LEN_COOKIE      18        ; Kind + Length + 16-byte cookie

%define TCBF_TFO_CLIENT         0x01      ; Client supports TFO
%define TCBF_TFO_SERVER         0x02      ; Server supports TFO
%define TCBF_TFO_COOKIE_VALID        0x04      ; Cookie is valid
%define TFO_COOKIE_EXPIRED      0x08      ; Cookie expired

struc tfo_cookie_t
    .data:            resb TFO_COOKIE_SIZE
    .timestamp:       resq 1      ; Creation timestamp
    .client_ip:       resd 1      ; Client IP (network order)
    .flags:           resb 1      ; TFO_COOKIE_* flags
    .pad:             resb 7
endstruc

struc tfo_context_t
    .server_key:      resb 32     ; Server secret key (256-bit)
    .cookie_lifetime: resd 1      ; Cookie lifetime in ms
    .queue_max:       resd 1      ; Max pending TFO connections
    .queue_len:       resd 1      ; Current pending TFO connections
    .flags:           resd 1      ; TCBF_TFO_SERVER, etc.
    .client_cache:    resq 1      ; Per-client cookie cache (hash table)
endstruc

%define TFO_MAX_QUEUE       100     ; Max pending TFO connections

section .bss
alignb 64
tfo_server_ctx:     resb tfo_context_t_size
tfo_client_cache:   resb kmem_cache_t_size
tfo_pending_cache:  resb kmem_cache_t_size

section .data
tfo_client_cache_name:  db "tfo_client_cookie", 0
tfo_pending_cache_name: db "tfo_pending_conn", 0

section .text

global tfo_init
global tfo_generate_cookie
global tfo_validate_cookie
global tfo_process_syn
global tfo_process_synack
global tfo_send_syn_with_data
global tfo_client_init
global tfo_server_enable
global tfo_client_cache_init
global tfo_pending_cache_init

; =============================================================================
; SipHash-2-4 for cookie generation/validation
; =============================================================================

; sip_round - Single SipHash round
%macro SIP_ROUND 0
    add rax, rcx
    rol rcx, 13
    xor rcx, rax
    rol rax, 32
    add rdx, r8
    rol r8, 16
    xor r8, rdx
    add rax, rcx
    rol rcx, 17
    xor rcx, rax
    rol rax, 32
    add rdx, r8
    rol r8, 21
    xor r8, rdx
%endmacro

; sip_hash_24 - SipHash-2-4
; Input: RDI = key (16 bytes), RSI = data, RDX = length
; Output: RAX = 64-bit hash
align 64
sip_hash_24:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi            ; key
    mov r13, rsi            ; data
    mov r14, rdx            ; length

    ; Load key (k0, k1)
    mov rax, [r12]
    mov rcx, [r12 + 8]

    ; Initialization constants
    mov rdx, 0x736f6d6570736575  ; "somepseu"
    xor rdx, [r12]
    mov r8, 0x646f72616e646f6d  ; "dorandom"
    xor r8, [r12 + 8]
    mov r9, 0x6c7967656e657261  ; "lygenera"
    xor r9, [r12]
    mov r10, 0x7465646279746573 ; "tedbytes"
    xor r10, [r12 + 8]

    ; Process data in 8-byte chunks
    mov r14, r14
    shr r14, 3
    test r14, r14
    jz .finalize

.chunk_loop:
    mov r9, [r13]
    add r13, 8
    xor r9, rdx
    SIP_ROUND
    SIP_ROUND
    dec r14
    jnz .chunk_loop

.finalize:
    ; Add padding and length
    ; Simplified finalization for cookie generation
    xor rax, rdx
    xor rax, r8
    xor rax, rcx
    xor rax, r10

    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_init — Initialize Fast Open subsystem
; -----------------------------------------------------------------------------
align 64
tfo_init:
    push rbp
    mov rbp, rsp
    push rbx

    ; Initialize server context
    lea rdi, [tfo_server_ctx]
    xor eax, eax
    mov rcx, tfo_context_t_size / 8
    rep stosq

    ; Generate server key (use RDRAND + TSC)
    lea rdi, [tfo_server_ctx + tfo_context_t.server_key]
    mov rcx, 4  ; 4 x 64-bit = 32 bytes
.gen_key:
    rdrand rax
    jnc .fallback
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .gen_key
    jmp .key_done

.fallback:
    call rdtsc_get_cycles
    mov [rdi], rax
    add rdi, 8
    dec rcx
    jnz .fallback

.key_done:
    ; Set defaults
    mov dword [tfo_server_ctx + tfo_context_t.cookie_lifetime], TFO_COOKIE_LIFETIME_MS
    mov dword [tfo_server_ctx + tfo_context_t.queue_max], TFO_MAX_QUEUE
    mov dword [tfo_server_ctx + tfo_context_t.flags], TCBF_TFO_SERVER

    ; Initialize client cookie cache
    call tfo_client_cache_init

    ; Initialize pending connection cache
    call tfo_pending_cache_init

    xor eax, eax
    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_client_cache_init — Initialize client cookie cache
; -----------------------------------------------------------------------------
align 64
tfo_client_cache_init:
    push rbp
    mov rbp, rsp
    push rbx

    lea rdi, [tfo_client_cache]
    lea rsi, [tfo_client_cache_name]
    mov rdx, tfo_cookie_t_size
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_pending_cache_init — Initialize pending TFO connection cache
; -----------------------------------------------------------------------------
align 64
tfo_pending_cache_init:
    push rbp
    mov rbp, rsp
    push rbx

    lea rdi, [tfo_pending_cache]
    lea rsi, [tfo_pending_cache_name]
    mov rdx, 64  ; pending connection struct size (estimate)
    mov rcx, 64
    xor r8, r8
    xor r9, r9
    call kmem_cache_create_in_place

    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_generate_cookie — Generate TFO cookie for client
; Input: EDI = client IP, ESI = server key index (unused, use main key)
; Output: RAX = 64-bit cookie (truncated from 128-bit)
; -----------------------------------------------------------------------------
align 64
tfo_generate_cookie:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi           ; client IP
    mov r13d, esi           ; key index (unused)

    ; Prepare input: client_ip | timestamp | server_secret
    call rdtsc_get_cycles
    mov r14, rax            ; timestamp

    ; Build input for hash: client_ip (4) | timestamp (8) | padding (4)
    sub rsp, 24
    mov [rsp], r12d
    mov [rsp + 4], r14d
    mov [rsp + 8], r14d     ; high 32 bits of timestamp
    mov dword [rsp + 12], 0
    mov dword [rsp + 16], 0
    mov dword [rsp + 20], 0

    ; Hash with server key
    lea rdi, [tfo_server_ctx + tfo_context_t.server_key]
    lea rsi, [rsp]
    mov rdx, 24
    call sip_hash_24
    add rsp, 24

    ; Truncate to 64-bit cookie
    ; Use lower 64 bits of hash
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_validate_cookie — Validate TFO cookie from client
; Input: EDI = client IP, RSI = cookie (64-bit)
; Output: RAX = 1 if valid, 0 if invalid/expired
; -----------------------------------------------------------------------------
align 64
tfo_validate_cookie:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov r12d, edi           ; client IP
    mov r13, rsi            ; cookie

    ; Generate expected cookie
    mov edi, r12d
    xor esi, esi
    call tfo_generate_cookie

    ; Compare
    cmp rax, r13
    je .check_timestamp

    ; Try with previous timestamp (allow 1 tick window)
    ; Simplified: just check exact match for now
    mov eax, 0
    jmp .done

.check_timestamp:
    ; Check if cookie is expired
    ; We'd need to store timestamp in cookie cache
    ; For now, accept if hash matches
    mov eax, 1

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_process_syn — Process incoming SYN for Fast Open
; Input: RDI = tcb_t* (listener), RSI = tcp_hdr_t*, RDX = net_pkt_t*
; Output: RAX = 1 if TFO cookie valid and data accepted, 0 otherwise
; -----------------------------------------------------------------------------
align 64
tfo_process_syn:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov rbx, rdi            ; listener tcb_t*
    mov r12, rsi            ; tcp_hdr_t*
    mov r13, rdx            ; net_pkt_t*

    ; Check if server has TFO enabled
    test dword [tfo_server_ctx + tfo_context_t.flags], TCBF_TFO_SERVER
    jz .no_tfo

    ; Check for Fast Open option in SYN
    ; Parse TCP options
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    movzx eax, al
    and eax, 0xF0
    shr eax, 4              ; data offset in 32-bit words
    cmp eax, 5
    jbe .no_options

    ; Parse options for Fast Open (kind=34)
    lea r14, [r12 + 20]     ; start of options
    mov r15d, eax
    shl r15d, 2             ; header length in bytes
    sub r15d, 20            ; options length

.parse_options:
    cmp r15d, 2
    jl .no_tfo

    movzx eax, byte [r14]
    cmp al, TFO_COOKIE_OPT
    je .found_tfo_option
    cmp al, 0
    je .no_tfo              ; EOL
    cmp al, 1
    je .skip_nop

    ; Multi-byte option
    movzx ecx, byte [r14 + 1]
    cmp r15d, ecx
    jl .no_tfo
    add r14, rcx
    sub r15d, ecx
    jmp .parse_options

.skip_nop:
    inc r14
    dec r15d
    jmp .parse_options

.found_tfo_option:
    ; Found Fast Open option
    movzx ecx, byte [r14 + 1]
    cmp cl, TFO_OPT_LEN_COOKIE
    jne .no_tfo

    ; Extract cookie (16 bytes after kind+len)
    lea r14, [r14 + 2]
    mov rax, [r14]
    mov rdx, [r14 + 8]

    ; Validate cookie
    mov edi, [rbx + tcb_t.local_ip]   ; server IP (listener)
    mov esi, [rbx + tcb_t.remote_ip]  ; client IP
    ; Need to extract client IP from packet - simplified
    ; For now, just validate the cookie value
    mov rsi, rax
    call tfo_validate_cookie
    test eax, eax
    jz .invalid_cookie

    ; Cookie valid! Accept TFO data
    ; Check if there's data in the SYN
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    and al, 0xF0
    shr al, 4
    shl eax, 2              ; header length in bytes
    mov ecx, [r13 + net_pkt_t.data_len]
    sub ecx, eax            ; payload length
    jle .no_data

    ; Valid TFO connection with data
    ; Mark TCB as TFO accepted
    or dword [rbx + tcb_t.flags], TCBF_TFO_CLIENT

    ; Store cookie for reference
    ; (would store in TCB for retransmission)

    mov eax, 1
    jmp .done

.no_data:
    ; SYN with valid cookie but no data - treat as regular SYN
    xor eax, eax
    jmp .done

.invalid_cookie:
    ; Invalid cookie - drop SYN or fall back to regular handshake
    ; Per RFC 7413, must fall back to regular handshake
    xor eax, eax

.no_options:
.no_tfo:
    xor eax, eax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_process_synack — Process SYN-ACK for Fast Open client
; Input: RDI = tcb_t*, RSI = tcp_hdr_t*
; -----------------------------------------------------------------------------
align 64
tfo_process_synack:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi

    ; Check for Fast Open cookie in SYN-ACK
    movzx eax, word [r12 + tcp_hdr_t.data_offset_flags]
    rol ax, 8
    movzx eax, al
    and eax, 0xF0
    shr eax, 4
    cmp eax, 5
    jbe .done

    ; Parse options for cookie
    lea r12, [r12 + 20]
    mov r13d, eax
    shl r13d, 2
    sub r13d, 20

.parse_loop:
    cmp r13d, 2
    jl .done
    movzx eax, byte [r12]
    cmp al, TFO_COOKIE_OPT
    je .found_cookie
    cmp al, 0
    je .done
    cmp al, 1
    je .skip_nop
    movzx ecx, byte [r12 + 1]
    add r12, rcx
    sub r13d, ecx
    jmp .parse_loop

.skip_nop:
    inc r12
    dec r13d
    jmp .parse_loop

.found_cookie:
    ; Extract and store cookie for future connections
    movzx ecx, byte [r12 + 1]
    cmp cl, TFO_OPT_LEN_COOKIE
    jne .done
    lea r12, [r12 + 2]
    mov rax, [r12]
    mov rdx, [r12 + 8]

    ; Store cookie in client cache
    ; (would need client IP context)
    ; For now, just mark as received
    or dword [rbx + tcb_t.flags], TCBF_TFO_COOKIE_VALID

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_send_syn_with_data — Send SYN with data and cookie (client side)
; Input: RDI = tcb_t*, RSI = data_ptr, RDX = data_len, RCX = cookie (optional)
; -----------------------------------------------------------------------------
align 64
tfo_send_syn_with_data:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13
    push r14

    mov rbx, rdi            ; tcb_t*
    mov r12, rsi            ; data pointer
    mov r13, rdx            ; data length
    mov r14, rcx            ; cookie (0 if none)

    ; Allocate packet
    call pktbuf_alloc
    test rax, rax
    jz .fail
    mov r12, rax            ; net_pkt_t*

    ; Ensure enough headroom for TCP + IP + Ethernet + Fast Open option
    cmp dword [r12 + net_pkt_t.headroom_offset], 20 + 20 + 14 + 18
    jb .free_fail

    sub dword [r12 + net_pkt_t.headroom_offset], 20 + 18  ; TCP header + Fast Open option
    mov dword [r12 + net_pkt_t.data_len], 20 + 18 + r13d

    ; Build TCP header with SYN + data
    mov rbx, r12
    mov edi, TCP_FLAG_SYN
    mov esi, r13d + 18      ; payload length including option
    call tcp_build_segment

    ; Add Fast Open option to TCP options
    mov rax, [r12 + net_pkt_t.virt_addr]
    add rax, [r12 + net_pkt_t.headroom_offset]
    lea r13, [rax + 20]     ; Start of options area

    ; Write Fast Open option with cookie
    mov byte [r13], TFO_COOKIE_OPT
    mov byte [r13 + 1], TFO_OPT_LEN_COOKIE
    test r14, r14
    jz .no_cookie
    mov [r13 + 2], r14      ; cookie low 64 bits
    mov [r13 + 10], rdx     ; cookie high 64 bits (if available)
    jmp .cookie_done

.no_cookie:
    ; Cookie request (empty cookie)
    mov qword [r13 + 2], 0
    mov qword [r13 + 10], 0

.cookie_done:
    ; Update data offset in TCP header
    mov rax, [r12 + net_pkt_t.virt_addr]
    add rax, [r12 + net_pkt_t.headroom_offset]
    movzx ecx, word [rax + tcp_hdr_t.data_offset_flags]
    rol cx, 8
    and cl, 0xF0
    shr cl, 4
    add cl, 2               ; 20 + 18 = 38 bytes = 9.5 -> 10 32-bit words
    shl cl, 4
    or cl, ch               ; preserve flags
    rol cx, 8
    mov [rax + tcp_hdr_t.data_offset_flags], cx

    ; Update data_len
    mov eax, [r12 + net_pkt_t.data_len]
    add eax, 18
    mov [r12 + net_pkt_t.data_len], eax

    ; Set ECN flags
    mov rdi, rbx
    mov rsi, rax
    call tcp_ecn_syn_sent

    ; Calculate checksum and send
    mov rdi, r12
    mov esi, [rbx + tcb_t.remote_ip]
    mov dl, IP_PROTO_TCP
    mov dh, 0
    call tcp_ecn_get_flags
    mov dl, al
    mov dh, ah
    call ip_output

    mov rax, r12
    jmp .done

.free_fail:
    mov rdi, r12
    call pktbuf_free
.fail:
    xor rax, rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_client_init — Initialize TFO for client socket
; Input: RDI = tcb_t*
; -----------------------------------------------------------------------------
align 64
tfo_client_init:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi

    ; Check if client has cached cookie for this server
    ; (would look up in client cookie cache)
    ; For now, just enable TFO flag
    or dword [rbx + tcb_t.flags], TCBF_TFO_CLIENT

    xor eax, eax
    pop rbx
    pop rbp
    ret

; =============================================================================
; tfo_server_enable — Enable/disable Fast Open on listener
; Input: RDI = tcb_t* (listener), RSI = 1 to enable, 0 to disable
; -----------------------------------------------------------------------------
align 64
tfo_server_enable:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    test esi, esi
    jz .disable

    or dword [tfo_server_ctx + tfo_context_t.flags], TCBF_TFO_SERVER
    or dword [rbx + tcb_t.flags], TCBF_TFO_SERVER
    xor eax, eax
    jmp .done

.disable:
    and dword [tfo_server_ctx + tfo_context_t.flags], ~TCBF_TFO_SERVER
    and dword [rbx + tcb_t.flags], ~TCBF_TFO_SERVER
    xor eax, eax

.done:
    pop rbx
    pop rbp
    ret

%endif ; GUARD_UNET_CORE_L4_TCP_FASTOPEN_ASM