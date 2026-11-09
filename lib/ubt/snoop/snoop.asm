; =============================================================================
; Utkarsha OS — lib/ubt/snoop/snoop.asm — HCI capture (btsnoop)
; =============================================================================
;   ubt_snoop_start(buffer, size, adapter)  capture into the buffer (adapter
;                                           0: every adapter)
;   ubt_snoop_stop() → RAX = the bytes captured (a whole btsnoop file)
;   ubt_snoop_cmd / _event / _acl_out / _acl_in    (from the HCI code: RDI
;                                           = adapter, RSI = packet, EDX =
;                                           length; every register kept)
;
; The buffer gets the btsnoop file header (version 1, datalink 1002: HCI
; packets with their H4 type byte), then one record per packet: original
; and included length, flags (bit 0: received, bit 1: command or event),
; cumulative drops, and the time in microseconds since year 0 (2000-01-01
; plus the monotonic clock), all big-endian. When the buffer is full the
; packets are counted as dropped. Common protocol analysers open it as it
; is.
; =============================================================================

%ifndef LIB_UBT_SNOOP_SNOOP_ASM
%define LIB_UBT_SNOOP_SNOOP_ASM

%define SNOOP_HEADER        16
%define SNOOP_RECORD        24
%define SNOOP_EPOCH_2000    0x00DCDDB30F2F8000  ; µs from year 0 to 2000

section .bss
alignb 8
ubt_snoop_buf:      resq 1
ubt_snoop_size:     resq 1
ubt_snoop_used:     resq 1
ubt_snoop_only:     resq 1          ; the adapter captured (0: all)
global ubt_snoop_drops
ubt_snoop_drops:    resd 1
ubt_snoop_on:       resd 1

section .text

; -----------------------------------------------------------------------------
; ubt_snoop_start — RDI = buffer, RSI = its size (16 at least), RDX = the
;                   adapter (0: all) → EAX = 0, or -1 (too small)
; -----------------------------------------------------------------------------
global ubt_snoop_start
ubt_snoop_start:
    mov eax, -1
    cmp rsi, SNOOP_HEADER
    jb .out
    mov [rel ubt_snoop_buf], rdi
    mov [rel ubt_snoop_size], rsi
    mov [rel ubt_snoop_only], rdx
    mov dword [rel ubt_snoop_drops], 0
    ; "btsnoop\0", version 1, datalink 1002 (H4)
    mov rax, 0x00706F6F6E737462         ; "btsnoop\0"
    mov [rdi], rax
    mov dword [rdi + 8], 0x01000000
    mov dword [rdi + 12], 0xEA030000
    mov qword [rel ubt_snoop_used], SNOOP_HEADER
    mov dword [rel ubt_snoop_on], 1
    xor eax, eax
.out:
    ret

; ubt_snoop_stop → RAX = the bytes in the buffer (capture off)
global ubt_snoop_stop
ubt_snoop_stop:
    mov dword [rel ubt_snoop_on], 0
    mov rax, [rel ubt_snoop_used]
    ret

; the four doors: ECX = (H4 type << 8) | flags, then the common recorder
global ubt_snoop_cmd
ubt_snoop_cmd:
    push rcx
    mov ecx, (1 << 8) | 2               ; command, sent
    jmp snoop_record
global ubt_snoop_event
ubt_snoop_event:
    push rcx
    mov ecx, (4 << 8) | 3               ; event, received
    jmp snoop_record
global ubt_snoop_acl_out
ubt_snoop_acl_out:
    push rcx
    mov ecx, (2 << 8) | 0               ; ACL, sent
    jmp snoop_record
global ubt_snoop_acl_in
ubt_snoop_acl_in:
    push rcx
    mov ecx, (2 << 8) | 1               ; ACL, received
; snoop_record — RDI = adapter, RSI = packet, EDX = length, ECX = type and
; flags, RCX of the caller on the stack: one record, every register kept
snoop_record:
    cmp dword [rel ubt_snoop_on], 0
    je .quick
    push rax
    push rdx
    push rsi
    push rdi
    push r8
    push r9
    push r10
    push r11
    push rbx
    push rbp
    mov rbp, rsp
    and rsp, -16                        ; (the clock is a hook)
    mov rax, [rel ubt_snoop_only]
    test rax, rax
    jz .take
    cmp rax, rdi
    jne .done
.take:
    mov ebx, ecx
    mov r8, rsi                         ; packet
    mov r9d, edx                        ; its length
    ; room for the record, the type byte and the packet?
    mov rax, [rel ubt_snoop_used]
    lea r10, [rax + r9 + SNOOP_RECORD + 1]
    cmp r10, [rel ubt_snoop_size]
    ja .drop
    mov r11, [rel ubt_snoop_buf]
    add r11, rax                        ; the record
    mov [rel ubt_snoop_used], r10
    lea eax, [r9 + 1]
    bswap eax
    mov [r11], eax                      ; original length
    mov [r11 + 4], eax                  ; included length
    movzx eax, bl
    bswap eax
    mov [r11 + 8], eax                  ; flags
    mov eax, [rel ubt_snoop_drops]
    bswap eax
    mov [r11 + 12], eax
    push r8
    push r9
    push r11
    sub rsp, 8
    call ubt_now
    add rsp, 8
    pop r11
    pop r9
    pop r8
    imul rax, rax, 1000
    mov rcx, SNOOP_EPOCH_2000
    add rax, rcx
    bswap rax
    mov [r11 + 16], rax
    mov eax, ebx
    shr eax, 8
    mov [r11 + 24], al                  ; the H4 type
    lea rdi, [r11 + 25]
    mov rsi, r8
    mov ecx, r9d
    rep movsb
    jmp .done
.drop:
    inc dword [rel ubt_snoop_drops]
.done:
    mov rsp, rbp
    pop rbp
    pop rbx
    pop r11
    pop r10
    pop r9
    pop r8
    pop rdi
    pop rsi
    pop rdx
    pop rax
.quick:
    pop rcx
    ret

%endif ; LIB_UBT_SNOOP_SNOOP_ASM
