; =============================================================================
; Utkarsha OS — lib/ubt/sm/keys.asm — the bond store
; =============================================================================
;   ubt_key_find(addr, type) → entry       by address; a resolvable private
;                                          address is resolved with the IRKs
;   ubt_key_get(addr, type) → entry        found, or a new one
;   ubt_key_add(entry)                     a saved bond put back (at boot)
;   ubt_key_forget(addr, type)
;   ubt_key_saved(entry)                   it changed: ubt_key_fn is told
;   ubt_key_resolve(addr) → entry          whose IRK made this address
;
; One entry per peer, BR/EDR and LE keys together. Keys are kept least
; significant octet first, as HCI and SMP carry them. What keeps them over
; a restart is the hook's business (the files under /sec/keys/bt/).
; =============================================================================

%ifndef LIB_UBT_SM_KEYS_ASM
%define LIB_UBT_SM_KEYS_ASM

%define UBT_MAX_KEYS        32

; ubt_key.flags
%define KEY_MITM            (1 << 0)    ; authenticated pairing
%define KEY_SC              (1 << 1)    ; Secure Connections
%define KEY_LINK            (1 << 2)    ; a BR/EDR link key
%define KEY_LTK             (1 << 3)    ; the peer's LTK (we encrypt with it
                                        ; as central)
%define KEY_OUR_LTK         (1 << 4)    ; the LTK we gave (asked for as
                                        ; peripheral)
%define KEY_IRK             (1 << 5)    ; the peer's identity key and address
%define KEY_CSRK            (1 << 6)    ; the peer's signing key

struc ubt_key
    .used:          resb 1
    .peer_type:     resb 1          ; LE address type (BR/EDR: 0)
    .flags:         resb 1          ; KEY_*
    .key_size:      resb 1
    .link_type:     resb 1          ; the HCI link key type
    .pad:           resb 1
    .peer:          resb 6
    .ediv:          resw 1          ; the peer's LTK's EDIV and Rand
    .our_ediv:      resw 1          ; ... and ours
    .rand:          resq 1
    .our_rand:      resq 1
    .ltk:           resb 16
    .our_ltk:       resb 16
    .irk:           resb 16
    .csrk:          resb 16
    .link_key:      resb 16
    .id_addr:       resb 6
    .id_type:       resb 1
    .pad2:          resb 1
    .sign_count:    resd 1          ; the peer's signed write counter
    .pad3:          resd 1
endstruc

section .bss
alignb 8
global ubt_keys
ubt_keys:           resb UBT_MAX_KEYS * ubt_key_size
global ubt_key_fn
ubt_key_fn:         resq 1          ; (entry): keep it; (entry with used = 0):
                                    ; forget it

section .text

; ubt_key_same — RDI = entry, RSI = address, EDX = type → ZF = 1 when it is
; that peer (its address, or its identity address)
ubt_key_same:
    mov eax, [rdi + ubt_key.peer]
    cmp eax, [rsi]
    jne .identity
    mov ax, [rdi + ubt_key.peer + 4]
    cmp ax, [rsi + 4]
    jne .identity
    cmp [rdi + ubt_key.peer_type], dl
    ret
.identity:
    test byte [rdi + ubt_key.flags], KEY_IRK
    jz .no
    mov eax, [rdi + ubt_key.id_addr]
    cmp eax, [rsi]
    jne .no
    mov ax, [rdi + ubt_key.id_addr + 4]
    cmp ax, [rsi + 4]
    jne .no
    cmp [rdi + ubt_key.id_type], dl
    ret
.no:
    or eax, 1                           ; ZF = 0
    ret

; -----------------------------------------------------------------------------
; ubt_key_find — RSI = address (6, least significant first), EDX = type
;   (RDI unused) → RAX = the entry, or 0
; -----------------------------------------------------------------------------
global ubt_key_find
ubt_key_find:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, edx
    lea rbx, [rel ubt_keys]
    xor ecx, ecx
.next:
    cmp ecx, UBT_MAX_KEYS
    jae .resolve
    cmp byte [rbx + ubt_key.used], 0
    je .skip
    push rcx
    mov rdi, rbx
    mov rsi, r12
    mov edx, r13d
    call ubt_key_same
    pop rcx
    je .found
.skip:
    add rbx, ubt_key_size
    inc ecx
    jmp .next
.resolve:
    ; a random resolvable address (top bits 01): whose IRK made it
    xor eax, eax
    cmp r13d, 1
    jne .out
    mov rdi, r12
    call ubt_key_resolve
    jmp .out
