; =============================================================================
; Tattva OS — boot/stage2/cpu/longmode.asm
; =============================================================================
; Verify long mode is supported and enter it.
; Must be called after GDT and paging are set up.
;
; Long mode entry sequence (STRICT ORDER — do not reorder):
;   1. Set PAE bit in CR4         (bit 5)
;   2. Load PML4 address into CR3
;   3. Set LME bit in EFER MSR   (MSR 0xC0000080, bit 8)
;   4. Enable paging + protected mode in CR0 simultaneously
;   5. Far jump to 64-bit code segment
;   6. Reload segment registers in 64-bit code
;   7. Enable SSE/AVX
;
; Any other order = triple fault with no error message.
;
; Author:  Utkarsha Labs
; Target:  x86-64, protected mode (32-bit) → long mode (64-bit)
; =============================================================================

%ifndef LONGMODE_ASM
%define LONGMODE_ASM

; MSR addresses
MSR_EFER        equ 0xC0000080      ; Extended Feature Enable Register
EFER_LME        equ (1 << 8)        ; Long Mode Enable bit
EFER_NXE        equ (1 << 11)       ; No-Execute Enable bit

; CR0 bits
CR0_PE          equ (1 << 0)        ; Protected mode Enable
CR0_MP          equ (1 << 1)        ; Monitor coProcessor
CR0_EM          equ (1 << 2)        ; EMulation (clear for SSE)
CR0_PG          equ (1 << 31)       ; Paging enable

; CR4 bits
CR4_PAE         equ (1 << 5)        ; Physical Address Extension
CR4_OSFXSR      equ (1 << 9)        ; OS support for FXSAVE/FXRSTOR
CR4_OSXMMEXCPT  equ (1 << 10)       ; OS support for SIMD exceptions
CR4_OSXSAVE     equ (1 << 18)       ; OS support for XSAVE (for AVX)

; =============================================================================
; longmode_check — verify CPU supports long mode
; Input:  [FEATURES_DEST] filled by cpu_detect
; Output: CF=0 supported, CF=1 not supported
; =============================================================================
longmode_check:
    mov eax, [FEATURES_DEST]
    test eax, CPU_FEAT_LM
    jz .not_supported
    clc
    ret
.not_supported:
    stc
    ret

[BITS 32]
; =============================================================================
; longmode_enter — switch from protected mode to long mode
; Input:  GDT loaded, paging set up, PML4 at PAGING_PML4
; Output: never returns in protected mode
;         execution continues in 64-bit code after far jump
; =============================================================================
longmode_enter:


    ; -------------------------------------------------------------------------
    ; STEP 1: Enable PAE in CR4
    ; PAE must be set before loading CR3 or enabling LME
    ; -------------------------------------------------------------------------
    mov eax, cr4
    or eax, CR4_PAE                 ; set PAE bit
    or eax, CR4_OSFXSR              ; enable FXSAVE/FXRSTOR (for SSE)
    or eax, CR4_OSXMMEXCPT          ; enable SIMD exception handling
    mov cr4, eax

    ; -------------------------------------------------------------------------
    ; STEP 2: Load PML4 physical address into CR3
    ; CR3 = physical address of PML4 page table
    ; Bits 11:0 of CR3 are control flags (cache disable, etc.)
    ; We use 0 for flags (enable caching, write-back)
    ; -------------------------------------------------------------------------
    mov eax, PAGING_PML4            ; PML4 physical address
    mov cr3, eax


    ; -------------------------------------------------------------------------
    ; STEP 3: Enable LME in EFER MSR
    ; Read EFER, set LME bit, write back
    ; Also enable NXE if CPU supports NX
    ; -------------------------------------------------------------------------
    mov ecx, MSR_EFER
    rdmsr                           ; EDX:EAX = EFER
    or eax, EFER_LME                ; set Long Mode Enable

    ; enable NX if supported
    mov ebx, [FEATURES_DEST]
    test ebx, CPU_FEAT_NX
    jz .no_nx_enable
    or eax, EFER_NXE                ; set No-Execute Enable
