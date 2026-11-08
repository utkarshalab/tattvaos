; =============================================================================
; Utkarsha OS — lib/ubt/gatt/db.asm — the GATT server's database
; =============================================================================
;   ubt_gatt_db_init(db)                       empty (handles from 1)
;   ubt_gatt_service(db, uuid, uuid_len, primary) → its handle
;   ubt_gatt_char(db, def) → the value's handle (EDX = its CCCD's, or 0)
;   ubt_gatt_desc(db, def) → its handle
;   ubt_gatt_set(db, handle, data, len)        a stored value changed
;   ubt_gatt_attr(db, handle) → the attribute, or 0
;   ubt_gatt_gap_gatt(db, name, len, appearance)   the GAP and GATT services
;   ubt_gatt_db_of(conn) → the database its adapter serves
;
; Attributes are kept in handle order; a value is either stored here (up
; to its maximum length) or read and written through the definition's
; functions. A characteristic that notifies or indicates gets its Client
; Characteristic Configuration descriptor, whose value is each link's own
; (att/server.asm keeps it).
; =============================================================================

%ifndef LIB_UBT_GATT_DB_ASM
%define LIB_UBT_GATT_DB_ASM

%define UBT_GATT_MAX        128     ; attributes
%define UBT_GATT_ARENA      4096    ; stored values and declarations

; attribute permissions (ubt_attr.perm)
%define ATT_PERM_READ       (1 << 0)
%define ATT_PERM_WRITE      (1 << 1)
%define ATT_PERM_READ_ENC   (1 << 2)    ; encryption needed to read
%define ATT_PERM_WRITE_ENC  (1 << 3)
%define ATT_PERM_READ_AUTH  (1 << 4)    ; an authenticated (MITM) link
%define ATT_PERM_WRITE_AUTH (1 << 5)
%define ATT_PERM_CCCD       (1 << 15)   ; ours: a per-link CCCD

; characteristic properties
%define GATT_PROP_BROADCAST (1 << 0)
%define GATT_PROP_READ      (1 << 1)
%define GATT_PROP_WRITE_NR  (1 << 2)    ; write without response
%define GATT_PROP_WRITE     (1 << 3)
%define GATT_PROP_NOTIFY    (1 << 4)
%define GATT_PROP_INDICATE  (1 << 5)
%define GATT_PROP_SIGNED    (1 << 6)    ; authenticated signed writes
%define GATT_PROP_EXT       (1 << 7)

; well-known UUIDs
%define GATT_PRIMARY        0x2800
%define GATT_SECONDARY      0x2801
%define GATT_INCLUDE        0x2802
%define GATT_CHARACTERISTIC 0x2803
%define GATT_CCCD           0x2902

struc ubt_attr
    .handle:        resw 1
    .perm:          resw 1
    .uuid_len:      resb 1          ; 2 or 16
    .props:         resb 1          ; a value's characteristic properties
    .pad:           resw 1
    .uuid:          resb 16         ; least significant first
    .value:         resq 1          ; the stored value (0: through read_fn)
    .len:           resw 1
    .max:           resw 1
    .pad2:          resd 1
    .read_fn:       resq 1          ; (conn, attr, offset, out, room) → EAX
                                    ; = length, or -(ATT error)
    .write_fn:      resq 1          ; (conn, attr, offset, data, len) → EAX
                                    ; = 0, or -(ATT error)
    .user:          resq 1
endstruc

; what ubt_gatt_char and ubt_gatt_desc are given
struc ubt_gatt_def
    .uuid:          resb 16
    .uuid_len:      resb 1
    .props:         resb 1
    .perm:          resw 1
    .len:           resw 1          ; the value's first length
    .max:           resw 1          ; and the most it may grow to
    .value:         resq 1          ; the first value (stored when no read_fn)
    .read_fn:       resq 1
    .write_fn:      resq 1
    .user:          resq 1
endstruc

struc ubt_gatt_db
    .count:         resd 1          ; attributes (the last handle)
    .used:          resd 1          ; bytes of the arena
    .attrs:         resb UBT_GATT_MAX * ubt_attr_size
    .arena:         resb UBT_GATT_ARENA
