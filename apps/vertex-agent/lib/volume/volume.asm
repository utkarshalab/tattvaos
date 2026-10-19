%ifndef GUARD_VERTEX_VOLUME_ASM
%define GUARD_VERTEX_VOLUME_ASM
; =============================================================================
; vertex-agent — Volume Manager
; =============================================================================
; Mount volumes into container mount namespaces
; emptyDir, hostPath, configMap, secret, PVC, CSI
; All via uxfs bind mounts / overlayfs
; =============================================================================

[BITS 64]

%include "storage/uxfs/uxfs.inc"
%include "lib/ulib/map.inc"
%include "security/usrauth/usrauth.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_volume_init — Initialize volume manager
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_volume_init
vertex_volume_init:
    push rbx
    push r12

    ; Volume map (volume_id -> volume_state)
    mov rdi, 4096
    call map_create
    test rax, rax
    jz .fail
    mov [volume_map], rax

    ; Mount namespace map (mntns_id -> mount_list)
    mov rdi, 2048
    call map_create
    test rax, rax
    jz .fail
    mov [mntns_mounts_map], rax

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
; vertex_volume_mount — Mount volume into container mount namespace
; Inputs:
;   RDI = container_mntns_handle
;   RSI = volume_spec (BXP: type, source, target, readonly, options)
; Returns: RAX = mount_handle, or 0
; -----------------------------------------------------------------------------
global vertex_volume_mount
vertex_volume_mount:
    push rbx
    push r12
    push r13
    push r14

    mov r12, rdi      ; container_mntns
    mov r13, rsi      ; volume_spec

    ; 1. Parse volume spec
    call vertex_volume_parse_spec
    test rax, rax
    jz .fail

    ; 2. Dispatch by volume type
    mov al, [volume_type]
    cmp al, VOLUME_EMPTYDIR
    je .mount_emptydir
    cmp al, VOLUME_HOSTPATH
    je .mount_hostpath
    cmp al, VOLUME_CONFIGMAP
    je .mount_configmap
    cmp al, VOLUME_SECRET
    je .mount_secret
    cmp al, VOLUME_PVC
    je .mount_pvc
    cmp al, VOLUME_CSI
    je .mount_csi
    jmp .fail

.mount_emptydir:
    call vertex_volume_mount_emptydir
    jmp .done

.mount_hostpath:
    call vertex_volume_mount_hostpath
    jmp .done

.mount_configmap:
    call vertex_volume_mount_configmap
    jmp .done

.mount_secret:
    call vertex_volume_mount_secret
    jmp .done

.mount_pvc:
    call vertex_volume_mount_pvc
    jmp .done

.mount_csi:
    call vertex_volume_mount_csi
    jmp .done

.fail:
    xor rax, rax

.done:
    pop r14
    pop r13
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; EmptyDir: tmpfs mount at tmp/app/vertex-agent/volumes/<pod>/<volume>/
; -----------------------------------------------------------------------------
vertex_volume_mount_emptydir:
    push rbx
    push r12

    ; 1. Generate volume path
    call vertex_volume_emptydir_path
    mov r12, rax

    ; 2. Create directory if needed
    mov rdi, r12
    call uxfs_mkdir_p

    ; 3. Mount tmpfs at target in container mntns
    mov rdi, r12          ; source (tmpfs)
    mov rsi, [volume_target]
    mov rdx, MS_BIND | MS_NOSUID | MS_NODEV | MS_NOEXEC
    test byte [volume_readonly], 1
    jz .not_ro
    or rdx, MS_RDONLY
.not_ro:
    mov rcx, container_mntns
    call uxfs_mount
    test rax, rax
    jz .fail

    ; 4. Track mount
    call vertex_volume_track_mount

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
; HostPath: bind mount from vol/ext/ or vol/att/
; -----------------------------------------------------------------------------
vertex_volume_mount_hostpath:
    push rbx
    push r12

    ; 1. Resolve host path (from vol/ext/ or vol/att/)
    mov rdi, [volume_source]
    call vertex_volume_resolve_hostpath
    test rax, rax
    jz .fail
    mov r12, rax

    ; 2. Bind mount into container mntns
    mov rdi, r12
    mov rsi, [volume_target]
    mov rdx, MS_BIND
    test byte [volume_readonly], 1
    jz .not_ro
    or rdx, MS_RDONLY
