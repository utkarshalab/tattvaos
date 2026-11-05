; ============================================================================
; Regions — Clients' Region Objects (cw_region)
; ============================================================================
; A client makes regions, adds and subtracts rectangles, and gives them to a
; surface as its opaque or input region, which takes a copy. Each region is
; its client's: it lives in the client's arena, so a disconnect frees it, and
; its handle resolves only for that client. Server.region_table holds
; ClientRegion records; Client.regions lists a client's own.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern handle_create
extern handle_destroy
extern handle_resolve
extern handle_table_init
extern region_add_rect
extern region_clear
extern region_init
extern region_subtract_rect

%define REGION_HANDLES  1024

struc ClientRegion
    .region:        resq 1      ; the ugfx Region
    .client:        resq 1      ; whose it is
    .next:          resq 1      ; Client.regions
    .handle:        resq 1
endstruc

section .text

; ---------------------------------------------------------------------------
; regions_init
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0, -ENOMEM
; ---------------------------------------------------------------------------
global regions_init
regions_init:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    mov esi, 48
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, r13
    mov rsi, r12
    mov edx, REGION_HANDLES
    call handle_table_init
    test rax, rax
    js .out
    mov [rbx + Server.region_table], r13
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; regions_create
;   A new empty region for a client
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = its handle, -ENOMEM
; ---------------------------------------------------------------------------
global regions_create
regions_create:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov rdi, [r12 + Client.arena]
    mov esi, ClientRegion_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov [r13 + ClientRegion.client], r12
    mov rdi, [r12 + Client.arena]
    call region_init
    test rax, rax
    jz .oom
    mov [r13 + ClientRegion.region], rax
    mov rdi, [rbx + Server.region_table]
    mov rsi, r13
    call handle_create
    test rax, rax
    jz .oom
    mov [r13 + ClientRegion.handle], rax
    mov rcx, [r12 + Client.regions]
    mov [r13 + ClientRegion.next], rcx
    mov [r12 + Client.regions], r13
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; regions_own
;   A client's own region from its handle
;   IN:  rdi = server*, rsi = client*, edx = handle
;   OUT: rax = Region*, 0 if there is no such region of that client's
; ---------------------------------------------------------------------------
global regions_own
regions_own:
    push rbx
    mov rbx, rsi
    mov rdi, [rdi + Server.region_table]
    mov esi, edx
    call handle_resolve
    test rax, rax
    jz .out
    cmp [rax + ClientRegion.client], rbx
    jne .none
    mov rax, [rax + ClientRegion.region]
    jmp .out
.none:
    xor eax, eax
.out:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; regions_destroy
;   IN:  rdi = server*, rsi = client*, edx = handle
;   OUT: rax = 0, -ENOENT if it is not that client's
; ---------------------------------------------------------------------------
global regions_destroy
regions_destroy:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    mov rdi, [rbx + Server.region_table]
    mov esi, r13d
    call handle_resolve
    test rax, rax
    jz .missing
    cmp [rax + ClientRegion.client], r12
    jne .missing
    lea rcx, [r12 + Client.regions]     ; off the client's list
.find:
    mov rdx, [rcx]
    test rdx, rdx
    jz .unlinked
    cmp rdx, rax
    je .unlink
    lea rcx, [rdx + ClientRegion.next]
    jmp .find
.unlink:
    mov rdx, [rax + ClientRegion.next]
    mov [rcx], rdx
.unlinked:
    mov rdi, [rbx + Server.region_table]
    mov esi, r13d
    call handle_destroy
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.missing:
    mov rax, -(ENOENT)
    jmp .out

; ---------------------------------------------------------------------------
; regions_destroy_client
;   A client going: every handle of its regions goes (their memory goes with
;   its arena)
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global regions_destroy_client
regions_destroy_client:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12, [rsi + Client.regions]
    mov qword [rsi + Client.regions], 0
.next:
    test r12, r12
    jz .done
    mov rdi, [rbx + Server.region_table]
    mov rsi, [r12 + ClientRegion.handle]
    call handle_destroy
    mov r12, [r12 + ClientRegion.next]
    jmp .next
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12

; ---------------------------------------------------------------------------
; regions_add, regions_subtract
;   IN:  rdi = Region*, rsi = rect* (x, y, width, height)
;   OUT: rax = 0, negative error
; regions_clear
;   IN:  rdi = Region*
; ---------------------------------------------------------------------------
global regions_add
regions_add:
    cmp dword [rsi + 8], 0              ; no width or height: nothing to add
    jle .empty
    cmp dword [rsi + 12], 0
    jle .empty
    jmp region_add_rect
.empty:
    xor eax, eax
    ret

global regions_subtract
regions_subtract:
    jmp region_subtract_rect

global regions_clear
regions_clear:
    jmp region_clear

section .data
global regions_version
regions_version: dq 0x020000
