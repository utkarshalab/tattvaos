%ifndef GUARD_VERTEX_NETWORK_ASM
%define GUARD_VERTEX_NETWORK_ASM
; =============================================================================
; vertex-agent — Network Manager
; =============================================================================
; Pod sandbox network namespaces, CNI-compatible operations
; Built on unet (native, no CNI plugins needed)
; =============================================================================

[BITS 64]

%include "net/unet/unet.inc"
%include "serve/niti/niti.inc"
%include "lib/ulib/map.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_network_init — Initialize network manager
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_network_init
vertex_network_init:
    push rbx
    push r12

    ; Network namespace map (netns_id -> netns_state)
    mov rdi, 2048
    call map_create
    test rax, rax
    jz .fail
    mov [netns_map], rax

    ; Pod IP pool (from node CIDR)
    call vertex_network_init_ipam

    ; Initialize niti firewall integration
    call vertex_network_niti_init

    pop r12
    pop rbx
    mov rax, 1
    ret

.fail:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_network_namespace_create — Create pod network namespace
; Inputs:
;   RDI = pause_fiber_handle
;   RSI = pod_ip (optional, 0 = auto-allocate)
; Returns: RAX = netns_handle, or 0
; -----------------------------------------------------------------------------
global vertex_network_namespace_create
vertex_network_namespace_create:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi      ; pause_fiber
    mov r13, rsi      ; pod_ip (or 0)

    ; 1. Allocate IP if not provided
    test r13, r13
    jnz .have_ip
    call vertex_network_ipam_allocate
    test rax, rax
    jz .fail
    mov r13, rax

.have_ip:
    ; 2. Create unet namespace
    mov rdi, r12
    mov rsi, r13
    mov rdx, NETNS_TYPE_POD
    call unet_namespace_create
    test rax, rax
    jz .fail
    mov r14, rax      ; netns_handle

    ; 3. Setup loopback
    mov rdi, r14
    mov rsi, 0x7F000001       ; 127.0.0.1
    mov rdx, 0xFF000000       ; /8
    call unet_interface_add
    test rax, rax
    jz .fail_loopback

    ; 4. Create veth pair to node bridge
    mov rdi, r14
    mov rsi, node_bridge_name
    call unet_veth_create
    test rax, rax
    jz .fail_veth
    mov rbx, rax      ; host_veth_iface

    ; 5. Configure pod-side interface
    mov rdi, r14
    mov rsi, rbx
    mov rdx, r13      ; pod_ip
    mov rcx, pod_netmask
    call unet_interface_configure
    test rax, rax
    jz .fail_config

    ; 6. Setup default route via gateway
    mov rdi, r14
    mov rsi, pod_gateway
    call unet_route_add
    test rax, rax
    jz .fail_route

    ; 7. Apply NetworkPolicy rules (from vertex-apiserver via niti)
    call vertex_network_apply_policies

    ; 8. Store netns state
    call vertex_network_store_netns

    mov rax, r14
    jmp .done

.fail_route:
.fail_config:
.fail_veth:
    call unet_namespace_destroy
.fail_loopback:
.fail:
    xor rax, rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_network_namespace_destroy — Destroy pod network namespace
; Inputs: RDI = netns_handle
; -----------------------------------------------------------------------------
global vertex_network_namespace_destroy
vertex_network_namespace_destroy:
    push rbx
    push r12

    mov r12, rdi

    ; Release IP
    mov rdi, [r12 + netns_state.pod_ip]
    call vertex_network_ipam_release

    ; Remove niti rules
    mov rdi, r12
    call vertex_network_remove_policies

    ; Destroy unet namespace
    mov rdi, r12
    call unet_namespace_destroy

    ; Remove from map
    mov rdi, [netns_map]
    mov rsi, [r12 + netns_state.netns_id]
    call map_remove

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_network_get_stats — Get network stats for pod/container
; Inputs: RDI = netns_handle, RSI = stats_out (BXP)
; -----------------------------------------------------------------------------
global vertex_network_get_stats
vertex_network_get_stats:
    push rbx
    push r12

    mov r12, rdi
    mov r13, rsi

    ; Collect from unet counters
    mov rdi, r12
    call unet_namespace_get_counters

    ; Format as BXP
    call vertex_network_format_stats

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_network_port_forward — Setup port forward (CRI: PortForward)
; Inputs:
;   RDI = pod_sandbox_id
;   RSI = port_forward_spec (BXP: local_port, pod_port, protocol)
; Returns: RAX = proxy_fiber_handle, or 0
; -----------------------------------------------------------------------------
global vertex_network_port_forward
vertex_network_port_forward:
    push rbx
    push r12
    push r13

    mov r12, rdi      ; pod_sandbox_id
    mov r13, rsi      ; spec

    ; 1. Find pod netns
    mov rdi, [sandbox_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    mov rdi, [rax + sandbox_state.netns_handle]

    ; 2. Parse spec
    call vertex_network_parse_port_forward
    test rax, rax
    jz .fail

    ; 3. Create proxy fiber: listens on localhost:local_port, forwards to podIP:pod_port
    mov rdi, vertex_port_forward_proxy
    mov rsi, r13
    mov rdx, PRIO_HIGH
    mov rcx, FIBER_RESTART_ON_FAILURE
    call fiber_create
    test rax, rax
    jz .fail

    ; 4. Store proxy handle for cleanup
    call vertex_network_store_port_forward

    pop r13
    pop r12
    pop rbx
    ret

.fail:
    pop r13
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_network_apply_policies — Apply NetworkPolicy to pod
; Internal: called when policies change
; -----------------------------------------------------------------------------
vertex_network_apply_policies:
    push rbx
    push r12

    ; 1. Get policies for this pod (from niti via label selector)
    ; 2. Translate to niti rules (allow/deny, ingress/egress)
    ; 3. Apply to netns

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_network_remove_policies — Remove NetworkPolicy rules
; -----------------------------------------------------------------------------
vertex_network_remove_policies:
    push rbx
    push r12

    ; Delete niti rules for this netns

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; IPAM
; -----------------------------------------------------------------------------

vertex_network_init_ipam:
    ; Initialize IPAM from node CIDR (from config)
    ret

vertex_network_ipam_allocate:
    ; Allocate next free IP from pod CIDR
    xor rax, rax
    ret

vertex_network_ipam_release:
    ; Release IP back to pool
    ret


; -----------------------------------------------------------------------------
; Port forward proxy fiber
; -----------------------------------------------------------------------------
vertex_port_forward_proxy:
    ; RDI = spec (local_port, pod_ip, pod_port, protocol)
    ; Loop: accept on local, connect to pod, proxy bytes
    ret


; -----------------------------------------------------------------------------
; Data structures
; -----------------------------------------------------------------------------
struc netns_state
    .netns_id       resq 1
    .pod_sandbox_id resq 1
    .pause_fiber    resq 1
    .pod_ip         resd 1
    .netmask        resd 1
    .gateway        resd 1
    .veth_host      resq 1
    .veth_pod       resq 1
    .policy_version resq 1
    .counters       resq 1      ; unet_counters pointer
endstruc

section .data
align 8
netns_map:              dq 0

node_bridge_name:       db "tattva0", 0
pod_netmask:            dd 0xFFFFFF00     ; /24
pod_gateway:            dd 0x0A000001     ; 10.0.0.1

%endif ; GUARD_VERTEX_NETWORK_ASM