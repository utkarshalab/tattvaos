; =============================================================================
; Utkarsha OS — lib/ubt/sdp/sdp.asm — the Service Discovery Protocol
; =============================================================================
;   ubt_sdp_init()                        the server on PSM 1, no records
;   ubt_sdp_add(record, len) → its handle (0: not one sequence, or no room)
;   ubt_sdp_remove(handle)
;   ubt_sdp_rfcomm_record(class, channel, name, len, out) → its length: a
;                                         serial-port style record
;   ubt_sdp_query(conn, uuids, n, first_id, last_id) → EAX
;                                         Service Search Attribute; the
;                                         answer, whole, to ubt_sdp_fn
;   ubt_sdp_close(conn)
;   ubt_sdp_attr(list, len, id) → RAX = the value element, EDX = its length
;   ubt_sdp_rfcomm_channel(data, len) → EAX = the RFCOMM channel (0: none)
;
; Data elements are big-endian with the usual headers (sizes 1-16, or a
; 1-, 2- or 4-byte length); UUIDs of every size match through the base
; UUID. The server answers Service Search, Service Attribute and Service
; Search Attribute with continuation (the state is the offset into the
; answer, made again each time) and refuses what it cannot parse; the
; client asks again while there is more.
; =============================================================================

%ifndef LIB_UBT_SDP_SDP_ASM
%define LIB_UBT_SDP_SDP_ASM

%define SDP_PSM             1
%define SDP_MAX_RECORDS     16
%define SDP_RECORD_MAX      512
%define SDP_ANSWER_MAX      4096
%define SDP_FIRST_HANDLE    0x00010000
%define SDP_MAX_UUIDS       12
%define SDP_MAX_RANGES      16
%define SDP_QUERIES         8           ; links querying at once

; PDUs
%define SDP_ERROR_RSP       0x01
%define SDP_SEARCH_REQ      0x02
%define SDP_SEARCH_RSP      0x03
%define SDP_ATTR_REQ        0x04
%define SDP_ATTR_RSP        0x05
%define SDP_SEARCH_ATTR_REQ 0x06
%define SDP_SEARCH_ATTR_RSP 0x07

; errors
%define SDP_E_HANDLE        0x0002
%define SDP_E_SYNTAX        0x0003
%define SDP_E_SIZE          0x0004
%define SDP_E_CONT          0x0005

; element types
%define SDE_NIL             0
%define SDE_UINT            1
%define SDE_UUID            3
%define SDE_DES             6
%define SDE_DEA             7

struc ubt_sdp_rec
    .handle:        resd 1          ; 0: free
    .len:           resd 1
    .data:          resb SDP_RECORD_MAX     ; 36 LL LL, attribute 0 first
endstruc

struc ubt_sdp_q
    .conn:          resq 1
    .chan:          resq 1
    .open:          resb 1
    .busy:          resb 1
    .tid:           resw 1
    .req_len:       resw 1
    .pad:           resw 1
    .got:           resd 1
    .pad2:          resd 1
    .req:           resb 96         ; parameters, without continuation
    .buf:           resb SDP_ANSWER_MAX
endstruc

; the server's working state for one request (on its stack)
struc sdp_work
    .uuids:         resb SDP_MAX_UUIDS * 16
    .n_uuids:       resd 1
    .n_ranges:      resd 1
    .ranges:        resd SDP_MAX_RANGES * 2     ; (first, last)
    .full_len:      resd 1
    .max:           resd 1
    .tid:           resw 1
    .pad:           resw 1
    .offset:        resd 1
    .cont:          resq 1          ; where the request's continuation is
    .chan:          resq 1
    .full:          resb SDP_ANSWER_MAX
    .rsp:           resb SDP_ANSWER_MAX
endstruc

section .bss
alignb 8
global ubt_sdp_records
ubt_sdp_records:    resb SDP_MAX_RECORDS * ubt_sdp_rec_size
ubt_sdp_next:       resd 1
ubt_sdp_pad:        resd 1
global ubt_sdp_fn
ubt_sdp_fn:         resq 1          ; (conn, ESI = status: 0, an SDP error,
                                    ;  or negative; RDX = data, ECX = length)
ubt_sdp_qs:         resq SDP_QUERIES

section .data
align 8
ubt_sdp_server_ops: dq ubt_sdp_srv_recv, 0
ubt_sdp_client_ops: dq ubt_sdp_cli_recv, ubt_sdp_cli_event

