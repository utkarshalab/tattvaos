; =============================================================================
; Utkarsha OS — lib/ubt/att/server.asm — the ATT bearer and the GATT server
; =============================================================================
;   ubt_att_recv(conn, pdu, len)          ATT on fixed CID 4 (LE)
;   ubt_att_of(conn) → its ATT state (made on first use)
;   ubt_att_free(conn)
;   ubt_gatt_notify(conn, handle, data, len)     → EAX = 0, or negative
;   ubt_gatt_indicate(conn, handle, data, len)   → EAX = 0, or negative
;   ubt_att_tick(adapter, now)            the 30-second transaction timeout
;
; The server answers every request against the database of the link's
; adapter (gatt/db.asm): Exchange MTU; Find Information; Find By Type
; Value; Read By Type; Read, Read Blob, Read Multiple and Read Multiple
; Variable; Read By Group Type; Write, Write Command, Signed Write
; Command (checked with the peer's CSRK and counter); Prepare and Execute
; Write. Permissions are checked against how secure the link is. A
; characteristic's client configuration is each link's own; notifications
; and indications go only where it asks for them, one indication at a
; time until confirmed. Responses go to att/client.asm.
; =============================================================================

%ifndef LIB_UBT_ATT_SERVER_ASM
%define LIB_UBT_ATT_SERVER_ASM

%define ATT_CID             4
%define ATT_DEFAULT_MTU     23
%define ATT_LOCAL_MTU       517         ; what we take
%define ATT_MAX_VALUE       512
%define ATT_TIMEOUT_MS      30000
%define ATT_CCCDS           16          ; client configurations per link
%define ATT_PREP_MAX        32          ; prepared writes queued (a whole
                                        ; 512-byte value at MTU 23)
%define ATT_PREP_BYTES      1024

; opcodes
%define ATT_ERROR_RSP       0x01
%define ATT_MTU_REQ         0x02
%define ATT_MTU_RSP         0x03
%define ATT_FIND_INFO_REQ   0x04
%define ATT_FIND_INFO_RSP   0x05
%define ATT_FIND_TYPE_REQ   0x06
%define ATT_FIND_TYPE_RSP   0x07
%define ATT_READ_TYPE_REQ   0x08
%define ATT_READ_TYPE_RSP   0x09
%define ATT_READ_REQ        0x0A
%define ATT_READ_RSP        0x0B
%define ATT_READ_BLOB_REQ   0x0C
%define ATT_READ_BLOB_RSP   0x0D
%define ATT_READ_MULT_REQ   0x0E
%define ATT_READ_MULT_RSP   0x0F
%define ATT_READ_GROUP_REQ  0x10
%define ATT_READ_GROUP_RSP  0x11
%define ATT_WRITE_REQ       0x12
%define ATT_WRITE_RSP       0x13
%define ATT_PREP_REQ        0x16
%define ATT_PREP_RSP        0x17
%define ATT_EXEC_REQ        0x18
%define ATT_EXEC_RSP        0x19
%define ATT_NOTIFY          0x1B
%define ATT_INDICATE        0x1D
%define ATT_CONFIRM         0x1E
%define ATT_READ_MULTV_REQ  0x20
%define ATT_READ_MULTV_RSP  0x21
%define ATT_WRITE_CMD       0x52
%define ATT_SIGNED_WRITE    0xD2

; errors
%define ATT_E_HANDLE        0x01
%define ATT_E_READ          0x02
%define ATT_E_WRITE         0x03
%define ATT_E_PDU           0x04
%define ATT_E_AUTHEN        0x05
%define ATT_E_NOT_SUPP      0x06
%define ATT_E_OFFSET        0x07
%define ATT_E_PREP_FULL     0x09
%define ATT_E_NOT_FOUND     0x0A
%define ATT_E_NOT_LONG      0x0B
%define ATT_E_LENGTH        0x0D
%define ATT_E_UNLIKELY      0x0E
%define ATT_E_ENCRYPTION    0x0F
%define ATT_E_GROUP         0x10
%define ATT_E_RESOURCES     0x11

struc ubt_att
    .mtu:           resw 1          ; agreed
    .dead:          resb 1          ; a transaction timed out: no more ATT
    .ind_wait:      resb 1          ; an indication of ours not confirmed
    .pad:           resd 1
    .ind_deadline:  resq 1
    .cccd:          resw ATT_CCCDS * 2      ; (handle, value)
    .prep_n:        resd 1
    .prep_used:     resd 1
    .prep:          resw ATT_PREP_MAX * 4   ; (handle, offset, length, at)
    .prep_buf:      resb ATT_PREP_BYTES
    ; the client's transaction (att/client.asm)
    .req:           resb 1          ; the request waiting (0: none)
    .proc:          resb 1          ; the procedure it is part of
    .uuid_len:      resb 1
    .pad2:          resb 1
    .start:         resw 1
    .end:           resw 1
    .handle:        resw 1
    .offset:        resw 1
    .wr_len:        resw 1
    .val_len:       resw 1
    .deadline:      resq 1
    .user:          resq 1
    .uuid:          resb 16
    .val:           resb ATT_MAX_VALUE
    .wr:            resb ATT_MAX_VALUE
endstruc

section .bss
alignb 8
global ubt_sign_counter
ubt_sign_counter:   resd 1          ; ours, for signed writes

section .rodata
global ubt_att_layout
ubt_att_layout:
    dd ubt_att_size, ubt_att.mtu, ubt_att.cccd, ubt_att.ind_wait, ubt_att.req, ubt_att.val
    dd ubt_att.dead, 0

section .text

; -----------------------------------------------------------------------------
; ubt_att_of — RDI = conn → RAX = its ATT state, made with the default MTU
;              on first use (0: no memory)
; -----------------------------------------------------------------------------
global ubt_att_of
ubt_att_of:
    mov rax, [rdi + ubt_conn.att]
    test rax, rax
    jnz .out
    push rdi
    mov edi, ubt_att_size
    mov esi, 8
    call usb_alloc
    pop rdi
    test rax, rax
    jz .out
    mov [rdi + ubt_conn.att], rax
    mov word [rax + ubt_att.mtu], ATT_DEFAULT_MTU
.out:
    ret

; ubt_att_free — RDI = conn: its ATT state given back
global ubt_att_free
ubt_att_free:
    mov rax, rdi
    mov rdi, [rax + ubt_conn.att]
    test rdi, rdi
    jz .out
    mov qword [rax + ubt_conn.att], 0
    mov esi, ubt_att_size
    mov edx, 8
    jmp usb_free
.out:
    ret

; att_send — RBX = conn, RDI = PDU, ESI = length (cut to the MTU)
att_send:
    sub rsp, 8
    mov rdx, rdi
    mov ecx, esi
    mov rax, [rbx + ubt_conn.att]
    movzx eax, word [rax + ubt_att.mtu]
    cmp ecx, eax
    jbe .len
    mov ecx, eax
.len:
    mov rdi, rbx
    mov esi, ATT_CID
    call l2cap_frame
    add rsp, 8
    ret

; att_error — RBX = conn, EDI = the request's opcode, ESI = handle, EDX =
; the error: Error Response
att_error:
    sub rsp, 24
    mov byte [rsp], ATT_ERROR_RSP
    mov [rsp + 1], dil
    mov [rsp + 2], si
    mov [rsp + 4], dl
    mov rdi, rsp
    mov esi, 5
    call att_send
    add rsp, 24
    ret

; att_uuid_is — RDI = attribute, RSI = UUID, EDX = its length (2 or 16)
; → ZF = 1 when the attribute's type is it (a 16-bit one compared in its
; 128-bit form too)
att_uuid_is:
    movzx eax, byte [rdi + ubt_attr.uuid_len]
    cmp eax, edx
    jne .mixed
    cmp edx, 2
    jne .long
    mov ax, [rdi + ubt_attr.uuid]
    cmp ax, [rsi]
    ret