.no_nx_enable:


    wrmsr                           ; write back EFER


    ; -------------------------------------------------------------------------
    ; STEP 4: Enable paging and protected mode simultaneously in CR0
    ; CRITICAL: must set PG and PE in the same write
    ; Both bits set in one mov cr0 instruction
    ; -------------------------------------------------------------------------
    mov eax, cr0
    or eax, (CR0_PE | CR0_PG)      ; set PE + PG together
    and eax, ~CR0_EM                ; clear EM (enable SSE, not emulation)
    or eax, CR0_MP                  ; set MP (monitor coprocessor)


    mov cr0, eax


    ; -------------------------------------------------------------------------
    ; STEP 5: Far jump to 64-bit code segment
    ; This flushes the instruction pipeline and activates long mode.
    ; SEL_CODE64 = 0x08 (64-bit code descriptor in GDT)
    ; longmode_64 = entry point in 64-bit code
    ; -------------------------------------------------------------------------
    jmp SEL_CODE64:longmode_64

; =============================================================================
; longmode_64 — we are now in 64-bit long mode
; All code below is [BITS 64]
; =============================================================================
[BITS 64]
longmode_64:

    ; -------------------------------------------------------------------------
    ; STEP 6: Reload all data segment registers
    ; After far jump: CS is loaded with 64-bit descriptor
    ; DS/ES/FS/GS/SS still have protected mode values
    ; Must reload with 64-bit data selector
    ; Forgetting ANY segment = subtle corruption bugs
    ; -------------------------------------------------------------------------
    mov ax, SEL_DATA64              ; 0x10
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov ss, ax

    ; set up 64-bit stack
    mov rsp, STACK_LONG             ; 64-bit stack pointer

    ; -------------------------------------------------------------------------
    ; STEP 6.5: KASLR - Randomize kernel physical base address
    ; -------------------------------------------------------------------------
    push rax
    push rbx
    push rcx
    push rdx

    ; Check if RDRAND is supported (CPUID.01H:ECX.30)
    mov eax, 1
    cpuid
    bt ecx, 30
    jnc .use_rdtsc

    ; RDRAND is supported, try to generate a hardware random number
    rdrand eax
    jc .have_rand

.use_rdtsc:
    ; Fallback to RDTSC for pseudo-randomness
    rdtsc                           ; EDX:EAX = TSC
    xor eax, edx

.have_rand:
    ; Constrain page index to 2MB - 16MB range
    ; 2MB = 512 pages, 16MB = 4096 pages. Range is 3584 pages.
    xor edx, edx
    mov ecx, 3584
    div ecx                         ; EDX = random % 3584
    add edx, 512                    ; EDX = page index (512 to 4095)
    shl rdx, 12                     ; RDX = page_index * 4096 (phys_dest)

    ; -------------------------------------------------------------------------
    ; The remap below this point only retargets PT0 entries 256-511 — 256 x
    ; 4KB pages, i.e. virtual 0x100000-0x200000, a single megabyte. Everything
    ; past that is covered by the identity-mapped 2MB huge pages in PD0-PD3,
    ; which this code never touches. A kernel bigger than that 1MB window
    ; would have most of its relocated bytes sitting at a physical address
    ; nothing points the CPU at — the copy would succeed and the boot would
    ; still be reading stale (or garbage) memory through the old identity
    ; mapping, caught here only because the ULF checksum then disagrees.
    ;
    ; Proper support needs 2MB-granular relocation through PD0 with the low
    ; 1MB's identity mapping kept separate from the kernel's, since KERNEL_LOAD
    ; (1MB) shares a 2MB huge page with reserved low memory. That is real
    ; paging work, not a one-line fix, so until it exists this skips
    ; relocation instead of producing a boot that sometimes decodes to
    ; whatever the destination page happened to hold.
    ; -------------------------------------------------------------------------
    mov eax, [KERNEL_LOAD]
    cmp eax, 0x00464C55              ; "ULF\0" — checked again properly below;
    jne .no_kaslr                    ; this guard only needs to not misread size
    mov eax, [KERNEL_LOAD + 4]       ; ULF header: image length in bytes
    cmp eax, 256 * 4096              ; 1MB: what the PT0 remap below can cover
    ja .no_kaslr

    ; Store physical kernel address in BootInfo (BOOT_INFO_ADDR + 20)
    mov [BOOT_INFO_ADDR + 20], edx

    ; Print diagnostic message: msg_kaslr_reloc followed by address
    mov rsi, msg_kaslr_reloc
    call uart_print_64
    mov rax, rdx
    call uart_print_hex64
    mov rsi, msg_crlf
    call uart_print_64
    jmp .kaslr_done

