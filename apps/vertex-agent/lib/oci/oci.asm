%ifndef GUARD_VERTEX_OCI_ASM
%define GUARD_VERTEX_OCI_ASM
; =============================================================================
; vertex-agent — OCI Image Spec Parser / Translator
; =============================================================================
; Parses OCI manifests, converts to .upk format for Utkarsha
; =============================================================================

[BITS 64]

%include "lib/uparser/uparser.inc"
%include "lib/ulib/vec.inc"
%include "lib/ulib/map.inc"

section .text

; -----------------------------------------------------------------------------
; vertex_oci_parse_manifest — Parse OCI image manifest (JSON → BXP)
; Inputs: RDI = manifest_json, RSI = len
; Returns: RAX = manifest_bxp, or 0
; -----------------------------------------------------------------------------
global vertex_oci_parse_manifest
vertex_oci_parse_manifest:
    push rbx
    push r12
    push r13

    mov r12, rdi
    mov r13, rsi

    ; Use uparser JSON grammar
    mov rdi, oci_manifest_grammar
    mov rsi, r12
    mov rdx, r13
    call uparser_parse
    test rax, rax
    jz .fail

    ; Convert AST to BXP
    call vertex_oci_ast_to_bxp

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
; vertex_oci_parse_config — Parse OCI image config (JSON → BXP)
; -----------------------------------------------------------------------------
global vertex_oci_parse_config
vertex_oci_parse_config:
    push rbx

    mov rdi, oci_config_grammar
    call uparser_parse
    test rax, rax
    jz .fail

    call vertex_oci_ast_to_bxp

    pop rbx
    ret

.fail:
    pop rbx
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_oci_to_upk — Convert OCI image to .upk package
; Inputs: RDI = manifest_bxp, RSI = config_bxp, RDX = layer_digests[]
; Returns: RAX = upk_path, or 0
; -----------------------------------------------------------------------------
global vertex_oci_to_upk
vertex_oci_to_upk:
    ; 1. Create .upk manifest
    ; 2. For each layer: create .upk layer file (uxfs snapshot)
    ; 3. Sign manifest
    ; 4. Write to data/vertex-agent/images/
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_oci_extract_layers — Extract layer digests from manifest
; Inputs: RDI = manifest_bxp
; Returns: RAX = vec of layer digests
; -----------------------------------------------------------------------------
global vertex_oci_extract_layers
vertex_oci_extract_layers:
    ; Parse manifest.layers[].digest
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; vertex_oci_get_platform — Get platform from manifest (for multi-arch)
; -----------------------------------------------------------------------------
global vertex_oci_get_platform
vertex_oci_get_platform:
    ; Return linux/amd64, linux/arm64, etc.
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; Grammar definitions (inline, or load from res/)
; -----------------------------------------------------------------------------
section .data
align 8

oci_manifest_grammar:
    ; JSON grammar for OCI manifest v1
    ; {
    ;   "schemaVersion": 2,
    ;   "mediaType": "application/vnd.oci.image.manifest.v1+json",
    ;   "config": {"mediaType": "...", "size": 1234, "digest": "sha256:..."},
    ;   "layers": [{"mediaType": "...", "size": 1234, "digest": "sha256:..."}],
    ;   "annotations": {}
    ; }
    dq 0

oci_config_grammar:
    ; JSON grammar for OCI image config
    ; {
    ;   "created": "2024-01-01T00:00:00Z",
    ;   "architecture": "amd64",
    ;   "os": "linux",
    ;   "config": {"Env": [], "Cmd": [], "Entrypoint": [], ...},
    ;   "rootfs": {"type": "layers", "diff_ids": ["sha256:..."]},
    ;   "history": []
    ; }
    dq 0

%endif ; GUARD_VERTEX_OCI_ASM