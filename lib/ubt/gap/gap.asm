; =============================================================================
; Utkarsha OS — lib/ubt/gap/gap.asm — discovery, names, advertising, scanning
; =============================================================================
;   ubt_le_advertise(adapter, type, data, len, rsp, rsp_len)   → HCI status
;   ubt_le_advertise_stop(adapter), ubt_le_scan(adapter, active, no_dups),
;   ubt_le_scan_stop(adapter)
;   ubt_inquiry(adapter, length, max), ubt_inquiry_cancel(adapter),
;   ubt_remote_name(adapter, addr), ubt_set_scan(adapter, bits),
;   ubt_set_name(adapter, name, len), ubt_set_class(adapter, class),
;   ubt_set_eir(adapter, data, len)
;   ubt_ad_find(data, len, type) → RAX = the field's value, EDX = its length
;   ubt_gap_event(adapter, event, len)   from the HCI core: what GAP hears
;
; Everything heard goes to adapter.gap_fn: devices found (LE advertising
; and scan responses, legacy and extended reports; BR/EDR inquiry results,
; standard, with RSSI and extended with EIR), the end of an inquiry, and
; remote names. Pairing events go on to the security code (sm/).
; =============================================================================

%ifndef LIB_UBT_GAP_GAP_ASM
%define LIB_UBT_GAP_GAP_ASM

%define GAP_GIAC            0x9E8B33        ; the general inquiry access code

section .rodata
global ubt_gap_layout
ubt_gap_layout:
    dd ubt_adapter.gap_fn, ubt_adapter.io_cap, ubt_adapter.bondable, ubt_adapter.sc_only
    dd ubt_adapter.gatt, ubt_conn.att, ubt_conn.smp, ubt_conn.pair
    dd ubt_conn.rfcomm, ubt_conn.sec, ubt_conn.key_size, ubt_conn_size
    dd ubt_found_size, ubt_name_size, ubt_adapter_size, ubt_adapter.legacy

section .text

; ubt_gap_cmd — RDI = adapter, ESI = opcode, RDX = parameters, ECX = length:
; sent and waited for → EAX = HCI status, or negative
ubt_gap_cmd:
    sub rsp, 8
    call ubt_hci_cmd
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_le_advertise — RDI = adapter, ESI = advertising type (0 connectable,
;                    2 scannable, 3 not connectable), RDX = advertising data,
;                    ECX = its length (31 at most), R8 = scan response data,
;                    R9D = its length → EAX = HCI status, or negative
; -----------------------------------------------------------------------------
global ubt_le_advertise
ubt_le_advertise:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 48
    mov rbx, rdi
    mov r12d, esi
    mov r13, rdx
    mov r14d, ecx
    mov r15, r8
    mov [rsp + 40], r9d
    ; parameters: 100 ms, the type, our public address, all channels
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov word [rsp], 0x00A0
    mov word [rsp + 2], 0x00A0
    mov [rsp + 4], r12b
    mov byte [rsp + 13], 7
    mov rdi, rbx
    mov esi, HCI_LE_SET_ADV_PARAMS
    mov rdx, rsp
    mov ecx, 15
    call ubt_gap_cmd
    test eax, eax
    jnz .out
    mov rdi, rbx
    mov esi, HCI_LE_SET_ADV_DATA
    mov rdx, r13
    mov ecx, r14d
    call .data
    test eax, eax
    jnz .out
    mov rdi, rbx
    mov esi, HCI_LE_SET_SCAN_RSP
    mov rdx, r15
    mov ecx, [rsp + 40]
    call .data
    test eax, eax
    jnz .out
    mov byte [rsp], 1
    mov rdi, rbx
    mov esi, HCI_LE_SET_ADV_ENABLE
    mov rdx, rsp
    mov ecx, 1
    call ubt_gap_cmd
.out:
    add rsp, 48
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; one data command: its length, then 31 bytes (the rest zero)
.data:
    push rbx
    push r12
    sub rsp, 40
    mov rbx, rdi
    mov r12d, esi
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov [rsp + 24], rax
    cmp ecx, 31
    jbe .len
    mov ecx, 31
.len:
    mov [rsp], cl
    lea rdi, [rsp + 1]
    mov rsi, rdx
    test rsi, rsi
    jz .send
    rep movsb
