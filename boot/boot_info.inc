%ifndef TATTVA_BOOT_INFO_INC
%define TATTVA_BOOT_INFO_INC
; =============================================================================
; Tattva OS — versioned BootInfo ABI shared by BIOS, UEFI, and the kernel.
; =============================================================================

BOOT_INFO_E820_PTR_OFF          equ 0
BOOT_INFO_E820_COUNT_OFF        equ 8
BOOT_INFO_DRIVE_OFF             equ 12
BOOT_INFO_FEATURES_OFF          equ 16
BOOT_INFO_KASLR_PHYS_OFF        equ 20
BOOT_INFO_ACPI_RSDP_OFF         equ 24
BOOT_INFO_FB_ADDR_OFF           equ 32
BOOT_INFO_FB_WIDTH_OFF          equ 40
BOOT_INFO_FB_HEIGHT_OFF         equ 44
BOOT_INFO_FB_PITCH_OFF          equ 48
BOOT_INFO_FB_FORMAT_OFF         equ 52
BOOT_INFO_INITRD_ADDR_OFF       equ 56
BOOT_INFO_INITRD_SIZE_OFF       equ 64
BOOT_INFO_EDD_ADDR_OFF          equ 72
BOOT_INFO_SMP_CORES_OFF         equ 80

; ABI v2 extension.  The magic and size make new fields fail closed instead
; of interpreting bytes left behind by an older loader.
BOOT_INFO_ABI_SIZE_OFF          equ 84
BOOT_INFO_AP_TRAMPOLINE_OFF     equ 88
BOOT_INFO_AP_TRAMPOLINE_SIZE_OFF equ 96
BOOT_INFO_BOOT_SOURCE_OFF       equ 100
BOOT_INFO_MAGIC_OFF             equ 104
BOOT_INFO_ABI_SIZE              equ 112
BOOT_INFO_MAGIC                 equ 0x3249424156544154 ; "TATVABI2"

BOOT_SOURCE_BIOS                equ 1
BOOT_SOURCE_UEFI                equ 2
BOOT_AP_TRAMPOLINE_BYTES        equ 4096

; Keep the wire ABI mechanically checkable by every assembly consumer.
%if BOOT_INFO_ABI_SIZE_OFF != 84 || BOOT_INFO_AP_TRAMPOLINE_OFF != 88 || BOOT_INFO_MAGIC_OFF != 104 || BOOT_INFO_ABI_SIZE != 112
    %error "BootInfo ABI v2 layout drift"
%endif
%if BOOT_INFO_ABI_SIZE % 8
    %error "BootInfo ABI size must remain qword-aligned"
%endif

%endif ; TATTVA_BOOT_INFO_INC
