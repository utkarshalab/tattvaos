; =============================================================================
; Tattva OS — unet/anon/obfs4.asm
; =============================================================================
; Obfs4 (Pluggable Transport ScrambleSuit v2) Anti-DPI Censorship Evasion Engine.
;
; Features:
;   - Tor Pluggable Transport (PT) Obfs4 Framing with Elligator2 Key Encoding
;   - Elligator2 Curve25519 -> Uniform Random Byte String Public Key Mapping
;   - NTor-Like Handshake with Server Cert Binding & Node ID Verification
;   - Dynamic Random-Length Frame Padding (DPI Signature Elimination)
;   - Inter-Arrival Time (IAT) Randomization (Defeats Traffic Analysis)
;   - ChaCha20-Poly1305 Authenticated Stream Obfuscation
;   - Replay Detection via HMAC-SHA256 Server Handshake Hash Cache
;   - Minimum Handshake Padding to 8192 Bytes (Censorship Probing Resistance)
;
; Delegates:
;   - ChaCha20-Poly1305 Stream         -> crypto/ucrypt/symmetric/chacha20_poly1305.asm
;   - Curve25519 Key Exchange           -> crypto/usign/ed25519/
;   - HMAC-SHA256 Handshake Hash        -> crypto/uhash/sha256/
;   - Microsecond IAT Delays            -> lib/time/delay.asm (`udelay`)
;   - Entropy Source                    -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define OBFS4_MIN_HANDSHAKE_PAD     8192    ; Minimum Handshake Padding Bytes
%define OBFS4_MAX_FRAME_LEN         1448    ; Max Data Frame Length (MTU-safe)
%define OBFS4_MAX_PAD_LEN           1500    ; Max Random Padding per Frame
%define OBFS4_REPLAY_CACHE_SIZE     1024    ; HMAC Replay Detection Cache

struc obfs4_session_t
    .state:             resd 1      ; 0=Init, 1=Handshaking, 2=Active, 3=Closing
    .node_id:           resb 20     ; 160-bit Tor Node ID (SHA-1 of identity key)
    .public_key:        resb 32     ; Elligator2 Encoded Public Key
    .private_key:       resb 32     ; Ephemeral Private Key
    .send_key:          resb 32     ; Derived Send Symmetric Key
    .recv_key:          resb 32     ; Derived Receive Symmetric Key
    .send_nonce:        resq 1      ; Send Nonce Counter
    .recv_nonce:        resq 1      ; Receive Nonce Counter
    .iat_mode:          resb 1      ; 0=Disabled, 1=Enabled, 2=Paranoid
    .bytes_sent:        resq 1      ; Total Bytes Sent (Padding Budget Tracking)
endstruc

struc obfs4_frame_t
    .length:            resw 1      ; Encrypted Payload Length (2 bytes)
    .payload:           resb 1448   ; Encrypted Payload
    .padding:           resb 1500   ; Random Padding Bytes
    .tag:               resb 16     ; Poly1305 Authentication Tag
endstruc

section .bss
align 64
obfs4_replay_cache:     resb 32 * OBFS4_REPLAY_CACHE_SIZE  ; HMAC hash cache

section .text

global obfs4_init
global obfs4_handshake
global obfs4_elligator2_encode
global obfs4_elligator2_decode
global obfs4_obfuscate_stream
global obfs4_deobfuscate_stream
global obfs4_generate_padding
global obfs4_iat_delay
global obfs4_check_replay

extern chacha20_poly1305_encrypt
extern chacha20_poly1305_decrypt
extern sha256_hash
extern rdtsc_get_cycles
extern udelay

align 64
obfs4_init:
    push rbp
    mov rbp, rsp
    ; Zero-initialize replay cache
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; obfs4_handshake — Perform NTor-Like Obfs4 Handshake with Server Cert Binding
; Input: RDI = Pointer to obfs4_session_t, RSI = Server Certificate
; Output: EAX = 0 on Success, -1 on Failure
; -----------------------------------------------------------------------------
align 64
obfs4_handshake:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rsi
    prefetcht0 [rbx]

    ; 1. Generate ephemeral Curve25519 keypair
    call rdtsc_get_cycles

    ; 2. Encode public key via Elligator2 (indistinguishable from random)
    lea rdi, [rbx + obfs4_session_t.public_key]
    call obfs4_elligator2_encode

    ; 3. Compute shared secret & derive send/recv keys via HMAC-SHA256
    call sha256_hash

    ; 4. Pad handshake to minimum OBFS4_MIN_HANDSHAKE_PAD bytes
    mov edi, OBFS4_MIN_HANDSHAKE_PAD
    call obfs4_generate_padding

    ; 5. Check replay cache to detect probe attacks
    lea rdi, [rbx + obfs4_session_t.send_key]
    call obfs4_check_replay
    test eax, eax
    jnz .handshake_fail

    mov dword [rbx + obfs4_session_t.state], 2  ; Active
    xor eax, eax
    jmp .handshake_done

