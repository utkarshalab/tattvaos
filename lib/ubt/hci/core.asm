; =============================================================================
; Utkarsha OS — lib/ubt/hci/core.asm — HCI commands, events, bring-up
; =============================================================================
;   ubt_hci_cmd(adapter, opcode, params, length)
;       send a command and wait (one second) for its Command Complete or
;       Command Status. EAX = its HCI status (0 success), or a negative
;       UBT_E*; return parameters after the status in adapter.wait_buf
;   ubt_hci_event(adapter, event, length)
;       an event from the transport: credits, the command waited for,
;       hardware errors; anything else to adapter.event_fn
;   ubt_hci_init(adapter)
;       reset, version, supported commands, features, buffer sizes,
;       address, event masks, then LE's buffer size and event mask when the
;       controller does LE. EAX = 0, else what failed is in failed_op and
;       failed_status
; =============================================================================

%ifndef LIB_UBT_HCI_CORE_ASM
%define LIB_UBT_HCI_CORE_ASM

section .rodata
; every event the core and the layers above use (the Core spec's default
; with the encryption, mode, link and LE meta events)
ubt_event_mask:     db 0xFF, 0xFF, 0xFB, 0xFF, 0x07, 0xF8, 0xBF, 0x3D
ubt_le_event_mask:  db 0xFF, 0xFF, 0x0F, 0x00, 0x00, 0x00, 0x00, 0x00

section .text

; -----------------------------------------------------------------------------
; ubt_hci_cmd
; Input:  RDI = ubt_adapter*, ESI = opcode, RDX = parameters, ECX = length
; Output: EAX = HCI status, or a negative UBT_E*
; -----------------------------------------------------------------------------
global ubt_hci_cmd
ubt_hci_cmd:
    push rbx
    push r12
    push r13
    sub rsp, 272                        ; the command: opcode, length, params
    mov rbx, rdi
    mov eax, -UBT_EIO
    cmp ecx, 255
    ja .out
    mov [rsp], si
    mov [rsp + 2], cl
    mov r12d, ecx
    xor eax, eax
.copy:
    cmp eax, r12d
    jae .send
    mov r8b, [rdx + rax]
    mov [rsp + 3 + rax], r8b
    inc eax
    jmp .copy
.send:
    ; waiting before sending: the answer can come while the command goes
    movzx eax, si
    mov [rbx + ubt_adapter.wait_op], eax
    mov dword [rbx + ubt_adapter.wait_done], 0
    mov dword [rbx + ubt_adapter.wait_len], 0
    mov rdi, rbx
    mov rsi, rsp
    lea edx, [r12d + 3]
    call ubt_tr_send_cmd
    test eax, eax
    js .failed
    mov r13d, UBT_CMD_TIMEOUT_US / 50
.wait:
    cmp dword [rbx + ubt_adapter.wait_done], 0
    jne .done
    mov rdi, rbx
    call ubt_tr_poll
    cmp dword [rbx + ubt_adapter.wait_done], 0
    jne .done
    dec r13d
    jz .timeout
    mov edi, 50
    call usb_delay
    jmp .wait
.done:
    mov eax, [rbx + ubt_adapter.wait_status]
    jmp .out
.timeout:
    mov eax, -UBT_ETIMEOUT
    jmp .out
.failed:
    mov eax, -UBT_EIO
.out:
    mov dword [rbx + ubt_adapter.wait_op], 0
    add rsp, 272
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_hci_event
; Input:  RDI = ubt_adapter*, RSI = the event (code, length, parameters),
;         EDX = its length
; -----------------------------------------------------------------------------
global ubt_hci_event
ubt_hci_event:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    inc dword [rbx + ubt_adapter.events]
    cmp r13d, 2
    jb .out
    movzx eax, byte [r12]
    cmp eax, HCI_EV_CMD_COMPLETE
    je .complete
    cmp eax, HCI_EV_CMD_STATUS
    je .status
    cmp eax, HCI_EV_HW_ERROR
    jne .upward
    inc dword [rbx + ubt_adapter.hw_errors]
    jmp .upward

.complete:
    ; credits, opcode, return parameters (status first)
    cmp r13d, 5
    jb .out
    movzx eax, byte [r12 + 2]
    mov [rbx + ubt_adapter.credits], eax
    movzx eax, word [r12 + 3]
    test eax, eax
    jz .out                             ; only credits (a no-op opcode)
    cmp eax, [rbx + ubt_adapter.wait_op]
    jne .upward
    xor eax, eax
    cmp r13d, 6
    jb .complete_status
    movzx eax, byte [r12 + 5]
.complete_status:
    mov [rbx + ubt_adapter.wait_status], eax
    mov ecx, r13d
    sub ecx, 6
    jns .copy_len
    xor ecx, ecx
.copy_len:
    cmp ecx, 72
    jbe .copy
    mov ecx, 72
.copy:
    mov [rbx + ubt_adapter.wait_len], ecx
    xor edx, edx
.byte:
    cmp edx, ecx
    jae .waited
    mov al, [r12 + rdx + 6]
    mov [rbx + ubt_adapter.wait_buf + rdx], al
    inc edx
    jmp .byte
.waited:
    mov dword [rbx + ubt_adapter.wait_done], 1
    jmp .out

