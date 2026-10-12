; ============================================================================
; Config Parser — Simple Text Config (key = value, sections)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

section .text

global config_parse
config_parse:
    PROLOGUE
    xor rax, rax
    ret

section .data

global config_version
config_version: dq 0x010000