endstruc

section .bss
alignb 8
global ubt_gatt_default
ubt_gatt_default:   resb ubt_gatt_db_size

section .rodata
global ubt_gatt_layout
ubt_gatt_layout:
    dd ubt_attr_size, ubt_gatt_def_size, ubt_gatt_db_size, ubt_gatt_db.attrs
    dd ubt_attr.value, ubt_attr.read_fn, ubt_gatt_def.value, ubt_gatt_def.read_fn

section .text

; ubt_gatt_db_of — RDI = conn → RAX = its adapter's database (the shared one
; when it has none)
global ubt_gatt_db_of
ubt_gatt_db_of:
    mov rax, [rdi + ubt_conn.adapter]
    mov rax, [rax + ubt_adapter.gatt]
    test rax, rax
    jnz .out
    lea rax, [rel ubt_gatt_default]
.out:
    ret

; ubt_gatt_db_init — RDI = db: emptied
global ubt_gatt_db_init
ubt_gatt_db_init:
    mov ecx, ubt_gatt_db_size
    xor eax, eax
    rep stosb
    ret

; ubt_gatt_attr — RDI = db, ESI = handle → RAX = its attribute, or 0
global ubt_gatt_attr
ubt_gatt_attr:
    xor eax, eax
    test esi, esi
    jz .out
    cmp esi, [rdi + ubt_gatt_db.count]
    ja .out
    lea eax, [rsi - 1]
    imul eax, eax, ubt_attr_size
    lea rax, [rdi + ubt_gatt_db.attrs + rax]
.out:
    ret

; db_new — RDI = db, ESI = 16-bit type (0: none yet) → RAX = a new, zeroed
; attribute with the next handle, or 0 when full
db_new:
    mov eax, [rdi + ubt_gatt_db.count]
    cmp eax, UBT_GATT_MAX
    jae .full
    inc eax
    mov [rdi + ubt_gatt_db.count], eax
    lea ecx, [rax - 1]
    imul ecx, ecx, ubt_attr_size
    lea rcx, [rdi + ubt_gatt_db.attrs + rcx]
    push rdi
    push rax
    mov rdi, rcx
    push rcx
    mov ecx, ubt_attr_size
    xor eax, eax
    rep stosb
    pop rcx
    pop rax
    pop rdi
    mov [rcx + ubt_attr.handle], ax
    mov byte [rcx + ubt_attr.uuid_len], 2
    mov [rcx + ubt_attr.uuid], si
    mov word [rcx + ubt_attr.perm], ATT_PERM_READ
    mov rax, rcx
    ret
.full:
    xor eax, eax
    ret

; db_store — RDI = db, RSI = data (0: zeros), EDX = length, ECX = room
; → RAX = where it is kept in the arena, or 0 when it is full
db_store:
    cmp edx, ecx
    jbe .fits
    mov edx, ecx
.fits:
    mov eax, [rdi + ubt_gatt_db.used]
    lea r8d, [rax + rcx]
    cmp r8d, UBT_GATT_ARENA
    ja .full
    mov [rdi + ubt_gatt_db.used], r8d
    lea rax, [rdi + ubt_gatt_db.arena + rax]
    push rax
    mov rdi, rax
    test rsi, rsi
    jz .zero
    mov ecx, edx
    rep movsb
    jmp .out
.zero:
    xor eax, eax
    mov ecx, edx
    rep stosb
.out:
    pop rax
    ret
.full:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ubt_gatt_service — RDI = db, RSI = UUID (least significant first), EDX = 2
;                    or 16, ECX = 1 primary, 0 secondary → EAX = its handle
;                    (0: full)
; -----------------------------------------------------------------------------
global ubt_gatt_service
ubt_gatt_service:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov esi, GATT_SECONDARY
    test ecx, ecx
    jz .type
    mov esi, GATT_PRIMARY
.type:
    call db_new
    test rax, rax
    jz .full
    mov r14, rax
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    mov ecx, r13d
    call db_store
    test rax, rax
    jz .full
    mov [r14 + ubt_attr.value], rax
    mov [r14 + ubt_attr.len], r13w
    mov [r14 + ubt_attr.max], r13w
    movzx eax, word [r14 + ubt_attr.handle]
    jmp .out