.send:
    mov rdi, rbx
    mov esi, r12d
    mov rdx, rsp
    mov ecx, 32
    call ubt_gap_cmd
    add rsp, 40
    pop r12
    pop rbx
    ret

; ubt_le_advertise_stop — RDI = adapter → EAX
global ubt_le_advertise_stop
ubt_le_advertise_stop:
    mov esi, HCI_LE_SET_ADV_ENABLE
    xor edx, edx
    jmp ubt_gap_byte

; ubt_gap_byte — RDI = adapter, ESI = opcode, EDX = one parameter byte → EAX
ubt_gap_byte:
    sub rsp, 8
    mov [rsp], dl
    mov rdx, rsp
    mov ecx, 1
    call ubt_hci_cmd
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_le_scan — RDI = adapter, ESI = 1 active (asks for scan responses),
;               EDX = 1 to have the controller drop duplicates → EAX
; -----------------------------------------------------------------------------
global ubt_le_scan
ubt_le_scan:
    push rbx
    push r12
    sub rsp, 24
    mov rbx, rdi
    mov r12d, edx
    mov [rsp], sil                      ; type
    mov word [rsp + 1], 0x0060          ; interval 60 ms
    mov word [rsp + 3], 0x0030          ; window 30 ms
    mov byte [rsp + 5], 0               ; our public address
    mov byte [rsp + 6], 0               ; everyone
    mov esi, HCI_LE_SET_SCAN_PARAMS
    mov rdx, rsp
    mov ecx, 7
    call ubt_gap_cmd
    test eax, eax
    jnz .out
    mov byte [rsp], 1
    mov [rsp + 1], r12b
    mov rdi, rbx
    mov esi, HCI_LE_SET_SCAN_ENABLE
    mov rdx, rsp
    mov ecx, 2
    call ubt_gap_cmd
.out:
    add rsp, 24
    pop r12
    pop rbx
    ret

; ubt_le_scan_stop — RDI = adapter → EAX
global ubt_le_scan_stop
ubt_le_scan_stop:
    sub rsp, 8
    mov word [rsp], 0
    mov esi, HCI_LE_SET_SCAN_ENABLE
    mov rdx, rsp
    mov ecx, 2
    call ubt_hci_cmd
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_inquiry — RDI = adapter, ESI = length (1.28 s units, 1-48), EDX = most
;               responses (0: no limit) → EAX. Results with RSSI and EIR.
; -----------------------------------------------------------------------------
global ubt_inquiry
ubt_inquiry:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov edx, 2                          ; extended inquiry results
    mov esi, HCI_WRITE_INQUIRY_MODE
    call ubt_gap_byte
    test eax, eax
    jnz .out
    mov dword [rsp], GAP_GIAC
    mov [rsp + 3], r12b
    mov [rsp + 4], r13b
    mov rdi, rbx
    mov esi, HCI_INQUIRY
    mov rdx, rsp
    mov ecx, 5
    call ubt_gap_cmd
.out:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret

; ubt_inquiry_cancel — RDI = adapter → EAX
global ubt_inquiry_cancel
ubt_inquiry_cancel:
    sub rsp, 8
    mov esi, HCI_INQUIRY_CANCEL
    xor edx, edx
    xor ecx, ecx
    call ubt_hci_cmd
    add rsp, 8
    ret

; ubt_remote_name — RDI = adapter, RSI = address → EAX (UBT_GAP_NAME later)
global ubt_remote_name
ubt_remote_name:
    sub rsp, 24
    mov eax, [rsi]
    mov [rsp], eax
    mov ax, [rsi + 4]
    mov [rsp + 4], ax
    mov byte [rsp + 6], 1               ; page scan repetition R1
    mov byte [rsp + 7], 0
    mov word [rsp + 8], 0               ; clock offset not known
    mov esi, HCI_REMOTE_NAME_REQ
    mov rdx, rsp
    mov ecx, 10
    call ubt_hci_cmd
    add rsp, 24
    ret

; ubt_set_scan — RDI = adapter, ESI = 1 discoverable | 2 connectable → EAX
global ubt_set_scan
ubt_set_scan:
    mov edx, esi
    mov esi, HCI_WRITE_SCAN_ENABLE
    jmp ubt_gap_byte

