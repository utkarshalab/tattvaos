; =============================================================================
; Utkarsha OS — lib/ubt/att/client.asm — the GATT client
; =============================================================================
;   ubt_gatt_mtu(conn)                       Exchange MTU
;   ubt_gatt_services(conn, uuid, uuid_len)  primary services: all (length
;                                            0) or those with this UUID
;   ubt_gatt_chars(conn, start, end)         characteristics in a range
;   ubt_gatt_descs(conn, start, end)         descriptors in a range
;   ubt_gatt_read(conn, handle)              a value, long ones read whole
;   ubt_gatt_read_multiple(conn, handles, n) several values in one
;   ubt_gatt_write(conn, handle, data, len)  acknowledged; long ones with
;                                            prepared writes
;   ubt_gatt_write_cmd(conn, handle, data, len)     not acknowledged
;   ubt_gatt_write_signed(conn, handle, data, len)  signed with our CSRK
;   ubt_gatt_subscribe(conn, cccd, bits)     1 notifications, 2 indications
; Each returns EAX = 0 (going), -UBT_EBUSY (one procedure at a time),
; -UBT_EIO (ATT timed out on the link), -UBT_ENOMEM.
;
; What comes back goes to ubt_gatt_fn(conn, ESI = GATT_EV_*, RDX =
; ubt_gatt_ev): services, characteristics, descriptors, values, then
; GATT_EV_DONE with the status (0, an ATT error, or GATT_TIMEOUT).
; Notifications and indications from the server go there too; indications
; are confirmed.
; =============================================================================

%ifndef LIB_UBT_ATT_CLIENT_ASM
%define LIB_UBT_ATT_CLIENT_ASM

%define GATT_EV_SERVICE     1
%define GATT_EV_CHAR        2
%define GATT_EV_DESC        3
%define GATT_EV_VALUE       4
%define GATT_EV_NOTIFY      5
%define GATT_EV_INDICATE    6
%define GATT_EV_DONE        7

%define GATT_TIMEOUT        0x100

; procedures
%define PROC_MTU            1
%define PROC_SERVICES       2
%define PROC_SERVICE_UUID   3
%define PROC_CHARS          4
%define PROC_DESCS          5
%define PROC_READ           6
%define PROC_READ_MULT      7
%define PROC_WRITE          8
%define PROC_WRITE_LONG     9

struc ubt_gatt_ev
    .handle:        resw 1          ; a service's start, a declaration's or
                                    ; descriptor's handle, a value's handle
    .end:           resw 1          ; a service's end
    .value_handle:  resw 1          ; a characteristic's value
    .props:         resb 1
    .uuid_len:      resb 1
    .uuid:          resb 16         ; least significant first
    .status:        resd 1          ; GATT_EV_DONE: 0, the ATT error, timeout
    .proc:          resd 1          ; ... which procedure ended
    .len:           resd 1          ; a value's length; DONE after MTU: it
    .pad:           resd 1
    .data:          resq 1
endstruc

section .bss
alignb 8
global ubt_gatt_fn
ubt_gatt_fn:        resq 1          ; (conn, ESI = GATT_EV_*, RDX = ubt_gatt_ev)

section .rodata
global ubt_gatt_ev_layout
ubt_gatt_ev_layout:
    dd ubt_gatt_ev_size, ubt_gatt_ev.status, ubt_gatt_ev.data, 0

section .text

; ---- helpers: RBX = conn, R12 = its ATT state --------------------------------

; gc_begin — RDI = conn → RBX, R12 set; CF = 1 with EAX = the error when a
; procedure cannot start
gc_begin:
    mov rbx, rdi
    sub rsp, 8
    call ubt_att_of
    add rsp, 8
    mov r12, rax
    mov eax, -UBT_ENOMEM
    test r12, r12
    jz .no
    mov eax, -UBT_EIO
    cmp byte [r12 + ubt_att.dead], 0
    jne .no
    mov eax, -UBT_EBUSY
    cmp byte [r12 + ubt_att.req], 0
    jne .no
    cmp byte [r12 + ubt_att.proc], 0
    jne .no
    clc
    ret
.no:
    stc
    ret

; gc_request — RDI = PDU, ESI = length: sent as the transaction waited for
gc_request:
    push r13
    mov r13, rdi
    mov al, [r13]
    mov [r12 + ubt_att.req], al
    call att_send
    call ubt_now
    test rax, rax
    jz .none
    add rax, ATT_TIMEOUT_MS
