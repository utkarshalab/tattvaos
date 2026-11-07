; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/aml.asm
; =============================================================================
; The AML interpreter as one include. It needs nothing from the kernel:
; memory comes from aml_init, and the outside world (regions, Notify,
; Sleep, the clock, Debug) through hooks. Plan: lib/io/acpi/ROADMAP.md.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_ASM
%define LIB_IO_ACPI_AML_ASM

%include "lib/io/acpi/aml/aml.inc"
%include "lib/io/acpi/aml/heap.asm"
%include "lib/io/acpi/aml/ns.asm"
%include "lib/io/acpi/aml/value.asm"
%include "lib/io/acpi/aml/parse.asm"
%include "lib/io/acpi/aml/exec.asm"
%include "lib/io/acpi/aml/ops.asm"
%include "lib/io/acpi/aml/field.asm"
%include "lib/io/acpi/aml/api.asm"
%include "lib/io/acpi/aml/init.asm"

%endif ; LIB_IO_ACPI_AML_ASM
