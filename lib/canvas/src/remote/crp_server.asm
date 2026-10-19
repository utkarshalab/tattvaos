; ============================================================================
; CRP — Canvas Remote Protocol (native, compressed, multi-viewer)
; Frame header + tile stream: tile(x,y,w,h,enc,len,payload)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/tattva.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

; struct offsets (hoisted above use)
%define CRP_MAGIC        0x50524343  ; "CRCP"
%define CRP_VERSION      1
%define CRP_PORT_DEFAULT 5901
%define CrpFrameHdr_SIZE    24
%define CrpTileHdr_SIZE    12

; CrpFrameHdr struct offsets
%define CrpFrameHdr_magic        0
%define CrpFrameHdr_version      4
%define CrpFrameHdr_flags        6
%define CrpFrameHdr_seq          8
%define CrpFrameHdr_tile_count   16
%define CrpFrameHdr_total_bytes  20

; CrpTileHdr struct offsets
%define CrpTileHdr_x             0
%define CrpTileHdr_y             2
%define CrpTileHdr_w             4
%define CrpTileHdr_h             6
%define CrpTileHdr_enc           8
%define CrpTileHdr_reserved      9
%define CrpTileHdr_len           10
%define TileDiff_tile_w          0
%define TileDiff_tile_h          4
%define TileDiff_cols            8
%define TileDiff_rows            12
%define TileDiff_dirty           24

section .text

; ---------------------------------------------------------------------------
; crp_server_init
; ---------------------------------------------------------------------------
global crp_server_init
crp_server_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov rdi, [rbx + Server.arena]
    mov rsi, CrpServer_SIZE
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax
    mov qword [r12 + CrpServer_server], rbx
    mov qword [r12 + CrpServer_listener], 0
    mov dword [r12 + CrpServer_port], CRP_PORT_DEFAULT
    mov qword [r12 + CrpServer_sessions], 0
    mov qword [r12 + CrpServer_voutput], r13
    mov byte [r12 + CrpServer_running], 0
    mov qword [rbx + Server.crp], r12
    mov rax, r12
    EPILOGUE_RESTORE rbx, r12, r13
    ret
.oom:
    mov rax, -(ENOMEM)
    EPILOGUE_RESTORE rbx, r12, r13
    ret

; ---------------------------------------------------------------------------
; crp_server_listen
; ---------------------------------------------------------------------------
global crp_server_listen
crp_server_listen:
    PROLOGUE_SAVE rbx, r12
    mov rbx, rdi
    mov r12d, esi
    ASSERT_PTR rbx
    mov dword [rbx + CrpServer_port], r12d
    call tv_tls_listen
    test rax, rax
    js .fail
    mov [rbx + CrpServer_listener], rax
    mov byte [rbx + CrpServer_running], 1
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12
    ret
.fail:
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12
    ret

; ---------------------------------------------------------------------------
; crp_send_frame
;   IN: rdi = CrpServer*, rsi = session (conn handle in rsi+8 layout)
;   Encodes all dirty tiles with adaptive choice
; ---------------------------------------------------------------------------
global crp_send_frame
crp_send_frame:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    mov rbx, rdi
    mov r12, rsi
    ASSERT_PTR rbx
    ASSERT_PTR r12
    mov r13, [rbx + CrpServer_voutput]
    test r13, r13
    jz .done
    mov rdi, r13
    call virtual_output_damage
    test rax, rax
    jz .done
    mov r14, [r13 + VirtualOutput.tilediff]
    mov r15, [r13 + VirtualOutput.fb]
    test r14, r14
    jz .done
    test r15, r15
    jz .done
    ; frame header
    sub rsp, 64
    mov dword [rsp + 0], CRP_MAGIC
    mov word [rsp + 4], CRP_VERSION
    mov word [rsp + 6], 0
    mov rax, [r13 + VirtualOutput.seq]
    inc qword [r13 + VirtualOutput.seq]
    mov [rsp + 8], rax
    mov eax, [r14 + 32]             ; dirty_count low dword
    mov [rsp + 16], eax
    mov dword [rsp + 20], 0
    mov rdi, [r12 + 8]  ; conn
    mov rsi, rsp
    mov rdx, CrpFrameHdr_SIZE
    call rfb_tls_write_all
    test rax, rax
    jnz .write_fail

    ; Emit each dirty tile as raw ARGB. Payload rows are written separately,
    ; which avoids a 16 KiB scratch allocation while remaining one byte stream.
    mov dword [rsp + 40], 0         ; tile index
