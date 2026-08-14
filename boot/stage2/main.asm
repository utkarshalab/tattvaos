; =============================================================================
; Tattva OS — boot/stage2/main.asm
; =============================================================================
; Main stage2 orchestrator.
; Called from entry.asm after UART is initialized.
; Calls each subsystem in strict order.
; Never returns — jumps to kernel at end.
;
; Order (strict — do not reorder):
;   1.  A20 enable
;   2.  CPU feature detection
;   3.  Memory map (E820)
;   4.  GDT setup
;   5.  IDT setup
;   6.  Paging setup
;   7.  Enable SSE/AVX
;   8.  Load kernel from disk
;   9.  Jump to kernel
;
; Author:  Utkarsha Labs
; Target:  x86-64, real mode (16-bit)
; =============================================================================

%ifndef MAIN_ASM
%define MAIN_ASM

; =============================================================================
; stage2_main — main boot orchestrator
; Input:  nothing (uart already initialized)
; Output: never returns
; =============================================================================
stage2_main:

    ; -------------------------------------------------------------------------
    ; STEP 1: Enable A20 line
    ; -------------------------------------------------------------------------
    mov si, msg_a20
    call uart_print

    call a20_enable                 ; try all methods, verify each

    jc .a20_failed                  ; carry set = all methods failed

    mov si, msg_ok
    call uart_println
    jmp .a20_done

.a20_failed:
    mov si, msg_fail
    call uart_println
    mov si, msg_a20_halt
    call uart_println
    jmp .halt

.a20_done:
    call test_a20
    call test_uart

    ; -------------------------------------------------------------------------
    ; STEP 2: Detect CPU features
    ; -------------------------------------------------------------------------
    mov si, msg_cpu
    call uart_print

    call cpu_detect                 ; fills feature table at FEATURES_DEST

    ; check long mode supported
    mov eax, [FEATURES_DEST]
    test eax, CPU_FEAT_LM           ; long mode flag
    jz .no_longmode

    mov si, msg_ok
    call uart_println
    jmp .cpu_done

.no_longmode:
    mov si, msg_fail
    call uart_println
    mov si, msg_cpu_halt
    call uart_println
    jmp .halt

.cpu_done:

    ; Initialize secondary cores (SMP AP Bootstrap)
    ; call smp_init_cores

    ; -------------------------------------------------------------------------
    ; STEP 3: Detect memory map (E820)
    ; -------------------------------------------------------------------------
    mov si, msg_mem
    call uart_print

    call e820_detect                ; fills table at E820_DEST
    call e820_parse                 ; find usable regions
    call e820_sort                  ; sort by base address
    call e820_merge                 ; merge overlapping entries
    call hide_survive_page          ; hide/reserve SURVIVE_PAGE from E820 map
    call e820_parse                 ; recalculate total usable memory after hiding
    call e820_print                 ; debug print final map

    ; print total usable RAM
    mov si, msg_ram
    call uart_print
    mov eax, [e820_total_mb]        ; total MB filled by e820_parse
    call uart_print_dec
    mov si, msg_mb
    call uart_println

.mem_done:
    call test_e820
    call test_fat32

    ; -------------------------------------------------------------------------
    ; STEP 3.4: Query disk geometry and EDD drive parameters
    ; -------------------------------------------------------------------------
    call disk_get_geometry
    call disk_query_edd

    mov si, msg_geom_prefix
    call uart_print
    xor eax, eax
    mov ax, [number_of_heads]
    call uart_print_dec
    mov si, msg_geom_heads
    call uart_print
    xor eax, eax
    mov ax, [sectors_per_track]
    call uart_print_dec
    mov si, msg_geom_spt
    call uart_println

    ; -------------------------------------------------------------------------
    ; STEP 3.5: Stream the kernel from disk to the 1MB mark
    ;
    ; fs_load_kernel (GPT/FAT32) is deliberately not tried first any more. It
    ; targets the KERNEL_TEMP bounce buffer, which is 32KB and cannot hold a
    ; 9.3MB image; it needs the same chunked unreal-mode transfer that
    ; kernel_stream_load performs before it can return to this path.
    ; -------------------------------------------------------------------------
    mov si, msg_kernel
    call uart_print

    call kernel_stream_load
    test ax, ax
    jz .kernel_failed

    mov si, msg_ok
    call uart_println
    jmp .kernel_done

.kernel_failed:
    call ks_report_error
    mov si, msg_help
    call uart_println
    mov si, msg_kernel_halt
    call uart_println
    jmp .halt

.kernel_done:
    ; Query and set VBE linear framebuffer mode
    call vbe_init

    ; Initialize BootInfo structure at 0x7000
    call boot_info_init

    ; -------------------------------------------------------------------------
    ; STEP 4: Setup GDT — never returns, continues in 32-bit protected mode
    ; -------------------------------------------------------------------------
    mov si, msg_gdt
    call uart_print

    call gdt_setup                  ; far jumps to pm32_entry, never returns

    ; never reaches here
    jmp .halt