.none:
    mov [r12 + ubt_att.deadline], rax
    pop r13
    ret

; gc_tell — ESI = event, RDX = ubt_gatt_ev: to ubt_gatt_fn
gc_tell:
    mov rax, [rel ubt_gatt_fn]
    test rax, rax
    jz .out
    mov rdi, rbx
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; gc_done — EDI = status: the procedure over, the user told
gc_done:
    sub rsp, 56
    xor eax, eax
%assign o 0
%rep 6
    mov [rsp + o], rax
%assign o o + 8
%endrep
    mov [rsp + ubt_gatt_ev.status], edi
    movzx eax, byte [r12 + ubt_att.proc]
    mov [rsp + ubt_gatt_ev.proc], eax
    cmp eax, PROC_MTU
    jne .clear
    movzx eax, word [r12 + ubt_att.mtu]
    mov [rsp + ubt_gatt_ev.len], eax
.clear:
    mov byte [r12 + ubt_att.req], 0
    mov byte [r12 + ubt_att.proc], 0
    mov qword [r12 + ubt_att.deadline], 0
    mov esi, GATT_EV_DONE
    mov rdx, rsp
    call gc_tell
    add rsp, 56
    ret

; gc_range_req — EDI = opcode, ESI = type (16-bit, 0: none): start..end of
; the procedure's range, then the type (or the UUID being sought)
gc_range_req:
    sub rsp, 40
    mov [rsp], dil
    mov ax, [r12 + ubt_att.start]
    mov [rsp + 1], ax
    mov ax, [r12 + ubt_att.end]
    mov [rsp + 3], ax
    mov ecx, 5
    test esi, esi
    jz .send
    mov [rsp + 5], si
    mov ecx, 7
    cmp byte [r12 + ubt_att.proc], PROC_SERVICE_UUID
    jne .send
    ; Find By Type Value: the UUID sought is the value
    movzx edx, byte [r12 + ubt_att.uuid_len]
    movdqu xmm0, [r12 + ubt_att.uuid]
    movdqu [rsp + 7], xmm0
    add ecx, edx
.send:
    mov rdi, rsp
    mov esi, ecx
    call gc_request
    add rsp, 40
    ret

; gc_next — the next range request of a discovery, or done when the range
; is used up. RAX = the last handle the response covered.
gc_next:
    movzx ecx, word [r12 + ubt_att.start]
    cmp eax, ecx
    jb .backwards                       ; a server going round in circles
    cmp eax, 0xFFFF
    jae .done
    movzx ecx, word [r12 + ubt_att.end]
    cmp eax, ecx
    jae .done
    inc eax
    mov [r12 + ubt_att.start], ax
    movzx eax, byte [r12 + ubt_att.proc]
    cmp eax, PROC_SERVICES
    je .services
    cmp eax, PROC_SERVICE_UUID
    je .by_uuid
    cmp eax, PROC_CHARS
    je .chars
    mov edi, ATT_FIND_INFO_REQ
    xor esi, esi
    jmp gc_range_req
.services:
    mov edi, ATT_READ_GROUP_REQ
    mov esi, GATT_PRIMARY
    jmp gc_range_req
.by_uuid:
    mov edi, ATT_FIND_TYPE_REQ
    mov esi, GATT_PRIMARY
    jmp gc_range_req
.chars:
    mov edi, ATT_READ_TYPE_REQ
    mov esi, GATT_CHARACTERISTIC
    jmp gc_range_req
.done:
    xor edi, edi
    jmp gc_done
.backwards:
    mov edi, ATT_E_PDU
    jmp gc_done

; -----------------------------------------------------------------------------
; the procedures
; -----------------------------------------------------------------------------
%macro GC_ENTER 0
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32
%endmacro
%macro GC_LEAVE 0
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
%endmacro

global ubt_gatt_mtu
ubt_gatt_mtu:
    GC_ENTER
    call gc_begin
    jc .out
    mov byte [r12 + ubt_att.proc], PROC_MTU
    mov byte [rsp], ATT_MTU_REQ
    mov word [rsp + 1], ATT_LOCAL_MTU
    mov rdi, rsp
    mov esi, 3
    call gc_request
    xor eax, eax
.out:
    GC_LEAVE