.long:
    movdqu xmm0, [rdi + ubt_attr.uuid]
    movdqu xmm1, [rsi]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    cmp eax, 0xFFFF
    ret
.mixed:
    ; 16 against 128: the base UUID 0000xxxx-0000-1000-8000-00805F9B34FB
    push rbx
    sub rsp, 16
    mov rbx, rsi
    cmp edx, 16
    je .their_long
    ; ours is 128: is it the base with their 16 bits?
    lea rcx, [rdi + ubt_attr.uuid]
    mov ax, [rbx]
    jmp .compare
.their_long:
    mov rcx, rbx
    mov ax, [rdi + ubt_attr.uuid]
.compare:
    mov rdx, 0x800000805F9B34FB         ; FB 34 9B 5F 80 00 00 80 in memory
    mov [rsp], rdx
    mov dword [rsp + 8], 0x00001000
    mov [rsp + 12], ax
    mov word [rsp + 14], 0
    movdqu xmm0, [rsp]
    movdqu xmm1, [rcx]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    add rsp, 16
    pop rbx
    cmp eax, 0xFFFF
    ret

; att_may — RBX = conn, RDI = attribute, ESI = 0 read, 1 write
; → EAX = 0, or the ATT error that refuses it
att_may:
    movzx ecx, word [rdi + ubt_attr.perm]
    test esi, esi
    jnz .write
    mov eax, ATT_E_READ
    test ecx, ATT_PERM_READ
    jz .out
    mov edx, ATT_PERM_READ_ENC
    mov r8d, ATT_PERM_READ_AUTH
    jmp .security
.write:
    mov eax, ATT_E_WRITE
    test ecx, ATT_PERM_WRITE
    jz .out
    mov edx, ATT_PERM_WRITE_ENC
    mov r8d, ATT_PERM_WRITE_AUTH
.security:
    movzx r9d, byte [rbx + ubt_conn.sec]
    test ecx, r8d
    jz .enc
    mov eax, ATT_E_AUTHEN               ; needs an authenticated link
    cmp r9d, 2
    jb .out
.enc:
    test ecx, edx
    jz .ok
    test r9d, r9d
    jnz .ok
    ; not encrypted: with a key it is only a matter of encrypting
    push rcx
    push rdi
    sub rsp, 8
    lea rsi, [rbx + ubt_conn.peer]
    movzx edx, byte [rbx + ubt_conn.peer_type]
    call ubt_key_find
    add rsp, 8
    pop rdi
    pop rcx
    test rax, rax
    mov eax, ATT_E_AUTHEN
    jz .out
    mov eax, ATT_E_ENCRYPTION
    ret
.ok:
    xor eax, eax
.out:
    ret

; att_cccd_slot — RBX = conn, R12 = ATT state, ESI = handle → RAX = its
; (handle, value) slot, or a free one (handle 0), or 0
att_cccd_slot:
    xor ecx, ecx
    xor r8d, r8d
.next:
    cmp ecx, ATT_CCCDS
    jae .free
    lea rax, [r12 + ubt_att.cccd + rcx * 4]
    cmp [rax], si
    je .out
    test r8, r8
    jnz .skip
    cmp word [rax], 0
    jne .skip
    mov r8, rax
.skip:
    inc ecx
    jmp .next
.free:
    mov rax, r8
.out:
    ret

