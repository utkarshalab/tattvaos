/* =============================================================================
 * File     : apps/ish/linker.ld
 * Project  : Utkarsha OS — Ishana Shell
 * Author   : Utkarsha Lab
 * License  : Apache-2.0
 * Description: Linker script for ish shell ELF image.
 * =============================================================================

ENTRY(ish_main)

SECTIONS
{
    /* Load at 2MB boundary — standard for Utkarsha OS user/app images */
    . = 0x200000;

    .text : {
        *(.text*)
        *(.text)
    }

    .rodata : {
        *(.rodata*)
        *(.rodata)
    }

    .data : {
        *(.data*)
        *(.data)
    }

    .bss : {
        *(.bss*)
        *(.bss)
        *(COMMON)
    }

    /* Discard debug notes */
    /DISCARD/ : {
        *(.note.*)
        *(.comment*)
    }
}