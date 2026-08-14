%ifndef GUARD_LIB_MEM_VIRT_COCO_CCA_ASM
%define GUARD_LIB_MEM_VIRT_COCO_CCA_ASM
; =============================================================================
; Tattva OS — lib/mem/virt/cca.asm
; =============================================================================
; ARM CCA (Confidential Compute Architecture) — Subfeature 35.3.
;
; Manages Realm execution environments, Realm Management Monitor (RMM)
; hypercalls (via SMC), and Realm Stage 2 page table configuration.
; Critical for private inference APIs targeting ARM/AArch64 platforms.
;
; Hardware model (ARMv9 CCA):
;   Detection:
;     - RMM features are queried via RMI_VERSION SMC (FID 0xC4000150).
;     - If RMM returns a valid version, ARM CCA is supported/active.
;
;   Memory isolation:
;     - Realm memory is isolated from the Normal World (Host/Hypervisor).
;     - RMM controls Stage 2 page tables for Realms.
;     - Granule transition commands (e.g., GPT_transition) configure memory
;       as Realm, Secure, or Non-Secure.
;
; Software model for Tattva OS:
;   - Simulation layers for RMM calls and Stage 2 page table ownership.
;   - Realm allocation/destruction tracked via `sys_cca_realm_count`.
;   - Page ownership tracked via 64KB `cca_page_realm_map` in .bss.
;
; API:
;   cca_detect()                — Check CCA/RMM capabilities.
;   cca_init()                  — Initialise CCA subsystem and clear maps.
;   cca_realm_create(id)        — Create a realm; returns 1 on success.
;   cca_realm_destroy(id)       — Destroy a realm; returns 1 on success.
;   cca_map_gpa(id, gpa, ipa)   — Map page into Realm Stage 2 (returns 1).
;   cca_unmap_gpa(id, gpa)      — Unmap page from Realm Stage 2 (returns 1).
;   cca_is_realm_page(gpa)      — Check if GPA is owned by any realm.
;   cca_smc_call(fid, x1,x2,x3) — Issue SMC (or simulate RMM response).
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_VIRT_CCA_ASM
%define LIB_MEM_VIRT_CCA_ASM

[BITS 64]

; ---------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------
CCA_MAX_REALMS          equ 16

; SMC/RMM Function IDs (FIDs)
SMC_RMI_VERSION             equ 0xC4000150
SMC_RMI_REALM_CREATE        equ 0xC4000151
SMC_RMI_REALM_DESTROY       equ 0xC4000152
SMC_RMI_RTT_MAP_UNPROTECTED equ 0xC400015F
SMC_RMI_RTT_UNMAP           equ 0xC4000162

; Simulation limits
CCA_SIM_MAP_PAGES       equ 65536       ; covers 256MB GPA space

; ---------------------------------------------------------------------------
section .text

; ---------------------------------------------------------------------------
; cca_detect — Probe ARM CCA / RMM capability
; Output: RAX = 1 if CCA supported, 0 otherwise; sets sys_cca_supported.
; Clobbers: RAX, RBX, RCX, RDX
; ---------------------------------------------------------------------------
global cca_detect
cca_detect:
    ; On x86-64 hardware, native ARM CCA is not supported.
    ; Check if sys_cca_supported is pre-set/mocked by tests.
    mov  rax, [sys_cca_supported]
    test rax, rax
    jnz  .supported

    ; Otherwise return 0
    xor  rax, rax
    ret

.supported:
    mov  rax, 1
    ret

; ---------------------------------------------------------------------------
; cca_init — Initialise the ARM CCA simulation layer
; Output: RAX = 1 on success, 0 otherwise
; Clobbers: RAX, RCX, RDI
; ---------------------------------------------------------------------------
global cca_init
cca_init:
    push rdi
    push rcx

    ; Set support capability to 1 for tests/simulation
    mov  qword [sys_cca_supported], 1

    ; Zero out the realms active array
    lea  rdi, [cca_realms_active]
    xor  rax, rax
    mov  rcx, CCA_MAX_REALMS
    rep  stosb

    ; Zero out the 64KB page-to-realm map
    lea  rdi, [cca_page_realm_map]
    xor  rax, rax
    mov  rcx, CCA_SIM_MAP_PAGES / 8
    rep  stosq

    mov  qword [sys_cca_realm_count], 0
    mov  qword [sys_cca_mapped_pages], 0
    inc  qword [sys_cca_init_count]

    mov  rax, 1
    pop  rcx
    pop  rdi
    ret