; att_read_value — RBX = conn, R12 = ATT state, RDI = attribute, ESI =
; offset, RDX = out, ECX = room → EAX = bytes, or -(ATT error)
att_read_value:
    push r13
    push r14
    push r15
    mov r13, rdi
    mov r14d, esi
    mov r15, rdx
    test word [r13 + ubt_attr.perm], ATT_PERM_CCCD
    jnz .cccd
    mov rax, [r13 + ubt_attr.read_fn]
    test rax, rax
    jz .stored
    mov r8d, ecx
    mov rcx, rdx
    mov edx, esi
    mov rsi, r13
    mov rdi, rbx
    call rax
    jmp .out
.stored:
    movzx eax, word [r13 + ubt_attr.len]
    cmp r14d, eax
    ja .bad_offset
    sub eax, r14d
    cmp eax, ecx
    jbe .copy
    mov eax, ecx
.copy:
    mov rsi, [r13 + ubt_attr.value]
    add rsi, r14
    mov rdi, r15
    mov ecx, eax
    rep movsb
    jmp .out
.cccd:
    ; this link's configuration (0 when it set none)
    mov eax, -ATT_E_OFFSET
    cmp r14d, 2
    ja .out
    push rcx
    movzx esi, word [r13 + ubt_attr.handle]
    call att_cccd_slot
    pop rcx
    xor edx, edx
    test rax, rax
    jz .cccd_value
    movzx esi, word [r13 + ubt_attr.handle]
    cmp [rax], si
    jne .cccd_value
    movzx edx, word [rax + 2]
.cccd_value:
    sub rsp, 8
    mov [rsp], dx
    mov eax, 2
    sub eax, r14d
    cmp eax, ecx
    jbe .cccd_copy
    mov eax, ecx
.cccd_copy:
    lea rsi, [rsp + r14]
    mov rdi, r15
    mov ecx, eax
    rep movsb
    add rsp, 8
    jmp .out
.bad_offset:
    mov eax, -ATT_E_OFFSET
.out:
    pop r15
    pop r14
    pop r13
    ret

; att_write_value — RBX = conn, R12 = ATT state, RDI = attribute, ESI =
; offset, RDX = data, ECX = length → EAX = 0, or -(ATT error)
att_write_value:
    push r13
    push r14
    sub rsp, 8
    mov r13, rdi
    test word [r13 + ubt_attr.perm], ATT_PERM_CCCD
    jnz .cccd
    mov rax, [r13 + ubt_attr.write_fn]
    test rax, rax
    jz .stored
    mov r8d, ecx
    mov rcx, rdx
    mov edx, esi
    mov rsi, r13
    mov rdi, rbx
    call rax
    jmp .out
.stored:
    mov eax, -ATT_E_WRITE
    cmp qword [r13 + ubt_attr.value], 0
    je .out
    movzx r8d, word [r13 + ubt_attr.max]
    mov eax, -ATT_E_OFFSET
    movzx r9d, word [r13 + ubt_attr.len]
    cmp esi, r9d
    ja .out
    mov eax, -ATT_E_LENGTH
    lea r9d, [rsi + rcx]
    cmp r9d, r8d
    ja .out
    mov [r13 + ubt_attr.len], r9w
    mov rdi, [r13 + ubt_attr.value]
    add rdi, rsi
    mov rsi, rdx
    rep movsb
    xor eax, eax
    jmp .out
.cccd:
    ; two bytes, at offset 0, bits the characteristic allows
    mov eax, -ATT_E_LENGTH
    test esi, esi
    jnz .out
    cmp ecx, 2
    jne .out
    movzx r14d, word [rdx]
    mov eax, -0xFD                      ; CCCD improperly configured
    test r14d, ~3
    jnz .out
    movzx esi, word [r13 + ubt_attr.handle]
    call att_cccd_slot
    mov ecx, -ATT_E_RESOURCES
    test rax, rax
    jz .cccd_full
    movzx esi, word [r13 + ubt_attr.handle]
    mov [rax], si
    mov [rax + 2], r14w
    test r14d, r14d
    jnz .cccd_kept
    mov word [rax], 0                   ; nothing asked: the slot is free
.cccd_kept:
    xor eax, eax
    jmp .out
.cccd_full:
    mov eax, ecx
.out:
    add rsp, 8
    pop r14
    pop r13
    ret

; -----------------------------------------------------------------------------
; ubt_att_recv — RDI = conn, RSI = PDU, EDX = its length
; -----------------------------------------------------------------------------
global ubt_att_recv
ubt_att_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 808                        ; [rsp + 8] the response (517 at most),
                                        ; [+528] scratch, [+552] one value
    mov rbx, rdi
    mov r13, rsi
    mov r14d, edx
    test r14d, r14d
    jz .out
    call ubt_att_of
    test rax, rax
    jz .out
    mov r12, rax
    cmp byte [r12 + ubt_att.dead], 0
    jne .out
    call ubt_gatt_db_of
    mov rbp, rax                        ; the database
    movzx r15d, byte [r13]              ; opcode
    ; responses, notifications, indications: the client's
    cmp r15d, ATT_ERROR_RSP
    je .client
    cmp r15d, ATT_NOTIFY
    je .client
    cmp r15d, ATT_INDICATE
    je .client
    cmp r15d, ATT_CONFIRM
    je .confirm
    test r15d, 1
    jnz .client_rsp
    cmp r15d, ATT_MTU_REQ
    je .mtu
    cmp r15d, ATT_FIND_INFO_REQ
    je .find_info
    cmp r15d, ATT_FIND_TYPE_REQ
    je .find_type
    cmp r15d, ATT_READ_TYPE_REQ
    je .read_type
    cmp r15d, ATT_READ_REQ
    je .read
    cmp r15d, ATT_READ_BLOB_REQ
    je .read_blob
    cmp r15d, ATT_READ_MULT_REQ
    je .read_mult
    cmp r15d, ATT_READ_MULTV_REQ
    je .read_mult
    cmp r15d, ATT_READ_GROUP_REQ
    je .read_group
    cmp r15d, ATT_WRITE_REQ
    je .write
    cmp r15d, ATT_WRITE_CMD
    je .write
    cmp r15d, ATT_SIGNED_WRITE
    je .signed
    cmp r15d, ATT_PREP_REQ
    je .prepare
    cmp r15d, ATT_EXEC_REQ
    je .execute
    ; commands (bit 6) are dropped unknown; requests get Request Not Supported
    test r15d, 0x40
    jnz .out
    xor esi, esi
    mov edx, ATT_E_NOT_SUPP
    jmp .error
