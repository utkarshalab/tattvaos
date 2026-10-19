%ifndef GUARD_VERTEX_SANDBOX_ASM
%define GUARD_VERTEX_SANDBOX_ASM
; =============================================================================
; vertex-agent — Pod Sandbox Manager
; =============================================================================
; Manages pod sandbox lifecycle: create, stop, remove, status
; A sandbox = pause fiber + netns + ipcns + shared mount namespace
; =============================================================================

[BITS 64]

%include "lib/ulib/vec.inc"
%include "lib/ulib/map.inc"
%include "security/usrauth/usrauth.inc"
%include "net/unet/unet.inc"
%include "storage/uxfs/uxfs.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_sandbox_init — Initialize sandbox manager
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_sandbox_init
vertex_sandbox_init:
    push rbx
    push r12

    ; Allocate sandbox map (pod_uid -> sandbox_state)
    mov rdi, 1024
    call map_create
    test rax, rax
    jz .fail
    mov [sandbox_map], rax

    ; Initialize pause fiber template
    call vertex_sandbox_pause_template_init

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
; vertex_sandbox_create — Create pod sandbox (CRI: RunPodSandbox)
; Inputs:
;   RDI = config pointer (BXP-encoded PodSandboxConfig)
;   RSI = runtime_handler (string, unused)
; Returns: RAX = sandbox_id (string), or 0 on error
; -----------------------------------------------------------------------------
global vertex_sandbox_create
vertex_sandbox_create:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi      ; config
    mov r13, rsi      ; runtime_handler

    ; 1. Parse config: get pod_uid, pod_name, namespace, annotations
    call vertex_sandbox_parse_config
    test rax, rax
    jz .fail

    ; 2. Generate sandbox ID (UUID v4)
    call vertex_gen_uuid
    mov r14, rax      ; sandbox_id

    ; 3. Allocate pod IP from unet IPAM
    mov rdi, pod_cidr
    call unet_ipam_allocate
    test rax, rax
    jz .fail_ip
    mov r15, rax      ; pod_ip

    ; 4. Create pause fiber (minimal, runs sched_idle_task)
    mov rdi, vertex_pause_fiber_entry
    xor rsi, rsi
    mov rdx, PRIO_IDLE
    mov rcx, FIBER_RESTART_ALWAYS
    call fiber_create
    test rax, rax
    jz .fail_fiber
    mov rbx, rax      ; pause_fiber_handle

    ; 5. Create network namespace attached to pause fiber
    mov rdi, rbx
    mov rsi, r15      ; pod_ip
    call unet_namespace_create
    test rax, rax
    jz .fail_netns

    ; 6. Create IPC namespace attached to pause fiber
    mov rdi, rbx
    call vertex_ipc_namespace_create
    test rax, rax
    jz .fail_ipcns

    ; 7. Create shared mount namespace (overlayfs base)
    mov rdi, rbx
    call vertex_mount_namespace_create
    test rax, rax
    jz .fail_mntns

    ; 8. Create sandbox subject in usrauth
    mov edi, pod_uid_from_config
    mov esi, 0        ; gid
    mov edx, K8S_POD_TYPE_ID
    mov ecx, USRAUTH_INTEGRITY_MEDIUM
    call usrauth_subject_create
    test eax, eax
    jl .fail_subject
    mov r12d, eax     ; sandbox_subject_handle

    ; 9. Grant sandbox capabilities
    call vertex_sandbox_grant_caps

    ; 10. Store sandbox state
    call vertex_sandbox_store_state

    ; 11. Write metadata to data/vertex-agent/pods/<sandbox_id>/
    call vertex_sandbox_write_metadata

    mov rax, r14
    jmp .done

.fail_mntns:
    call vertex_ipc_namespace_destroy
.fail_ipcns:
    call unet_namespace_destroy
.fail_netns:
    call fiber_kill
.fail_fiber:
.fail_ip:
.fail:
    xor rax, rax