.status:
    cmp r13d, 6
    jb .out
    movzx eax, byte [r12 + 3]
    mov [rbx + ubt_adapter.credits], eax
    movzx eax, word [r12 + 4]
    test eax, eax
    jz .out
    cmp eax, [rbx + ubt_adapter.wait_op]
    jne .upward
    movzx eax, byte [r12 + 2]
    mov [rbx + ubt_adapter.wait_status], eax
    mov dword [rbx + ubt_adapter.wait_len], 0
    mov dword [rbx + ubt_adapter.wait_done], 1
    jmp .out

.upward:
    mov rax, [rbx + ubt_adapter.event_fn]
    test rax, rax
    jz .out
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call rax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ubt_hci_step — one bring-up command with no parameters (RBX = adapter,
; EDI = opcode); CF = 1 when it failed (recorded)
ubt_hci_step:
    sub rsp, 8
    mov esi, edi
    xor edx, edx
    xor ecx, ecx
.go:
    mov rdi, rbx
    mov [rbx + ubt_adapter.failed_op], esi
    call ubt_hci_cmd
    add rsp, 8
    mov [rbx + ubt_adapter.failed_status], eax
    test eax, eax
    jnz .bad
    clc
    ret
.bad:
    stc
    ret

; ubt_hci_step_with — the same with parameters: ESI = opcode, RDX, ECX
ubt_hci_step_with:
    sub rsp, 8
    jmp ubt_hci_step.go

; -----------------------------------------------------------------------------
; ubt_hci_init
; Input:  RDI = ubt_adapter*
; Output: EAX = 0 (the adapter is UBT_UP), else not 0 (UBT_FAILED)
; -----------------------------------------------------------------------------
global ubt_hci_init
ubt_hci_init:
    push rbx
    mov rbx, rdi
    mov dword [rbx + ubt_adapter.credits], 1
    mov edi, HCI_RESET
    call ubt_hci_step
    jc .failed
    ; what it is
    mov edi, HCI_READ_LOCAL_VERSION
    call ubt_hci_step
    jc .failed
    mov al, [rbx + ubt_adapter.wait_buf]
    mov [rbx + ubt_adapter.hci_version], al
    mov ax, [rbx + ubt_adapter.wait_buf + 1]
    mov [rbx + ubt_adapter.hci_revision], ax
    mov al, [rbx + ubt_adapter.wait_buf + 3]
    mov [rbx + ubt_adapter.lmp_version], al
    mov ax, [rbx + ubt_adapter.wait_buf + 4]
    mov [rbx + ubt_adapter.manufacturer], ax
    mov ax, [rbx + ubt_adapter.wait_buf + 6]
    mov [rbx + ubt_adapter.lmp_subversion], ax
    mov edi, HCI_READ_LOCAL_COMMANDS
    call ubt_hci_step
    jc .failed
    lea rdi, [rbx + ubt_adapter.commands]
    lea rsi, [rbx + ubt_adapter.wait_buf]
    mov ecx, 64
    rep movsb
    mov edi, HCI_READ_LOCAL_FEATURES
    call ubt_hci_step
    jc .failed
    mov rax, [rbx + ubt_adapter.wait_buf]
    mov [rbx + ubt_adapter.features], rax
    bt rax, 8 * HCI_FEAT_LE_BYTE + HCI_FEAT_LE_BIT  ; byte 4: the upper half
    setc byte [rbx + ubt_adapter.le]
    mov edi, HCI_READ_BUFFER_SIZE
    call ubt_hci_step
    jc .failed
    mov ax, [rbx + ubt_adapter.wait_buf]
    mov [rbx + ubt_adapter.acl_mtu], ax
    mov al, [rbx + ubt_adapter.wait_buf + 2]
    mov [rbx + ubt_adapter.sco_mtu], al
    mov ax, [rbx + ubt_adapter.wait_buf + 3]
    mov [rbx + ubt_adapter.acl_count], ax
    mov ax, [rbx + ubt_adapter.wait_buf + 5]
    mov [rbx + ubt_adapter.sco_count], ax
    mov edi, HCI_READ_BD_ADDR
    call ubt_hci_step
    jc .failed
    mov eax, [rbx + ubt_adapter.wait_buf]
    mov [rbx + ubt_adapter.bdaddr], eax
    mov ax, [rbx + ubt_adapter.wait_buf + 4]
    mov [rbx + ubt_adapter.bdaddr + 4], ax
    mov esi, HCI_SET_EVENT_MASK
    lea rdx, [rel ubt_event_mask]
    mov ecx, 8
    call ubt_hci_step_with
    jc .failed
    cmp byte [rbx + ubt_adapter.le], 0
    je .up
    mov edi, HCI_LE_READ_BUFFER_SIZE
    call ubt_hci_step
    jc .failed
    mov ax, [rbx + ubt_adapter.wait_buf]
    mov [rbx + ubt_adapter.le_mtu], ax
    mov al, [rbx + ubt_adapter.wait_buf + 2]
    mov [rbx + ubt_adapter.le_count], al
    mov esi, HCI_LE_SET_EVENT_MASK
    lea rdx, [rel ubt_le_event_mask]
    mov ecx, 8
    call ubt_hci_step_with
    jc .failed
.up:
    mov dword [rbx + ubt_adapter.state], UBT_UP
    mov dword [rbx + ubt_adapter.failed_op], 0
    xor eax, eax
    pop rbx
    ret
.failed:
    mov dword [rbx + ubt_adapter.state], UBT_FAILED
    mov eax, 1
    pop rbx
    ret

%endif ; LIB_UBT_HCI_CORE_ASM