.client_rsp:
    cmp r15d, ATT_MTU_RSP
    jb .out
.client:
    mov rdi, rbx
    mov rsi, r13
    mov edx, r14d
    call ubt_att_client_recv
    jmp .out
.confirm:
    mov byte [r12 + ubt_att.ind_wait], 0
    mov qword [r12 + ubt_att.ind_deadline], 0
    jmp .out

.invalid:
    xor esi, esi
    mov edx, ATT_E_PDU
.error:
    mov edi, r15d
    call att_error
    jmp .out

; ---- Exchange MTU: theirs, ours back; the smaller is used (at least 23) ----
.mtu:
    cmp r14d, 3
    jne .invalid
    movzx eax, word [r13 + 1]
    cmp eax, ATT_LOCAL_MTU
    jbe .mtu_min
    mov eax, ATT_LOCAL_MTU
.mtu_min:
    cmp eax, ATT_DEFAULT_MTU
    jae .mtu_set
    mov eax, ATT_DEFAULT_MTU
.mtu_set:
    mov byte [rsp + 8], ATT_MTU_RSP
    mov word [rsp + 9], ATT_LOCAL_MTU
    lea rdi, [rsp + 8]
    mov esi, 3
    push rax
    sub rsp, 8
    call att_send                       ; answered at the old MTU
    add rsp, 8
    pop rax
    mov [r12 + ubt_att.mtu], ax
    jmp .out

; the handle range of a request: R8D = start, R9D = end → CF = 1 (answered
; with Invalid Handle) when it makes no sense
.range:
    movzx r8d, word [r13 + 1]
    movzx r9d, word [r13 + 3]
    test r8d, r8d
    jz .range_bad
    cmp r8d, r9d
    ja .range_bad
    clc
    ret
.range_bad:
    mov edi, r15d
    mov esi, r8d
    mov edx, ATT_E_HANDLE
    sub rsp, 8
    call att_error
    add rsp, 8
    stc
    ret

; ---- Find Information: (handle, UUID) of one format, as many as fit --------
.find_info:
    cmp r14d, 5
    jne .invalid
    call .range
    jc .out
    mov byte [rsp + 8], ATT_FIND_INFO_RSP
    mov dword [rsp + 528], 2            ; length so far ([rsp+528]: scratch)
    xor r10d, r10d                      ; the format (UUID length) chosen
    mov ecx, r8d
.fi_next:
    cmp ecx, r9d
    ja .fi_done
    cmp ecx, [rbp + ubt_gatt_db.count]
    ja .fi_done
    lea eax, [rcx - 1]
    imul eax, eax, ubt_attr_size
    lea rdi, [rbp + ubt_gatt_db.attrs + rax]
    movzx eax, byte [rdi + ubt_attr.uuid_len]
    test r10d, r10d
    jnz .fi_format
    mov r10d, eax
    mov edx, 1
    cmp eax, 2
    je .fi_fmt
    mov edx, 2
.fi_fmt:
    mov [rsp + 9], dl
.fi_format:
    cmp eax, r10d
    jne .fi_done                        ; the other format: another request
    mov edx, [rsp + 528]
    lea r11d, [rdx + rax + 2]
    movzx esi, word [r12 + ubt_att.mtu]
    cmp r11d, esi
    ja .fi_done
    mov [rsp + 8 + rdx], cx
    push rcx
    lea rsi, [rdi + ubt_attr.uuid]
    lea rdi, [rsp + 8 + 8 + rdx + 2]
    mov ecx, eax
    rep movsb
    pop rcx
    mov [rsp + 528], r11d
    inc ecx
    jmp .fi_next
.fi_done:
    test r10d, r10d
    jz .not_found
    lea rdi, [rsp + 8]
    mov esi, [rsp + 528]
    call att_send
    jmp .out
.not_found:
    mov edi, r15d
    movzx esi, word [r13 + 1]
    mov edx, ATT_E_NOT_FOUND
    call att_error
    jmp .out

; ---- Find By Type Value: (found, group end) of attributes of a 16-bit type
;      with that value (services by UUID) ---------------------------------------
.find_type:
    cmp r14d, 7
    jb .invalid
    call .range
    jc .out
    mov byte [rsp + 8], ATT_FIND_TYPE_RSP
    mov dword [rsp + 528], 1
    mov ecx, r8d
.ft_next:
    cmp ecx, r9d
    ja .ft_done
    cmp ecx, [rbp + ubt_gatt_db.count]
    ja .ft_done
    lea eax, [rcx - 1]
    imul eax, eax, ubt_attr_size
    lea rdi, [rbp + ubt_gatt_db.attrs + rax]
    cmp byte [rdi + ubt_attr.uuid_len], 2
    jne .ft_skip
    mov ax, [rdi + ubt_attr.uuid]
    cmp ax, [r13 + 5]
    jne .ft_skip
    ; the value, compared whole
    lea edx, [r14d - 7]
    movzx eax, word [rdi + ubt_attr.len]
    cmp eax, edx
    jne .ft_skip
    cmp qword [rdi + ubt_attr.value], 0
    je .ft_skip
    push rcx
    push rdi
    mov rsi, [rdi + ubt_attr.value]
    lea rdi, [r13 + 7]
    mov ecx, edx
    repe cmpsb
    pop rdi
    pop rcx
    jne .ft_skip
    mov edx, [rsp + 528]
    lea r11d, [rdx + 4]
    movzx eax, word [r12 + ubt_att.mtu]
    cmp r11d, eax
    ja .ft_done
    mov [rsp + 8 + rdx], cx
    push rcx
    call .group_end                     ; ECX = the group's last handle
    mov [rsp + 8 + 8 + rdx + 2], cx
    pop rcx
    mov [rsp + 528], r11d