; ---------------------------------------------------------------------------
; cca_realm_create — Create and register a Realm
; Input:  RDI = Realm ID (1 to 16)
; Output: RAX = 1 on success, 0 on failure (invalid ID, or already exists)
; Clobbers: RAX, RDX
; ---------------------------------------------------------------------------
global cca_realm_create
cca_realm_create:
    ; Verify Realm ID range: [1, 16]
    test rdi, rdi
    jz   .fail
    cmp  rdi, CCA_MAX_REALMS
    ja   .fail

    ; Check if already active
    lea  rdx, [cca_realms_active]
    movzx rax, byte [rdx + rdi - 1]
    test rax, rax
    jnz  .fail                      ; already exists

    ; Mark as active
    mov  byte [rdx + rdi - 1], 1
    inc  qword [sys_cca_realm_count]
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; cca_realm_destroy — Destroy an active Realm
; Input:  RDI = Realm ID (1 to 16)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, RDX, RDI
; ---------------------------------------------------------------------------
global cca_realm_destroy
cca_realm_destroy:
    ; Verify Realm ID range: [1, 16]
    test rdi, rdi
    jz   .fail
    cmp  rdi, CCA_MAX_REALMS
    ja   .fail

    ; Check if active
    lea  rdx, [cca_realms_active]
    movzx rax, byte [rdx + rdi - 1]
    test rax, rax
    jz   .fail                      ; not active

    ; Deactivate
    mov  byte [rdx + rdi - 1], 0
    dec  qword [sys_cca_realm_count]

    ; Clean up all page mapping entries associated with this realm
    mov  rcx, CCA_SIM_MAP_PAGES
    lea  rdx, [cca_page_realm_map]
.clean_loop:
    cmp  byte [rdx], dil            ; check if page matches realm ID
    jne  .next_page
    mov  byte [rdx], 0              ; clear page ownership
    dec  qword [sys_cca_mapped_pages]
.next_page:
    inc  rdx
    loop .clean_loop

    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; cca_map_gpa — Map a GPA to an IPA in the Stage 2 page table of the Realm
; Input:  RDI = Realm ID (1 to 16)
;         RSI = GPA (page-aligned)
;         RDX = IPA (page-aligned)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX, R8
; ---------------------------------------------------------------------------
global cca_map_gpa
cca_map_gpa:
    ; Verify Realm ID
    test rdi, rdi
    jz   .fail
    cmp  rdi, CCA_MAX_REALMS
    ja   .fail

    ; Check if realm is active
    lea  rcx, [cca_realms_active]
    movzx rax, byte [rcx + rdi - 1]
    test rax, rax
    jz   .fail

    ; Check bounds on GPA
    mov  rax, rsi
    shr  rax, 12                    ; page index
    cmp  rax, CCA_SIM_MAP_PAGES - 1
    ja   .fail

    ; Map the page
    lea  rcx, [cca_page_realm_map]
    movzx r8, byte [rcx + rax]
    test r8, r8
    jnz  .fail                      ; already mapped by some realm

    mov  byte [rcx + rax], dil
    inc  qword [sys_cca_mapped_pages]
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; cca_unmap_gpa — Unmap a GPA from Stage 2 page tables of the Realm
; Input:  RDI = Realm ID (1 to 16)
;         RSI = GPA (page-aligned)
; Output: RAX = 1 on success, 0 on failure
; Clobbers: RAX, RCX
; ---------------------------------------------------------------------------
global cca_unmap_gpa
cca_unmap_gpa:
    ; Verify Realm ID
    test rdi, rdi
    jz   .fail
    cmp  rdi, CCA_MAX_REALMS
    ja   .fail

    ; Check if realm is active
    lea  rcx, [cca_realms_active]
    movzx rax, byte [rcx + rdi - 1]
    test rax, rax
    jz   .fail

    ; Check bounds on GPA
    mov  rax, rsi
    shr  rax, 12
    cmp  rax, CCA_SIM_MAP_PAGES - 1
    ja   .fail

    ; Verify currently owned by this specific realm
    lea  rcx, [cca_page_realm_map]
    cmp  byte [rcx + rax], dil
    jne  .fail

    mov  byte [rcx + rax], 0
    dec  qword [sys_cca_mapped_pages]
    mov  rax, 1
    ret

