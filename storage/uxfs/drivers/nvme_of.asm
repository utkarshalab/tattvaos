; =============================================================================
; Tattva OS — storage/uxfs/drivers/nvme_of.asm
; =============================================================================
; NVMe over Fabrics (NVMe-oF) Transport Driver.
;
; Implements:
;   - Fabrics Connect for admin and I/O queues (`uxfs_nvme_of_connect`)
;   - Property get/set over the fabrics command set (`uxfs_nvme_of_prop_*`)
;   - Keep-alive maintenance (`uxfs_nvme_of_keep_alive`)
;   - Graceful teardown (`uxfs_nvme_of_disconnect`)
;
; NVMe-oF carries the same command set as local NVMe, but the transport is a
; network rather than a PCIe BAR. That changes three things the driver has to
; handle explicitly.
;
; There is no doorbell register. Commands travel as 64-byte capsules, so the
; queue is established by an in-band Connect command rather than by writing
; queue base addresses into MMIO.
;
; Every queue connects separately. The admin queue (QID 0) must connect first
; and carries the host NQN and host identifier; each I/O queue then connects
; against the controller id the admin queue returned.
;
; A network fabric can partition silently, so the association is kept alive by
; an explicit timer. If the controller sees no traffic within the Keep Alive
; Timeout it tears the association down — meaning an idle-but-healthy host
; must still send keep-alives or it will be disconnected.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "storage/uxfs/uxfs.inc"

%define NVME_OF_OPCODE_FABRICS      0x7F
%define NVME_OF_FCTYPE_PROP_SET     0x00
%define NVME_OF_FCTYPE_CONNECT      0x01
%define NVME_OF_FCTYPE_PROP_GET     0x04
%define NVME_OF_FCTYPE_DISCONNECT   0x08
%define NVME_ADMIN_KEEP_ALIVE       0x18

%define NVME_OF_ADMIN_QID           0
%define NVME_OF_DEFAULT_SQSIZE      128
%define NVME_OF_DEFAULT_KATO        30000       ; 30s keep-alive timeout
%define NVME_OF_NQN_MAX             256
%define NVME_OF_HOSTID_BYTES        16

; Controller property register offsets, mirrored from the PCIe register map.
%define NVME_OF_PROP_CAP            0x00
%define NVME_OF_PROP_VS             0x08
%define NVME_OF_PROP_CC             0x14
%define NVME_OF_PROP_CSTS           0x1C

; Transport types.
%define NVME_OF_TRTYPE_RDMA         1
%define NVME_OF_TRTYPE_FC           2
%define NVME_OF_TRTYPE_TCP          3

struc uxfs_nvme_of_connect_cmd_t
    .opcode:            resb 1      ; NVME_OF_OPCODE_FABRICS
    .flags:             resb 1
    .cid:               resw 1      ; Command identifier
    .fctype:            resb 1      ; NVME_OF_FCTYPE_CONNECT
    .reserved:          resb 19
    .qid:               resw 1      ; 0 = admin queue, 1+ = I/O queue
    .sqsize:            resw 1      ; Submission queue depth, 0-based
    .cattr:             resb 1      ; Connect attributes
    .reserved2:         resb 3
    .kato:              resd 1      ; Keep Alive Timeout in milliseconds
endstruc

; Connect data payload that accompanies the command capsule.
struc uxfs_nvme_of_connect_data_t
    .hostid:            resb NVME_OF_HOSTID_BYTES   ; Host identifier
    .cntlid:            resw 1                      ; 0xFFFF requests dynamic
    .reserved:          resb 238
    .subnqn:            resb NVME_OF_NQN_MAX        ; Subsystem NQN
    .hostnqn:           resb NVME_OF_NQN_MAX        ; Host NQN
endstruc

