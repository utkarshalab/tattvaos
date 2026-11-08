; =============================================================================
; Utkarsha OS — lib/ubt/tr/mem.asm — an in-memory transport
; =============================================================================
; An adapter whose controller is code, not hardware: commands and ACL
; packets go to hooks, and events and ACL packets come back through
; ubt_hci_event and ubt_acl_input. The host tests put a virtual radio
; behind it (two adapters talking to each other); later, sim/ does.
;
;   ubt_mem_adapter(ctx)    a new adapter on this transport (down; the
;                           caller brings it up with ubt_hci_init)
;   ubt_mem_remove(adapter) its links closed, off the list, freed
;
; Hooks: ubt_mem_cmd_fn(adapter, bytes, length), ubt_mem_acl_fn(adapter,
; packet, length) → 0 or -UBT_EBUSY, ubt_mem_poll_fn(adapter).
; =============================================================================

%ifndef LIB_UBT_TR_MEM_ASM
%define LIB_UBT_TR_MEM_ASM

section .bss
alignb 8
global ubt_mem_cmd_fn
ubt_mem_cmd_fn:     resq 1
global ubt_mem_acl_fn
ubt_mem_acl_fn:     resq 1
global ubt_mem_poll_fn
ubt_mem_poll_fn:    resq 1

section .text

; -----------------------------------------------------------------------------
; ubt_mem_adapter — RDI = the transport's context → RAX = adapter, or 0
; -----------------------------------------------------------------------------
global ubt_mem_adapter
ubt_mem_adapter:
    push rbx
    push r12
    sub rsp, 8
    mov r12, rdi
    xor eax, eax
    cmp dword [rel ubt_adapter_total], UBT_MAX_ADAPTERS
    jae .out
    mov edi, ubt_adapter_size
    mov esi, 8
    call usb_alloc
    test rax, rax
    jz .out
    mov rbx, rax
    mov [rbx + ubt_adapter.tr_ctx], r12
    lea rax, [rel ubt_mem_cmd]
    mov [rbx + ubt_adapter.tr_cmd], rax
    lea rax, [rel ubt_mem_acl]
    mov [rbx + ubt_adapter.tr_acl], rax
    lea rax, [rel ubt_mem_poll]
    mov [rbx + ubt_adapter.tr_poll], rax
    mov eax, [rel ubt_next_index]
    mov [rbx + ubt_adapter.index], eax
    inc dword [rel ubt_next_index]
    mov eax, [rel ubt_adapter_total]
    lea rcx, [rel ubt_adapters]
    mov [rcx + rax * 8], rbx
    inc dword [rel ubt_adapter_total]
    mov rax, rbx
.out:
    add rsp, 8
    pop r12
    pop rbx
    ret

; the transport's functions: through the hooks
ubt_mem_cmd:
    mov rax, [rel ubt_mem_cmd_fn]
    test rax, rax
    jz .none
    push rdx
    call rax
    pop rax                             ; the length: all of it sent
    ret
.none:
    mov eax, -UBT_EIO
    ret

ubt_mem_acl:
    push rbx
    mov rbx, rdi
    mov rax, [rel ubt_mem_acl_fn]
    test rax, rax
    jz .none
    call rax
    test eax, eax
    jnz .out
    inc dword [rbx + ubt_adapter.acl_tx]
    jmp .out
.none:
    mov eax, -UBT_EIO
.out:
    pop rbx
    ret

ubt_mem_poll:
    mov rax, [rel ubt_mem_poll_fn]
    test rax, rax
    jz .out
    sub rsp, 8
    call rax
    add rsp, 8
.out:
    ret

; -----------------------------------------------------------------------------
; ubt_mem_remove — RDI = adapter
; -----------------------------------------------------------------------------
global ubt_mem_remove
ubt_mem_remove:
    push rbx
    mov rbx, rdi
    xor ecx, ecx
    lea rdx, [rel ubt_adapters]
.find:
    cmp ecx, [rel ubt_adapter_total]
    jae .out
    cmp [rdx + rcx * 8], rbx
    je .unlist
    inc ecx
    jmp .find
.unlist:
    dec dword [rel ubt_adapter_total]
.shift:
    cmp ecx, [rel ubt_adapter_total]
    jae .free
    mov rax, [rdx + rcx * 8 + 8]
    mov [rdx + rcx * 8], rax
    inc ecx
    jmp .shift
.free:
    mov dword [rbx + ubt_adapter.state], UBT_GONE
    call ubt_conns_drop
    mov rdi, rbx
    mov esi, ubt_adapter_size
    mov edx, 8
    call usb_free
.out:
    pop rbx
    ret

%endif ; LIB_UBT_TR_MEM_ASM