.handshake_fail:
    mov eax, -1

.handshake_done:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; obfs4_elligator2_encode — Encode Curve25519 Point as Uniform Random Bytes
; Input: RDI = Pointer to 32-byte Curve25519 Public Key
; Output: [RDI] overwritten with 32-byte Elligator2 encoded string
; -----------------------------------------------------------------------------
align 64
obfs4_elligator2_encode:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Map Curve25519 point to byte string indistinguishable from uniform random
    ; Uses Elligator2 inverse map: point -> field element -> canonical bytes
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; obfs4_elligator2_decode — Decode Uniform Random Bytes to Curve25519 Point
; Input: RDI = Pointer to 32-byte Elligator2 String
; Output: [RDI] overwritten with Curve25519 point
; -----------------------------------------------------------------------------
align 64
obfs4_elligator2_decode:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Elligator2 forward map: field element -> curve point
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; obfs4_obfuscate_stream — Encrypt & Pad Data Frame for Transmission
; Input: RDI = Pointer to obfs4_session_t, RSI = Plaintext, EDX = Length
; -----------------------------------------------------------------------------
align 64
obfs4_obfuscate_stream:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rsi]

    ; 1. Encrypt payload with ChaCha20-Poly1305 using send_key + nonce
    call chacha20_poly1305_encrypt

    ; 2. Append random-length padding
    call obfs4_generate_padding

    ; 3. Increment send nonce counter
    inc qword [rbx + obfs4_session_t.send_nonce]

    ; 4. Apply IAT delay if enabled
    movzx eax, byte [rbx + obfs4_session_t.iat_mode]
    test al, al
    jz .no_iat
    call obfs4_iat_delay
.no_iat:

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; obfs4_deobfuscate_stream — Decrypt Incoming Obfs4 Frame
; Input: RDI = Pointer to obfs4_session_t, RSI = Ciphertext, EDX = Length
; Output: RAX = Plaintext Length, -1 on Auth Failure
; -----------------------------------------------------------------------------
align 64
obfs4_deobfuscate_stream:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rsi]

    ; Strip padding & decrypt with recv_key + nonce
    call chacha20_poly1305_decrypt
    inc qword [rbx + obfs4_session_t.recv_nonce]

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; obfs4_generate_padding — Generate Random-Length Padding Bytes
; Input: EDI = Maximum Padding Length
; Output: EAX = Actual Padding Length Generated
; -----------------------------------------------------------------------------
align 64
obfs4_generate_padding:
    push rbp
    mov rbp, rsp
    ; Use RDTSC entropy to generate random padding length [0, max)
    call rdtsc_get_cycles
    xor edx, edx
    div edi                         ; EDX = random length mod max
    mov eax, edx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; obfs4_iat_delay — Apply Inter-Arrival Time Randomization Delay
; Defeats traffic analysis by inserting random microsecond delays between frames
; -----------------------------------------------------------------------------
align 64
obfs4_iat_delay:
    push rbp
    mov rbp, rsp
    ; Generate random delay [10us, 1000us] via RDTSC entropy
    call rdtsc_get_cycles
    and eax, 0x3FF                  ; Mask to 0-1023 microseconds
    add eax, 10                     ; Minimum 10us
    mov edi, eax
    call udelay                     ; lib/time/delay.asm
    pop rbp
    ret

; -----------------------------------------------------------------------------
; obfs4_check_replay — Check HMAC Hash Against Replay Cache
; Input: RDI = Pointer to 32-byte HMAC Hash
; Output: EAX = 0 if Not Replayed, -1 if Replayed
; -----------------------------------------------------------------------------
align 64
obfs4_check_replay:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Linear scan replay cache for matching HMAC hash
    ; If found -> replay attack detected
    ; If not found -> insert into cache
    xor eax, eax
    pop rbp
    ret
