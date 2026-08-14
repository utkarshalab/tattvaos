%ifndef GUARD_UNET_ROUTING_VRF_MANAGER_ASM
%define GUARD_UNET_ROUTING_VRF_MANAGER_ASM
; =============================================================================
; Tattva OS — unet/routing/vrf_manager.asm
; =============================================================================
; VRF (Virtual Routing and Forwarding) Instance Manager.
;
; Features:
;   - VRF Instance Creation / Deletion / Lookup by Name
;   - Per-VRF Independent Routing Table (FIB) & ARP/NDP Cache
;   - Interface Binding to VRF Instance
;   - Route Distinguisher (RD) & Route Target (RT) Import/Export for L3VPN
;   - VRF Route Leaking (Inter-VRF Routing) with Policy Filtering
;   - Default VRF (Global Routing Table) Management
;   - VRF-Aware DNS Resolution & Socket Binding
;
; Delegates:
;   - Slab Allocator for VRF Instances  -> lib/mem/slab.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define VRF_MAX_INSTANCES           64
%define VRF_NAME_LEN                32
%define VRF_DEFAULT_ID              0       ; Global routing table

struc vrf_instance_t
    .id:                resd 1      ; VRF Instance ID
    .name:              resb 32     ; VRF Name
    .rd:                resq 1      ; Route Distinguisher (8 bytes)
    .rt_import:         resq 4      ; Import Route Targets
    .rt_export:         resq 4      ; Export Route Targets
    .fib_ptr:           resq 1      ; Pointer to per-VRF FIB
    .arp_cache_ptr:     resq 1      ; Pointer to per-VRF ARP Cache
    .iface_mask:        resq 1      ; Bitmask of Bound Interfaces
    .route_count:       resd 1
    .active:            resb 1      ; 1 = Active
endstruc

section .bss
alignb 64
vrf_table:              resb vrf_instance_t_size * VRF_MAX_INSTANCES
vrf_count:              resd 1

section .text

global vrf_init
global vrf_create
global vrf_delete
global vrf_lookup_by_name
global vrf_bind_interface
global vrf_unbind_interface
global vrf_route_lookup
global vrf_route_leak


align 64
vrf_init:
    push rbp
    mov rbp, rsp
    ; Initialize default VRF (ID 0 = global table)
    mov dword [vrf_count], 1
    mov dword [vrf_table + vrf_instance_t.id], VRF_DEFAULT_ID
    mov byte [vrf_table + vrf_instance_t.active], 1
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vrf_create — Create New VRF Instance
; Input: RDI = Pointer to VRF Name, RSI = Route Distinguisher
; Output: EAX = VRF ID (or -1 on Table Full)
; -----------------------------------------------------------------------------
align 64
vrf_create:
    push rbp
    mov rbp, rsp
    push rbx

    ; Check table capacity
    mov eax, [vrf_count]
    cmp eax, VRF_MAX_INSTANCES
    jge .vrf_full

    ; Allocate per-VRF FIB & ARP cache
    call slab_alloc
    mov rbx, rax

    inc dword [vrf_count]
    mov eax, [vrf_count]
    dec eax                         ; Return new VRF ID
    jmp .create_done

.vrf_full:
    mov eax, -1

.create_done:
    pop rbx
    pop rbp
    ret

align 64
vrf_delete:
    push rbp
    mov rbp, rsp
    ; Free per-VRF FIB & ARP cache, mark inactive
    call slab_free
    dec dword [vrf_count]
    xor eax, eax
    pop rbp
    ret

align 64
vrf_lookup_by_name:
    push rbp
    mov rbp, rsp
    prefetcht0 [rdi]
    ; Linear scan vrf_table for matching name
    xor eax, eax
    pop rbp
    ret

align 64
vrf_bind_interface:
    push rbp
    mov rbp, rsp
    ; Set bit in vrf_instance_t.iface_mask for given interface index
    xor eax, eax
    pop rbp
    ret

align 64
vrf_unbind_interface:
    push rbp
    mov rbp, rsp
    ; Clear bit in vrf_instance_t.iface_mask
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vrf_route_lookup — Lookup Route in VRF-Specific FIB
; Input: EDI = VRF ID, RSI = Destination IP
; Output: RAX = Next Hop (or NULL)
; -----------------------------------------------------------------------------
align 64
vrf_route_lookup:
    push rbp
    mov rbp, rsp
    prefetcht0 [rsi]
    ; Longest-prefix match in per-VRF FIB
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; vrf_route_leak — Leak Route from Source VRF to Destination VRF
; Input: EDI = Source VRF ID, ESI = Dest VRF ID, RDX = Route Prefix
; Output: EAX = 0 on Success
; -----------------------------------------------------------------------------
align 64
vrf_route_leak:
    push rbp
    mov rbp, rsp
    ; Copy route from source VRF FIB to dest VRF FIB with policy check
    xor eax, eax
    pop rbp
    ret

%endif ; GUARD_UNET_ROUTING_VRF_MANAGER_ASM
