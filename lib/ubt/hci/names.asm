; =============================================================================
; Utkarsha OS — lib/ubt/hci/names.asm — HCI names, versions, layouts
; =============================================================================
;   ubt_hci_cmd_info(opcode)  → RAX = its entry in ubt_hci_cmds, or 0
;   ubt_hci_event_info(code), ubt_hci_le_info(subevent)   the same
;   ubt_hci_name(entry) → RAX = its name; ubt_hci_params(entry),
;   ubt_hci_returns(entry): its layouts ("field:size,..."); EAX of
;   ubt_hci_version(entry) = major << 8 | minor (the Core version it came in)
;
; The tables (hci/tables.asm) are made from hci/hci.def and sorted, so the
; lookups halve the range each step.
; =============================================================================

%ifndef LIB_UBT_HCI_NAMES_ASM
%define LIB_UBT_HCI_NAMES_ASM

%include "lib/ubt/hci/tables.asm"

section .text

; hci_find — RDI = table, ECX = entries, ESI = code → RAX = entry, or 0
hci_find:
    xor r8d, r8d                        ; low
    mov r9d, ecx                        ; high (past the end)
.step:
    cmp r8d, r9d
    jae .none
    lea eax, [r8 + r9]
    shr eax, 1
    mov edx, eax
    shl edx, 4
    movzx r10d, word [rdi + rdx]
    cmp esi, r10d
    je .found
    jb .lower
    lea r8d, [rax + 1]
    jmp .step
.lower:
    mov r9d, eax
    jmp .step
.found:
    lea rax, [rdi + rdx]
    ret
.none:
    xor eax, eax
    ret

global ubt_hci_cmd_info
ubt_hci_cmd_info:
    mov esi, edi
    lea rdi, [rel ubt_hci_cmds]
    mov ecx, [rel ubt_hci_cmds_n]
    jmp hci_find

global ubt_hci_event_info
ubt_hci_event_info:
    mov esi, edi
    lea rdi, [rel ubt_hci_events]
    mov ecx, [rel ubt_hci_events_n]
    jmp hci_find

global ubt_hci_le_info
ubt_hci_le_info:
    mov esi, edi
    lea rdi, [rel ubt_hci_le_events]
    mov ecx, [rel ubt_hci_le_events_n]
    jmp hci_find

; the strings of an entry (RDI): name at +4, parameters +8, returns +12
global ubt_hci_name
ubt_hci_name:
    mov eax, [rdi + 4]
    jmp hci_string
global ubt_hci_params
ubt_hci_params:
    mov eax, [rdi + 8]
    jmp hci_string
global ubt_hci_returns
ubt_hci_returns:
    mov eax, [rdi + 12]
hci_string:
    lea rcx, [rel ubt_hci_strings]
    add rax, rcx
    ret

global ubt_hci_version
ubt_hci_version:
    movzx eax, byte [rdi + 2]
    shl eax, 8
    mov al, [rdi + 3]
    ret

%endif ; LIB_UBT_HCI_NAMES_ASM
