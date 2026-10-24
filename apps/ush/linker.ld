/* =============================================================================
 * File     : apps/ush/linker.ld
 * Project  : Utkarsha OS — Utkarsha Shell
 * Author   : Utkarsha Lab
 * License  : Apache-2.0
 * Description: Linker script for ush shell ELF image.
 * =============================================================================

ENTRY(ush_main)

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