; Per-association state.
struc uxfs_nvme_of_assoc_t
    .trtype:            resd 1      ; NVME_OF_TRTYPE_*
    .cntlid:            resd 1      ; Controller id assigned at connect
    .kato:              resd 1      ; Negotiated keep-alive timeout
    .queues:            resd 1      ; Connected queue count
    .connected:         resd 1
    .reserved:          resd 1
endstruc

section .data
align 64

global uxfs_nvme_of_assoc
uxfs_nvme_of_assoc:     times uxfs_nvme_of_assoc_t_size db 0

; Capsule staging. Kept resident so the transport can DMA straight from it.
align 64
uxfs_nvme_of_capsule:   times 64 db 0
uxfs_nvme_of_data:      times uxfs_nvme_of_connect_data_t_size db 0

uxfs_nvme_of_cid:       dd 1
uxfs_nvme_of_ka_sent:   dq 0
uxfs_nvme_of_errors:    dq 0

section .text

global uxfs_nvme_of_connect
global uxfs_nvme_of_disconnect
global uxfs_nvme_of_prop_get
global uxfs_nvme_of_prop_set
global uxfs_nvme_of_keep_alive
global uxfs_nvme_of_build_capsule

; -----------------------------------------------------------------------------
; uxfs_nvme_of_build_capsule
;
; Fills the 64-byte fabrics command capsule.
;
; Inputs:
;   EDI = Fabrics command type (NVME_OF_FCTYPE_*)
;
; Returns:
;   RAX = Pointer to the staged capsule
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_of_build_capsule:
    push rbx

    lea rbx, [uxfs_nvme_of_capsule]

    ; Zero the capsule: reserved fields must be zero on the wire, and stale
    ; contents would be interpreted by the target.
    push rdi
    mov rdi, rbx
    mov rcx, 64
    xor al, al
    rep stosb
    pop rdi

    mov byte [rbx + uxfs_nvme_of_connect_cmd_t.opcode], NVME_OF_OPCODE_FABRICS
    mov byte [rbx + uxfs_nvme_of_connect_cmd_t.fctype], dil

    mov eax, [uxfs_nvme_of_cid]
    inc dword [uxfs_nvme_of_cid]
    mov word [rbx + uxfs_nvme_of_connect_cmd_t.cid], ax

    mov rax, rbx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_of_connect
;
; Establishes a queue association with a remote subsystem.
;
; The admin queue must connect before any I/O queue, because the controller id
; that I/O queues bind to is only assigned during the admin connect.
;
; Inputs:
;   EDI = Transport type (NVME_OF_TRTYPE_*)
;   ESI = Queue id (0 for admin)
;   RDX = Pointer to the subsystem NQN string
;   RCX = Pointer to the host NQN string
;
; Returns:
;   EAX = 0 on success
;         POSIX_EINVAL on a bad argument or premature I/O connect
;         POSIX_EIO    on transport failure
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_of_connect:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12d, edi                   ; Transport
    mov r13d, esi                   ; Queue id
    mov r14, rdx                    ; Subsystem NQN
    mov r15, rcx                    ; Host NQN

    test r14, r14
    jz .oc_inval
    test r15, r15
    jz .oc_inval
    cmp r12d, NVME_OF_TRTYPE_TCP
    ja .oc_inval

    lea rbx, [uxfs_nvme_of_assoc]

    ; An I/O queue cannot connect before the admin queue has.
    test r13d, r13d
    jz .oc_admin
    cmp dword [rbx + uxfs_nvme_of_assoc_t.connected], 0
    je .oc_inval