.no_kaslr:
    mov dword [BOOT_INFO_ADDR + 20], 0

.kaslr_done:
    pop rdx
    pop rcx
    pop rbx
    pop rax

    ; -------------------------------------------------------------------------
    ; STEP 7: Enable AVX via XSETBV if supported
    ; CR4.OSXSAVE must be set first, then XSETBV sets XCR0
    ; -------------------------------------------------------------------------
    mov eax, [FEATURES_DEST]
    test eax, CPU_FEAT_AVX
    jz .no_avx_enable

    ; set CR4.OSXSAVE
    mov rax, cr4
    or rax, CR4_OSXSAVE
    mov cr4, rax

    ; set XCR0: enable x87, SSE, AVX
    xor rcx, rcx                    ; XCR0 index = 0
    xgetbv                          ; read XCR0 into EDX:EAX
    or eax, 0x07                    ; bit 0=x87, bit 1=SSE, bit 2=AVX
    xsetbv                          ; write back

.no_avx_enable:

    ; -------------------------------------------------------------------------
    ; STEP 8: Print confirmation via UART
    ; (UART still works in long mode, same port I/O)
    ; -------------------------------------------------------------------------
    mov rsi, msg_longmode_ok
    call uart_print_64              ; note: uart_print needs 64-bit version

    ; Run 64-bit survive unit test
    call test_survive

    ; -------------------------------------------------------------------------
    ; STEP 9: Load and jump to kernel
    ; Copy kernel from real-mode temp buffer (0x20000) to randomized physical address
    ; -------------------------------------------------------------------------
    mov rsi, msg_kernel_load
    call uart_print_64

    ; -------------------------------------------------------------------------
    ; KASLR relocation, skipped when no randomized address was chosen.
    ;
    ; BOOT_INFO_KASLR_PHYS is a dword and the qword immediately after it holds
    ; the ACPI RSDP pointer, so this has to be a 32-bit load. Reading eight
    ; bytes pulled the RSDP's low half into the high half of the address and
    ; turned a field nothing had set into a plausible-looking nonzero
    ; destination — which then got used both as a memcpy target and as the
    ; physical base for virtual 1MB-2MB.
    ;
    ; Nothing sets the field yet, so the branch below is the live path:
    ; kernel_stream_load already placed the image at KERNEL_LOAD while still in
    ; real mode, and there is nothing left to copy or remap.
    ; -------------------------------------------------------------------------
    xor edi, edi
    mov edi, [BOOT_INFO_ADDR + 20]  ; 32-bit load, zero-extended into RDI
    test rdi, rdi
    jz .kernel_in_place

    push rdi
    call kernel_load                ; relocate KERNEL_LOAD → phys_dest
    pop rbx                         ; RBX = phys_dest

    ; Repoint virtual 1MB-2MB at the new physical home. Only the first
    ; megabyte: PT0 is the sole 4KB-granular table, and everything above 2MB
    ; is covered by the identity huge pages, so a randomized base would have to
    ; stay 2MB-aligned for the rest of the image to follow.
    mov rdi, PAGING_PT0 + 256 * 8   ; pointer to entry 256 of PT0
    mov rcx, 256                    ; 256 entries (1MB)

.update_kaslr_page_table:
    mov rax, rbx
    or rax, 0x03                    ; present + read/write
    mov [rdi], rax
    mov dword [rdi + 4], 0          ; NX=0 (executable)
    
    add rbx, 0x1000                 ; next physical page (4KB)
    add rdi, 8                      ; next page table entry
    dec rcx
    jnz .update_kaslr_page_table

    ; Flush TLB by reloading CR3
    mov rax, cr3
    mov cr3, rax

