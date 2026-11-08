; =============================================================================
; Utkarsha OS — lib/ubt/sm/br.asm — BR/EDR pairing (to come: Secure Simple
; Pairing)
; =============================================================================
; For now BR/EDR links cannot be paired from here: ubt_br_pair says so and
; the controller's pairing events are left alone.
; =============================================================================

%ifndef LIB_UBT_SM_BR_ASM
%define LIB_UBT_SM_BR_ASM

section .text

global ubt_br_pair
ubt_br_pair:
    mov eax, -UBT_EIO
    ret

global ubt_br_confirm
global ubt_br_passkey
global ubt_br_event
global ubt_br_encrypted
global ubt_br_free
ubt_br_confirm:
ubt_br_passkey:
ubt_br_event:
ubt_br_encrypted:
ubt_br_free:
    ret

%endif ; LIB_UBT_SM_BR_ASM