.ft_skip:
    inc ecx
    jmp .ft_next
.ft_done:
    cmp dword [rsp + 528], 1
    je .not_found
    lea rdi, [rsp + 8]
    mov esi, [rsp + 528]
    call att_send
    jmp .out

; .group_end — ECX = a service declaration's handle (one call deep: RDX and
; R11 kept) → ECX = the handle before the next service, or the last
.group_end:
    push r11
    mov eax, ecx
.ge_next:
    inc eax
    cmp eax, [rbp + ubt_gatt_db.count]
    ja .ge_last
    lea r11d, [rax - 1]
    imul r11d, r11d, ubt_attr_size
    lea r11, [rbp + ubt_gatt_db.attrs + r11]
    cmp byte [r11 + ubt_attr.uuid_len], 2
    jne .ge_next
    cmp word [r11 + ubt_attr.uuid], GATT_PRIMARY
    je .ge_found
    cmp word [r11 + ubt_attr.uuid], GATT_SECONDARY
    je .ge_found
    jmp .ge_next
.ge_found:
    lea ecx, [rax - 1]
    pop r11
    ret
.ge_last:
    mov ecx, [rbp + ubt_gatt_db.count]
    pop r11
    ret

; ---- Read By Type: (handle, value) of a type, all of one length -----------
.read_type:
    cmp r14d, 7
    je .rt_ok
    cmp r14d, 21
    jne .invalid
.rt_ok:
    call .range
    jc .out
    lea edx, [r14d - 5]                 ; the type's length
    mov [rsp + 532], edx
    mov byte [rsp + 8], ATT_READ_TYPE_RSP
    mov dword [rsp + 528], 2
    mov dword [rsp + 536], 0            ; each pair's length (0: not yet)
    mov r10d, r8d
.rt_next:
    cmp r10d, r9d
    ja .rt_done
    cmp r10d, [rbp + ubt_gatt_db.count]
    ja .rt_done
    lea eax, [r10 - 1]
    imul eax, eax, ubt_attr_size
    lea rdi, [rbp + ubt_gatt_db.attrs + rax]
    lea rsi, [r13 + 5]
    mov edx, [rsp + 532]
    push rdi
    push r9
    call att_uuid_is
    pop r9
    pop rdi
    jne .rt_skip
    ; may it be read? the first refused answers the request
    push rdi
    push r9
    xor esi, esi
    call att_may
    pop r9
    pop rdi
    test eax, eax
    jz .rt_read
    cmp dword [rsp + 536], 0
    jne .rt_done                        ; what came before is answered
    mov edi, r15d
    mov esi, r10d
    mov edx, eax
    call att_error
    jmp .out
.rt_read:
    ; the value (as much as fits a pair: MTU - 4, at most 253)
    movzx ecx, word [r12 + ubt_att.mtu]
    sub ecx, 4
    cmp ecx, 253
    jbe .rt_room
    mov ecx, 253
.rt_room:
    push r9
    push r10
    xor esi, esi
    lea rdx, [rsp + 16 + 552]           ; (two pushes) one value
    call att_read_value
    pop r10
    pop r9
    test eax, eax
    jns .rt_got
    cmp dword [rsp + 536], 0
    jne .rt_done
    neg eax
    mov edi, r15d
    mov esi, r10d
    mov edx, eax
    call att_error
    jmp .out
.rt_got:
    lea edx, [rax + 2]                  ; this pair's length
    cmp dword [rsp + 536], 0
    jne .rt_same
    mov [rsp + 536], edx
    mov [rsp + 9], dl
.rt_same:
    cmp edx, [rsp + 536]
    jne .rt_done                        ; another length: another request
    mov ecx, [rsp + 528]
    lea r11d, [rcx + rdx]
    movzx esi, word [r12 + ubt_att.mtu]
    cmp r11d, esi
    ja .rt_done
    mov [rsp + 8 + rcx], r10w
    lea rdi, [rsp + 8 + rcx + 2]
    lea rsi, [rsp + 552]
    mov ecx, eax
    rep movsb
    mov [rsp + 528], r11d
.rt_skip:
    inc r10d
    jmp .rt_next
.rt_done:
    cmp dword [rsp + 536], 0
    je .not_found
    lea rdi, [rsp + 8]
    mov esi, [rsp + 528]
    call att_send
    jmp .out

; ---- Read and Read Blob ----------------------------------------------------
.read:
    cmp r14d, 3
    jne .invalid
    xor eax, eax
    jmp .read_at
.read_blob:
    cmp r14d, 5
    jne .invalid
    movzx eax, word [r13 + 3]
.read_at:
    mov [rsp + 528], eax                ; offset
    mov rdi, rbp
    movzx esi, word [r13 + 1]
    call ubt_gatt_attr
    test rax, rax
    jz .bad_handle
    mov rdi, rax
    push rdi
    sub rsp, 8
    xor esi, esi
    call att_may
    add rsp, 8
    pop rdi
    test eax, eax
    jnz .refused
    movzx ecx, word [r12 + ubt_att.mtu]
    dec ecx
    mov esi, [rsp + 528]
    lea rdx, [rsp + 9]
    call att_read_value
    test eax, eax
    js .read_err
    mov byte [rsp + 8], ATT_READ_RSP
    cmp r15d, ATT_READ_REQ
    je .read_send
    mov byte [rsp + 8], ATT_READ_BLOB_RSP