; ubt_gatt_services — RDI = conn, RSI = UUID (least significant first), EDX
; = its length (0: every primary service)
global ubt_gatt_services
ubt_gatt_services:
    GC_ENTER
    mov r13, rsi
    mov r14d, edx
    call gc_begin
    jc .out
    mov word [r12 + ubt_att.start], 1
    mov word [r12 + ubt_att.end], 0xFFFF
    mov byte [r12 + ubt_att.proc], PROC_SERVICES
    mov edi, ATT_READ_GROUP_REQ
    test r14d, r14d
    jz .ask
    mov byte [r12 + ubt_att.proc], PROC_SERVICE_UUID
    mov [r12 + ubt_att.uuid_len], r14b
    movdqu xmm0, [r13]
    movdqu [r12 + ubt_att.uuid], xmm0
    mov edi, ATT_FIND_TYPE_REQ
.ask:
    mov esi, GATT_PRIMARY
    call gc_range_req
    xor eax, eax
.out:
    GC_LEAVE

; ubt_gatt_chars / ubt_gatt_descs — RDI = conn, ESI = start, EDX = end
global ubt_gatt_chars
ubt_gatt_chars:
    mov r8d, PROC_CHARS
    jmp gc_ranged
global ubt_gatt_descs
ubt_gatt_descs:
    mov r8d, PROC_DESCS
gc_ranged:
    GC_ENTER
    mov r13d, esi
    mov r14d, edx
    mov r15d, r8d
    call gc_begin
    jc .out
    mov [r12 + ubt_att.start], r13w
    mov [r12 + ubt_att.end], r14w
    mov [r12 + ubt_att.proc], r15b
    mov edi, ATT_READ_TYPE_REQ
    mov esi, GATT_CHARACTERISTIC
    cmp r15d, PROC_CHARS
    je .ask
    mov edi, ATT_FIND_INFO_REQ
    xor esi, esi
.ask:
    call gc_range_req
    xor eax, eax
.out:
    GC_LEAVE

; ubt_gatt_read — RDI = conn, ESI = handle
global ubt_gatt_read
ubt_gatt_read:
    GC_ENTER
    mov r13d, esi
    call gc_begin
    jc .out
    mov byte [r12 + ubt_att.proc], PROC_READ
    mov [r12 + ubt_att.handle], r13w
    mov word [r12 + ubt_att.val_len], 0
    mov byte [rsp], ATT_READ_REQ
    mov [rsp + 1], r13w
    mov rdi, rsp
    mov esi, 3
    call gc_request
    xor eax, eax
.out:
    GC_LEAVE

; ubt_gatt_read_multiple — RDI = conn, RSI = handles (16-bit), EDX = count
; (2 or more): one VALUE with them one after another
global ubt_gatt_read_multiple
ubt_gatt_read_multiple:
    GC_ENTER
    mov r13, rsi
    mov r14d, edx
    call gc_begin
    jc .out
    mov eax, -UBT_EIO
    cmp r14d, 2
    jb .out
    lea ecx, [r14d * 2 + 1]
    movzx edx, word [r12 + ubt_att.mtu]
    cmp ecx, edx
    ja .out
    mov byte [r12 + ubt_att.proc], PROC_READ_MULT
    mov byte [r12 + ubt_att.wr], ATT_READ_MULT_REQ
    lea rdi, [r12 + ubt_att.wr + 1]
    mov rsi, r13
    lea ecx, [r14d * 2]
    rep movsb
    lea rdi, [r12 + ubt_att.wr]
    lea esi, [r14d * 2 + 1]
    call gc_request
    xor eax, eax
.out:
    GC_LEAVE

; ubt_gatt_write — RDI = conn, ESI = handle, RDX = data, ECX = length (512 at
; most): a Write Request when it fits, else prepared writes and Execute
global ubt_gatt_write
ubt_gatt_write:
    GC_ENTER
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx
    call gc_begin
    jc .out
    mov eax, -UBT_EIO
    cmp r15d, ATT_MAX_VALUE
    ja .out
    mov [r12 + ubt_att.handle], r13w
    mov [r12 + ubt_att.wr_len], r15w
    mov word [r12 + ubt_att.offset], 0
    lea rdi, [r12 + ubt_att.wr]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    movzx eax, word [r12 + ubt_att.mtu]
    sub eax, 3
    cmp r15d, eax
    ja .long
    mov byte [r12 + ubt_att.proc], PROC_WRITE
    mov edi, ATT_WRITE_REQ
    call gc_write_pdu
    xor eax, eax
    jmp .out
