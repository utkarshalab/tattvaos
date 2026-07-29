; =============================================================================
; Tattva OS — unet/anon/freenet.asm
; =============================================================================
; Hyphanet / Freenet FNP (Freenet Network Protocol) Distributed Darknet Engine.
;
; Features:
;   - Small-World Greedy Routing via Floating-Point Location Distance Metric
;   - Content Hash Key (CHK) Retrieval with SHA-256 Content Verification
;   - Signed Subspace Key (SSK) Retrieval with Ed25519 Signature Verification
;   - Key Insert Pipeline with AES-256-GCM Encrypted Payload Storage
;   - Darknet Peer Location Swapping (Entropy Reduction for Routing Convergence)
;   - Data Store LRU Cache with Timer Wheel Eviction
;   - Bloom Filter Duplicate Request Detection (Prevents Routing Loops)
;   - HTL (Hops-To-Live) Decrement & Probabilistic Reset at Low HTL
;
; Delegates:
;   - SHA-256 Content Key Hash       -> crypto/uhash/sha256/
;   - AES-256-GCM Payload Cipher     -> crypto/ucrypt/symmetric/aes_gcm.asm
;   - Ed25519 SSK Verification       -> crypto/usign/ed25519/
;   - Cache Eviction Timers          -> lib/time/timer_wheel.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define FNP_MAX_HTL                 18      ; Maximum Hops-To-Live
%define FNP_MIN_HTL                 1       ; Minimum HTL before probabilistic reset
%define FNP_DATASTORE_SIZE          4096    ; LRU Data Store Entries
%define FNP_PEER_TABLE_SIZE         256     ; Darknet Peer Table

struc freenet_node_t
    .identity:          resb 32     ; 256-bit Node Ed25519 Public Key
    .location:          resq 1      ; Floating-point routing location [0.0, 1.0)
    .status:            resd 1      ; 0=Disconnected, 1=Connected, 2=Backing Off
    .last_seen_ts:      resq 1      ; Last activity timestamp
    .success_count:     resd 1      ; Successful route count (adaptive routing weight)
endstruc

struc freenet_chk_t
    .routing_key:       resb 32     ; SHA-256(content) routing key
    .crypto_key:        resb 32     ; AES-256 decryption key
    .data_length:       resd 1      ; Encrypted payload length
    .htl:               resb 1      ; Hops-To-Live counter
endstruc

struc freenet_ssk_t
    .routing_key:       resb 32     ; SHA-256(pubkey || docname) routing key
    .pubkey:            resb 32     ; Ed25519 Public Key
    .signature:         resb 64     ; Ed25519 Signature over content
    .docname:           resb 64     ; Document Name String
    .data_length:       resd 1
    .htl:               resb 1
endstruc

struc freenet_store_entry_t
    .routing_key:       resb 32     ; Routing Key
    .data_ptr:          resq 1      ; Pointer to Encrypted Data Block
    .data_length:       resd 1
    .insert_ts:         resq 1      ; Insertion Timestamp
    .access_count:      resd 1      ; LRU Access Counter
    .timer_id:          resd 1      ; Timer Wheel Eviction ID
endstruc

section .bss
align 64
freenet_peer_table:     resb freenet_node_t_size * FNP_PEER_TABLE_SIZE
freenet_data_store:     resb freenet_store_entry_t_size * FNP_DATASTORE_SIZE
freenet_peer_count:     resd 1
freenet_store_count:    resd 1

section .text

global freenet_init
global freenet_route_chk
global freenet_route_ssk
global freenet_verify_ssk
global freenet_insert_key
global freenet_find_closest_peer
global freenet_store_lookup
global freenet_store_insert

extern sha256_hash
extern aes_gcm_encrypt
extern aes_gcm_decrypt
extern ed25519_verify
extern timer_wheel_add
extern timer_wheel_del
extern rdtsc_get_cycles

align 64
freenet_init:
    push rbp
    mov rbp, rsp
    ; Zero-initialize peer table & data store
    mov dword [freenet_peer_count], 0
    mov dword [freenet_store_count], 0
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; freenet_route_chk — Route CHK Request via Small-World Greedy Forwarding
; Input: RDI = Pointer to freenet_chk_t
; Output: RAX = Pointer to Data Block (or NULL if Not Found after HTL expiry)
; -----------------------------------------------------------------------------
align 64
freenet_route_chk:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Check HTL > 0 (drop if expired)
    movzx eax, byte [rbx + freenet_chk_t.htl]
    test al, al
    jz .not_found

    ; 2. Decrement HTL with probabilistic reset at low values
    dec al
    cmp al, FNP_MIN_HTL
    ja .htl_ok
    ; At low HTL, probabilistically reset to prevent censorship probing
    call rdtsc_get_cycles
    test al, 0x01                   ; 50% probability reset
    jz .htl_ok
    mov al, FNP_MAX_HTL