.read_send:
    lea rdi, [rsp + 8]
    lea esi, [rax + 1]
    call att_send
    jmp .out
.read_err:
    neg eax
.refused:
    mov edi, r15d
    movzx esi, word [r13 + 1]
    mov edx, eax
    call att_error
    jmp .out
.bad_handle:
    mov edi, r15d
    movzx esi, word [r13 + 1]
    mov edx, ATT_E_HANDLE
    call att_error
    jmp .out

; ---- Read Multiple (values one after another) and Read Multiple Variable
;      (each with its length) -------------------------------------------------
.read_mult:
    cmp r14d, 5
    jb .invalid
    test r14d, 1
    jz .invalid
    mov byte [rsp + 8], ATT_READ_MULT_RSP
    cmp r15d, ATT_READ_MULT_REQ
    je .rm_start
    mov byte [rsp + 8], ATT_READ_MULTV_RSP
.rm_start:
    mov dword [rsp + 528], 1            ; length so far
    mov r10d, 1                         ; the next handle's place in the PDU
.rm_next:
    cmp r10d, r14d
    jae .rm_done
    mov rdi, rbp
    movzx esi, word [r13 + r10]
    call ubt_gatt_attr
    test rax, rax
    jz .rm_bad
    mov rdi, rax
    push rdi
    push r10
    xor esi, esi
    call att_may
    pop r10
    pop rdi
    test eax, eax
    jnz .rm_refused
    ; room: what is left of the MTU (variable: less its length field)
    movzx ecx, word [r12 + ubt_att.mtu]
    sub ecx, [rsp + 528]
    mov r11d, 0
    cmp r15d, ATT_READ_MULT_REQ
    je .rm_room
    sub ecx, 2
    mov r11d, 2
.rm_room:
    test ecx, ecx
    jle .rm_done
    push r10
    push r11
    mov edx, [rsp + 16 + 528]
    add edx, r11d
    lea rdx, [rsp + 16 + 8 + rdx]
    xor esi, esi
    call att_read_value
    pop r11
    pop r10
    test eax, eax
    js .rm_err
    mov edx, [rsp + 528]
    test r11d, r11d
    jz .rm_len
    mov [rsp + 8 + rdx], ax
.rm_len:
    add edx, eax
    add edx, r11d
    mov [rsp + 528], edx
    add r10d, 2
    jmp .rm_next
.rm_done:
    lea rdi, [rsp + 8]
    mov esi, [rsp + 528]
    call att_send
    jmp .out
.rm_bad:
    mov eax, ATT_E_HANDLE
    jmp .rm_refused
.rm_err:
    neg eax
.rm_refused:
    mov edi, r15d
    movzx esi, word [r13 + r10]
    mov edx, eax
    call att_error
    jmp .out

; ---- Read By Group Type: (start, end, value) of the services ---------------
.read_group:
    cmp r14d, 7
    je .rg_ok
    cmp r14d, 21
    jne .invalid
.rg_ok:
    call .range
    jc .out
    ; only service declarations make groups
    mov edx, r14d
    sub edx, 5
    mov [rsp + 532], edx
    cmp edx, 2
    jne .rg_unsupported
    movzx eax, word [r13 + 5]
    cmp eax, GATT_PRIMARY
    je .rg_go
    cmp eax, GATT_SECONDARY
    je .rg_go
.rg_unsupported:
    mov edi, r15d
    movzx esi, word [r13 + 1]
    mov edx, ATT_E_GROUP
    call att_error
    jmp .out
.rg_go:
    mov byte [rsp + 8], ATT_READ_GROUP_RSP
    mov dword [rsp + 528], 2
    mov dword [rsp + 536], 0
    mov ecx, r8d
.rg_next:
    cmp ecx, r9d
    ja .rg_done
    cmp ecx, [rbp + ubt_gatt_db.count]
    ja .rg_done
    lea eax, [rcx - 1]
    imul eax, eax, ubt_attr_size
    lea rdi, [rbp + ubt_gatt_db.attrs + rax]
    cmp byte [rdi + ubt_attr.uuid_len], 2
    jne .rg_skip
    mov ax, [rdi + ubt_attr.uuid]
    cmp ax, [r13 + 5]
    jne .rg_skip
    movzx eax, word [rdi + ubt_attr.len]
    lea edx, [rax + 4]                  ; this entry's length
    cmp dword [rsp + 536], 0
    jne .rg_same
    mov [rsp + 536], edx
    mov [rsp + 9], dl
.rg_same:
    cmp edx, [rsp + 536]
    jne .rg_done
    mov r10d, [rsp + 528]
    lea r11d, [r10 + rdx]
    movzx esi, word [r12 + ubt_att.mtu]
    cmp r11d, esi
    ja .rg_done
    mov [rsp + 8 + r10], cx
    push rcx
    push rdx
    call .group_end
    mov [rsp + 16 + 8 + r10 + 2], cx
    pop rdx
    pop rcx
    push rcx
    mov rsi, [rdi + ubt_attr.value]
    lea rdi, [rsp + 8 + 8 + r10 + 4]
    lea ecx, [rdx - 4]
    rep movsb
    pop rcx
    mov [rsp + 528], r11d
    ; the next one after this group
    push rdx
    call .group_end
    pop rdx
.rg_skip:
    inc ecx
    jmp .rg_next
.rg_done:
    cmp dword [rsp + 536], 0
    je .not_found
    lea rdi, [rsp + 8]
    mov esi, [rsp + 528]
    call att_send
    jmp .out