.full:
    xor eax, eax
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; db_value — RBX = db, R12 = def, R14 = the attribute: the def's UUID,
; permissions, value (stored or through its functions) → CF = 1 when full
db_value:
    sub rsp, 8
    movzx eax, byte [r12 + ubt_gatt_def.uuid_len]
    mov [r14 + ubt_attr.uuid_len], al
    movdqu xmm0, [r12 + ubt_gatt_def.uuid]
    movdqu [r14 + ubt_attr.uuid], xmm0
    mov ax, [r12 + ubt_gatt_def.perm]
    mov [r14 + ubt_attr.perm], ax
    mov al, [r12 + ubt_gatt_def.props]
    mov [r14 + ubt_attr.props], al
    mov rax, [r12 + ubt_gatt_def.read_fn]
    mov [r14 + ubt_attr.read_fn], rax
    mov rax, [r12 + ubt_gatt_def.write_fn]
    mov [r14 + ubt_attr.write_fn], rax
    mov rax, [r12 + ubt_gatt_def.user]
    mov [r14 + ubt_attr.user], rax
    cmp qword [r12 + ubt_gatt_def.read_fn], 0
    jne .done
    movzx ecx, word [r12 + ubt_gatt_def.max]
    movzx edx, word [r12 + ubt_gatt_def.len]
    cmp ecx, edx
    jae .room
    mov ecx, edx
.room:
    mov [r14 + ubt_attr.max], cx
    mov [r14 + ubt_attr.len], dx
    mov rdi, rbx
    mov rsi, [r12 + ubt_gatt_def.value]
    call db_store
    test rax, rax
    jz .full
    mov [r14 + ubt_attr.value], rax
.done:
    add rsp, 8
    clc
    ret
.full:
    add rsp, 8
    stc
    ret

; -----------------------------------------------------------------------------
; ubt_gatt_char — RDI = db, RSI = ubt_gatt_def → EAX = the value's handle
;                 (0: full), EDX = its CCCD's handle (0: none)
; -----------------------------------------------------------------------------
global ubt_gatt_char
ubt_gatt_char:
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 32                         ; the declaration's value
    mov rbx, rdi
    mov r12, rsi
    ; the declaration: properties, the value's handle, its UUID
    mov rdi, rbx
    mov esi, GATT_CHARACTERISTIC
    call db_new
    test rax, rax
    jz .full
    mov r13, rax
    mov al, [r12 + ubt_gatt_def.props]
    mov [rsp], al
    movzx eax, word [r13 + ubt_attr.handle]
    inc eax
    mov [rsp + 1], ax
    movdqu xmm0, [r12 + ubt_gatt_def.uuid]
    movdqu [rsp + 3], xmm0
    movzx edx, byte [r12 + ubt_gatt_def.uuid_len]
    add edx, 3
    mov [r13 + ubt_attr.len], dx
    mov [r13 + ubt_attr.max], dx
    mov rdi, rbx
    mov rsi, rsp
    mov ecx, edx
    call db_store
    test rax, rax
    jz .full
    mov [r13 + ubt_attr.value], rax
    ; the value
    mov rdi, rbx
    xor esi, esi
    call db_new
    test rax, rax
    jz .full
    mov r14, rax
    call db_value
    jc .full
    movzx r15d, word [r14 + ubt_attr.handle]
    ; its CCCD when it notifies or indicates
    xor edx, edx
    test byte [r12 + ubt_gatt_def.props], GATT_PROP_NOTIFY | GATT_PROP_INDICATE
    jz .done
    mov rdi, rbx
    mov esi, GATT_CCCD
    call db_new
    test rax, rax
    jz .full
    mov word [rax + ubt_attr.perm], ATT_PERM_READ | ATT_PERM_WRITE | ATT_PERM_CCCD
    mov word [rax + ubt_attr.len], 2
    mov word [rax + ubt_attr.max], 2
    movzx edx, word [rax + ubt_attr.handle]
.done:
    mov eax, r15d
    jmp .out
.full:
    xor eax, eax
    xor edx, edx