.found:
    mov rax, rbx
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_key_resolve — RDI = a random address → RAX = the entry whose IRK
;   resolves it, or 0. hash = ah(IRK, prand): the address is hash (its low
;   24 bits) then prand (high 24, top bits 01).
; -----------------------------------------------------------------------------
global ubt_key_resolve
ubt_key_resolve:
    push rbx
    push r12
    push r13
    sub rsp, 48                         ; [rsp] IRK (most significant first),
                                        ; [+16] prand, [+24] hash
    mov r12, rdi
    xor eax, eax
    mov cl, [r12 + 5]
    and cl, 0xC0
    cmp cl, 0x40
    jne .out
    ; prand most significant first: address bytes 5, 4, 3
    mov al, [r12 + 5]
    mov [rsp + 16], al
    mov al, [r12 + 4]
    mov [rsp + 17], al
    mov al, [r12 + 3]
    mov [rsp + 18], al
    lea rbx, [rel ubt_keys]
    xor r13d, r13d
.next:
    xor eax, eax
    cmp r13d, UBT_MAX_KEYS
    jae .out
    cmp byte [rbx + ubt_key.used], 0
    je .skip
    test byte [rbx + ubt_key.flags], KEY_IRK
    jz .skip
    xor ecx, ecx
.irk:
    mov al, [rbx + ubt_key.irk + rcx]
    mov edx, 15
    sub edx, ecx
    mov [rsp + rdx], al
    inc ecx
    cmp ecx, 16
    jb .irk
    mov rdi, rsp
    lea rsi, [rsp + 16]
    lea rdx, [rsp + 24]
    call ubt_ah
    ; the hash most significant first against address bytes 2, 1, 0
    mov al, [rsp + 24]
    cmp al, [r12 + 2]
    jne .skip
    mov al, [rsp + 25]
    cmp al, [r12 + 1]
    jne .skip
    mov al, [rsp + 26]
    cmp al, [r12]
    jne .skip
    mov rax, rbx
    jmp .out
.skip:
    add rbx, ubt_key_size
    inc r13d
    jmp .next
.out:
    pxor xmm0, xmm0
    movdqu [rsp], xmm0
    add rsp, 48
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ubt_key_get — RSI = address, EDX = type → RAX = its entry, a new one when
;   it has none, 0 when the store is full
; -----------------------------------------------------------------------------
global ubt_key_get
ubt_key_get:
    push rbx
    push r12
    push r13
    mov r12, rsi
    mov r13d, edx
    call ubt_key_find
    test rax, rax
    jnz .out
    lea rbx, [rel ubt_keys]
    xor ecx, ecx
.slot:
    cmp ecx, UBT_MAX_KEYS
    jae .full
    cmp byte [rbx + ubt_key.used], 0
    je .new
    add rbx, ubt_key_size
    inc ecx
    jmp .slot
.new:
    mov rdi, rbx
    mov ecx, ubt_key_size
    xor eax, eax
    rep stosb
    mov byte [rbx + ubt_key.used], 1
    mov [rbx + ubt_key.peer_type], r13b
    mov eax, [r12]
    mov [rbx + ubt_key.peer], eax
    mov ax, [r12 + 4]
    mov [rbx + ubt_key.peer + 4], ax
    mov rax, rbx
    jmp .out
.full:
    xor eax, eax
.out:
    pop r13
    pop r12
    pop rbx
    ret

; ubt_key_add — RDI = a whole entry (from storage): copied in → RAX = where,
; or 0 (full)
global ubt_key_add
ubt_key_add:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    lea rsi, [r12 + ubt_key.peer]
    movzx edx, byte [r12 + ubt_key.peer_type]
    call ubt_key_get
    test rax, rax
    jz .out
    mov rbx, rax
    mov rdi, rbx
    mov rsi, r12
    mov ecx, ubt_key_size
    rep movsb
    mov byte [rbx + ubt_key.used], 1
    mov rax, rbx
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; ubt_key_saved — RDI = entry: ubt_key_fn keeps it
global ubt_key_saved
ubt_key_saved:
    mov rax, [rel ubt_key_fn]
    test rax, rax
    jz .out
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; ubt_key_forget — RSI = address, EDX = type: its entry wiped, the hook told
global ubt_key_forget
ubt_key_forget:
    push rbx
    call ubt_key_find
    test rax, rax
    jz .out
    mov rbx, rax
    mov rdi, rbx
    mov ecx, ubt_key_size
    xor eax, eax
    rep stosb
    mov rdi, rbx
    call ubt_key_saved
.out:
    pop rbx
    ret

%endif ; LIB_UBT_SM_KEYS_ASM