section .rodata
; a serial-port style record; the class at 8, the channel at 26, the name's
; length at 39 (the sequence's length at 1)
sdp_rfcomm_tpl:
    db 0x35, 0
    db 0x09, 0x00, 0x01, 0x35, 0x03, 0x19, 0, 0
    db 0x09, 0x00, 0x04, 0x35, 0x0C, 0x35, 0x03, 0x19, 0x01, 0x00
    db 0x35, 0x05, 0x19, 0x00, 0x03, 0x08, 0
    db 0x09, 0x00, 0x05, 0x35, 0x03, 0x19, 0x10, 0x02
    db 0x09, 0x01, 0x00, 0x25, 0
SDP_TPL_LEN equ $ - sdp_rfcomm_tpl
global ubt_sdp_layout
ubt_sdp_layout:
    dd ubt_sdp_rec_size, ubt_sdp_q_size, sdp_work_size, 0

section .text

; -----------------------------------------------------------------------------
; ubt_sde — RSI = an element, RDI = the end of what holds it
; → EAX = type, ECX = header length, EDX = data length; CF = 1 when it does
;   not parse or runs past the end
; -----------------------------------------------------------------------------
global ubt_sde
ubt_sde:
    cmp rsi, rdi
    jae .bad
    movzx eax, byte [rsi]
    mov r8d, eax
    shr eax, 3
    and r8d, 7
    cmp r8d, 5
    jae .length
    mov ecx, r8d
    mov edx, 1
    shl edx, cl
    mov ecx, 1
    test eax, eax
    jnz .check
    test r8d, r8d                       ; nil: size 0 only, no data
    jnz .bad
    xor edx, edx
    jmp .check
.length:
    cmp r8d, 5
    jne .len16
    lea r9, [rsi + 2]
    cmp r9, rdi
    ja .bad
    movzx edx, byte [rsi + 1]
    mov ecx, 2
    jmp .check
.len16:
    cmp r8d, 6
    jne .len32
    lea r9, [rsi + 3]
    cmp r9, rdi
    ja .bad
    movzx edx, word [rsi + 1]
    xchg dl, dh
    mov ecx, 3
    jmp .check
.len32:
    lea r9, [rsi + 5]
    cmp r9, rdi
    ja .bad
    mov edx, [rsi + 1]
    bswap edx
    mov ecx, 5
.check:
    lea r9, [rsi + rcx]
    add r9, rdx
    cmp r9, rdi
    ja .bad
    clc
    ret
.bad:
    stc
    ret

; sde_uuid128 — RSI = a UUID element (known good), RDX = out (16, big-endian,
; filled in from the base UUID 00000000-0000-1000-8000-00805F9B34FB)
sde_uuid128:
    mov dword [rdx], 0
    mov dword [rdx + 4], 0x00100000
    mov dword [rdx + 8], 0x80000080
    mov dword [rdx + 12], 0xFB349B5F
    movzx eax, byte [rsi]
    and eax, 7
    cmp eax, 1
    je .u16
    cmp eax, 2
    je .u32
    movdqu xmm0, [rsi + 1]
    movdqu [rdx], xmm0
    ret
.u16:
    mov ax, [rsi + 1]
    mov [rdx + 2], ax
    ret
.u32:
    mov eax, [rsi + 1]
    mov [rdx], eax
    ret

; sde_has_uuid — RSI = data, RDI = its end, RDX = a UUID (16, big-endian)
; → ZF = 1 when a UUID element anywhere in it (sequences opened) is that one
sde_has_uuid:
    push rbx
    push r12
    push r13
    sub rsp, 32
    mov rbx, rsi
    mov r12, rdi
    mov r13, rdx
.next:
    cmp rbx, r12
    jae .no
    mov rsi, rbx
    mov rdi, r12
    call ubt_sde
    jc .no
    cmp eax, SDE_DES
    je .open
    cmp eax, SDE_DEA
    je .open
    cmp eax, SDE_UUID
    jne .skip
    mov [rsp + 16], ecx
    mov [rsp + 20], edx
    mov rsi, rbx
    mov rdx, rsp
    call sde_uuid128
    mov ecx, [rsp + 16]
    mov edx, [rsp + 20]
    movdqu xmm0, [rsp]
    movdqu xmm1, [r13]
    pcmpeqb xmm0, xmm1
    pmovmskb eax, xmm0
    cmp eax, 0xFFFF
    je .yes
.skip:
    add rbx, rcx
    add rbx, rdx
    jmp .next
.open:
    add rbx, rcx                        ; into the sequence
    jmp .next
.yes:
    xor eax, eax                        ; ZF = 1
    jmp .out
.no:
    or eax, 1
.out:
    lea rsp, [rsp + 32]
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_sdp_init — the records cleared, the server on PSM 1
; -----------------------------------------------------------------------------
global ubt_sdp_init
ubt_sdp_init:
    sub rsp, 8
    lea rdi, [rel ubt_sdp_records]
    mov ecx, SDP_MAX_RECORDS * ubt_sdp_rec_size
    xor eax, eax
    rep stosb
    mov dword [rel ubt_sdp_next], SDP_FIRST_HANDLE
    mov edi, SDP_PSM
    mov esi, L2CAP_MODE_BASIC
    lea rdx, [rel ubt_sdp_server_ops]
    xor ecx, ecx
    call l2cap_server
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_sdp_add — RDI = a record (one sequence of attribute ID, value pairs,
;   without attribute 0), ESI = its length → EAX = its handle, or 0
; -----------------------------------------------------------------------------
global ubt_sdp_add
ubt_sdp_add:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov r12, rdi
    mov r13d, esi
    mov rsi, r12
    lea rdi, [r12 + r13]
    call ubt_sde
    jc .none
    cmp eax, SDE_DES
    jne .none
    lea eax, [rcx + rdx]
    cmp eax, r13d
    jne .none
    lea eax, [rdx + 8 + 3]
    cmp eax, SDP_RECORD_MAX
    ja .none
    mov r14d, ecx                       ; the header's length
    lea rbx, [rel ubt_sdp_records]
    xor r8d, r8d
.slot:
    cmp r8d, SDP_MAX_RECORDS
    jae .none
    cmp dword [rbx + ubt_sdp_rec.handle], 0
    je .free
    add rbx, ubt_sdp_rec_size
    inc r8d
    jmp .slot
.free:
    mov eax, [rel ubt_sdp_next]
    inc dword [rel ubt_sdp_next]
    mov [rbx + ubt_sdp_rec.handle], eax
    ; 36 LL LL | 09 00 00 | 0A hh hh hh hh | the pairs
    lea r9d, [rdx + 8]
    mov byte [rbx + ubt_sdp_rec.data], 0x36
    mov [rbx + ubt_sdp_rec.data + 1], r9b
    shr r9d, 8
    mov [rbx + ubt_sdp_rec.data + 1], r9b
    lea r9d, [rdx + 8]
    mov [rbx + ubt_sdp_rec.data + 2], r9b
    mov byte [rbx + ubt_sdp_rec.data + 3], 0x09
    mov word [rbx + ubt_sdp_rec.data + 4], 0
    mov byte [rbx + ubt_sdp_rec.data + 6], 0x0A
    mov r10d, eax
    bswap r10d
    mov [rbx + ubt_sdp_rec.data + 7], r10d
    lea rdi, [rbx + ubt_sdp_rec.data + 11]
    lea rsi, [r12 + r14]
    mov ecx, edx
    rep movsb
    lea ecx, [rdx + 11]
    mov [rbx + ubt_sdp_rec.len], ecx
    jmp .out
.none:
    xor eax, eax
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_sdp_remove — EDI = handle
global ubt_sdp_remove
ubt_sdp_remove:
    lea rax, [rel ubt_sdp_records]
    xor ecx, ecx
.next:
    cmp ecx, SDP_MAX_RECORDS
    jae .out
    cmp [rax + ubt_sdp_rec.handle], edi
    jne .skip
    mov dword [rax + ubt_sdp_rec.handle], 0
.skip:
    add rax, ubt_sdp_rec_size
    inc ecx
    jmp .next
.out:
    ret

; -----------------------------------------------------------------------------
; ubt_sdp_rfcomm_record — EDI = service class (16-bit), ESI = RFCOMM channel,
;   RDX = name, ECX = its length (64 at most), R8 = out (104 bytes)
;   → EAX = the record's length: class, L2CAP and RFCOMM with the channel,
;   the public browse group, the name
; -----------------------------------------------------------------------------
global ubt_sdp_rfcomm_record
ubt_sdp_rfcomm_record:
    push rbx
    mov rbx, r8
    cmp ecx, 64
    jbe .len
    mov ecx, 64
.len:
    push rsi
    push rdi
    push rdx
    push rcx
    mov rdi, rbx
    lea rsi, [rel sdp_rfcomm_tpl]
    mov ecx, SDP_TPL_LEN
    rep movsb
    pop rcx
    pop rsi                             ; the name
    mov [rbx + 39], cl
    lea eax, [rcx + SDP_TPL_LEN - 2]
    mov [rbx + 1], al
    lea rdi, [rbx + SDP_TPL_LEN]
    push rcx
    rep movsb
    pop rcx
    pop rdi                             ; the class
    mov eax, edi
    mov [rbx + 9], al
    mov [rbx + 8], ah
    pop rsi                             ; the channel
    mov [rbx + 26], sil
    lea eax, [rcx + SDP_TPL_LEN]
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_sdp_attr — RDI = an attribute list (a sequence of ID, value), ESI =
;   its length, EDX = the ID → RAX = the value element, EDX = its whole
;   length; RAX = 0 when it is not there
; -----------------------------------------------------------------------------
global ubt_sdp_attr
ubt_sdp_attr:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    lea r12, [rdi + rsi]
    mov r13d, edx
    mov rsi, rbx
    mov rdi, r12
    call ubt_sde
    jc .none
    cmp eax, SDE_DES
    jne .none
    lea rbx, [rbx + rcx]
    lea r12, [rbx + rdx]                ; inside the sequence
.pair:
    mov rsi, rbx
    mov rdi, r12
    call ubt_sde
    jc .none
    cmp byte [rbx], 0x09                ; the ID: a uint16
    jne .none
    movzx r10d, word [rbx + 1]          ; (ubt_sde uses R8 and R9)
    rol r10w, 8
    add rbx, 3
    mov rsi, rbx
    mov rdi, r12
    call ubt_sde
    jc .none
    lea eax, [rcx + rdx]
    cmp r10d, r13d
    je .found
    add rbx, rax
    jmp .pair
.found:
    mov edx, eax
    mov rax, rbx
    jmp .out
.none:
    xor eax, eax
    xor edx, edx
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_sdp_rfcomm_channel — RDI = data (a record, a list, an answer), ESI =
;   its length → EAX = the first RFCOMM channel in it (the uint8 after UUID
;   0x0003), or 0
; -----------------------------------------------------------------------------
global ubt_sdp_rfcomm_channel
ubt_sdp_rfcomm_channel:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    lea r12, [rdi + rsi]
.next:
    mov rsi, rbx
    mov rdi, r12
    call ubt_sde
    jc .none
    cmp eax, SDE_DES
    je .open
    cmp eax, SDE_DEA
    je .open
    cmp byte [rbx], 0x19                ; UUID16
    jne .skip
    cmp word [rbx + 1], 0x0300          ; 0x0003, big-endian
    jne .skip
    lea rax, [rbx + 5]
    cmp rax, r12
    ja .none
    cmp byte [rbx + 3], 0x08            ; uint8
    jne .skip
    movzx eax, byte [rbx + 4]
    jmp .out
.skip:
    add rbx, rcx
    add rbx, rdx
    jmp .next
.open:
    add rbx, rcx
    jmp .next
.none:
    xor eax, eax
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ---- the server ---------------------------------------------------------------
; working registers: RBX = sdp_work, R12 = the request's parameters, R13 =
; their end

; sdp_pattern — R12 at a ServiceSearchPattern → R12 past it; UUIDs into the
; work area. CF = 1 when malformed
sdp_pattern:
    push r14
    push r15
    sub rsp, 8
    mov rsi, r12
    mov rdi, r13
    call ubt_sde
    jc .bad
    cmp eax, SDE_DES
    jne .bad
    lea r14, [r12 + rcx]                ; the UUIDs
    lea r15, [r14 + rdx]                ; their end
    mov r12, r15
    mov dword [rbx + sdp_work.n_uuids], 0
.uuid:
    cmp r14, r15
    jae .done
    mov rsi, r14
    mov rdi, r15
    call ubt_sde
    jc .bad
    cmp eax, SDE_UUID
    jne .bad
    mov eax, [rbx + sdp_work.n_uuids]
    cmp eax, SDP_MAX_UUIDS
    jae .bad
    push rcx
    push rdx
    shl eax, 4
    lea rdx, [rbx + sdp_work.uuids + rax]
    mov rsi, r14
    call sde_uuid128
    pop rdx
    pop rcx
    inc dword [rbx + sdp_work.n_uuids]
    add r14, rcx
    add r14, rdx
    jmp .uuid
.done:
    cmp dword [rbx + sdp_work.n_uuids], 0
    je .bad
    add rsp, 8
    pop r15
    pop r14
    clc
    ret
.bad:
    add rsp, 8
    pop r15
    pop r14
    stc
    ret

; sdp_idlist — R12 at an AttributeIDList → R12 past it, ranges into the work
; area. CF = 1 when malformed
sdp_idlist:
    push r14
    push r15
    sub rsp, 8
    mov rsi, r12
    mov rdi, r13
    call ubt_sde
    jc .bad
    cmp eax, SDE_DES
    jne .bad
    lea r14, [r12 + rcx]
    lea r15, [r14 + rdx]
    mov r12, r15
    mov dword [rbx + sdp_work.n_ranges], 0
.id:
    cmp r14, r15
    jae .done
    mov eax, [rbx + sdp_work.n_ranges]
    cmp eax, SDP_MAX_RANGES
    jae .bad
    lea r8, [rbx + sdp_work.ranges + rax * 8]
    cmp byte [r14], 0x09                ; one ID
    je .one
    cmp byte [r14], 0x0A                ; a range: first, last
    jne .bad
    lea rax, [r14 + 5]
    cmp rax, r15
    ja .bad
    movzx eax, word [r14 + 1]
    rol ax, 8
    mov [r8], eax
    movzx eax, word [r14 + 3]
    rol ax, 8
    mov [r8 + 4], eax
    add r14, 5
    inc dword [rbx + sdp_work.n_ranges]
    jmp .id
.one:
    lea rax, [r14 + 3]
    cmp rax, r15
    ja .bad
    movzx eax, word [r14 + 1]
    rol ax, 8
    mov [r8], eax
    mov [r8 + 4], eax
    add r14, 3
    inc dword [rbx + sdp_work.n_ranges]
    jmp .id
.done:
    cmp dword [rbx + sdp_work.n_ranges], 0
    je .bad
    add rsp, 8
    pop r15
    pop r14
    clc
    ret
.bad:
    add rsp, 8
    pop r15
    pop r14
    stc
    ret

; sdp_cont — R12 at the ContinuationState → the offset into the answer in
; sdp_work.offset (0 when none). CF = 1 when it is not one of ours
sdp_cont:
    lea rax, [r12 + 1]
    cmp rax, r13
    ja .bad
    movzx eax, byte [r12]
    test eax, eax
    jz .none
    cmp eax, 2
    jne .bad
    lea rax, [r12 + 3]
    cmp rax, r13
    ja .bad
    movzx eax, word [r12 + 1]
    rol ax, 8
    mov [rbx + sdp_work.offset], eax
    clc
    ret
.none:
    mov dword [rbx + sdp_work.offset], 0
    clc
    ret
.bad:
    stc
    ret

; sdp_matches — RDI = a record → ZF = 1 when it has every UUID of the pattern
sdp_matches:
    push r14
    push r15
    sub rsp, 8
    mov r14, rdi
    xor r15d, r15d
.uuid:
    cmp r15d, [rbx + sdp_work.n_uuids]
    jae .yes
    lea rsi, [r14 + ubt_sdp_rec.data]
    mov eax, [r14 + ubt_sdp_rec.len]
    lea rdi, [rsi + rax]
    mov eax, r15d
    shl eax, 4
    lea rdx, [rbx + sdp_work.uuids + rax]
    call sde_has_uuid
    jne .no
    inc r15d
    jmp .uuid
.yes:
    xor eax, eax
    jmp .out
.no:
    or eax, 1
.out:
    lea rsp, [rsp + 8]
    pop r15
    pop r14
    ret

; sdp_attrs — RDI = a record, RSI = out → EAX = the length written: a
; sequence (36 LL LL) of the record's pairs whose IDs the ranges hold;
; nothing written (EAX = 0) when it would pass RDX (the end of room)
sdp_attrs:
    push r12
    push r13
    push r14
    push r15
    push rbp
    mov r14, rsi                        ; out
    mov rbp, rdx                        ; the end of room
    lea r12, [rdi + ubt_sdp_rec.data + 3]
    mov eax, [rdi + ubt_sdp_rec.len]
    lea r13, [rdi + ubt_sdp_rec.data + rax]
    lea r15, [r14 + 3]
    lea rax, [r15]
    cmp rax, rbp
    ja .full
.pair:
    cmp r12, r13
    jae .close
    ; the ID (uint16), then its value
    movzx r10d, word [r12 + 1]          ; the ID (ubt_sde uses R8 and R9)
    rol r10w, 8
    lea rsi, [r12 + 3]
    mov rdi, r13
    call ubt_sde
    jc .close
    lea r9d, [rcx + rdx + 3]            ; the pair's length
    ; in a range?
    xor ecx, ecx
.range:
    cmp ecx, [rbx + sdp_work.n_ranges]
    jae .skip
    cmp r10d, [rbx + sdp_work.ranges + rcx * 8]
    jb .range_next
    cmp r10d, [rbx + sdp_work.ranges + rcx * 8 + 4]
    jbe .take
.range_next:
    inc ecx
    jmp .range
.take:
    lea rax, [r15 + r9]
    cmp rax, rbp
    ja .full
    mov rsi, r12
    mov rdi, r15
    mov ecx, r9d
    rep movsb
    mov r15, rdi
.skip:
    add r12, r9
    jmp .pair
.close:
    mov rax, r15
    sub rax, r14
    lea ecx, [rax - 3]
    mov byte [r14], 0x36
    rol cx, 8
    mov [r14 + 1], cx                   ; big-endian
    jmp .out
.full:
    xor eax, eax
.out:
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; sdp_send — RBX = work, EDI = PDU id, RSI = parameters, ECX = their length:
; the response with the request's transaction ID
sdp_send:
    sub rsp, 8
    lea rdx, [rbx + sdp_work.rsp]
    mov [rdx], dil
    mov ax, [rbx + sdp_work.tid]
    mov [rdx + 1], ax
    mov [rdx + 4], cl
    mov [rdx + 3], ch
    push rcx
    lea rdi, [rdx + 5]
    rep movsb
    pop rcx
    mov rdi, [rbx + sdp_work.chan]
    lea rsi, [rbx + sdp_work.rsp]
    lea edx, [rcx + 5]
    call l2cap_send
    add rsp, 8
    ret

; sdp_error — RBX = work, EDI = error code
sdp_error:
    sub rsp, 8
    mov eax, edi
    xchg al, ah
    mov [rsp], ax
    mov edi, SDP_ERROR_RSP
    mov rsi, rsp
    mov ecx, 2
    call sdp_send
    add rsp, 8
    ret

; -----------------------------------------------------------------------------
; ubt_sdp_srv_recv — RDI = the channel, RSI = a request, EDX = its length
; -----------------------------------------------------------------------------
ubt_sdp_srv_recv:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, sdp_work_size              ; (8 mod 16: aligned with the pushes)
    mov rbx, rsp
    mov [rbx + sdp_work.chan], rdi
    mov r14, rsi
    mov r15d, edx
    cmp r15d, 5
    jb .size
    mov ax, [r14 + 1]
    mov [rbx + sdp_work.tid], ax
    movzx eax, word [r14 + 3]
    rol ax, 8
    add eax, 5
    cmp eax, r15d
    jne .size
    lea r12, [r14 + 5]
    lea r13, [r14 + r15]
    ; the most we may send: what L2CAP takes, less the header
    mov rax, [rbx + sdp_work.chan]
    movzx eax, word [rax + l2cap_chan.omtu]
    cmp eax, SDP_ANSWER_MAX
    jbe .mtu
    mov eax, SDP_ANSWER_MAX
.mtu:
    sub eax, 5
    mov [rbx + sdp_work.max], eax
    movzx eax, byte [r14]
    cmp eax, SDP_SEARCH_REQ
    je .search
    cmp eax, SDP_ATTR_REQ
    je .attr
    cmp eax, SDP_SEARCH_ATTR_REQ
    je .search_attr
.syntax:
    mov edi, SDP_E_SYNTAX
    call sdp_error
    jmp .out
.size:
    cmp r15d, 3
    jb .out
    mov ax, [r14 + 1]
    mov [rbx + sdp_work.tid], ax
    mov edi, SDP_E_SIZE
    call sdp_error
    jmp .out
.bad_cont:
    mov edi, SDP_E_CONT
    call sdp_error
    jmp .out

; ---- Service Search: the handles of the records matching -------------------
.search:
    call sdp_pattern
    jc .syntax
    lea rax, [r12 + 2]
    cmp rax, r13
    ja .syntax
    movzx ebp, word [r12]
    rol bp, 8                           ; the most handles wanted
    add r12, 2
    call sdp_cont
    jc .bad_cont
    ; every match, as handles, in the full answer
    lea r14, [rbx + sdp_work.full]
    xor r15d, r15d                      ; how many
    lea rdi, [rel ubt_sdp_records]
    xor ecx, ecx
.s_rec:
    cmp ecx, SDP_MAX_RECORDS
    jae .s_got
    cmp r15d, ebp
    jae .s_got
    cmp dword [rdi + ubt_sdp_rec.handle], 0
    je .s_skip
    push rcx
    push rdi
    call sdp_matches
    pop rdi
    pop rcx
    jne .s_skip
    mov eax, [rdi + ubt_sdp_rec.handle]
    bswap eax
    mov [r14 + r15 * 4], eax
    inc r15d
.s_skip:
    add rdi, ubt_sdp_rec_size
    inc ecx
    jmp .s_rec
.s_got:
    ; from the continuation's index, as many as fit
    mov eax, [rbx + sdp_work.offset]
    cmp eax, r15d
    ja .bad_cont
    mov ecx, [rbx + sdp_work.max]
    sub ecx, 4 + 3                      ; counts, continuation
    shr ecx, 2
    mov edx, r15d
    sub edx, eax                        ; left
    cmp edx, ecx
    jbe .s_fits
    mov edx, ecx
.s_fits:
    ; total, current, handles, continuation
    lea rdi, [rbx + sdp_work.rsp + 1024]
    mov [rdi + 1], r15b
    mov ecx, r15d
    mov [rdi], ch
    mov [rdi + 3], dl
    mov [rdi + 2], dh
    lea rsi, [r14 + rax * 4]
    push rax
    push rdx
    lea rdi, [rdi + 4]
    lea ecx, [rdx * 4]
    rep movsb
    pop rdx
    pop rax
    add eax, edx
    mov byte [rdi], 0
    lea r8d, [rdx * 4 + 5]
    cmp eax, r15d
    jae .s_send
    mov byte [rdi], 2
    mov [rdi + 2], al
    mov [rdi + 1], ah
    add r8d, 2
.s_send:
    mov edi, SDP_SEARCH_RSP
    lea rsi, [rbx + sdp_work.rsp + 1024]
    mov ecx, r8d
    call sdp_send
    jmp .out

; ---- Service Attribute: one record's attributes --------------------------------
.attr:
    lea rax, [r12 + 6]
    cmp rax, r13
    ja .syntax
    mov r14d, [r12]
    bswap r14d                          ; the handle
    movzx ebp, word [r12 + 4]
    rol bp, 8                           ; most bytes wanted
    cmp ebp, 7
    jb .syntax
    add r12, 6
    call sdp_idlist
    jc .syntax
    call sdp_cont
    jc .bad_cont
    lea rdi, [rel ubt_sdp_records]
    xor ecx, ecx
.a_find:
    cmp ecx, SDP_MAX_RECORDS
    jae .a_none
    cmp [rdi + ubt_sdp_rec.handle], r14d
    je .a_found
    add rdi, ubt_sdp_rec_size
    inc ecx
    jmp .a_find
.a_none:
    mov edi, SDP_E_HANDLE
    call sdp_error
    jmp .out
.a_found:
    lea rsi, [rbx + sdp_work.full]
    lea rdx, [rbx + sdp_work.full + SDP_ANSWER_MAX]
    call sdp_attrs
    mov [rbx + sdp_work.full_len], eax
    mov edi, SDP_ATTR_RSP
    jmp .slice

; ---- Service Search Attribute: every matching record's attributes ---------------
.search_attr:
    call sdp_pattern
    jc .syntax
    lea rax, [r12 + 2]
    cmp rax, r13
    ja .syntax
    movzx ebp, word [r12]
    rol bp, 8
    cmp ebp, 7
    jb .syntax
    add r12, 2
    call sdp_idlist
    jc .syntax
    call sdp_cont
    jc .bad_cont
    ; 36 LL LL, then each record's sequence
    lea r14, [rbx + sdp_work.full + 3]
    lea rdi, [rel ubt_sdp_records]
    xor r15d, r15d
.sa_rec:
    cmp r15d, SDP_MAX_RECORDS
    jae .sa_close
    cmp dword [rdi + ubt_sdp_rec.handle], 0
    je .sa_skip
    push rdi
    sub rsp, 8
    call sdp_matches
    lea rsp, [rsp + 8]                  ; (keeps ZF)
    pop rdi
    jne .sa_skip
    push rdi
    sub rsp, 8
    mov rsi, r14
    lea rdx, [rbx + sdp_work.full + SDP_ANSWER_MAX]
    call sdp_attrs
    add rsp, 8
    pop rdi
    test eax, eax
    jz .sa_close                        ; no more room: what fitted
    add r14, rax
.sa_skip:
    add rdi, ubt_sdp_rec_size
    inc r15d
    jmp .sa_rec
.sa_close:
    lea rax, [rbx + sdp_work.full]
    sub r14, rax
    lea ecx, [r14 - 3]
    mov byte [rbx + sdp_work.full], 0x36
    mov [rbx + sdp_work.full + 2], cl
    mov [rbx + sdp_work.full + 1], ch
    mov [rbx + sdp_work.full_len], r14d
    mov edi, SDP_SEARCH_ATTR_RSP

; the answer from the continuation's offset: byte count, bytes, continuation
; (EDI = the PDU, EBP = the most the client takes)
.slice:
    mov r15d, edi
    mov eax, [rbx + sdp_work.offset]
    mov ecx, [rbx + sdp_work.full_len]
    cmp eax, ecx
    ja .bad_cont
    sub ecx, eax                        ; left
    mov edx, [rbx + sdp_work.max]
    sub edx, 2 + 3                      ; count, continuation
    cmp edx, ebp
    jbe .room
    mov edx, ebp
.room:
    cmp ecx, edx
    jbe .slice_fits
    mov ecx, edx
.slice_fits:
    lea rdi, [rbx + sdp_work.rsp + 1024]
    mov [rdi + 1], cl
    mov [rdi], ch
    lea rsi, [rbx + sdp_work.full + rax]
    push rax
    push rcx
    add rdi, 2
    rep movsb
    pop rcx
    pop rax
    add eax, ecx
    lea r8d, [rcx + 3]
    mov byte [rdi], 0
    cmp eax, [rbx + sdp_work.full_len]
    jae .slice_send
    mov byte [rdi], 2
    mov [rdi + 2], al
    mov [rdi + 1], ah
    add r8d, 2
.slice_send:
    mov edi, r15d
    lea rsi, [rbx + sdp_work.rsp + 1024]
    mov ecx, r8d
    call sdp_send
.out:
    add rsp, sdp_work_size
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ---- the client --------------------------------------------------------------

; sdp_q_of — RDI = conn, ESI = 1 to make one → RAX = its query, or 0
sdp_q_of:
    push rbx
    push r12
    sub rsp, 8
    mov rbx, rdi
    mov r12d, esi
    xor ecx, ecx
    xor r8d, r8d                        ; a free slot
.next:
    cmp ecx, SDP_QUERIES
    jae .none
    lea rdx, [rel ubt_sdp_qs]
    mov rax, [rdx + rcx * 8]
    test rax, rax
    jz .free
    cmp [rax + ubt_sdp_q.conn], rbx
    je .out
    jmp .skip
.free:
    test r8, r8
    jnz .skip
    lea r8, [rdx + rcx * 8]
.skip:
    inc ecx
    jmp .next
.none:
    xor eax, eax
    test r12d, r12d
    jz .out
    test r8, r8
    jz .out
    push r8
    sub rsp, 8
    mov edi, ubt_sdp_q_size
    mov esi, 8
    call usb_alloc
    add rsp, 8
    pop r8
    test rax, rax
    jz .out
    mov [r8], rax
    mov [rax + ubt_sdp_q.conn], rbx
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; sdp_q_free — RDI = query: off the table, given back
sdp_q_free:
    lea rdx, [rel ubt_sdp_qs]
    xor ecx, ecx
.next:
    cmp ecx, SDP_QUERIES
    jae .free
    cmp [rdx + rcx * 8], rdi
    jne .skip
    mov qword [rdx + rcx * 8], 0
.skip:
    inc ecx
    jmp .next
.free:
    mov esi, ubt_sdp_q_size
    mov edx, 8
    jmp usb_free

; sdp_q_send — RBX = query, RSI = continuation (0: none): the request
sdp_q_send:
    push r12
    sub rsp, 112
    mov r12, rsi
    mov byte [rsp], SDP_SEARCH_ATTR_REQ
    inc word [rbx + ubt_sdp_q.tid]
    mov ax, [rbx + ubt_sdp_q.tid]
    mov [rsp + 2], al
    mov [rsp + 1], ah
    lea rdi, [rsp + 5]
    lea rsi, [rbx + ubt_sdp_q.req]
    movzx ecx, word [rbx + ubt_sdp_q.req_len]
    rep movsb
    mov byte [rdi], 0
    mov ecx, 1
    test r12, r12
    jz .cont_done
    movzx ecx, byte [r12]
    inc ecx
    cmp ecx, 17
    jbe .cont_copy
    mov ecx, 1
    mov byte [rdi], 0
    jmp .cont_done
.cont_copy:
    mov rsi, r12
    push rcx
    rep movsb
    pop rcx
.cont_done:
    movzx eax, word [rbx + ubt_sdp_q.req_len]
    add eax, ecx
    mov [rsp + 4], al
    mov [rsp + 3], ah
    lea edx, [rax + 5]
    mov rdi, [rbx + ubt_sdp_q.chan]
    mov rsi, rsp
    call l2cap_send
    add rsp, 112
    pop r12
    ret

; sdp_q_done — RBX = query, ESI = status, RDX = data, ECX = length
sdp_q_done:
    mov byte [rbx + ubt_sdp_q.busy], 0
    mov rax, [rel ubt_sdp_fn]
    test rax, rax
    jz .out
    mov rdi, [rbx + ubt_sdp_q.conn]
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; -----------------------------------------------------------------------------
; ubt_sdp_query — RDI = conn, RSI = 16-bit UUIDs, EDX = how many (1-12), ECX
;   = the first attribute ID, R8D = the last → EAX = 0, or -UBT_EBUSY,
;   -UBT_ENOMEM, -UBT_EIO
; -----------------------------------------------------------------------------
global ubt_sdp_query
ubt_sdp_query:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov r13, rsi
    mov r14d, edx
    mov r15d, ecx
    push r8
    sub rsp, 8
    mov esi, 1
    call sdp_q_of
    add rsp, 8
    pop r8
    mov rbx, rax
    mov eax, -UBT_ENOMEM
    test rbx, rbx
    jz .out
    mov eax, -UBT_EBUSY
    cmp byte [rbx + ubt_sdp_q.busy], 0
    jne .out
    mov eax, -UBT_EIO
    test r14d, r14d
    jz .out
    cmp r14d, SDP_MAX_UUIDS
    ja .out
    ; 35 3n (19 uuid)*n | FF FF | 35 05 0A first last
    lea rdi, [rbx + ubt_sdp_q.req]
    mov byte [rdi], 0x35
    lea eax, [r14d * 3]
    mov [rdi + 1], al
    add rdi, 2
    xor ecx, ecx
.uuid:
    cmp ecx, r14d
    jae .uuids
    mov byte [rdi], 0x19
    mov ax, [r13 + rcx * 2]
    mov [rdi + 2], al
    mov [rdi + 1], ah
    add rdi, 3
    inc ecx
    jmp .uuid
.uuids:
    mov word [rdi], 0xFFFF
    mov byte [rdi + 2], 0x35
    mov byte [rdi + 3], 5
    mov byte [rdi + 4], 0x0A
    mov eax, r15d
    mov [rdi + 6], al
    mov [rdi + 5], ah
    mov eax, r8d
    mov [rdi + 8], al
    mov [rdi + 7], ah
    add rdi, 9
    lea rax, [rbx + ubt_sdp_q.req]
    sub rdi, rax
    mov [rbx + ubt_sdp_q.req_len], di
    mov dword [rbx + ubt_sdp_q.got], 0
    mov byte [rbx + ubt_sdp_q.busy], 1
    cmp byte [rbx + ubt_sdp_q.open], 0
    je .open
    xor esi, esi
    call sdp_q_send
    xor eax, eax
    jmp .out
.open:
    xor eax, eax
    cmp qword [rbx + ubt_sdp_q.chan], 0
    jne .out                            ; opening already: sent when open
    mov rdi, r12
    mov esi, SDP_PSM
    mov edx, L2CAP_MODE_BASIC
    lea rcx, [rel ubt_sdp_client_ops]
    mov r8, rbx
    call l2cap_connect
    mov [rbx + ubt_sdp_q.chan], rax
    test rax, rax
    jnz .opening
    mov byte [rbx + ubt_sdp_q.busy], 0
    mov eax, -UBT_EIO
    jmp .out
.opening:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_sdp_close — RDI = conn: the client's channel closed
global ubt_sdp_close
ubt_sdp_close:
    sub rsp, 8
    xor esi, esi
    call sdp_q_of
    test rax, rax
    jz .out
    mov rdi, [rax + ubt_sdp_q.chan]
    test rdi, rdi
    jz .out
    call l2cap_disconnect
.out:
    add rsp, 8
    ret

; ubt_sdp_cli_event — RDI = chan, ESI = event, EDX = why
ubt_sdp_cli_event:
    push rbx
    mov rbx, [rdi + l2cap_chan.user]
    cmp esi, L2CAP_EV_OPEN
    jne .gone
    mov byte [rbx + ubt_sdp_q.open], 1
    cmp byte [rbx + ubt_sdp_q.busy], 0
    je .out
    xor esi, esi
    call sdp_q_send
    jmp .out
.gone:
    ; closed or refused: a waiting query fails; the state goes with it
    cmp byte [rbx + ubt_sdp_q.busy], 0
    je .free
    mov esi, -UBT_EIO
    xor edx, edx
    xor ecx, ecx
    call sdp_q_done
.free:
    mov rdi, rbx
    call sdp_q_free
.out:
    pop rbx
    ret

; ubt_sdp_cli_recv — RDI = chan, RSI = a response, EDX = its length
ubt_sdp_cli_recv:
    push rbx
    push r12
    push r13
    mov rbx, [rdi + l2cap_chan.user]
    mov r12, rsi
    mov r13d, edx
    cmp byte [rbx + ubt_sdp_q.busy], 0
    je .out
    cmp r13d, 5
    jb .broken
    mov ax, [r12 + 1]
    rol ax, 8
    cmp ax, [rbx + ubt_sdp_q.tid]
    jne .out                            ; not the answer to ours
    movzx eax, word [r12 + 3]
    rol ax, 8
    add eax, 5
    cmp eax, r13d
    jne .broken
    cmp byte [r12], SDP_ERROR_RSP
    je .error
    cmp byte [r12], SDP_SEARCH_ATTR_RSP
    jne .broken
    ; byte count, the bytes, continuation
    cmp r13d, 5 + 3
    jb .broken
    movzx ecx, word [r12 + 5]
    rol cx, 8
    lea eax, [rcx + 5 + 2 + 1]
    cmp eax, r13d
    ja .broken
    mov eax, [rbx + ubt_sdp_q.got]
    lea edx, [rax + rcx]
    cmp edx, SDP_ANSWER_MAX
    ja .broken
    lea rdi, [rbx + ubt_sdp_q.buf + rax]
    lea rsi, [r12 + 7]
    mov [rbx + ubt_sdp_q.got], edx
    push rcx
    rep movsb
    pop rcx
    ; more?
    lea rsi, [r12 + 7 + rcx]
    cmp byte [rsi], 0
    je .whole
    call sdp_q_send
    jmp .out
.whole:
    xor esi, esi
    lea rdx, [rbx + ubt_sdp_q.buf]
    mov ecx, [rbx + ubt_sdp_q.got]
    call sdp_q_done
    jmp .out
.error:
    cmp r13d, 7
    jb .broken
    movzx esi, word [r12 + 5]
    rol si, 8
    xor edx, edx
    xor ecx, ecx
    call sdp_q_done
    jmp .out
.broken:
    mov esi, SDP_E_SYNTAX
    xor edx, edx
    xor ecx, ecx
    call sdp_q_done
.out:
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_UBT_SDP_SDP_ASM
