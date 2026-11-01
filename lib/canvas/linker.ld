/* ==========================================================================
 * Canvas images: link layout (the one copy; the Makefile only uses it)
 * ==========================================================================
 * Three loadable segments, none both writable and executable (W^X):
 *   text    R-X   code
 *   rodata  R--   constants
 *   data    RW-   initialised data, then bss
 * Each starts on a fresh 4 KiB page so the loader can map it with its own
 * protection. The entry point is canvasd_init; other images pass -e.
 * ========================================================================== */

ENTRY(canvasd_init)

PHDRS
{
    text    PT_LOAD FLAGS(5);           /* R X */
    rodata  PT_LOAD FLAGS(4);           /* R   */
    data    PT_LOAD FLAGS(6);           /* R W */
}

SECTIONS
{
    . = 0x200000;
    .text : { *(.text .text.*) } :text

    . = ALIGN(0x1000);
    .rodata : { *(.rodata .rodata.*) } :rodata

    . = ALIGN(0x1000);
    .data : { *(.data .data.*) } :data
    .bss : { *(.bss .bss.*) *(COMMON) } :data

    /DISCARD/ : { *(.note.*) *(.comment*) *(.eh_frame*) }
}
