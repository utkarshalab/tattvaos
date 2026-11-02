/* ==========================================================================
 * Canvas UBF programs: link layout (tools/ubfpack.py reads the result)
 * ==========================================================================
 * Linked at image offset 0, so every address in the output is an image
 * offset. Four sections, one UBF segment each, each on a fresh 4 KiB page so
 * the loader can give it its own protection:
 *   .text    R-X
 *   .rodata  R--   holds the import slots
 *   .data    RW-
 *   .bss     RW-   no bytes in the file
 * ========================================================================== */

SECTIONS
{
    . = 0;
    .text : { *(.text .text.*) }

    . = ALIGN(0x1000);
    .rodata : { *(.rodata .rodata.*) }

    . = ALIGN(0x1000);
    .data : { *(.data .data.*) }

    . = ALIGN(0x1000);
    .bss : { *(.bss .bss.*) *(COMMON) }

    /DISCARD/ : { *(.note.*) *(.comment*) *(.eh_frame*) }
}