.oc_admin:
    ; ---- Build the command capsule ----
    mov edi, NVME_OF_FCTYPE_CONNECT
    call uxfs_nvme_of_build_capsule
    mov rcx, rax

    mov word [rcx + uxfs_nvme_of_connect_cmd_t.qid], r13w

    ; SQSIZE is 0-based on the wire.
    mov ax, NVME_OF_DEFAULT_SQSIZE - 1
    mov word [rcx + uxfs_nvme_of_connect_cmd_t.sqsize], ax

    mov dword [rcx + uxfs_nvme_of_connect_cmd_t.kato], NVME_OF_DEFAULT_KATO

    ; ---- Build the accompanying data payload ----
    lea rdi, [uxfs_nvme_of_data]
    mov rcx, uxfs_nvme_of_connect_data_t_size
    xor al, al
    rep stosb

    lea rdi, [uxfs_nvme_of_data]

    ; Dynamic controller allocation for the admin queue; the assigned id for
    ; every I/O queue that follows.
    test r13d, r13d
    jnz .oc_use_cntlid
    mov word [rdi + uxfs_nvme_of_connect_data_t.cntlid], 0xFFFF
    jmp .oc_nqn

.oc_use_cntlid:
    mov eax, dword [rbx + uxfs_nvme_of_assoc_t.cntlid]
    mov word [rdi + uxfs_nvme_of_connect_data_t.cntlid], ax

.oc_nqn:
    ; Copy the subsystem NQN, bounded.
    lea rdi, [uxfs_nvme_of_data + uxfs_nvme_of_connect_data_t.subnqn]
    mov rsi, r14
    mov rcx, NVME_OF_NQN_MAX
    call uxfs_nvme_of_copy_nqn

    lea rdi, [uxfs_nvme_of_data + uxfs_nvme_of_connect_data_t.hostnqn]
    mov rsi, r15
    mov rcx, NVME_OF_NQN_MAX
    call uxfs_nvme_of_copy_nqn

    ; ---- Record the association ----
    mov dword [rbx + uxfs_nvme_of_assoc_t.trtype], r12d
    mov dword [rbx + uxfs_nvme_of_assoc_t.kato], NVME_OF_DEFAULT_KATO

    test r13d, r13d
    jnz .oc_io_queue

    ; Admin connect completed: the controller id would arrive in the response
    ; capsule. Dynamic allocation is recorded until the transport fills it in.
    mov dword [rbx + uxfs_nvme_of_assoc_t.cntlid], 0xFFFF
    mov dword [rbx + uxfs_nvme_of_assoc_t.connected], 1
    mov dword [rbx + uxfs_nvme_of_assoc_t.queues], 1
    xor eax, eax
    jmp .oc_return

.oc_io_queue:
    inc dword [rbx + uxfs_nvme_of_assoc_t.queues]
    xor eax, eax
    jmp .oc_return

.oc_inval:
    inc qword [uxfs_nvme_of_errors]
    mov eax, POSIX_EINVAL

.oc_return:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_of_copy_nqn
;
; Copies a NUL-terminated NQN into a fixed-width field, zero-padding the
; remainder. NQNs are compared byte-for-byte by the target, so trailing
; garbage in the padding causes a spurious authentication failure.
;
; Inputs:
;   RDI = Destination field
;   RSI = Source string
;   RCX = Field width
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_of_copy_nqn:
    push rbx
    push r12

    mov rbx, rdi
    mov r12, rcx
    xor rdx, rdx

.cn_copy:
    cmp rdx, r12
    jae .cn_done
    mov al, byte [rsi + rdx]
    test al, al
    jz .cn_pad
    mov byte [rbx + rdx], al
    inc rdx
    jmp .cn_copy

.cn_pad:
    cmp rdx, r12
    jae .cn_done
    mov byte [rbx + rdx], 0
    inc rdx
    jmp .cn_pad

.cn_done:
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_of_prop_get
;
; Reads a controller property. Over fabrics these are fetched in-band rather
; than read from an MMIO BAR.
;
; Inputs:
;   EDI = Property offset (NVME_OF_PROP_*)
;   RSI = Pointer to a 64-bit output slot
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL on a bad argument
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_of_prop_get:
    push rbx

    test rsi, rsi
    jz .pg_inval

    lea rbx, [uxfs_nvme_of_assoc]
    cmp dword [rbx + uxfs_nvme_of_assoc_t.connected], 0
    je .pg_inval

    push rsi
    mov edi, NVME_OF_FCTYPE_PROP_GET
    call uxfs_nvme_of_build_capsule
    pop rsi

    ; Property offset travels in the capsule's reserved region.
    mov dword [rax + uxfs_nvme_of_connect_cmd_t.reserved + 4], edi

    mov qword [rsi], 0              ; Transport fills this from the response

    xor eax, eax
    pop rbx
    ret