.done:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_sandbox_stop — Stop pod sandbox (CRI: StopPodSandbox)
; Inputs: RDI = sandbox_id string
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_sandbox_stop
vertex_sandbox_stop:
    push rbx
    push r12

    mov r12, rdi

    ; 1. Lookup sandbox state
    mov rdi, [sandbox_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .not_found
    mov rbx, rax

    ; 2. Kill pause fiber (cascades to child containers)
    mov rdi, [rbx + sandbox_state.pause_fiber]
    call fiber_kill

    ; 3. Wait for fiber to exit (with timeout)
    mov rdi, 30000000000
    call fiber_wait

    ; 4. Teardown namespaces
    mov rdi, [rbx + sandbox_state.netns_handle]
    call unet_namespace_destroy

    mov rdi, [rbx + sandbox_state.ipcns_handle]
    call vertex_ipc_namespace_destroy

    mov rdi, [rbx + sandbox_state.mntns_handle]
    call vertex_mount_namespace_destroy

    ; 5. Update state
    mov dword [rbx + sandbox_state.status], SANDBOX_NOTREADY

    pop r12
    pop rbx
    mov rax, 1
    ret

.not_found:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_sandbox_remove — Remove pod sandbox (CRI: RemovePodSandbox)
; Inputs: RDI = sandbox_id string
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_sandbox_remove
vertex_sandbox_remove:
    push rbx
    push r12

    mov r12, rdi

    ; Must be stopped first
    call vertex_sandbox_stop
    test rax, rax
    jz .fail

    ; Release pod IP
    mov rdi, [rbx + sandbox_state.pod_ip]
    call unet_ipam_release

    ; Destroy usrauth subject
    mov edi, [rbx + sandbox_state.subject_handle]
    call usrauth_subject_destroy

    ; Remove from map
    mov rdi, [sandbox_map]
    mov rsi, r12
    call map_remove

    ; Delete metadata directory
    call vertex_sandbox_delete_metadata

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
; vertex_sandbox_status — Get sandbox status (CRI: PodSandboxStatus)
; Inputs: RDI = sandbox_id, RSI = verbose (bool)
; Returns: RAX = status pointer (BXP), or 0
; -----------------------------------------------------------------------------
global vertex_sandbox_status
vertex_sandbox_status:
    push rbx
    push r12

    mov r12, rdi
    mov r13, rsi

    mov rdi, [sandbox_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .not_found

    ; Build status response
    call vertex_sandbox_build_status

    pop r12
    pop rbx
    ret

.not_found:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_sandbox_list — List sandboxes (CRI: ListPodSandbox)
; Inputs: RDI = filter (optional)
; Returns: RAX = list pointer
; -----------------------------------------------------------------------------
global vertex_sandbox_list
vertex_sandbox_list:
    push rbx

    mov rdi, [sandbox_map]
    call map_values
    ; Filter if needed
    test rdi, rdi
    jz .empty

    call vertex_sandbox_filter_list

.empty:
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_sandbox_shutdown — Cleanup on agent shutdown
; -----------------------------------------------------------------------------
global vertex_sandbox_shutdown
vertex_sandbox_shutdown:
    push rbx

    mov rdi, [sandbox_map]
    call map_iter_begin
.iter:
    call map_iter_next
    test rax, rax
    jz .done

    ; Stop each sandbox
    mov rdi, rax
    call vertex_sandbox_stop
    jmp .iter

.done:
    mov rdi, [sandbox_map]
    call map_destroy
    pop rbx
    ret


; -----------------------------------------------------------------------------
; Internal: pause fiber template
; -----------------------------------------------------------------------------
vertex_sandbox_pause_template_init:
    ; Pause fiber just yields forever
    ret

vertex_pause_fiber_entry:
.pause_loop:
    call fiber_yield
    jmp .pause_loop


; -----------------------------------------------------------------------------
; Data structures
; -----------------------------------------------------------------------------
struc sandbox_state
    .sandbox_id       resq 1
    .pod_uid          resq 1
    .pod_name         resq 1
    .namespace        resq 1
    .pause_fiber      resq 1
    .netns_handle     resq 1
    .ipcns_handle     resq 1
    .mntns_handle     resq 1
    .subject_handle   resd 1
    .pod_ip           resd 1
    .status           resd 1
    .created_ns       resq 1
    .annotations      resq 1
endstruc

section .data
align 8
sandbox_map:            dq 0

pod_cidr:               dd 0x0A000000     ; 10.0.0.0/8 default, overridden by config
K8S_POD_TYPE_ID:        equ 0x1001

SANDBOX_READY:          equ 1
SANDBOX_NOTREADY:       equ 2

%endif ; GUARD_VERTEX_SANDBOX_ASM