.kernel_in_place:

    ; Copy initrd to 32MB if loaded
    xor rax, rax
    mov al, [rel initrd_loaded]
    test al, al
    jz .skip_initrd_copy

    mov rsi, 0x40000                ; source: 0x40000 (loaded in real mode segment 0x4000)
    mov rdi, 0x2000000              ; destination: 32MB mark
    xor rcx, rcx
    mov ecx, [rel initrd_size]
    add rcx, 7
    shr rcx, 3                      ; quadword count
    cld
    rep movsq

    ; Populate BootInfo fields
    mov rdi, BOOT_INFO_ADDR
    mov qword [rdi + 56], 0x2000000 ; BOOT_INFO_INITRD_ADDR
    xor rax, rax
    mov eax, [rel initrd_size]
    mov [rdi + 64], rax             ; BOOT_INFO_INITRD_SIZE
    jmp .initrd_done

.skip_initrd_copy:
    mov rdi, BOOT_INFO_ADDR
    mov qword [rdi + 56], 0
    mov qword [rdi + 64], 0

.initrd_done:

    ; 1. Verify ULF magic number at KERNEL_LOAD (0x100000)
    mov eax, [KERNEL_LOAD]          ; load first dword (magic)
    cmp eax, 0x00464C55             ; check if it matches "ULF\0"
    jne .ulf_bad_magic

    ; 2. Verify kernel size constraints (must be multiple of 8, >= 32 bytes, <= 32MB)
    mov ecx, [KERNEL_LOAD + 4]      ; ecx = total size of binary in bytes
    test ecx, 7                     ; must be 8-byte aligned
    jnz .ulf_bad_size
    cmp ecx, 32
    jl .ulf_bad_size
    cmp ecx, 32 * 1024 * 1024       ; max 32MB
    jg .ulf_bad_size

    ; 3. Verify Checksum
    mov rsi, KERNEL_LOAD
    mov ebx, ecx
    shr ebx, 3                      ; rbx = number of 8-byte quadwords
    jz .checksum_done
    
    xor rax, rax                    ; rax = calculated sum
    xor rdx, rdx                    ; rdx = current offset

.checksum_loop:
    cmp rdx, 16                     ; skip the checksum field at offset 16 (0x10)
    je .skip_field
    add rax, [rsi + rdx]
.skip_field:
    add rdx, 8
    dec rbx
    jnz .checksum_loop

.checksum_done:
    mov r8, [KERNEL_LOAD + 16]      ; load checksum from header
    cmp rax, r8
    jne .ulf_bad_checksum

    ; 5. Print success and dynamic jump
    mov rsi, msg_kernel_ok
    call uart_print_64

    ; Perform Measured Boot TPM measurements
    call tpm_measure_all

    ; Save the pristine state snapshot and register the panic vector
    call survive_snapshot_save
    call survive_vector_install

    ; 4. Retrieve dynamic entry point from header (offset 8)
    mov rax, [KERNEL_LOAD + 8]      ; rax = entry_point

    mov rdi, BOOT_INFO_ADDR         ; Pass BootInfo pointer in RDI (System V ABI)
    jmp rax                         ; jump dynamically!

.ulf_bad_magic:
    mov rsi, msg_ulf_err_magic
    call uart_print_64
    jmp .halt

.ulf_bad_size:
    mov rsi, msg_ulf_err_size
    call uart_print_64
    jmp .halt

.ulf_bad_checksum:
    mov rsi, msg_ulf_err_checksum
    call uart_print_64
    jmp .halt

.halt:
    cli
    hlt
    jmp .halt

    ; never reaches here
    cli
    hlt


; =============================================================================
; Data (in 64-bit section)
; =============================================================================
msg_longmode_ok:    db "Long mode OK", 0x0D, 0x0A, 0
msg_kernel_load:    db "Kernel... ", 0
msg_kaslr_reloc:    db "KASLR: Kernel physically relocated to ", 0
msg_crlf:           db 0x0D, 0x0A, 0
msg_kernel_ok:      db "OK", 0x0D, 0x0A, 0
msg_ulf_err_magic:  db "FAIL (Bad Magic)", 0x0D, 0x0A, 0
msg_ulf_err_size:   db "FAIL (Bad Size)", 0x0D, 0x0A, 0
msg_ulf_err_checksum:db "FAIL (Bad Checksum)", 0x0D, 0x0A, 0

; Switch back to 16-bit for rest of stage2
[BITS 16]

%endif ; LONGMODE_ASM