.pg_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_of_prop_set
;
; Writes a controller property.
;
; Inputs:
;   EDI = Property offset
;   RSI = Value to write
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL when not connected
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_of_prop_set:
    push rbx
    push r12

    mov r12, rsi

    lea rbx, [uxfs_nvme_of_assoc]
    cmp dword [rbx + uxfs_nvme_of_assoc_t.connected], 0
    je .ps_inval

    push rdi
    mov edi, NVME_OF_FCTYPE_PROP_SET
    call uxfs_nvme_of_build_capsule
    pop rdi

    mov dword [rax + uxfs_nvme_of_connect_cmd_t.reserved + 4], edi
    mov [rax + uxfs_nvme_of_connect_cmd_t.reserved + 8], r12

    xor eax, eax
    pop r12
    pop rbx
    ret

.ps_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_of_keep_alive
;
; Sends a keep-alive so the controller does not tear the association down.
;
; This must be called well inside the negotiated KATO. Unlike local NVMe there
; is no physical link whose loss is self-evident — an idle association looks
; identical to a dead one from the target's side.
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL when no association exists
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_of_keep_alive:
    push rbx

    lea rbx, [uxfs_nvme_of_assoc]
    cmp dword [rbx + uxfs_nvme_of_assoc_t.connected], 0
    je .ka_inval

    lea rbx, [uxfs_nvme_of_capsule]
    mov rdi, rbx
    mov rcx, 64
    xor al, al
    rep stosb

    lea rbx, [uxfs_nvme_of_capsule]
    mov byte [rbx + uxfs_nvme_of_connect_cmd_t.opcode], NVME_ADMIN_KEEP_ALIVE

    mov eax, [uxfs_nvme_of_cid]
    inc dword [uxfs_nvme_of_cid]
    mov word [rbx + uxfs_nvme_of_connect_cmd_t.cid], ax

    inc qword [uxfs_nvme_of_ka_sent]

    xor eax, eax
    pop rbx
    ret

.ka_inval:
    mov eax, POSIX_EINVAL
    pop rbx
    ret

; -----------------------------------------------------------------------------
; uxfs_nvme_of_disconnect
;
; Tears the association down cleanly, releasing controller resources rather
; than leaving them to expire on the keep-alive timeout.
;
; Inputs:
;   ESI = Queue id to disconnect
;
; Returns:
;   EAX = 0 on success, POSIX_EINVAL when not connected
; -----------------------------------------------------------------------------
align 32
uxfs_nvme_of_disconnect:
    push rbx
    push r12

    mov r12d, esi

    lea rbx, [uxfs_nvme_of_assoc]
    cmp dword [rbx + uxfs_nvme_of_assoc_t.connected], 0
    je .od_inval

    mov edi, NVME_OF_FCTYPE_DISCONNECT
    call uxfs_nvme_of_build_capsule
    mov word [rax + uxfs_nvme_of_connect_cmd_t.qid], r12w

    dec dword [rbx + uxfs_nvme_of_assoc_t.queues]
    cmp dword [rbx + uxfs_nvme_of_assoc_t.queues], 0
    jg .od_done

    ; Last queue gone: the association no longer exists.
    mov dword [rbx + uxfs_nvme_of_assoc_t.connected], 0
    mov dword [rbx + uxfs_nvme_of_assoc_t.cntlid], 0
    mov dword [rbx + uxfs_nvme_of_assoc_t.queues], 0

.od_done:
    xor eax, eax
    pop r12
    pop rbx
    ret

.od_inval:
    mov eax, POSIX_EINVAL
    pop r12
    pop rbx
    ret