.not_ro:
    mov rcx, container_mntns
    call uxfs_mount
    test rax, rax
    jz .fail

    call vertex_volume_track_mount

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
; ConfigMap: read-only overlay from conf/
; -----------------------------------------------------------------------------
vertex_volume_mount_configmap:
    push rbx
    push r12

    ; 1. Get configmap data from conf/apps/<app>/ or conf/
    mov rdi, [volume_configmap_name]
    call vertex_volume_configmap_path
    test rax, rax
    jz .fail
    mov r12, rax

    ; 2. Create read-only bind mount
    mov rdi, r12
    mov rsi, [volume_target]
    mov rdx, MS_BIND | MS_RDONLY
    mov rcx, container_mntns
    call uxfs_mount
    test rax, rax
    jz .fail

    call vertex_volume_track_mount

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
; Secret: read-only overlay from sec/vault/
; -----------------------------------------------------------------------------
vertex_volume_mount_secret:
    push rbx
    push r12

    ; 1. Get secret from sec/vault/<app>/
    mov rdi, [volume_secret_name]
    call vertex_volume_secret_path
    test rax, rax
    jz .fail
    mov r12, rax

    ; 2. Verify caller has cap to read this secret
    call vertex_volume_check_secret_access
    test rax, rax
    jz .fail

    ; 3. Read-only bind mount
    mov rdi, r12
    mov rsi, [volume_target]
    mov rdx, MS_BIND | MS_RDONLY | MS_NOSUID | MS_NODEV | MS_NOEXEC
    mov rcx, container_mntns
    call uxfs_mount
    test rax, rax
    jz .fail

    call vertex_volume_track_mount

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
; PVC: bind mount from data/<app>/ (provisioned by vertex-controllers)
; -----------------------------------------------------------------------------
vertex_volume_mount_pvc:
    push rbx
    push r12

    ; 1. Get PVC path from data/vertex-agent/pvc/<pvc_name>/
    mov rdi, [volume_pvc_name]
    call vertex_volume_pvc_path
    test rax, rax
    jz .fail
    mov r12, rax

    ; 2. Bind mount (read/write unless readonly)
    mov rdi, r12
    mov rsi, [volume_target]
    mov rdx, MS_BIND
    test byte [volume_readonly], 1
    jz .not_ro
    or rdx, MS_RDONLY
.not_ro:
    mov rcx, container_mntns
    call uxfs_mount
    test rax, rax
    jz .fail

    call vertex_volume_track_mount

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
; CSI: Call CSI driver via gRPC (unix socket)
; -----------------------------------------------------------------------------
vertex_volume_mount_csi:
    push rbx
    push r12

    ; 1. Connect to CSI driver socket
    mov rdi, [volume_csi_driver]
    call vertex_csi_connect
    test rax, rax
    jz .fail
    mov r12, rax

    ; 2. Call NodeStageVolume (if needed)
    ; 3. Call NodePublishVolume
    mov rdi, r12
    mov rsi, [volume_target]
    mov rdx, [volume_csi_volume_id]
    mov rcx, [volume_readonly]
    call vertex_csi_node_publish
    test rax, rax
    jz .fail

    call vertex_volume_track_mount

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
; vertex_volume_unmount — Unmount volume from container mntns
; Inputs: RDI = mount_handle
; -----------------------------------------------------------------------------
global vertex_volume_unmount
vertex_volume_unmount:
    push rbx
    push r12

    mov r12, rdi

    ; 1. Unmount from container mntns
    mov rdi, [r12 + mount_state.target_path]
    mov rsi, [r12 + mount_state.mntns_handle]
    call uxfs_unmount

    ; 2. For emptyDir: cleanup tmpfs dir if no other mounts
    mov al, [r12 + mount_state.type]
    cmp al, VOLUME_EMPTYDIR
    jne .done
    call vertex_volume_emptydir_cleanup

.done:
    ; 3. Remove from tracking
    call vertex_volume_untrack_mount

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_volume_container_mounts_get — Get all mounts for container
; Used for ContainerStatus
; -----------------------------------------------------------------------------
global vertex_volume_container_mounts_get
vertex_volume_container_mounts_get:
    push rbx
    push r12

    mov r12, rdi      ; container_mntns

    mov rdi, [mntns_mounts_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .empty

    ; Format mount list as BXP
    call vertex_volume_format_mounts

    pop r12
    pop rbx
    ret

.empty:
    xor rax, rax
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_volume_shutdown — Cleanup on agent shutdown
; -----------------------------------------------------------------------------
global vertex_volume_shutdown
vertex_volume_shutdown:
    push rbx

    ; Unmount all tracked mounts
    mov rdi, [mntns_mounts_map]
    call map_iter_begin
.iter:
    call map_iter_next
    test rax, rax
    jz .done
    mov rdi, rax
    call vertex_volume_unmount
    jmp .iter

.done:
    mov rdi, [volume_map]
    call map_destroy
    mov rdi, [mntns_mounts_map]
    call map_destroy

    pop rbx
    ret


; -----------------------------------------------------------------------------
; Data structures
; -----------------------------------------------------------------------------
struc mount_state
    .mount_handle     resq 1
    .mntns_handle     resq 1
    .type             resb 1
    .source_path      resq 1
    .target_path      resq 1
    .readonly         resb 1
    .options          resq 1
endstruc

; Volume types
VOLUME_EMPTYDIR:      equ 1
VOLUME_HOSTPATH:      equ 2
VOLUME_CONFIGMAP:     equ 3
VOLUME_SECRET:        equ 4
VOLUME_PVC:           equ 5
VOLUME_CSI:           equ 6

section .data
align 8
volume_map:             dq 0
mntns_mounts_map:       dq 0

container_mntns:        dq 0
volume_type:            db 0
volume_source:          dq 0
volume_target:          dq 0
volume_readonly:        db 0
volume_options:         dq 0
volume_configmap_name:  dq 0
volume_secret_name:     dq 0
volume_pvc_name:        dq 0
volume_csi_driver:      dq 0
volume_csi_volume_id:   dq 0

%endif ; GUARD_VERTEX_VOLUME_ASM