.out:
    add rsp, 32
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_gatt_desc — RDI = db, RSI = ubt_gatt_def → EAX = its handle (0: full)
global ubt_gatt_desc
ubt_gatt_desc:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov rbx, rdi
    mov r12, rsi
    xor esi, esi
    call db_new
    test rax, rax
    jz .full
    mov r14, rax
    call db_value
    jc .full
    movzx eax, word [r14 + ubt_attr.handle]
    jmp .out
.full:
    xor eax, eax
.out:
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; ubt_gatt_set — RDI = db, ESI = handle, RDX = data, ECX = length (cut to
; the attribute's maximum) → EAX = 0, or -1 (no such stored value)
global ubt_gatt_set
ubt_gatt_set:
    push rdx
    push rcx
    call ubt_gatt_attr
    pop rcx
    pop rsi
    test rax, rax
    jz .bad
    mov rdi, [rax + ubt_attr.value]
    test rdi, rdi
    jz .bad
    movzx edx, word [rax + ubt_attr.max]
    cmp ecx, edx
    jbe .len
    mov ecx, edx
.len:
    mov [rax + ubt_attr.len], cx
    rep movsb
    xor eax, eax
    ret
.bad:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; ubt_gatt_gap_gatt — RDI = db, RSI = device name, EDX = its length, ECX =
;   appearance: the GAP service (Device Name, Appearance) and the GATT
;   service (Service Changed, indicated) → EAX = Service Changed's handle
; -----------------------------------------------------------------------------
global ubt_gatt_gap_gatt
ubt_gatt_gap_gatt:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 88                         ; a ubt_gatt_def, a UUID, appearance
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov [rsp + 80], cx
    ; GAP
    mov word [rsp + 72], 0x1800
    mov rdi, rbx
    lea rsi, [rsp + 72]
    mov edx, 2
    mov ecx, 1
    call ubt_gatt_service
    call .def
    mov word [rsp + ubt_gatt_def.uuid], 0x2A00          ; Device Name
    mov byte [rsp + ubt_gatt_def.props], GATT_PROP_READ
    mov [rsp + ubt_gatt_def.len], r13w
    mov word [rsp + ubt_gatt_def.max], 248
    mov [rsp + ubt_gatt_def.value], r12
    mov rdi, rbx
    mov rsi, rsp
    call ubt_gatt_char
    call .def
    mov word [rsp + ubt_gatt_def.uuid], 0x2A01          ; Appearance
    mov byte [rsp + ubt_gatt_def.props], GATT_PROP_READ
    mov word [rsp + ubt_gatt_def.len], 2
    mov word [rsp + ubt_gatt_def.max], 2
    lea rax, [rsp + 80]
    mov [rsp + ubt_gatt_def.value], rax
    mov rdi, rbx
    mov rsi, rsp
    call ubt_gatt_char
    ; GATT: Service Changed (start, end), indicated
    mov word [rsp + 72], 0x1801
    mov rdi, rbx
    lea rsi, [rsp + 72]
    mov edx, 2
    mov ecx, 1
    call ubt_gatt_service
    call .def
    mov word [rsp + ubt_gatt_def.uuid], 0x2A05
    mov byte [rsp + ubt_gatt_def.props], GATT_PROP_INDICATE
    mov word [rsp + ubt_gatt_def.perm], 0
    mov word [rsp + ubt_gatt_def.len], 4
    mov word [rsp + ubt_gatt_def.max], 4
    mov qword [rsp + ubt_gatt_def.value], 0
    mov rdi, rbx
    mov rsi, rsp
    call ubt_gatt_char
    add rsp, 88
    pop r14
    pop r13
    pop r12
    pop rbx
    ret
; a clean def (one call deep: it is at [rsp + 8]), 16-bit UUID, readable
.def:
    xor eax, eax
%assign o 8
%rep 7
    mov [rsp + o], rax
%assign o o + 8
%endrep
    mov byte [rsp + 8 + ubt_gatt_def.uuid_len], 2
    mov word [rsp + 8 + ubt_gatt_def.perm], ATT_PERM_READ
    ret

%endif ; LIB_UBT_GATT_DB_ASM
