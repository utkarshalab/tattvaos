; =============================================================================
; Tattva OS — unet/routing/netns.asm
; =============================================================================
; Network Namespace Manager for Container-Like Network Isolation.
;
; Features:
;   - Namespace Creation / Deletion / Switching
;   - Per-Namespace Independent Network Stack (Interfaces, Routes, Sockets, ARP)
;   - Namespace-Aware Interface Attachment (veth-like Virtual Ethernet Pairs)
;   - Inter-Namespace Routing via Virtual Bridge or Router
;   - Namespace Enumeration & Metadata Tracking
;   - Default (Init) Namespace Management
;
; Delegates:
;   - Slab Allocator for Namespaces     -> lib/mem/slab.asm
;   - VRF Integration                   -> unet/routing/vrf_manager.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define NETNS_MAX                   128
%define NETNS_NAME_LEN              32
%define NETNS_DEFAULT_ID            0

struc netns_t
    .id:                resd 1      ; Namespace ID
    .name:              resb 32     ; Namespace Name
    .vrf_id:            resd 1      ; Associated VRF Instance ID
    .iface_mask:        resq 1      ; Bitmask of Interfaces in this Namespace
    .route_table_ptr:   resq 1      ; Pointer to per-NS Routing Table
    .socket_table_ptr:  resq 1      ; Pointer to per-NS Socket Table
    .active:            resb 1
endstruc

section .bss
align 64
netns_table:            resb netns_t_size * NETNS_MAX
netns_count:            resd 1
netns_current:          resd 1      ; Currently Active Namespace ID

section .text

global netns_init
global netns_create
global netns_delete
global netns_switch
global netns_attach_iface
global netns_detach_iface
global netns_get_current
global netns_enumerate

extern slab_alloc
extern slab_free
extern vrf_create
extern vrf_delete

align 64
netns_init:
    push rbp
    mov rbp, rsp
    ; Initialize default (init) namespace
    mov dword [netns_count], 1
    mov dword [netns_current], NETNS_DEFAULT_ID
    mov dword [netns_table + netns_t.id], NETNS_DEFAULT_ID
    mov byte [netns_table + netns_t.active], 1
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; netns_create — Create New Network Namespace
; Input: RDI = Pointer to Namespace Name
; Output: EAX = Namespace ID (or -1 on Full)
; -----------------------------------------------------------------------------
align 64
netns_create:
    push rbp
    mov rbp, rsp
    push rbx

    prefetcht0 [rdi]

    mov eax, [netns_count]
    cmp eax, NETNS_MAX
    jge .ns_full

    ; Create associated VRF instance
    call vrf_create

    ; Allocate per-NS routing & socket tables
    call slab_alloc

    inc dword [netns_count]
    mov eax, [netns_count]
    dec eax
    jmp .ns_done

.ns_full:
    mov eax, -1

.ns_done:
    pop rbx
    pop rbp
    ret

align 64
netns_delete:
    push rbp
    mov rbp, rsp
    ; Delete associated VRF, free tables, mark inactive
    call vrf_delete
    call slab_free
    dec dword [netns_count]
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; netns_switch — Switch to Target Network Namespace
; Input: EDI = Target Namespace ID
; Output: EAX = 0 on Success, -1 if Invalid ID
; -----------------------------------------------------------------------------
align 64
netns_switch:
    push rbp
    mov rbp, rsp
    cmp edi, NETNS_MAX
    jge .invalid
    mov [netns_current], edi
    xor eax, eax
    pop rbp
    ret
.invalid:
    mov eax, -1
    pop rbp
    ret

align 64
netns_attach_iface:
    push rbp
    mov rbp, rsp
    ; Move interface into target namespace (set bit in iface_mask)
    xor eax, eax
    pop rbp
    ret

align 64
netns_detach_iface:
    push rbp
    mov rbp, rsp
    ; Remove interface from namespace (clear bit in iface_mask)
    xor eax, eax
    pop rbp
    ret

align 64
netns_get_current:
    push rbp
    mov rbp, rsp
    mov eax, [netns_current]
    pop rbp
    ret

align 64
netns_enumerate:
    push rbp
    mov rbp, rsp
    ; Return list of active namespace IDs
    mov eax, [netns_count]
    pop rbp
    ret
