%ifndef GUARD_VERTEX_CRI_ASM
%define GUARD_VERTEX_CRI_ASM
; =============================================================================
; vertex-agent — CRI Protobuf Definitions (BXP-encoded)
; =============================================================================
; CRI gRPC messages translated to BXP for internal use
; Generated from cri-api.proto (k8s.io/cri-api/pkg/apis/runtime/v1)
; =============================================================================

[BITS 64]

%include "lib/uparser/uparser.inc"
%include "lib/ulib/vec.inc"

section .text

; -----------------------------------------------------------------------------
; CRI Message IDs (matching protobuf field numbers)
; -----------------------------------------------------------------------------
; RuntimeService
CRI_VERSION:                    equ 1
CRI_RUN_POD_SANDBOX:            equ 2
CRI_STOP_POD_SANDBOX:           equ 3
CRI_REMOVE_POD_SANDBOX:         equ 4
CRI_POD_SANDBOX_STATUS:         equ 5
CRI_LIST_POD_SANDBOX:           equ 6
CRI_CREATE_CONTAINER:           equ 7
CRI_START_CONTAINER:            equ 8
CRI_STOP_CONTAINER:             equ 9
CRI_REMOVE_CONTAINER:           equ 10
CRI_CONTAINER_STATUS:           equ 11
CRI_LIST_CONTAINERS:            equ 12
CRI_EXEC_SYNC:                  equ 13
CRI_EXEC:                       equ 14
CRI_ATTACH:                     equ 15
CRI_PORT_FORWARD:               equ 16
CRI_CONTAINER_STATS:            equ 17
CRI_LIST_CONTAINER_STATS:       equ 18
CRI_UPDATE_CONTAINER_RESOURCES: equ 19
CRI_REOPEN_CONTAINER_LOG:       equ 20
CRI_RUNTIME_CONFIG:             equ 21
CRI_STATUS:                     equ 22

; ImageService
CRI_LIST_IMAGES:                equ 100
CRI_IMAGE_STATUS:               equ 101
CRI_PULL_IMAGE:                 equ 102
CRI_REMOVE_IMAGE:               equ 103
CRI_IMAGE_FS_INFO:              equ 104

; -----------------------------------------------------------------------------
; vertex_cri_decode — Decode CRI request (protobuf → BXP)
; Inputs: RDI = protobuf_data, RSI = len, RDX = method_id
; Returns: RAX = BXP request, or 0
; -----------------------------------------------------------------------------
global vertex_cri_decode
vertex_cri_decode:
    push rbx
    push r12

    mov r12, rdx      ; method_id

    ; Dispatch to method-specific decoder
    cmp r12d, CRI_RUN_POD_SANDBOX
    je .decode_run_pod_sandbox
    cmp r12d, CRI_STOP_POD_SANDBOX
    je .decode_stop_pod_sandbox
    cmp r12d, CRI_CREATE_CONTAINER
    je .decode_create_container
    ; ... add all methods

    ; Generic protobuf decode
    call vertex_cri_protobuf_decode

    pop r12
    pop rbx
    ret

.decode_run_pod_sandbox:
    call vertex_cri_decode_run_pod_sandbox
    jmp .done

.decode_stop_pod_sandbox:
    call vertex_cri_decode_stop_pod_sandbox
    jmp .done

.decode_create_container:
    call vertex_cri_decode_create_container
    jmp .done

.done:
    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; vertex_cri_encode — Encode CRI response (BXP → protobuf)
; Inputs: RDI = BXP response, RSI = method_id
; Returns: RAX = protobuf_data, RDX = len
; -----------------------------------------------------------------------------
global vertex_cri_encode
vertex_cri_encode:
    push rbx
    push r12

    mov r12, rsi

    ; Dispatch to method-specific encoder
    call vertex_cri_protobuf_encode

    pop r12
    pop rbx
    ret


; -----------------------------------------------------------------------------
; Specific decoders
; -----------------------------------------------------------------------------

vertex_cri_decode_run_pod_sandbox:
    ; PodSandboxConfig → BXP
    ; Fields: metadata, hostname, log_directory, dns_config, port_mappings,
    ;         labels, annotations, linux (security_context, cgroup_parent),
    ;         runtime_handler
    xor rax, rax
    ret

vertex_cri_decode_stop_pod_sandbox:
    ; PodSandboxId → BXP
    xor rax, rax
    ret

vertex_cri_decode_create_container:
    ; ContainerConfig → BXP
    ; Fields: metadata, image, command, args, working_dir, env, mounts,
    ;         devices, labels, annotations, linux (resources, security_context)
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; gRPC server stub (uses serve/userve when ready)
; -----------------------------------------------------------------------------

; vertex_grpc_server_start — Start CRI gRPC server
; Returns: RAX = server_handle, or 0
global vertex_grpc_server_start
vertex_grpc_server_start:
    ; TODO: Integrate with serve/userve HTTP/2 or QUIC server
    ; For now: stub
    mov rax, 1
    ret


; vertex_grpc_server_stop — Stop gRPC server
global vertex_grpc_server_stop
vertex_grpc_server_stop:
    ret


; vertex_grpc_drain — Wait for in-flight requests
; Inputs: RDI = timeout_ns
global vertex_grpc_drain
vertex_grpc_drain:
    ret


; -----------------------------------------------------------------------------
; Protobuf helpers (minimal, for CRI only)
; -----------------------------------------------------------------------------

vertex_cri_protobuf_decode:
    ; Wire format: (field_number << 3) | wire_type
    ; Wire types: 0=varint, 1=64-bit, 2=length-delimited, 5=32-bit
    xor rax, rax
    ret

vertex_cri_protobuf_encode:
    xor rax, rax
    ret


; -----------------------------------------------------------------------------
; CRI Structures (BXP layout)
; -----------------------------------------------------------------------------
struc cri_pod_sandbox_config
    .metadata           resq 1      ; PodSandboxMetadata
    .hostname           resq 1
    .log_directory      resq 1
    .dns_config         resq 1      ; DNSConfig
    .port_mappings      resq 1      ; vec PortMapping
    .labels             resq 1      ; map
    .annotations        resq 1      ; map
    .linux              resq 1      ; LinuxPodSandboxConfig
    .runtime_handler    resq 1
endstruc

struc cri_container_config
    .metadata           resq 1      ; ContainerMetadata
    .image              resq 1      ; ImageSpec
    .command            resq 1      ; vec string
    .args               resq 1      ; vec string
    .working_dir        resq 1
    .env                resq 1      ; vec EnvVar
    .mounts             resq 1      ; vec Mount
    .devices            resq 1      ; vec Device
    .labels             resq 1
    .annotations        resq 1
    .linux              resq 1      ; LinuxContainerConfig
endstruc

struc cri_linux_container_resources
    .cpu_period         resq 1
    .cpu_quota          resq 1
    .cpu_shares         resq 1
    .memory_limit_in_bytes  resq 1
    .memory_swap_limit_in_bytes resq 1
    .oom_score_adj      resd 1
    .cpuset_cpus        resq 1
    .cpuset_mems        resq 1
    .hugepage_limits    resq 1      ; vec HugepageLimit
endstruc

%endif ; GUARD_VERTEX_CRI_ASM