; ubt_set_class — RDI = adapter, ESI = class of device (24 bits) → EAX
global ubt_set_class
ubt_set_class:
    sub rsp, 8
    mov [rsp], esi
    mov esi, HCI_WRITE_CLASS
    mov rdx, rsp
    mov ecx, 3
    call ubt_hci_cmd
    add rsp, 8
    ret

; ubt_set_name — RDI = adapter, RSI = name, EDX = length (248 at most) → EAX
global ubt_set_name
ubt_set_name:
    mov ecx, 248
    mov r8d, HCI_WRITE_LOCAL_NAME
    xor r9d, r9d
    jmp ubt_gap_block

; ubt_set_eir — RDI = adapter, RSI = EIR data, EDX = length (240 at most) → EAX
global ubt_set_eir
ubt_set_eir:
    mov ecx, 240
    mov r8d, HCI_WRITE_EIR
    mov r9d, 1                          ; one byte before: FEC wanted
    jmp ubt_gap_block

; ubt_gap_block — RDI = adapter, RSI = data, EDX = length, ECX = the field's
; size, R8D = opcode, R9D = 1 for a leading 1 byte: a fixed-size field,
; zero-filled, sent and waited for → EAX
ubt_gap_block:
    push rbx
    push r12
    push r13
    sub rsp, 256
    mov rbx, rdi
    mov r12d, r8d
    lea r13d, [rcx + r9]                ; the command's length
    cmp edx, ecx
    jbe .fits
    mov edx, ecx
.fits:
    push rsi
    push rdx
    lea rdi, [rsp + 16]
    xor eax, eax
    mov ecx, 256
    rep stosb
    pop rdx
    pop rsi
    mov rdi, rsp
    test r9d, r9d
    jz .copy
    mov byte [rdi], 1
    inc rdi
.copy:
    mov ecx, edx
    rep movsb
    mov rdi, rbx
    mov esi, r12d
    mov rdx, rsp
    mov ecx, r13d
    call ubt_hci_cmd
    add rsp, 256
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_ad_find — RDI = advertising data or EIR, ESI = its length, EDX = the AD
;               type → RAX = that field's value, EDX = its length; RAX = 0
;               when there is none (or the data stops making sense)
; -----------------------------------------------------------------------------
global ubt_ad_find
ubt_ad_find:
    lea r8, [rdi + rsi]                 ; the end
.field:
    lea rax, [rdi + 2]
    cmp rax, r8
    ja .none
    movzx ecx, byte [rdi]               ; length: type and value
    test ecx, ecx
    jz .none                            ; the rest is padding
    lea rax, [rdi + rcx + 1]
    cmp rax, r8
    ja .none
    cmp [rdi + 1], dl
    je .found
    mov rdi, rax
    jmp .field
.found:
    lea rax, [rdi + 2]
    lea edx, [rcx - 1]
    ret
.none:
    xor eax, eax
    xor edx, edx
    ret

; -----------------------------------------------------------------------------
; ubt_gap_event — RDI = adapter, RSI = event, EDX = length (from the core,
;                 after the link layer)
; -----------------------------------------------------------------------------
global ubt_gap_event
ubt_gap_event:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 56                         ; [rsp] a ubt_found or ubt_name
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    cmp r13d, 2
    jb .out
    lea rbp, [r12 + r13]                ; the end
    movzx eax, byte [r12]
    cmp eax, HCI_EV_INQUIRY_RESULT
    je .inquiry
    cmp eax, HCI_EV_INQUIRY_RSSI
    je .inquiry_rssi
    cmp eax, HCI_EV_INQUIRY_EXT
    je .inquiry_ext
    cmp eax, HCI_EV_INQUIRY_DONE
    je .inquiry_done
    cmp eax, HCI_EV_REMOTE_NAME
    je .name
    cmp eax, HCI_EV_LE_META
    je .le
    ; pairing and encryption: the security code
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call ubt_sec_event
    jmp .out

.inquiry:
    ; responses of 14 bytes: address, page scan mode, 2 reserved, class, clock
    movzx r14d, byte [r12 + 2]
    lea r15, [r12 + 3]
