%ifndef GUARD_VERTEX_CONTAINER_ASM
%define GUARD_VERTEX_CONTAINER_ASM
; =============================================================================
; vertex-agent — Container Manager
; =============================================================================
; Manages container lifecycle within a pod sandbox
; A container = fiber + attenuated capabilities + private mount namespace
; =============================================================================

[BITS 64]

%include "lib/ulib/vec.inc"
%include "lib/ulib/map.inc"
%include "security/usrauth/usrauth.inc"
%include "storage/uxfs/uxfs.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_container_init — Initialize container manager
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_container_init
vertex_container_init:
    push rbx
    push r12

    ; Allocate container map (container_id -> container_state)
    mov rdi, 4096
    call map_create
    test rax, rax
    jz .fail
    mov [container_map], rax

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
; vertex_container_create — Create container (CRI: CreateContainer)
; Inputs:
;   RDI = pod_sandbox_id
;   RSI = config pointer (BXP-encoded ContainerConfig)
; Returns: RAX = container_id, or 0 on error
; -----------------------------------------------------------------------------
global vertex_container_create
vertex_container_create:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi      ; pod_sandbox_id
    mov r13, rsi      ; config

    ; 1. Verify sandbox exists and is ready
    mov rdi, [sandbox_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail_sandbox
    cmp dword [rax + sandbox_state.status], SANDBOX_READY
    jne .fail_sandbox_not_ready
    mov rbx, rax      ; sandbox_state

    ; 2. Parse container config: image, cmd, args, env, mounts, resources
    call vertex_container_parse_config
    test rax, rax
    jz .fail

    ; 3. Generate container ID
    call vertex_gen_uuid
    mov r14, rax      ; container_id

    ; 4. Resolve image → overlayfs mount
    mov rdi, image_ref
    call vertex_image_resolve
    test rax, rax
    jz .fail_image
    mov r15, rax      ; image_mount_handle

    ; 5. Create container's private mount namespace (overlayfs)
    ;    Lower = image layers + sandbox shared mounts
    ;    Upper = per-container RW layer
    mov rdi, rbx
    mov rsi, r15
    call vertex_container_mount_namespace_create
    test rax, rax
    jz .fail_mntns

    ; 6. Create container subject (attenuated from sandbox subject)
    mov edi, [rbx + sandbox_state.subject_handle]
    mov rsi, container_caps_requested
    call vertex_container_delegate_caps
    test rax, rax
    jz .fail_caps
    mov r12, rax      ; container_subject_handle

    ; 7. Create container fiber
    ;    Entry point = user command (from config)
    mov rdi, container_entry_point
    mov rsi, container_args
    mov rdx, PRIO_NORMAL
    mov rcx, FIBER_RESTART_ON_FAILURE
    call fiber_create
    test rax, rax
    jz .fail_fiber
    mov rdi, rax

    ; 8. Attach subject handle to fiber control block
    mov rsi, r12
    call fiber_set_subject

    ; 9. Apply resource limits (CPU quota, memory arena)
    call vertex_container_apply_resources

    ; 10. Store container state
    call vertex_container_store_state

    ; 11. Write metadata
    call vertex_container_write_metadata

    mov rax, r14
    jmp .done

.fail_mntns:
.fail_caps:
.fail_fiber:
    ; Cleanup on failure
    call vertex_container_cleanup_partial
.fail_image:
.fail_sandbox_not_ready:
.fail_sandbox:
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
; vertex_container_start — Start container (CRI: StartContainer)
; Inputs: RDI = container_id
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_container_start
vertex_container_start:
    push rbx
    push r12

    mov r12, rdi

    mov rdi, [container_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    ; Resume fiber
    mov rdi, [rax + container_state.fiber_handle]
    call fiber_resume

    ; Update state
    mov dword [rax + container_state.status], CONTAINER_RUNNING

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
; vertex_container_stop — Stop container (CRI: StopContainer)
; Inputs: RDI = container_id, RSI = timeout_ns
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_container_stop
vertex_container_stop:
    push rbx
    push r12
    push r13

    mov r12, rdi      ; container_id
    mov r13, rsi      ; timeout_ns

    mov rdi, [container_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    ; Send stop signal (fiber_kill with graceful timeout)
    mov rdi, [rax + container_state.fiber_handle]
    test r13, r13
    jz .force_kill
    call fiber_stop_graceful
    jmp .wait_done

.force_kill:
    call fiber_kill

.wait_done:
    ; Wait for exit
    test r13, r13
    jz .skip_wait
    mov rdi, r13
    call fiber_wait

.skip_wait:
    mov dword [rax + container_state.status], CONTAINER_EXITED
    call vertex_container_collect_exit_code

    pop r13
    pop r12
    pop rbx
    mov rax, 1
    ret

.fail:
    pop r13
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_container_remove — Remove container (CRI: RemoveContainer)
; Inputs: RDI = container_id
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_container_remove
vertex_container_remove:
    push rbx
    push r12

    mov r12, rdi

    ; Must be stopped first
    call vertex_container_stop
    test rax, rax
    jz .fail

    ; Cleanup mount namespace
    mov rdi, [rax + container_state.mntns_handle]
    call vertex_container_mount_namespace_destroy

    ; Destroy subject
    mov edi, [rax + container_state.subject_handle]
    call usrauth_subject_destroy

    ; Remove from map
    mov rdi, [container_map]
    mov rsi, r12
    call map_remove

    ; Delete metadata
    call vertex_container_delete_metadata

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
; vertex_container_status — Get container status (CRI: ContainerStatus)
; Inputs: RDI = container_id, RSI = verbose
; Returns: RAX = status pointer (BXP)
; -----------------------------------------------------------------------------
global vertex_container_status
vertex_container_status:
    push rbx
    push r12

    mov r12, rdi
    mov r13, rsi

    mov rdi, [container_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    call vertex_container_build_status

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
; vertex_container_list — List containers (CRI: ListContainers)
; -----------------------------------------------------------------------------
global vertex_container_list
vertex_container_list:
    push rbx

    mov rdi, [container_map]
    call map_values

    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_container_stats — Get container resource stats (CRI: ContainerStats)
; Inputs: RDI = container_id
; Returns: RAX = stats pointer (BXP)
; -----------------------------------------------------------------------------
global vertex_container_stats
vertex_container_stats:
    push rbx
    push r12

    mov r12, rdi

    mov rdi, [container_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    ; Collect: CPU (ticks), Memory (arena), Network, FS
    call vertex_container_collect_stats

    pop r12
    pop rbx
    ret

.fail:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_container_update_resources — Update resources (CRI: UpdateContainerResources)
; Inputs: RDI = container_id, RSI = resources (BXP)
; -----------------------------------------------------------------------------
global vertex_container_update_resources
vertex_container_update_resources:
    push rbx
    push r12

    mov r12, rdi
    mov r13, rsi

    mov rdi, [container_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    call vertex_container_apply_resources

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
; vertex_container_reopen_log — Reopen log file (CRI: ReopenContainerLog)
; -----------------------------------------------------------------------------
global vertex_container_reopen_log
vertex_container_reopen_log:
    push rbx

    mov rdi, [container_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .fail

    ; Rotate ulog sink
    mov rdi, [rax + container_state.log_sink]
    call ulog_sink_rotate

    pop rbx
    mov rax, 1
    ret

.fail:
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_container_shutdown — Cleanup on agent shutdown
; -----------------------------------------------------------------------------
global vertex_container_shutdown
vertex_container_shutdown:
    push rbx

    mov rdi, [container_map]
    call map_iter_begin
.iter:
    call map_iter_next
    test rax, rax
    jz .done

    ; Stop each container
    mov rdi, [rax + container_state.fiber_handle]
    call fiber_kill
    jmp .iter

.done:
    mov rdi, [container_map]
    call map_destroy
    pop rbx
    ret


; -----------------------------------------------------------------------------
; Exec/Attach support
; -----------------------------------------------------------------------------

; vertex_container_exec — Create exec session (CRI: Exec)
; vertex_container_attach — Attach to container (CRI: Attach)
; vertex_container_port_forward — Port forward (CRI: PortForward)

; TODO: Implement

; -----------------------------------------------------------------------------
; Data structures
; -----------------------------------------------------------------------------
struc container_state
    .container_id       resq 1
    .pod_sandbox_id     resq 1
    .image_ref          resq 1
    .fiber_handle       resq 1
    .mntns_handle       resq 1
    .subject_handle     resd 1
    .status             resd 1
    .exit_code          resd 1
    .log_sink           resq 1
    .cpu_quota_ns       resq 1
    .mem_limit_bytes    resq 1
    .created_ns         resq 1
    .started_ns         resq 1
    .finished_ns        resq 1
    .config             resq 1
endstruc

CONTAINER_CREATED:      equ 1
CONTAINER_RUNNING:      equ 2
CONTAINER_EXITED:       equ 3
CONTAINER_UNKNOWN:      equ 0

section .data
align 8
container_map:          dq 0

%endif ; GUARD_VERTEX_CONTAINER_ASM