.halt:
    cli
    hlt
    jmp .halt

; =============================================================================
; Strings
; =============================================================================
msg_a20:        db "A20...    ", 0
msg_cpu:        db "CPU...    ", 0
msg_mem:        db "Memory... ", 0
msg_gdt:        db "GDT...    ", 0
msg_idt:        db "IDT...    ", 0
msg_paging:     db "Paging... ", 0
msg_lm:         db "LongMode. ", 0
msg_ok:         db "OK", 0
msg_fail:       db "FAIL", 0
msg_ram:        db "RAM: ", 0
msg_kernel:     db "Kernel... ", 0
msg_help:       db "Help: is the ULF image written at LBA 65?", 0
msg_a20_halt:   db "HALT: A20 enable failed on all methods", 0
msg_cpu_halt:   db "HALT: CPU does not support long mode", 0
msg_kernel_halt:db "HALT: Kernel load failed", 0
msg_geom_prefix: db "Disk: ", 0
msg_geom_heads:  db " Heads, ", 0
msg_geom_spt:    db " Sectors/Track", 0


; CPU feature flags (stored at FEATURES_DEST by cpu_detect)
CPU_FEAT_LM     equ (1 << 0)       ; long mode supported
CPU_FEAT_NX     equ (1 << 1)       ; NX/XD bit supported
CPU_FEAT_SSE    equ (1 << 2)       ; SSE supported
CPU_FEAT_SSE2   equ (1 << 3)       ; SSE2 supported
CPU_FEAT_AVX    equ (1 << 4)       ; AVX supported
CPU_FEAT_AVX2   equ (1 << 5)       ; AVX2 supported
CPU_FEAT_AVX512 equ (1 << 6)       ; AVX-512 supported
CPU_FEAT_AMX    equ (1 << 7)       ; AMX supported

; =============================================================================
; stage2_main_pm32 — 32-bit protected mode continuation
; Called from pm32_entry in gdt_load.asm after GDT far jump.
; Continues boot: IDT → paging → long mode.
; Never returns.
; =============================================================================
[BITS 32]
stage2_main_pm32:
    call idt_setup
    call paging_setup
    call test_paging
    call simd_enable
    call longmode_enter

    cli
    hlt
[BITS 16]

; =============================================================================
; boot_info_init — initialize BootInfo structure at 0x7000
; Input: none
; Output: none
; Clobbers: none (preserves all registers)
; =============================================================================
boot_info_init:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push es

    cld                             ; Clear direction flag for rep stosd
    ; Zero out the 88-byte BootInfo structure (22 dwords)
    mov edi, BOOT_INFO_ADDR
    mov ecx, 22
    xor eax, eax
    rep stosd

    ; 1. e820_map_addr -> E820_DEST + 2
    mov dword [BOOT_INFO_E820_ADDR], E820_DEST + 2
    mov dword [BOOT_INFO_E820_ADDR + 4], 0

    ; 2. e820_count -> load count word from E820_DEST
    xor eax, eax
    mov ax, [E820_DEST]
    mov [BOOT_INFO_E820_COUNT], eax

    ; 3. boot_drive -> load byte, zero-extend to dword
    xor eax, eax
    mov al, [boot_drive]
    mov [BOOT_INFO_DRIVE], eax

    ; 4. cpu_features -> load from FEATURES_DEST
    mov eax, [FEATURES_DEST]
    mov [BOOT_INFO_FEATURES], eax

    ; 5. acpi_rsdp -> call acpi_find_rsdp
    call acpi_find_rsdp
    mov [BOOT_INFO_ACPI_RSDP], eax
    mov dword [BOOT_INFO_ACPI_RSDP + 4], 0

    ; 6. framebuffer_addr -> best_fb_addr
    mov eax, [best_fb_addr]
    mov [BOOT_INFO_FB_ADDR], eax
    mov dword [BOOT_INFO_FB_ADDR + 4], 0

    ; 7. framebuffer_width -> best_width
    xor eax, eax
    mov ax, [best_width]
    mov [BOOT_INFO_FB_WIDTH], eax

    ; 8. framebuffer_height -> best_height
    xor eax, eax
    mov ax, [best_height]
    mov [BOOT_INFO_FB_HEIGHT], eax

    ; 9. framebuffer_pitch -> best_pitch
    xor eax, eax
    mov ax, [best_pitch]
    mov [BOOT_INFO_FB_PITCH], eax

    ; 10. framebuffer_format -> best_bpp
    xor eax, eax
    mov al, [best_bpp]
    mov [BOOT_INFO_FB_FORMAT], eax

    ; 11. edd_params -> absolute physical address of edd_params_block
    xor eax, eax
    cmp byte [edd_supported], 1
    jne .skip_edd
    mov eax, edd_params_block
.skip_edd:
    mov [BOOT_INFO_EDD_ADDR], eax
    mov dword [BOOT_INFO_EDD_ADDR + 4], 0

    pop es
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

%endif ; MAIN_ASM