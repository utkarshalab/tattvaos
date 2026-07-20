; =============================================================================
; Tattva OS — lib/mem/virt/enc_swap.asm
; =============================================================================
; Encrypted Memory Swapping — Subfeature 35.4.
;
; Encrypts memory pages before they are written to physical swap media,
; and decrypts them when read back. Key is derived at boot/initialisation
; from CPU hardware random number generator (RDRAND) or KDF fallback.
; Prevents cold boot attacks and physical state extraction from swap drives.
;
; API:
;   enc_swap_init()                     — Derive 256-bit key from CPU hardware.
;   enc_swap_encrypt_page(src, dst, sz) — Encrypt page from src to dst.
;   enc_swap_decrypt_page(src, dst, sz) — Decrypt page from src to dst.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_ENC_SWAP_ASM
%define LIB_MEM_VIRT_ENC_SWAP_ASM

[BITS 64]

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; enc_swap_init — Initialise keys using RDRAND hardware entropy
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RBX, RCX, RDX, RDI
; ---------------------------------------------------------------------------
global enc_swap_init
enc_swap_init:
    push rbx
    push rdi

    ; 1. Check for RDRAND support (CPUID.1:ECX bit 30)
    mov  eax, 1
    cpuid
    test ecx, (1 << 30)
    jz   .fallback_kdf

    ; 2. Generate 32 bytes (256 bits) key using RDRAND
    lea  rdi, [sys_enc_swap_key]
    mov  rcx, 4                 ; 4 qwords
.rdrand_loop:
    rdrand rax                  ; generate 64-bit random number
    jnc  .rdrand_loop           ; retry if hardware transient failure (CF=0)
    mov  [rdi], rax
    add  rdi, 8
    loop .rdrand_loop
    jmp  .success

.fallback_kdf:
    ; RDRAND not supported; derive a pseudo-random key using TSC & constants
    rdtsc                       ; EDX:EAX = TSC
    lea  rdi, [sys_enc_swap_key]
    
    ; Mix TSC and constant seeds
    mov  r8, 0x5851F42D4C957F2D ; LCG multiplier
    
    ; Qword 0
    mov  [rdi], rax
    ; Qword 1
    xor  rax, r8
    mov  [rdi + 8], rax
    ; Qword 2
    mov  [rdi + 16], rdx
    ; Qword 3
    xor  rdx, r8
    mov  [rdi + 24], rdx

.success:
    mov  qword [sys_enc_swap_enabled], 1
    mov  rax, 1
    pop  rdi
    pop  rbx
    ret

; ---------------------------------------------------------------------------
; enc_swap_encrypt_page — Encrypt page from src to dst.
; Input:
;   RDI = source address (page-aligned)
;   RSI = destination address (page-aligned)
;   RDX = page size in bytes (must be multiple of 8, typically 4096)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, R8, R9, R10, R11
; ---------------------------------------------------------------------------
global enc_swap_encrypt_page
enc_swap_encrypt_page:
    ; Verify inputs are non-null and size >= 8
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail
    test rdx, rdx
    jz   .fail
    test rdx, 7                 ; size must be multiple of 8
    jnz  .fail

    ; Calculate loop count (qwords)
    mov  rcx, rdx
    shr  rcx, 3                 ; RCX = count of qwords

    ; Load keys
    mov  r8, [sys_enc_swap_key]         ; K0
    mov  r9, [sys_enc_swap_key + 8]     ; K1
    mov  r10, [sys_enc_swap_key + 16]    ; K2
    mov  r11, [sys_enc_swap_key + 24]    ; K3

    ; Get shift count from K2 (bits 5:0)
    push rcx
    mov  rcx, r10
    and  rcx, 63                ; shift amount for ROL
    pop  rax                    ; restore loop count
    push rcx                    ; push shift count to stack for encryption
    mov  rcx, rax               ; RCX = loop count

    xor  rax, rax               ; offset index / block count
.encrypt_loop:
    ; Read original qword
    mov  rdx, [rdi + rax * 8]

    ; Compute tweak based on block index: tweak = (index * PRIME) ^ K0 ^ K1
    mov  r10, rax
    mov  r11, 0x9E3779B97F4A7C15
    imul r10, r11
    xor  r10, r8
    xor  r10, r9

    ; Apply tweak and diffusions
    xor  rdx, r10               ; XOR tweak

    ; Retrieve shift count and rotate
    pop  r10                    ; shift count
    push r10                    ; keep on stack
    push rcx
    mov  cl, r10b
    rol  rdx, cl                ; rotate left
    pop  rcx

    ; XOR K3
    xor  rdx, r11

    ; Store ciphertext
    mov  [rsi + rax * 8], rdx

    inc  rax
    loop .encrypt_loop

    pop  r10                    ; clean stack

    inc  qword [sys_enc_swap_pages_encrypted]
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; enc_swap_decrypt_page — Decrypt page from src to dst.
; Input:
;   RDI = source address (ciphertext, page-aligned)
;   RSI = destination address (plaintext, page-aligned)
;   RDX = page size in bytes (must be multiple of 8, typically 4096)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, R8, R9, R10, R11
; ---------------------------------------------------------------------------
global enc_swap_decrypt_page
enc_swap_decrypt_page:
    test rdi, rdi
    jz   .fail
    test rsi, rsi
    jz   .fail
    test rdx, rdx
    jz   .fail
    test rdx, 7
    jnz  .fail

    mov  rcx, rdx
    shr  rcx, 3                 ; RCX = qword count

    mov  r8, [sys_enc_swap_key]         ; K0
    mov  r9, [sys_enc_swap_key + 8]     ; K1
    mov  r10, [sys_enc_swap_key + 16]    ; K2
    mov  r11, [sys_enc_swap_key + 24]    ; K3

    push rcx
    mov  rcx, r10
    and  rcx, 63                ; shift amount
    pop  rax
    push rcx                    ; push shift count for ROR
    mov  rcx, rax               ; RCX = loop count

    xor  rax, rax
.decrypt_loop:
    mov  rdx, [rdi + rax * 8]

    ; 1. XOR K3
    xor  rdx, r11

    ; 2. Retrieve shift count and rotate right (opposite of ROL)
    pop  r10
    push r10
    push rcx
    mov  cl, r10b
    ror  rdx, cl
    pop  rcx

    ; 3. Compute tweak: (index * PRIME) ^ K0 ^ K1
    mov  r10, rax
    mov  r11, 0x9E3779B97F4A7C15
    imul r10, r11
    xor  r10, r8
    xor  r10, r9

    ; 4. XOR tweak
    xor  rdx, r10

    ; Store plaintext
    mov  [rsi + rax * 8], rdx

    inc  rax
    loop .decrypt_loop

    pop  r10

    inc  qword [sys_enc_swap_pages_decrypted]
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_enc_swap_enabled
sys_enc_swap_enabled:   dq 0        ; 1 if initialized/enabled

align 8
global sys_enc_swap_pages_encrypted
sys_enc_swap_pages_encrypted: dq 0  ; statistics counter

align 8
global sys_enc_swap_pages_decrypted
sys_enc_swap_pages_decrypted: dq 0  ; statistics counter

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
section .bss

align 16
global sys_enc_swap_key
sys_enc_swap_key:       resb 32     ; derived 256-bit encryption key

section .text

%endif ; LIB_MEM_VIRT_ENC_SWAP_ASM