.tile_loop:
    mov eax, [r14 + TileDiff_cols]
    imul eax, [r14 + TileDiff_rows]
    cmp [rsp + 40], eax
    jae .tiles_done
    mov eax, [rsp + 40]
    mov ecx, eax
    shr eax, 3
    and ecx, 7
    mov rdx, [r14 + TileDiff_dirty]
    movzx eax, byte [rdx + rax]
    bt eax, ecx
    jnc .next_tile

    xor edx, edx
    mov ecx, [r14 + TileDiff_cols]
    div ecx                         ; eax=row, edx=column
    mov [rsp + 44], eax
    mov [rsp + 48], edx
    imul edx, [r14 + TileDiff_tile_w]
    mov [rsp + 52], edx             ; x
    imul eax, [r14 + TileDiff_tile_h]
    mov [rsp + 56], eax             ; y
    mov ecx, [r14 + TileDiff_tile_w]
    mov eax, [r13 + VirtualOutput.width]
    sub eax, edx
    cmp ecx, eax
    cmova ecx, eax
    mov [rsp + 60], ecx             ; w
    mov edx, [r14 + TileDiff_tile_h]
    mov eax, [r13 + VirtualOutput.height]
    sub eax, [rsp + 56]
    cmp edx, eax
    cmova edx, eax                  ; h
    mov eax, [rsp + 52]
    mov word [rsp + 24 + CrpTileHdr_x], ax
    mov eax, [rsp + 56]
    mov word [rsp + 24 + CrpTileHdr_y], ax
    mov word [rsp + 24 + CrpTileHdr_w], cx
    mov word [rsp + 24 + CrpTileHdr_h], dx
    mov byte [rsp + 24 + CrpTileHdr_enc], 0
    mov byte [rsp + 24 + CrpTileHdr_reserved], 0
    mov eax, ecx
    imul eax, edx
    shl eax, 2
    mov word [rsp + 24 + CrpTileHdr_len], ax
    mov rdi, [r12 + CrpSession.conn]
    lea rsi, [rsp + 24]
    mov rdx, CrpTileHdr_SIZE
    call rfb_tls_write_all
    test rax, rax
    jnz .write_fail

    mov dword [rsp + 44], 0         ; payload row
.payload_row:
    mov eax, [rsp + 44]
    movzx ecx, word [rsp + 24 + CrpTileHdr_h]
    cmp eax, ecx
    jae .next_tile
    add eax, [rsp + 56]
    imul rax, [r15 + PixBuf.stride]
    mov rsi, [r15 + PixBuf.data]
    add rsi, rax
    mov eax, [rsp + 52]
    shl eax, 2
    add rsi, rax
    movzx edx, word [rsp + 24 + CrpTileHdr_w]
    shl edx, 2
    mov rdi, [r12 + CrpSession.conn]
    call rfb_tls_write_all
    test rax, rax
    jnz .write_fail
    inc dword [rsp + 44]
    jmp .payload_row
.next_tile:
    inc dword [rsp + 40]
    jmp .tile_loop
.tiles_done:
    add rsp, 64
.done:
    xor rax, rax
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret
.write_fail:
    add rsp, 64
    mov rax, -(EREMOTE_TLS)
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15
    ret

section .data
global crp_server_version
crp_server_version: dq 0x010000