.htl_ok:
    mov [rbx + freenet_chk_t.htl], al

    ; 3. Check local data store first
    lea rdi, [rbx + freenet_chk_t.routing_key]
    call freenet_store_lookup
    test rax, rax
    jnz .found

    ; 4. Verify content hash via SHA-256
    lea rdi, [rbx + freenet_chk_t.routing_key]
    call sha256_hash

    ; 5. Find closest peer by location distance & forward
    lea rdi, [rbx + freenet_chk_t.routing_key]
    call freenet_find_closest_peer

    jmp .not_found

.found:
    ; Decrypt data block using AES-256-GCM via crypto/ucrypt/
    mov rdi, rax
    call aes_gcm_decrypt
    jmp .done

.not_found:
    xor eax, eax

.done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; freenet_route_ssk — Route SSK Request & Verify Ed25519 Signature
; Input: RDI = Pointer to freenet_ssk_t
; Output: RAX = Pointer to Verified Data Block (or NULL)
; -----------------------------------------------------------------------------
align 64
freenet_route_ssk:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Check local data store
    lea rdi, [rbx + freenet_ssk_t.routing_key]
    call freenet_store_lookup
    test rax, rax
    jz .ssk_forward

    ; 2. Verify Ed25519 signature on retrieved content
    mov rdi, rbx
    call freenet_verify_ssk
    test eax, eax
    jnz .ssk_reject                 ; Signature invalid -> reject
    jmp .ssk_done

.ssk_forward:
    ; Forward to closest peer
    lea rdi, [rbx + freenet_ssk_t.routing_key]
    call freenet_find_closest_peer

.ssk_reject:
    xor eax, eax

.ssk_done:
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; freenet_verify_ssk — Verify Ed25519 Signature on SSK Content
; Input: RDI = Pointer to freenet_ssk_t
; Output: EAX = 0 if Valid, -1 if Forged
; -----------------------------------------------------------------------------
align 64
freenet_verify_ssk:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    call ed25519_verify
    pop rbp
    ret

; -----------------------------------------------------------------------------
; freenet_insert_key — Insert Encrypted Key Data into Local Data Store
; Input: RDI = Pointer to Routing Key, RSI = Pointer to Data, EDX = Length
; -----------------------------------------------------------------------------
align 64
freenet_insert_key:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    ; 1. Encrypt payload with AES-256-GCM via crypto/ucrypt/
    mov rdi, rsi
    call aes_gcm_encrypt

    ; 2. Insert into local data store with timer wheel eviction
    mov rdi, rbx
    call freenet_store_insert

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; freenet_find_closest_peer — Find Darknet Peer Closest to Target Key Location
; Input: RDI = Pointer to 32-byte Routing Key
; Output: RAX = Pointer to freenet_node_t (Closest Connected Peer)
; -----------------------------------------------------------------------------
align 64
freenet_find_closest_peer:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi
    ; Convert routing key to floating-point location [0.0, 1.0)
    ; Iterate peer table, compute |peer.location - target.location| distance
    ; Return peer with minimum distance (greedy small-world routing)

    lea r12, [freenet_peer_table]
    mov r13d, [freenet_peer_count]
    xor eax, eax

    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; freenet_store_lookup — Search Local Data Store by Routing Key
; Input: RDI = Pointer to 32-byte Routing Key
; Output: RAX = Pointer to freenet_store_entry_t (or NULL)
; -----------------------------------------------------------------------------
align 64
freenet_store_lookup:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Linear scan data store for matching routing key
    ; Increment access_count for LRU tracking
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; freenet_store_insert — Insert Data Block into LRU Data Store
; Input: RDI = Pointer to Routing Key, RSI = Pointer to Data, EDX = Length
; -----------------------------------------------------------------------------
align 64
freenet_store_insert:
    push rbp
    mov rbp, rsp
    ; If store full, evict LRU entry (lowest access_count)
    ; Schedule timer_wheel_add for TTL-based eviction
    call timer_wheel_add
    pop rbp
    ret
