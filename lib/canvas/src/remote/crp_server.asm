; ============================================================================
; CRP — Canvas Remote Protocol (native, compressed, multi-viewer)
; Frame header + tile stream: tile(x,y,w,h,enc,len,payload)
; ============================================================================

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/ut.inc"
%include "inc/struct_offsets.inc"
%include "inc/externs.inc"

%define CRP_MAGIC        0x50524343  ; "CRCP"
%define CRP_VERSION      1
%define CRP_PORT_DEFAULT 5901

; CrpFrameHdr struct offsets
struc CrpFrameHdr
    .magic:                   resd 1
    .version:                 resw 1
    .flags:                   resw 1
    .seq:                     resq 1
    .tile_count:              resd 1
    .total_bytes:             resq 1
    resb 4
endstruc

; CrpTileHdr struct offsets
struc CrpTileHdr
    .x:                       resw 1
    .y:                       resw 1
    .w:                       resw 1
    .h:                       resw 1
    .enc:                     resb 1
    .reserved:                resb 1
    .len:                     resw 1
endstruc

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
    mov rsi, CrpServer_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r12, rax
    mov qword [r12 + CrpServer.server], rbx
    mov qword [r12 + CrpServer.listener], 0
    mov dword [r12 + CrpServer.port], CRP_PORT_DEFAULT
    mov qword [r12 + CrpServer.sessions], 0
    mov qword [r12 + CrpServer.voutput], r13
    mov byte [r12 + CrpServer.running], 0
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
    mov dword [rbx + CrpServer.port], r12d
    call ut_tls_listen
    test rax, rax
    js .fail
    mov [rbx + CrpServer.listener], rax
    mov byte [rbx + CrpServer.running], 1
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
    mov r13, [rbx + CrpServer.voutput]
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
    mov rdx, CrpFrameHdr_size
    call rfb_tls_write_all
    test rax, rax
    jnz .write_fail

    ; Emit each dirty tile as raw ARGB. Payload rows are written separately,
    ; which avoids a 16 KiB scratch allocation while remaining one byte stream.
    mov dword [rsp + 40], 0         ; tile index
.tile_loop:
    mov eax, [r14 + TileDiff.cols]
    imul eax, [r14 + TileDiff.rows]
    cmp [rsp + 40], eax
    jae .tiles_done
    mov eax, [rsp + 40]
    mov ecx, eax
    shr eax, 3
    and ecx, 7
    mov rdx, [r14 + TileDiff.dirty]
    movzx eax, byte [rdx + rax]
    bt eax, ecx
    jnc .next_tile

    xor edx, edx
    mov ecx, [r14 + TileDiff.cols]
    div ecx                         ; eax=row, edx=column
    mov [rsp + 44], eax
    mov [rsp + 48], edx
    imul edx, [r14 + TileDiff.tile_w]
    mov [rsp + 52], edx             ; x
    imul eax, [r14 + TileDiff.tile_h]
    mov [rsp + 56], eax             ; y
    mov ecx, [r14 + TileDiff.tile_w]
    mov eax, [r13 + VirtualOutput.width]
    sub eax, edx
    cmp ecx, eax
    cmova ecx, eax
    mov [rsp + 60], ecx             ; w
    mov edx, [r14 + TileDiff.tile_h]
    mov eax, [r13 + VirtualOutput.height]
    sub eax, [rsp + 56]
    cmp edx, eax
    cmova edx, eax                  ; h
    mov eax, [rsp + 52]
    mov word [rsp + 24 + CrpTileHdr.x], ax
    mov eax, [rsp + 56]
    mov word [rsp + 24 + CrpTileHdr.y], ax
    mov word [rsp + 24 + CrpTileHdr.w], cx
    mov word [rsp + 24 + CrpTileHdr.h], dx
    mov byte [rsp + 24 + CrpTileHdr.enc], 0
    mov byte [rsp + 24 + CrpTileHdr.reserved], 0
    mov eax, ecx
    imul eax, edx
    shl eax, 2
    mov word [rsp + 24 + CrpTileHdr.len], ax
    mov rdi, [r12 + CrpSession.conn]
    lea rsi, [rsp + 24]
    mov rdx, CrpTileHdr_size
    call rfb_tls_write_all
    test rax, rax
    jnz .write_fail

    mov dword [rsp + 44], 0         ; payload row
.payload_row:
    mov eax, [rsp + 44]
    movzx ecx, word [rsp + 24 + CrpTileHdr.h]
    cmp eax, ecx
    jae .next_tile
    add eax, [rsp + 56]
    imul rax, [r15 + PixBuf.stride]
    mov rsi, [r15 + PixBuf.data]
    add rsi, rax
    mov eax, [rsp + 52]
    shl eax, 2
    add rsi, rax
    movzx edx, word [rsp + 24 + CrpTileHdr.w]
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
