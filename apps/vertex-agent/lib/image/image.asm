%ifndef GUARD_VERTEX_IMAGE_ASM
%define GUARD_VERTEX_IMAGE_ASM
; =============================================================================
; vertex-agent — Image Manager
; =============================================================================
; Pull, unpack, store, GC container images
; OCI → .upk → uxfs overlayfs layers
; =============================================================================

[BITS 64]

%include "lib/ulib/vec.inc"
%include "lib/ulib/map.inc"
%include "lib/ulib/ring.inc"
%include "net/uhttp/uhttp.inc"
%include "storage/uxfs/uxfs.inc"
%include "crypto/usign/usign.inc"
%include "pkg/registry/registry.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_image_init — Initialize image manager
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_image_init
vertex_image_init:
    push rbx
    push r12

    ; Image index map (digest -> layer_info)
    mov rdi, 8192
    call map_create
    test rax, rax
    jz .fail
    mov [layer_index_map], rax

    ; Image metadata map (image_ref -> image_info)
    mov rdi, 4096
    call map_create
    test rax, rax
    jz .fail
    mov [image_meta_map], rax

    ; Pull queue (ring buffer for concurrent pulls)
    mov rdi, 64
    call ring_create
    test rax, rax
    jz .fail
    mov [pull_queue], rax

    ; Initialize local image store
    call vertex_image_store_init

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
; vertex_image_pull — Pull image (CRI: PullImage)
; Inputs:
;   RDI = image_ref (string, e.g., "docker.io/library/nginx:latest")
;   RSI = auth_config (optional, BXP)
;   RDX = sandbox_config (optional, for platform selection)
; Returns: RAX = image manifest digest, or 0 on error
; -----------------------------------------------------------------------------
global vertex_image_pull
vertex_image_pull:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi      ; image_ref
    mov r13, rsi      ; auth_config
    mov r14, rdx      ; sandbox_config

    ; 1. Check local store first
    mov rdi, [image_meta_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .need_pull

    ; Verify all layers present
    call vertex_image_verify_layers
    test rax, rax
    jnz .already_have

.need_pull:
    ; 2. Resolve registry + repo + tag/digest
    mov rdi, r12
    call vertex_image_parse_ref
    test rax, rax
    jz .fail

    ; 3. Get registry credentials
    test r13, r13
    jz .use_default_auth
    mov rdi, r13
    call vertex_image_extract_auth
    jmp .got_auth

.use_default_auth:
    call vertex_image_get_default_auth

.got_auth:
    mov r15, rax      ; auth_token

    ; 4. Fetch manifest from registry
    mov rdi, registry_url
    mov rsi, repo_path
    mov rdx, tag_or_digest
    mov rcx, r15
    call registry_manifest_get
    test rax, rax
    jz .fail_manifest
    mov rbx, rax      ; manifest (BXP)

    ; 5. Verify manifest signature (if signed)
    call vertex_image_verify_manifest_sig
    ; Non-fatal: log warning if unsigned

    ; 6. For each layer in manifest:
    ;    - Check if already in store (by digest)
    ;    - If missing, download blob
    ;    - Verify blob digest
    ;    - Convert to uxfs layer snapshot
    mov rdi, rbx
    call vertex_image_process_layers
    test rax, rax
    jz .fail_layers

    ; 7. Store image config
    call vertex_image_store_config

    ; 8. Write image metadata
    call vertex_image_write_metadata

    ; 9. Return manifest digest
    mov rax, [rbx + manifest_digest]
    jmp .done

.already_have:
    mov rax, [rax + image_info.digest]
    jmp .done

.fail_layers:
.fail_manifest:
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
; vertex_image_remove — Remove image (CRI: RemoveImage)
; Inputs: RDI = image_ref
; Returns: RAX = 1 (ok), 0 (fail)
; -----------------------------------------------------------------------------
global vertex_image_remove
vertex_image_remove:
    push rbx
    push r12

    mov r12, rdi

    ; 1. Lookup image metadata
    mov rdi, [image_meta_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .not_found
    mov rbx, rax

    ; 2. Check if any container uses this image
    call vertex_image_check_references
    test rax, rax
    jnz .in_use

    ; 3. For each layer, decrement refcount, delete if zero
    mov rdi, [rbx + image_info.layer_digests]
    call vertex_image_release_layers

    ; 4. Remove from maps
    mov rdi, [image_meta_map]
    mov rsi, r12
    call map_remove

    ; 5. Delete metadata
    call vertex_image_delete_metadata

    pop r12
    pop rbx
    mov rax, 1
    ret

.in_use:
.not_found:
    pop r12
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_image_list — List images (CRI: ListImages)
; Inputs: RDI = filter (optional)
; Returns: RAX = list pointer
; -----------------------------------------------------------------------------
global vertex_image_list
vertex_image_list:
    push rbx

    mov rdi, [image_meta_map]
    call map_values

    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_image_status — Get image status (CRI: ImageStatus)
; Inputs: RDI = image_ref
; Returns: RAX = image_info pointer (BXP)
; -----------------------------------------------------------------------------
global vertex_image_status
vertex_image_status:
    push rbx
    push r12

    mov r12, rdi

    ; Check local
    mov rdi, [image_meta_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jnz .found_local

    ; Check remote (registry)
    call vertex_image_remote_status

.found_local:
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_image_fs_info — Get image filesystem info (CRI: ImageFsInfo)
; Returns: RAX = fs_info pointer (BXP)
; -----------------------------------------------------------------------------
global vertex_image_fs_info
vertex_image_fs_info:
    push rbx

    ; Get uxfs stats for data/vertex-agent/images/
    mov rdi, image_store_path
    call uxfs_statfs
    call vertex_image_build_fs_info

    pop rbx
    ret


; -----------------------------------------------------------------------------
; Layer management
; -----------------------------------------------------------------------------

; vertex_image_layer_get — Get layer mount handle by digest
; Returns: RAX = mount_handle, or 0
global vertex_image_layer_get
vertex_image_layer_get:
    push rbx
    push r12

    mov r12, rdi      ; digest

    mov rdi, [layer_index_map]
    mov rsi, r12
    call map_get
    test rax, rax
    jz .not_found

    ; Layer exists, return mount handle
    mov rax, [rax + layer_info.mount_handle]
    jmp .done

.not_found:
    xor rax, rax

.done:
    pop r12
    pop rbx
    ret


; vertex_image_layer_mount — Mount layer for container
; Inputs: RDI = layer_digest, RSI = container_mntns
; Returns: RAX = mount_handle
global vertex_image_layer_mount
vertex_image_layer_mount:
    push rbx
    push r12

    mov r12, rdi      ; digest
    mov r13, rsi      ; target_mntns

    call vertex_image_layer_get
    test rax, rax
    jnz .already_mounted

    ; Mount the layer snapshot
    call vertex_image_mount_layer_snapshot

.already_mounted:
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; Background: Image GC
; -----------------------------------------------------------------------------

vertex_image_gc_fiber:
.loop:
    mov rdi, 300000000000     ; 5 minutes
    call mono_sleep_ns
    call vertex_image_gc_collect
    jmp .loop


global vertex_image_gc_collect
vertex_image_gc_collect:
    push rbx
    push r12

    ; 1. Scan all containers for referenced layers
    call vertex_image_scan_referenced_layers

    ; 2. For each layer in index with refcount == 0:
    ;    - Unmount if mounted
    ;    - Delete uxfs snapshot
    ;    - Remove from index
    call vertex_image_prune_unreferenced

    ; 3. Prune unused images (no containers, no tags)
    call vertex_image_prune_unused_images

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; OCI → .upk conversion
; -----------------------------------------------------------------------------

; vertex_image_oci_to_upk — Convert OCI image to .upk package
; Inputs: RDI = OCI manifest, RSI = layers[], RDX = config
; Returns: RAX = .upk package path
global vertex_image_oci_to_upk
vertex_image_oci_to_upk:
    ; TODO: Implement
    xor rax, rax
    ret


; vertex_image_upk_to_layers — Unpack .upk to uxfs layer snapshots
; TODO: Implement

; -----------------------------------------------------------------------------
; Data structures
; -----------------------------------------------------------------------------
struc layer_info
    .digest             resq 1      ; SHA256 digest
    .size               resq 1      ; uncompressed size
    .mount_handle       resq 1      ; uxfs mount handle
    .refcount           resd 1      ; number of containers/images using
    .compressed         resb 1      ; 1 if compressed on disk
    .created_ns         resq 1
endstruc

struc image_info
    .ref                resq 1      ; image reference string
    .digest             resq 1      ; manifest digest
    .config_digest      resq 1      ; config digest
    .layer_digests      resq 1      ; vec of layer digests
    .size               resq 1      ; total size
    .created_ns         resq 1
    .tags               resq 1      ; vec of tags
endstruc

section .data
align 8
layer_index_map:        dq 0
image_meta_map:         dq 0
pull_queue:             dq 0

image_store_path:       db "data/vertex-agent/images/", 0
registry_url:           dq 0
repo_path:              dq 0
tag_or_digest:          dq 0

%endif ; GUARD_VERTEX_IMAGE_ASM