.fail:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; cca_is_realm_page — Query if page belongs to any Realm
; Input:  RDI = GPA (page-aligned)
; Output: RAX = Realm ID (1-16) if owned, 0 if not or OOR
; Clobbers: RAX
; ---------------------------------------------------------------------------
global cca_is_realm_page
cca_is_realm_page:
    mov  rax, rdi
    shr  rax, 12
    cmp  rax, CCA_SIM_MAP_PAGES - 1
    ja   .not_owned

    lea  rcx, [cca_page_realm_map]
    movzx rax, byte [rcx + rax]
    ret

.not_owned:
    xor  rax, rax
    ret

; ---------------------------------------------------------------------------
; cca_smc_call — Simulate/Invoke Secure Monitor Call (SMC) for RMM
; Input:
;   RDI = SMC Function ID (SMC_RMI_*)
;   RSI = param 1
;   RDX = param 2
;   RCX = param 3
; Output: RAX = RMM return code (0 = success)
; Clobbers: RAX
; ---------------------------------------------------------------------------
global cca_smc_call
cca_smc_call:
    ; In simulation/x86, we branch based on RDI and execute mock operations
    mov  r11, SMC_RMI_VERSION
    cmp  rdi, r11
    je   .version
    mov  r11, SMC_RMI_REALM_CREATE
    cmp  rdi, r11
    je   .realm_create
    mov  r11, SMC_RMI_REALM_DESTROY
    cmp  rdi, r11
    je   .realm_destroy
    mov  r11, SMC_RMI_RTT_MAP_UNPROTECTED
    cmp  rdi, r11
    je   .map
    mov  r11, SMC_RMI_RTT_UNMAP
    cmp  rdi, r11
    je   .unmap

    ; Unknown or unhandled function
    mov  rax, -1
    ret

.version:
    ; Return version 0x00010000 (1.0)
    mov  rax, 0x00010000
    ret

.realm_create:
    ; RSI = realm ID
    push rdi
    mov  rdi, rsi
    call cca_realm_create
    pop  rdi
    test rax, rax
    jz   .fail
    xor  rax, rax                   ; 0 = SMC success
    ret

.realm_destroy:
    ; RSI = realm ID
    push rdi
    mov  rdi, rsi
    call cca_realm_destroy
    pop  rdi
    test rax, rax
    jz   .fail
    xor  rax, rax
    ret

.map:
    ; RSI = realm ID, RDX = GPA, RCX = IPA
    push rdi
    mov  rdi, rsi
    mov  rsi, rdx
    mov  rdx, rcx
    call cca_map_gpa
    pop  rdi
    test rax, rax
    jz   .fail
    xor  rax, rax
    ret

.unmap:
    ; RSI = realm ID, RDX = GPA
    push rdi
    mov  rdi, rsi
    mov  rsi, rdx
    call cca_unmap_gpa
    pop  rdi
    test rax, rax
    jz   .fail
    xor  rax, rax
    ret

.fail:
    mov  rax, 1                     ; error
    ret

; ---------------------------------------------------------------------------
; Data
; ---------------------------------------------------------------------------
section .data

align 8
global sys_cca_supported
sys_cca_supported:      dq 0        ; set to 1 in simulation

align 8
global sys_cca_realm_count
sys_cca_realm_count:    dq 0        ; active realms count

align 8
global sys_cca_mapped_pages
sys_cca_mapped_pages:   dq 0        ; total pages mapped to any realm

align 8
global sys_cca_init_count
sys_cca_init_count:     dq 0        ; init count

; ---------------------------------------------------------------------------
; BSS
; ---------------------------------------------------------------------------
section .bss

alignb 16
cca_realms_active:      resb CCA_MAX_REALMS

alignb 64
cca_page_realm_map:     resb CCA_SIM_MAP_PAGES

section .text

%endif ; LIB_MEM_VIRT_CCA_ASM

%endif ; GUARD_LIB_MEM_VIRT_COCO_CCA_ASM