; ---- Write Request and Write Command -----------------------------------------
.write:
    cmp r14d, 3
    jb .write_invalid
    mov rdi, rbp
    movzx esi, word [r13 + 1]
    call ubt_gatt_attr
    test rax, rax
    jz .write_bad_handle
    mov rdi, rax
    push rdi
    sub rsp, 8
    mov esi, 1
    call att_may
    add rsp, 8
    pop rdi
    test eax, eax
    jnz .write_refused
    xor esi, esi
    lea rdx, [r13 + 3]
    lea ecx, [r14d - 3]
    call att_write_value
    test eax, eax
    js .write_err
    cmp r15d, ATT_WRITE_REQ
    jne .out
    mov byte [rsp + 8], ATT_WRITE_RSP
    lea rdi, [rsp + 8]
    mov esi, 1
    call att_send
    jmp .out
.write_err:
    neg eax
.write_refused:
    cmp r15d, ATT_WRITE_REQ
    jne .out                            ; commands are never answered
    mov edi, r15d
    movzx esi, word [r13 + 1]
    mov edx, eax
    call att_error
    jmp .out
.write_bad_handle:
    mov eax, ATT_E_HANDLE
    jmp .write_refused
.write_invalid:
    cmp r15d, ATT_WRITE_REQ
    jne .out
    jmp .invalid

; ---- Signed Write Command: opcode, handle, value, counter, MAC; written
;      only on an unencrypted link, from a bonded peer's CSRK, with a counter
;      that went up ---------------------------------------------------------------
.signed:
    cmp r14d, 3 + 12
    jb .out
    cmp byte [rbx + ubt_conn.sec], 0
    jne .out                            ; encrypted links use plain writes
    lea rsi, [rbx + ubt_conn.peer]
    movzx edx, byte [rbx + ubt_conn.peer_type]
    call ubt_key_find
    test rax, rax
    jz .out
    test byte [rax + ubt_key.flags], KEY_CSRK
    jz .out
    mov [rsp + 528], rax
    ; the counter must be new
    mov ecx, [r13 + r14 - 12]
    cmp ecx, [rax + ubt_key.sign_count]
    jb .out
    lea rdi, [rax + ubt_key.csrk]
    mov rsi, r13
    lea edx, [r14d - 8]                 ; everything up to the MAC
    lea rcx, [rsp + 8]
    call ubt_att_sign
    mov rax, [rsp + 8]
    cmp rax, [r13 + r14 - 8]
    jne .out
    mov rax, [rsp + 528]
    mov ecx, [r13 + r14 - 12]
    inc ecx
    mov [rax + ubt_key.sign_count], ecx
    ; then as a Write Command (checked as a write, never answered)
    mov rdi, rbp
    movzx esi, word [r13 + 1]
    call ubt_gatt_attr
    test rax, rax
    jz .out
    mov rdi, rax
    push rdi
    sub rsp, 8
    mov esi, 1
    call att_may
    add rsp, 8
    pop rdi
    cmp eax, ATT_E_AUTHEN
    je .signed_ok                       ; the signature authenticates it
    cmp eax, ATT_E_ENCRYPTION
    je .signed_ok
    test eax, eax
    jnz .out
.signed_ok:
    xor esi, esi
    lea rdx, [r13 + 3]
    lea ecx, [r14d - 15]
    call att_write_value
    jmp .out

; ---- Prepare Write: queued, echoed --------------------------------------------
.prepare:
    cmp r14d, 5
    jb .invalid
    mov rdi, rbp
    movzx esi, word [r13 + 1]
    call ubt_gatt_attr
    test rax, rax
    jz .bad_handle
    mov rdi, rax
    sub rsp, 8
    mov esi, 1
    call att_may
    add rsp, 8
    test eax, eax
    jnz .refused
    mov eax, [r12 + ubt_att.prep_n]
    cmp eax, ATT_PREP_MAX
    jae .prep_full
    lea ecx, [r14d - 5]                 ; the part's length
    mov edx, [r12 + ubt_att.prep_used]
    lea r8d, [rdx + rcx]
    cmp r8d, ATT_PREP_BYTES
    ja .prep_full
    lea r9, [r12 + ubt_att.prep + rax * 8]
    mov r10w, [r13 + 1]
    mov [r9], r10w
    mov r10w, [r13 + 3]
    mov [r9 + 2], r10w
    mov [r9 + 4], cx
    mov [r9 + 6], dx
    inc dword [r12 + ubt_att.prep_n]
    mov [r12 + ubt_att.prep_used], r8d
    lea rdi, [r12 + ubt_att.prep_buf + rdx]
    lea rsi, [r13 + 5]
    rep movsb
    ; the request echoed
    mov rsi, r13
    lea rdi, [rsp + 8]
    mov ecx, r14d
    rep movsb
    mov byte [rsp + 8], ATT_PREP_RSP
    lea rdi, [rsp + 8]
    mov esi, r14d
    call att_send
    jmp .out
.prep_full:
    mov edi, r15d
    movzx esi, word [r13 + 1]
    mov edx, ATT_E_PREP_FULL
    call att_error
    jmp .out

; ---- Execute Write: the queue written in order (or dropped) -----------------
.execute:
    cmp r14d, 2
    jne .invalid
    cmp byte [r13 + 1], 0
    je .exec_done
    xor r10d, r10d
