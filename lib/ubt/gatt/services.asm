; =============================================================================
; Utkarsha OS — lib/ubt/gatt/services.asm — built-in GATT services
; =============================================================================
;   ubt_gatt_dis(db, maker, model, software) → the service's handle
;                       Device Information: Manufacturer Name, Model Number,
;                       Software Revision (strings ending with 0)
;   ubt_gatt_battery(db, level) → the Battery Level value's handle
;   ubt_gatt_battery_set(db, handle, level)    stored, and notified to every
;                       link served from this database that subscribed
;   ubt_gatt_changed(db, sc_handle, start, end) Service Changed indicated to
;                       every link that subscribed
; =============================================================================

%ifndef LIB_UBT_GATT_SERVICES_ASM
%define LIB_UBT_GATT_SERVICES_ASM

section .text

; svc_strlen — RSI = a string ending with 0 (0: none) → ECX = its length
; (at most 64)
svc_strlen:
    xor ecx, ecx
    test rsi, rsi
    jz .out
.next:
    cmp ecx, 64
    jae .out
    cmp byte [rsi + rcx], 0
    je .out
    inc ecx
    jmp .next
.out:
    ret

; svc_char — RDI = db, ESI = 16-bit UUID, EDX = properties, RCX = value,
; R8D = its length, R9D = its maximum → EAX = the value's handle
svc_char:
    sub rsp, 72                         ; a ubt_gatt_def
    push rdi
    push rcx
    lea rdi, [rsp + 16]
    mov ecx, 56
    push rax
    xor eax, eax
    rep stosb
    pop rax
    pop rcx
    pop rdi
    mov [rsp + ubt_gatt_def.uuid], si
    mov byte [rsp + ubt_gatt_def.uuid_len], 2
    mov [rsp + ubt_gatt_def.props], dl
    mov word [rsp + ubt_gatt_def.perm], ATT_PERM_READ
    mov [rsp + ubt_gatt_def.len], r8w
    mov [rsp + ubt_gatt_def.max], r9w
    mov [rsp + ubt_gatt_def.value], rcx
    mov rsi, rsp
    call ubt_gatt_char
    add rsp, 72
    ret

; -----------------------------------------------------------------------------
; ubt_gatt_dis — RDI = db, RSI = maker, RDX = model, RCX = software (strings
;                ending with 0; 0 leaves one out) → EAX = the service's handle
; -----------------------------------------------------------------------------
global ubt_gatt_dis
ubt_gatt_dis:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 16
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov word [rsp], 0x180A
    mov rdi, rbx
    mov rsi, rsp
    mov edx, 2
    mov ecx, 1
    call ubt_gatt_service
    mov r15d, eax
    mov rsi, r12
    mov edi, 0x2A29                     ; Manufacturer Name String
    call .string
    mov rsi, r13
    mov edi, 0x2A24                     ; Model Number String
    call .string
    mov rsi, r14
    mov edi, 0x2A28                     ; Software Revision String
    call .string
    mov eax, r15d
    add rsp, 16
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; one string characteristic: EDI = UUID, RSI = the string (0: none)
.string:
    test rsi, rsi
    jz .none
    push rdi
    call svc_strlen
    pop rax
    mov r8d, ecx
    mov r9d, ecx
    mov rcx, rsi
    mov esi, eax
    mov edx, GATT_PROP_READ
    mov rdi, rbx
    sub rsp, 8
    call svc_char
    add rsp, 8
.none:
    ret

; -----------------------------------------------------------------------------
; ubt_gatt_battery — RDI = db, ESI = level (0-100) → EAX = Battery Level's
;                    value handle (its CCCD follows it)
; -----------------------------------------------------------------------------
global ubt_gatt_battery
ubt_gatt_battery:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov [rsp + 8], sil
    mov word [rsp], 0x180F
    mov rsi, rsp
    mov edx, 2
    mov ecx, 1
    call ubt_gatt_service
    mov rdi, rbx
    mov esi, 0x2A19
    mov edx, GATT_PROP_READ | GATT_PROP_NOTIFY
    lea rcx, [rsp + 8]
    mov r8d, 1
    mov r9d, 1
    call svc_char
    add rsp, 16
    pop rbx
    ret

; svc_each — RDI = db, RSI = function (conn, R12 = argument), R12 = its
; argument: called for every LE link whose adapter serves this database
svc_each:
    push rbx
    push r13
    push r14
    push r15
    push rbp
    mov r13, rdi
    mov r14, rsi
    xor ebp, ebp
.adapter:
    cmp ebp, [rel ubt_adapter_total]
    jae .out
    lea rax, [rel ubt_adapters]
    mov rbx, [rax + rbp * 8]
    inc ebp
    mov rax, [rbx + ubt_adapter.gatt]
    test rax, rax
    jnz .db
    lea rax, [rel ubt_gatt_default]
.db:
    cmp rax, r13
    jne .adapter
    xor r15d, r15d
.conn:
    cmp r15d, UBT_MAX_CONNS
    jae .adapter
    mov rdi, [rbx + ubt_adapter.conns + r15 * 8]
    inc r15d
    test rdi, rdi
    jz .conn
    cmp byte [rdi + ubt_conn.type], UBT_LINK_LE
    jne .conn
    call r14
    jmp .conn
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_gatt_battery_set — RDI = db, ESI = Battery Level's handle, EDX = level
; → EAX = 0, or -1 (not a stored value)
; -----------------------------------------------------------------------------
global ubt_gatt_battery_set
ubt_gatt_battery_set:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov rbx, rdi
    mov r13d, esi
    mov [rsp], dl
    mov rdx, rsp
    mov ecx, 1
    call ubt_gatt_set
    test eax, eax
    jnz .out
    ; R12 = handle << 8 | level for the notifier
    movzx r12d, byte [rsp]
    mov eax, r13d
    shl eax, 8
    or r12d, eax
    mov rdi, rbx
    lea rsi, [rel .notify]
    call svc_each
    xor eax, eax
.out:
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret
.notify:
    sub rsp, 24
    mov eax, r12d
    mov [rsp], al
    shr eax, 8
    mov esi, eax
    mov rdx, rsp
    mov ecx, 1
    call ubt_gatt_notify
    add rsp, 24
    ret

; -----------------------------------------------------------------------------
; ubt_gatt_changed — RDI = db, ESI = Service Changed's value handle, EDX =
;   the first handle changed, ECX = the last: stored and indicated
; -----------------------------------------------------------------------------
global ubt_gatt_changed
ubt_gatt_changed:
    push rbx
    push r12
    push r13
    sub rsp, 16
    mov rbx, rdi
    mov r13d, esi
    mov [rsp], dx
    mov [rsp + 2], cx
    mov r12d, [rsp]                     ; start, end for the indicator
    mov rdx, rsp
    mov ecx, 4
    call ubt_gatt_set                   ; (no stored value: still indicated)
    shl r13, 32
    or r12, r13
    mov rdi, rbx
    lea rsi, [rel .indicate]
    call svc_each
    add rsp, 16
    pop r13
    pop r12
    pop rbx
    ret
.indicate:
    sub rsp, 24
    mov [rsp], r12d
    mov rsi, r12
    shr rsi, 32
    mov rdx, rsp
    mov ecx, 4
    call ubt_gatt_indicate
    add rsp, 24
    ret

%endif ; LIB_UBT_GATT_SERVICES_ASM