.long:
    mov byte [r12 + ubt_att.proc], PROC_WRITE_LONG
    call gc_prepare_next
    xor eax, eax
.out:
    GC_LEAVE

; gc_write_pdu — EDI = opcode: opcode, handle, the whole wr buffer (a
; request is waited for, a command is not)
gc_write_pdu:
    push r13
    sub rsp, 528
    mov r13d, edi
    mov [rsp], dil
    mov ax, [r12 + ubt_att.handle]
    mov [rsp + 1], ax
    lea rdi, [rsp + 3]
    lea rsi, [r12 + ubt_att.wr]
    movzx ecx, word [r12 + ubt_att.wr_len]
    rep movsb
    mov rdi, rsp
    movzx esi, word [r12 + ubt_att.wr_len]
    add esi, 3
    cmp r13d, ATT_WRITE_REQ
    jne .command
    call gc_request
    jmp .out
.command:
    call att_send
.out:
    add rsp, 528
    pop r13
    ret

; gc_prepare_next — the next part of a long write, or Execute when all are
; queued
gc_prepare_next:
    sub rsp, 536
    movzx eax, word [r12 + ubt_att.offset]
    movzx ecx, word [r12 + ubt_att.wr_len]
    cmp eax, ecx
    jae .execute
    sub ecx, eax                        ; left
    movzx edx, word [r12 + ubt_att.mtu]
    sub edx, 5
    cmp ecx, edx
    jbe .part
    mov ecx, edx
.part:
    mov byte [rsp], ATT_PREP_REQ
    mov dx, [r12 + ubt_att.handle]
    mov [rsp + 1], dx
    mov [rsp + 3], ax
    mov [rsp + 528], ecx                ; this part's length
    lea rsi, [r12 + ubt_att.wr + rax]
    lea rdi, [rsp + 5]
    rep movsb
    mov rdi, rsp
    mov esi, [rsp + 528]
    add esi, 5
    call gc_request
    jmp .out
.execute:
    mov byte [rsp], ATT_EXEC_REQ
    mov byte [rsp + 1], 1
    mov rdi, rsp
    mov esi, 2
    call gc_request
.out:
    add rsp, 536
    ret

; ubt_gatt_write_cmd — RDI = conn, ESI = handle, RDX = data, ECX = length:
; Write Command (cut to the MTU), nothing waited for
global ubt_gatt_write_cmd
ubt_gatt_write_cmd:
    mov r8d, ATT_WRITE_CMD
    jmp gc_command
; ubt_gatt_write_signed — the same signed with our CSRK and the next counter
global ubt_gatt_write_signed
ubt_gatt_write_signed:
    mov r8d, ATT_SIGNED_WRITE