.exec_next:
    cmp r10d, [r12 + ubt_att.prep_n]
    jae .exec_done
    lea r9, [r12 + ubt_att.prep + r10 * 8]
    mov rdi, rbp
    movzx esi, word [r9]
    push r10
    push r9
    call ubt_gatt_attr
    pop r9
    pop r10
    test rax, rax
    jz .exec_next_one
    mov rdi, rax
    movzx esi, word [r9 + 2]
    movzx ecx, word [r9 + 4]
    movzx edx, word [r9 + 6]
    lea rdx, [r12 + ubt_att.prep_buf + rdx]
    push r10
    push r9
    call att_write_value
    pop r9
    pop r10
    test eax, eax
    jns .exec_next_one
    ; the first failure answers; the rest of the queue goes
    neg eax
    mov dword [r12 + ubt_att.prep_n], 0
    mov dword [r12 + ubt_att.prep_used], 0
    mov edi, r15d
    movzx esi, word [r9]
    mov edx, eax
    call att_error
    jmp .out
.exec_next_one:
    inc r10d
    jmp .exec_next
.exec_done:
    mov dword [r12 + ubt_att.prep_n], 0
    mov dword [r12 + ubt_att.prep_used], 0
    mov byte [rsp + 8], ATT_EXEC_RSP
    lea rdi, [rsp + 8]
    mov esi, 1
    call att_send

.out:
    add rsp, 808
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_att_sign — RDI = CSRK (16, on-air order), RSI = the message (opcode,
;   handle, value, counter: on-air order), EDX = its length, RCX = out (8):
;   the MAC, the 64 most significant bits of AES-CMAC(CSRK, m), m and the
;   key turned to the specification's order and the result back
; -----------------------------------------------------------------------------
global ubt_att_sign
ubt_att_sign:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 600                        ; key, message (up to 528), MAC
    mov r12, rsi
    mov r13d, edx
    mov r14, rcx
    mov rsi, rdi
    mov rdi, rsp
    mov ecx, 16
    call ubt_rev
    lea rdi, [rsp + 16]
    mov rsi, r12
    mov ecx, r13d
    call ubt_rev
    mov rdi, rsp
    lea rsi, [rsp + 16]
    mov edx, r13d
    lea rcx, [rsp + 560]
    call ubt_cmac
    ; on air: the result turned back, its top 8 octets
    lea rdi, [rsp + 576]
    lea rsi, [rsp + 560]
    mov ecx, 16
    call ubt_rev
    mov rax, [rsp + 576 + 8]
    mov [r14], rax
    pxor xmm0, xmm0
    movdqu [rsp], xmm0
    add rsp, 600
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_gatt_notify — RDI = conn, ESI = handle, RDX = value, ECX = length
; ubt_gatt_indicate — the same, confirmed (one at a time)
; Output: EAX = 0 sent, 1 not asked for by the client, negative otherwise
; -----------------------------------------------------------------------------
global ubt_gatt_notify
ubt_gatt_notify:
    mov r8d, ATT_NOTIFY
    jmp att_push
global ubt_gatt_indicate
ubt_gatt_indicate:
    mov r8d, ATT_INDICATE
att_push:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 528
    mov rbx, rdi
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx
    mov [rsp + 520], r8d
    call ubt_att_of
    test rax, rax
    jz .nomem
    mov r12, rax
    mov eax, -UBT_EIO
    cmp byte [r12 + ubt_att.dead], 0
    jne .out
    ; the client's configuration: the CCCD after the value
    lea esi, [r13d + 1]
    call att_cccd_slot
    test rax, rax
    jz .not_asked
    lea ecx, [r13d + 1]
    cmp [rax], cx
    jne .not_asked
    movzx ecx, word [rax + 2]
    mov edx, 1                          ; notifications
    cmp dword [rsp + 520], ATT_NOTIFY
    je .bit
    mov edx, 2                          ; indications
    cmp byte [r12 + ubt_att.ind_wait], 0
    mov eax, -UBT_EBUSY
    jne .out
.bit:
    test ecx, edx
    jz .not_asked
    mov eax, [rsp + 520]
    mov [rsp], al
    mov [rsp + 1], r13w
    movzx ecx, word [r12 + ubt_att.mtu]
    sub ecx, 3
    cmp r15d, ecx
    jbe .len
    mov r15d, ecx                       ; cut to the MTU
.len:
    lea rdi, [rsp + 3]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    mov rdi, rsp
    lea esi, [r15d + 3]
    call att_send
    cmp dword [rsp + 520], ATT_INDICATE
    jne .sent
    mov byte [r12 + ubt_att.ind_wait], 1
    call ubt_now
    test rax, rax
    jz .sent
    add rax, ATT_TIMEOUT_MS
    mov [r12 + ubt_att.ind_deadline], rax
.sent:
    xor eax, eax
    jmp .out
.not_asked:
    mov eax, 1
    jmp .out
.nomem:
    mov eax, -UBT_ENOMEM
.out:
    add rsp, 528
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_att_tick — RDI = adapter, RSI = now: a request or indication not
;   answered in 30 s ends ATT on that link
; -----------------------------------------------------------------------------
global ubt_att_tick
ubt_att_tick:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r13, rdi
    mov r14, rsi
    xor r15d, r15d
.next:
    cmp r15d, UBT_MAX_CONNS
    jae .out
    mov rbx, [r13 + ubt_adapter.conns + r15 * 8]
    inc r15d
    test rbx, rbx
    jz .next
    mov r12, [rbx + ubt_conn.att]
    test r12, r12
    jz .next
    cmp byte [r12 + ubt_att.dead], 0
    jne .next
    mov rax, [r12 + ubt_att.ind_deadline]
    test rax, rax
    jz .request
    cmp r14, rax
    jae .dead
.request:
    mov rax, [r12 + ubt_att.deadline]
    test rax, rax
    jz .next
    cmp r14, rax
    jb .next
.dead:
    mov byte [r12 + ubt_att.dead], 1
    mov qword [r12 + ubt_att.deadline], 0
    mov qword [r12 + ubt_att.ind_deadline], 0
    call ubt_att_client_timeout
    jmp .next
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_UBT_ATT_SERVER_ASM