.inq_next:
    test r14d, r14d
    jz .out
    lea rax, [r15 + 14]
    cmp rax, rbp
    ja .out
    call .found_br
    mov byte [rsp + ubt_found.rssi], 127
    mov eax, [r15 + 9]
    and eax, 0xFFFFFF
    mov [rsp + ubt_found.class], eax
    call .tell
    add r15, 14
    dec r14d
    jmp .inq_next

.inquiry_rssi:
    ; responses of 14 bytes: address, page scan mode, reserved, class, clock, RSSI
    movzx r14d, byte [r12 + 2]
    lea r15, [r12 + 3]
.rssi_next:
    test r14d, r14d
    jz .out
    lea rax, [r15 + 14]
    cmp rax, rbp
    ja .out
    call .found_br
    mov eax, [r15 + 8]
    and eax, 0xFFFFFF
    mov [rsp + ubt_found.class], eax
    mov al, [r15 + 13]
    mov [rsp + ubt_found.rssi], al
    call .tell
    add r15, 14
    dec r14d
    jmp .rssi_next

.inquiry_ext:
    ; one response: address, mode, reserved, class, clock, RSSI, 240 bytes EIR
    lea r15, [r12 + 3]
    lea rax, [r15 + 14]
    cmp rax, rbp
    ja .out
    call .found_br
    mov eax, [r15 + 8]
    and eax, 0xFFFFFF
    mov [rsp + ubt_found.class], eax
    mov al, [r15 + 13]
    mov [rsp + ubt_found.rssi], al
    lea rax, [r15 + 14]
    mov [rsp + ubt_found.data], rax
    mov rcx, rbp
    sub rcx, rax
    cmp ecx, 240
    jbe .eir_len
    mov ecx, 240
.eir_len:
    mov [rsp + ubt_found.data_len], ecx
    call .tell
    jmp .out

.inquiry_done:
    mov esi, UBT_GAP_INQUIRY_DONE
    xor edx, edx
    call .hook
    jmp .out

.name:
    ; status, address, the name (up to 248 bytes, ended by a 0 when shorter)
    cmp r13d, 2 + 7
    jb .out
    xor eax, eax
    mov [rsp], rax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov al, [r12 + 2]
    mov [rsp + ubt_name.status], al
    mov eax, [r12 + 3]
    mov [rsp + ubt_name.addr], eax
    mov ax, [r12 + 7]
    mov [rsp + ubt_name.addr + 4], ax
    lea rsi, [r12 + 9]
    mov [rsp + ubt_name.name], rsi
    xor ecx, ecx
.name_len:
    lea rax, [rsi + rcx]
    cmp rax, rbp
    jae .name_done
    cmp ecx, 248
    jae .name_done
    cmp byte [rax], 0
    je .name_done
    inc ecx
    jmp .name_len
.name_done:
    mov [rsp + ubt_name.len], ecx
    mov esi, UBT_GAP_NAME
    mov rdx, rsp
    call .hook
    jmp .out

.le:
    cmp r13d, 3
    jb .out
    movzx eax, byte [r12 + 2]
    cmp eax, HCI_LE_EV_ADV_REPORT
    je .adv
    cmp eax, HCI_LE_EV_EXT_ADV_REPORT
    je .ext_adv
    mov rdi, rbx                        ; LTK requests: the security code
    mov rsi, r12
    mov edx, r13d
    call ubt_sec_event
    jmp .out

.adv:
    ; reports: type, address type, address, data length, data, RSSI
    cmp r13d, 4
    jb .out
    movzx r14d, byte [r12 + 3]
    lea r15, [r12 + 4]
.adv_next:
    test r14d, r14d
    jz .out
    lea rax, [r15 + 9]
    cmp rax, rbp
    ja .out
    movzx ecx, byte [r15 + 8]
    lea rax, [r15 + rcx + 10]
    cmp rax, rbp
    ja .out
    call .found_clear
    movzx eax, byte [r15]
    mov [rsp + ubt_found.event_type], ax
    mov byte [rsp + ubt_found.kind], UBT_FOUND_LE
    cmp eax, 4                          ; SCAN_RSP
    jne .adv_kind
    mov byte [rsp + ubt_found.kind], UBT_FOUND_LE_RSP