gc_command:
    GC_ENTER
    sub rsp, 544
    mov r13d, esi
    mov r14, rdx
    mov r15d, ecx
    mov [rsp + 536], r8d
    mov rbx, rdi
    call ubt_att_of
    mov r12, rax
    mov eax, -UBT_ENOMEM
    test r12, r12
    jz .out
    mov eax, -UBT_EIO
    cmp byte [r12 + ubt_att.dead], 0
    jne .out
    ; room: MTU less opcode and handle (and a signature's 12)
    movzx ecx, word [r12 + ubt_att.mtu]
    sub ecx, 3
    cmp dword [rsp + 536], ATT_SIGNED_WRITE
    jne .room
    sub ecx, 12
.room:
    cmp r15d, ecx
    jbe .fits
    mov r15d, ecx
.fits:
    mov eax, [rsp + 536]
    mov [rsp], al
    mov [rsp + 1], r13w
    lea rdi, [rsp + 3]
    mov rsi, r14
    mov ecx, r15d
    rep movsb
    lea esi, [r15d + 3]
    cmp dword [rsp + 536], ATT_SIGNED_WRITE
    jne .send
    ; counter, then the MAC over everything before it
    call ubt_local_keys_make
    mov eax, [rel ubt_sign_counter]
    inc dword [rel ubt_sign_counter]
    mov [rsp + r15 + 3], eax
    lea rdi, [rel ubt_local_csrk]
    mov rsi, rsp
    lea edx, [r15d + 7]
    lea rcx, [rsp + r15 + 7]
    call ubt_att_sign
    lea esi, [r15d + 15]
.send:
    mov rdi, rsp
    call att_send
    xor eax, eax
.out:
    add rsp, 544
    GC_LEAVE

; ubt_gatt_subscribe — RDI = conn, ESI = the CCCD's handle, EDX = 1
; notifications, 2 indications, 0 neither: a Write Request of it
global ubt_gatt_subscribe
ubt_gatt_subscribe:
    sub rsp, 8
    mov [rsp], dx
    mov rdx, rsp
    mov ecx, 2
    call ubt_gatt_write
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_att_client_recv — RDI = conn, RSI = a response, notification or
;   indication, EDX = its length (from ubt_att_recv)
; -----------------------------------------------------------------------------
global ubt_att_client_recv
ubt_att_client_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 72                         ; [rsp] a ubt_gatt_ev, [+48] scratch
    mov rbx, rdi
    mov r13, rsi
    mov r14d, edx
    mov r12, [rbx + ubt_conn.att]
    call .clear
    movzx r15d, byte [r13]
    cmp r15d, ATT_NOTIFY
    je .push
    cmp r15d, ATT_INDICATE
    je .push
    ; a response: to the request waiting, if any
    movzx eax, byte [r12 + ubt_att.req]
    test eax, eax
    jz .out
    cmp r15d, ATT_ERROR_RSP
    je .error
    inc eax
    cmp r15d, eax
    jne .out                            ; not what was asked
    mov byte [r12 + ubt_att.req], 0
    mov qword [r12 + ubt_att.deadline], 0
    cmp r15d, ATT_MTU_RSP
    je .mtu
    cmp r15d, ATT_READ_GROUP_RSP
    je .services
    cmp r15d, ATT_FIND_TYPE_RSP
    je .by_uuid
    cmp r15d, ATT_READ_TYPE_RSP
    je .chars
    cmp r15d, ATT_FIND_INFO_RSP
    je .descs
    cmp r15d, ATT_READ_RSP
    je .value
    cmp r15d, ATT_READ_BLOB_RSP
    je .value
    cmp r15d, ATT_READ_MULT_RSP
    je .multiple
    cmp r15d, ATT_WRITE_RSP
    je .written
    cmp r15d, ATT_PREP_RSP
    je .prepared
    cmp r15d, ATT_EXEC_RSP
    je .written
    jmp .out

.push:
    ; a notification or indication: handle, value
    cmp r14d, 3
    jb .out
    mov ax, [r13 + 1]
    mov [rsp + ubt_gatt_ev.handle], ax
    lea rax, [r13 + 3]
    mov [rsp + ubt_gatt_ev.data], rax
    lea eax, [r14d - 3]
    mov [rsp + ubt_gatt_ev.len], eax
    mov esi, GATT_EV_NOTIFY
    cmp r15d, ATT_NOTIFY
    je .push_tell
    mov esi, GATT_EV_INDICATE
.push_tell:
    mov rdx, rsp
    call gc_tell
    cmp r15d, ATT_INDICATE
    jne .out
    mov byte [rsp + 48], ATT_CONFIRM
    lea rdi, [rsp + 48]
    mov esi, 1
    call att_send
    jmp .out

.error:
    ; opcode asked, handle, error: discovery ends on "not found", a long read
    ; on "not long"
    cmp r14d, 5
    jb .out
    mov al, [r13 + 1]
    cmp al, [r12 + ubt_att.req]
    jne .out
    movzx edi, byte [r13 + 4]
    movzx eax, byte [r12 + ubt_att.proc]
    cmp eax, PROC_READ
    je .error_read
    cmp eax, PROC_DESCS
    ja .error_done
    cmp edi, ATT_E_NOT_FOUND
    jne .error_done
    xor edi, edi
.error_done:
    call gc_done
    jmp .out
.error_read:
    cmp edi, ATT_E_NOT_LONG
    jne .error_done
    cmp word [r12 + ubt_att.val_len], 0
    je .error_done
    jmp .value_tell

.mtu:
    cmp r14d, 3
    jb .bad
    movzx eax, word [r13 + 1]
    cmp eax, ATT_LOCAL_MTU
    jbe .mtu_min
    mov eax, ATT_LOCAL_MTU
.mtu_min:
    cmp eax, ATT_DEFAULT_MTU
    jae .mtu_set
    mov eax, ATT_DEFAULT_MTU
.mtu_set:
    mov [r12 + ubt_att.mtu], ax
    xor edi, edi
    call gc_done
    jmp .out

.services:
    ; length, then (start, end, UUID) of that length
    cmp r14d, 2
    jb .bad
    movzx ebp, byte [r13 + 1]
    cmp ebp, 6
    je .svc_ok
    cmp ebp, 20
    jne .bad
.svc_ok:
    lea r15, [r13 + 2]
    mov dword [rsp + 48], 0xFFFF
.svc_next:
    lea rcx, [r15 + rbp]
    lea rdx, [r13 + r14]
    cmp rcx, rdx
    ja .svc_more
    call .clear
    mov ax, [r15]
    mov [rsp + ubt_gatt_ev.handle], ax
    mov ax, [r15 + 2]
    mov [rsp + ubt_gatt_ev.end], ax
    lea ecx, [rbp - 4]
    mov [rsp + ubt_gatt_ev.uuid_len], cl
    lea rsi, [r15 + 4]
    lea rdi, [rsp + ubt_gatt_ev.uuid]
    rep movsb
    mov esi, GATT_EV_SERVICE
    mov rdx, rsp
    call gc_tell
    movzx eax, word [r15 + 2]
    add r15, rbp
    mov [rsp + 48], eax
    jmp .svc_next
.svc_more:
    mov eax, [rsp + 48]
    call gc_next
    jmp .out

.by_uuid:
    ; (found, end) pairs: services with the UUID sought
    lea r15, [r13 + 1]
    mov dword [rsp + 48], 0xFFFF
.uuid_next:
    lea rcx, [r15 + 4]
    lea rdx, [r13 + r14]
    cmp rcx, rdx
    ja .uuid_more
    call .clear
    mov ax, [r15]
    mov [rsp + ubt_gatt_ev.handle], ax
    mov ax, [r15 + 2]
    mov [rsp + ubt_gatt_ev.end], ax
    mov al, [r12 + ubt_att.uuid_len]
    mov [rsp + ubt_gatt_ev.uuid_len], al
    movdqu xmm0, [r12 + ubt_att.uuid]
    movdqu [rsp + ubt_gatt_ev.uuid], xmm0
    mov esi, GATT_EV_SERVICE
    mov rdx, rsp
    call gc_tell
    movzx eax, word [r15 + 2]
    mov [rsp + 48], eax
    add r15, 4
    jmp .uuid_next
.uuid_more:
    mov eax, [rsp + 48]
    call gc_next
    jmp .out

.chars:
    ; length, then (handle, properties, value handle, UUID)
    cmp r14d, 2
    jb .bad
    movzx ebp, byte [r13 + 1]
    cmp ebp, 7
    je .chr_ok
    cmp ebp, 21
    jne .bad
.chr_ok:
    lea r15, [r13 + 2]
    mov dword [rsp + 48], 0xFFFF
.chr_next:
    lea rcx, [r15 + rbp]
    lea rdx, [r13 + r14]
    cmp rcx, rdx
    ja .chr_more
    call .clear
    mov ax, [r15]
    mov [rsp + ubt_gatt_ev.handle], ax
    mov al, [r15 + 2]
    mov [rsp + ubt_gatt_ev.props], al
    mov ax, [r15 + 3]
    mov [rsp + ubt_gatt_ev.value_handle], ax
    lea ecx, [rbp - 5]
    mov [rsp + ubt_gatt_ev.uuid_len], cl
    lea rsi, [r15 + 5]
    lea rdi, [rsp + ubt_gatt_ev.uuid]
    rep movsb
    mov esi, GATT_EV_CHAR
    mov rdx, rsp
    call gc_tell
    movzx eax, word [r15]
    mov [rsp + 48], eax
    add r15, rbp
    jmp .chr_next
.chr_more:
    mov eax, [rsp + 48]
    call gc_next
    jmp .out

.descs:
    ; format (1: 16-bit UUIDs, 2: 128-bit), then (handle, UUID)
    cmp r14d, 2
    jb .bad
    mov ebp, 4
    cmp byte [r13 + 1], 1
    je .dsc_ok
    mov ebp, 18
    cmp byte [r13 + 1], 2
    jne .bad
.dsc_ok:
    lea r15, [r13 + 2]
    mov dword [rsp + 48], 0xFFFF
.dsc_next:
    lea rcx, [r15 + rbp]
    lea rdx, [r13 + r14]
    cmp rcx, rdx
    ja .dsc_more
    call .clear
    mov ax, [r15]
    mov [rsp + ubt_gatt_ev.handle], ax
    lea ecx, [rbp - 2]
    mov [rsp + ubt_gatt_ev.uuid_len], cl
    lea rsi, [r15 + 2]
    lea rdi, [rsp + ubt_gatt_ev.uuid]
    rep movsb
    mov esi, GATT_EV_DESC
    mov rdx, rsp
    call gc_tell
    movzx eax, word [r15]
    mov [rsp + 48], eax
    add r15, rbp
    jmp .dsc_next
.dsc_more:
    mov eax, [rsp + 48]
    call gc_next
    jmp .out

.value:
    ; a part of the value: kept; a full response means there may be more
    lea ecx, [r14d - 1]
    movzx eax, word [r12 + ubt_att.val_len]
    lea edx, [rax + rcx]
    cmp edx, ATT_MAX_VALUE
    jbe .val_room
    mov ecx, ATT_MAX_VALUE
    sub ecx, eax
    mov edx, ATT_MAX_VALUE
.val_room:
    lea rdi, [r12 + ubt_att.val + rax]
    lea rsi, [r13 + 1]
    mov [r12 + ubt_att.val_len], dx
    push rcx
    rep movsb
    pop rcx
    movzx eax, word [r12 + ubt_att.mtu]
    dec eax
    cmp ecx, eax
    jb .value_tell                      ; short: the end
    cmp edx, ATT_MAX_VALUE
    jae .value_tell
    ; Read Blob from where it stopped
    mov byte [rsp + 48], ATT_READ_BLOB_REQ
    mov ax, [r12 + ubt_att.handle]
    mov [rsp + 49], ax
    mov [rsp + 51], dx
    lea rdi, [rsp + 48]
    mov esi, 5
    call gc_request
    jmp .out
.value_tell:
    call .clear
    mov ax, [r12 + ubt_att.handle]
    mov [rsp + ubt_gatt_ev.handle], ax
    lea rax, [r12 + ubt_att.val]
    mov [rsp + ubt_gatt_ev.data], rax
    movzx eax, word [r12 + ubt_att.val_len]
    mov [rsp + ubt_gatt_ev.len], eax
    mov esi, GATT_EV_VALUE
    mov rdx, rsp
    call gc_tell
    xor edi, edi
    call gc_done
    jmp .out

.multiple:
    lea rax, [r13 + 1]
    mov [rsp + ubt_gatt_ev.data], rax
    lea eax, [r14d - 1]
    mov [rsp + ubt_gatt_ev.len], eax
    mov esi, GATT_EV_VALUE
    mov rdx, rsp
    call gc_tell
    xor edi, edi
    call gc_done
    jmp .out

.written:
    xor edi, edi
    call gc_done
    jmp .out

.prepared:
    ; the echo must be what we sent; then the next part
    cmp r14d, 5
    jb .bad
    mov ax, [r13 + 1]
    cmp ax, [r12 + ubt_att.handle]
    jne .prep_bad
    movzx eax, word [r13 + 3]
    cmp ax, [r12 + ubt_att.offset]
    jne .prep_bad
    lea ecx, [r14d - 5]
    lea rsi, [r13 + 5]
    lea rdi, [r12 + ubt_att.wr + rax]
    repe cmpsb
    jne .prep_bad
    lea ecx, [r14d - 5]
    add [r12 + ubt_att.offset], cx
    call gc_prepare_next
    jmp .out
.prep_bad:
    ; the server got something else: the queue dropped, the write failed
    mov byte [rsp + 48], ATT_EXEC_REQ
    mov byte [rsp + 49], 0
    lea rdi, [rsp + 48]
    mov esi, 2
    call att_send
    mov edi, ATT_E_UNLIKELY
    call gc_done
    jmp .out

.bad:
    mov edi, ATT_E_PDU
    call gc_done
.out:
    add rsp, 72
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; the event record cleared (one call deep: it is at [rsp + 8])
.clear:
    xor eax, eax
%assign o 8
%rep 6
    mov [rsp + o], rax
%assign o o + 8
%endrep
    ret

; ubt_att_client_timeout — RBX = conn, R12 = ATT state: a waiting
; procedure ends with the timeout
global ubt_att_client_timeout
ubt_att_client_timeout:
    cmp byte [r12 + ubt_att.proc], 0
    je .out
    sub rsp, 8
    mov edi, GATT_TIMEOUT
    call gc_done
    add rsp, 8
.out:
    ret

%endif ; LIB_UBT_ATT_CLIENT_ASM