.adv_kind:
    mov al, [r15 + 1]
    mov [rsp + ubt_found.addr_type], al
    mov eax, [r15 + 2]
    mov [rsp + ubt_found.addr], eax
    mov ax, [r15 + 6]
    mov [rsp + ubt_found.addr + 4], ax
    movzx ecx, byte [r15 + 8]
    mov [rsp + ubt_found.data_len], ecx
    lea rax, [r15 + 9]
    mov [rsp + ubt_found.data], rax
    mov al, [r15 + rcx + 9]
    mov [rsp + ubt_found.rssi], al
    call .tell
    movzx ecx, byte [r15 + 8]
    lea r15, [r15 + rcx + 10]
    dec r14d
    jmp .adv_next

.ext_adv:
    ; reports: properties (2), address type, address, primary and secondary
    ; PHY, SID, TX power, RSSI, periodic interval (2), direct address type
    ; and address, data length, data
    cmp r13d, 4
    jb .out
    movzx r14d, byte [r12 + 3]
    lea r15, [r12 + 4]
.ext_next:
    test r14d, r14d
    jz .out
    lea rax, [r15 + 24]
    cmp rax, rbp
    ja .out
    movzx ecx, byte [r15 + 23]
    lea rax, [r15 + rcx + 24]
    cmp rax, rbp
    ja .out
    call .found_clear
    movzx eax, word [r15]
    mov [rsp + ubt_found.event_type], ax
    mov byte [rsp + ubt_found.kind], UBT_FOUND_LE
    test eax, 1 << 3                    ; a scan response
    jz .ext_kind
    mov byte [rsp + ubt_found.kind], UBT_FOUND_LE_RSP
.ext_kind:
    mov al, [r15 + 2]
    mov [rsp + ubt_found.addr_type], al
    mov eax, [r15 + 3]
    mov [rsp + ubt_found.addr], eax
    mov ax, [r15 + 7]
    mov [rsp + ubt_found.addr + 4], ax
    mov al, [r15 + 10]
    mov [rsp + ubt_found.phy], al       ; the secondary PHY (0: none)
    mov al, [r15 + 11]
    mov [rsp + ubt_found.sid], al
    mov al, [r15 + 12]
    mov [rsp + ubt_found.tx_power], al
    mov al, [r15 + 13]
    mov [rsp + ubt_found.rssi], al
    movzx ecx, byte [r15 + 23]
    mov [rsp + ubt_found.data_len], ecx
    lea rax, [r15 + 24]
    mov [rsp + ubt_found.data], rax
    call .tell
    movzx ecx, byte [r15 + 23]
    lea r15, [r15 + rcx + 24]
    dec r14d
    jmp .ext_next

.out:
    add rsp, 56
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; the helpers below run one call deep: the record is at [rsp + 8]
.found_clear:
    xor eax, eax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov [rsp + 24], rax
    mov [rsp + 32], rax
    mov [rsp + 40], rax
    mov byte [rsp + 8 + ubt_found.tx_power], 127
    ret
.found_br:
    ; R15 = a response: its address; no data
    xor eax, eax
    mov [rsp + 8], rax
    mov [rsp + 16], rax
    mov [rsp + 24], rax
    mov [rsp + 32], rax
    mov [rsp + 40], rax
    mov byte [rsp + 8 + ubt_found.kind], UBT_FOUND_BR
    mov byte [rsp + 8 + ubt_found.tx_power], 127
    mov eax, [r15]
    mov [rsp + 8 + ubt_found.addr], eax
    mov ax, [r15 + 4]
    mov [rsp + 8 + ubt_found.addr + 4], ax
    ret
.tell:
    lea rdx, [rsp + 8]
    mov esi, UBT_GAP_FOUND
; .hook — ESI = kind, RDX = record: to gap_fn (from one call deep)
.hook:
    mov rax, [rbx + ubt_adapter.gap_fn]
    test rax, rax
    jz .no_hook
    mov rdi, rbx
    sub rsp, 8
    call rax
    add rsp, 8
.no_hook:
    ret

; ubt_gap_tell — RDI = adapter, ESI = UBT_GAP_*, RDX = record: to gap_fn
global ubt_gap_tell
ubt_gap_tell:
    mov rax, [rdi + ubt_adapter.gap_fn]
    test rax, rax
    jz .out
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

%endif ; LIB_UBT_GAP_GAP_ASM
