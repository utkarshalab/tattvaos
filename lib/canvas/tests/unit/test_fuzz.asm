; ============================================================================
; Unit Test — Fuzzing the Server's Wire and Input (FND-10)
; ============================================================================
; test_fuzz_suite -> eax = failed cases (each case returns 0 / 1).
; A trusted client holding every capability sends random messages: random
; objects, opcodes, lengths and bytes (so random handles, sizes and counts),
; mixed with random raw input records of every type. The server must not
; crash (a crash fails the suite, ending the process), and afterwards a
; second client, well behaved, must still get its answer. Each case starts
; from a fixed seed, so a failure repeats.
;
; To reach past the handle checks, A makes real buffers and surfaces every
; 32 rounds, and the handles the server's replies give are put back into
; random messages' first two dwords half of the time.
;
; QA-03: the parsers of what comes from outside without a client. EDID
; (edid_parse, edid_find_preferred_mode): a monitor's block with 1 to 16
; random bytes, its checksum made right three times in four so the parser
; reads on. ICC profiles (icc_transform_build, then icc_transform_pixbuf
; when one is made): an RGB profile of every curve kind with random bytes,
; tag offsets and sizes, and cut short. Settings files (config_parse): a
; file of every kind of line and value, 1 to 16 random bytes and cut
; short, against a schema of every kind of key. Each must not crash, and most
; must get through: a third of the EDIDs parsed (about 45% are), a
; twentieth of the profiles made (about 9%), a twentieth of the settings
; files with no mistake at all.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/color.inc"
%include "inc/cwp.inc"
%include "inc/channel.inc"
%include "inc/backend.inc"
%include "inc/struct_offsets.inc"
%include "inc/config.inc"

extern arena_init
extern client_accept_trusted
extern msgbuf_read
extern msgbuf_write
extern server_init
extern server_poll
extern virtual_input_inject
extern edid_parse
extern edid_find_preferred_mode
extern icc_transform_build
extern icc_transform_pixbuf
extern config_parse

%define HEAP_SIZE   (4 * 1024 * 1024)  ; small, so a stray read past it faults
%define ROUNDS      12000               ; messages and records a case
%define PAYLOAD_MAX 128                 ; random bytes a message carries
%define OBJECTS     40                  ; object ids tried: 0 to 39
%define OPCODES     24
%define INPUT_TYPES 13                  ; 0 to 12: every type and past them
%define OP_SYNC     1
%define OP_CREATE   0
%define HANDLES     16                  ; replies' handles kept, a ring
%define PARSE_ROUNDS 20000              ; mutants a parser case
%define SMALL_HEAP  (256 * 1024)

section .text

global test_fuzz_suite
global test_fuzz_main
test_fuzz_suite:
test_fuzz_main:
    push rbx
    xor ebx, ebx
%macro CASE 2
    mov rdi, %2
    call fresh
    call %1
    add ebx, eax
%endmacro
    CASE tf_wire, 0x9E3779B97F4A7C15
    CASE tf_wire, 0x0123456789ABCDEF
    CASE tf_input, 0xD1B54A32D192ED03
    CASE tf_mixed, 0x8CB92BA72F3D8DD7
    mov rax, 0x5851F42D4C957F2D
    mov [rel seed], rax
    call tf_edid
    add ebx, eax
    mov rax, 0x14057B7EF767814F
    mov [rel seed], rax
    call tf_icc
    add ebx, eax
    mov rax, 0x2127599BF4325C37
    mov [rel seed], rax
    call tf_config
    add ebx, eax
    mov eax, ebx
    pop rbx
    ret

%macro PASS 0
    xor eax, eax
    add rsp, 8
    ret
.fail:
    mov eax, 1
    add rsp, 8
    ret
%endmacro

; rdi = the seed: a started server on 64x48, the fuzzing client A with every
; capability and the well-behaved client B, both drained
fresh:
    sub rsp, 8
    mov [rel seed], rdi
    mov qword [rel handled], 0
    mov dword [rel handle_next], 0
    lea rdi, [rel handles]
    xor eax, eax
    mov ecx, HANDLES
    rep stosd
    lea rdi, [rel arena]
    lea rsi, [rel heap]
    mov edx, HEAP_SIZE
    call arena_init
    lea rdi, [rel server]
    lea rsi, [rel arena]
    mov edx, 64
    mov ecx, 48
    xor r8d, r8d
    call server_init
    lea rdi, [rel server]
    lea rsi, [rel pair_a]
    mov edx, 0x03FFFFFF                 ; every capability there is
    call client_accept_trusted
    lea rdi, [rel server]
    lea rsi, [rel pair_b]
    mov edx, CAP_DISPLAY
    call client_accept_trusted
    call drain
    add rsp, 8
    ret

; -> rax = the next random number (xorshift64*)
random:
    mov rax, [rel seed]
    mov rcx, rax
    shr rcx, 12
    xor rax, rcx
    mov rcx, rax
    shl rcx, 25
    xor rax, rcx
    mov rcx, rax
    shr rcx, 27
    xor rax, rcx
    mov [rel seed], rax
    mov rcx, 0x2545F4914F6CDD1D
    imul rax, rcx
    ret

; edi = n -> eax = a random number below n
below:
    push rbx
    mov ebx, edi
    call random
    shr rax, 32
    xor edx, edx
    div ebx
    mov eax, edx
    pop rbx
    ret

; One random message from A: its object, opcode, length, every byte random.
message:
    push rbx
    mov edi, OBJECTS
    call below
    mov [rel hdr + MsgHdr.obj], eax
    mov edi, OPCODES
    call below
    mov [rel hdr + MsgHdr.opcode], ax
    mov word [rel hdr + MsgHdr.flags], 0
    mov edi, PAYLOAD_MAX + 1
    call below
    mov [rel hdr + MsgHdr.len], eax
    xor ebx, ebx                        ; the bytes; small numbers often,
.byte:                                  ; so sizes and handles are near real
    call random
    test al, 3
    jnz .keep
    and rax, 0xFF                       ; a quarter of the dwords small
.keep:
    lea rcx, [rel payload]
    mov [rcx + rbx * 8], rax
    inc ebx
    cmp ebx, PAYLOAD_MAX / 8
    jb .byte
    call random                         ; known handles, half the time
    test al, 1
    jz .first_done
    call known
    mov [rel payload], eax
.first_done:
    call random
    test al, 2
    jz .second_done
    call known
    mov [rel payload + 4], eax
.second_done:
    mov rdi, [rel pair_a + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel payload]
    call msgbuf_write                   ; full: dropped, the next poll empties
    pop rbx
    ret

; -> eax = one of the handles replies gave (0 before any)
known:
    sub rsp, 8
    mov edi, HANDLES
    call below
    lea rcx, [rel handles]
    mov eax, [rcx + rax * 4]
    add rsp, 8
    ret

; Real objects from A: a buffer of a random size up to 64x64, a surface.
objects:
    sub rsp, 8
    mov edi, 64
    call below
    inc eax
    mov [rel payload], eax
    mov edi, 64
    call below
    inc eax
    mov [rel payload + 4], eax
    mov dword [rel payload + 8], DRM_FORMAT_BGRA8888
    mov dword [rel payload + 12], 0
    mov qword [rel payload + 16], 0
    mov dword [rel hdr + MsgHdr.obj], CWP_OBJ_BUFFER
    mov word [rel hdr + MsgHdr.opcode], OP_CREATE
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], 24
    mov rdi, [rel pair_a + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel payload]
    call msgbuf_write
    mov dword [rel hdr + MsgHdr.obj], CWP_OBJ_SURFACE
    mov dword [rel hdr + MsgHdr.len], 0
    mov rdi, [rel pair_a + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel payload]
    call msgbuf_write
    add rsp, 8
    ret

; One random raw input record: any type, code, value and device 0-9.
record:
    push rbx
    push r12
    push r13
    mov edi, INPUT_TYPES
    call below
    mov ebx, eax
    call random
    mov r12d, eax
    test r12d, 0x10000000               ; often a small code
    jz .code
    and r12d, 0xFFFF
.code:
    call random
    mov r13d, eax
    mov edi, 10
    call below
    mov r8d, eax
    lea rdi, [rel server]
    mov esi, ebx
    mov edx, r12d
    mov ecx, r13d
    call virtual_input_inject
    pop r13
    pop r12
    pop rbx
    ret

; A turn, and what both clients were sent read and dropped.
turn:
    sub rsp, 8
    lea rdi, [rel server]
    call server_poll
    test rax, rax
    js .counted
    add [rel handled], rax
.counted:
    call drain
    add rsp, 8
    ret

drain:
    sub rsp, 8
.a:
    mov rdi, [rel pair_a + ChannelPair.server_to_client]
    lea rsi, [rel ans_hdr]
    lea rdx, [rel ans]
    mov ecx, 4096
    call msgbuf_read
    test rax, rax
    js .b
    test word [rel ans_hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jz .a
    cmp rax, 4
    jb .a
    mov ecx, [rel handle_next]          ; a reply's first dword, kept
    and ecx, HANDLES - 1
    lea rdx, [rel handles]
    mov eax, [rel ans]
    mov [rdx + rcx * 4], eax
    inc dword [rel handle_next]
    jmp .a
.b:
    mov rdi, [rel pair_b + ChannelPair.server_to_client]
    lea rsi, [rel ans_hdr]
    lea rdx, [rel ans]
    mov ecx, 4096
    call msgbuf_read
    test rax, rax
    jns .b
    add rsp, 8
    ret

; -> eax = 1 if client B, after everything, still has its sync answered
b_answered:
    sub rsp, 8
    mov dword [rel hdr + MsgHdr.obj], CWP_OBJ_DISPLAY
    mov word [rel hdr + MsgHdr.opcode], OP_SYNC
    mov word [rel hdr + MsgHdr.flags], 0
    mov dword [rel hdr + MsgHdr.len], 0
    mov rdi, [rel pair_b + ChannelPair.client_to_server]
    lea rsi, [rel hdr]
    lea rdx, [rel payload]
    call msgbuf_write
    lea rdi, [rel server]
    call server_poll
.next:
    mov rdi, [rel pair_b + ChannelPair.server_to_client]
    lea rsi, [rel ans_hdr]
    lea rdx, [rel ans]
    mov ecx, 4096
    call msgbuf_read
    test rax, rax
    js .no
    test word [rel ans_hdr + MsgHdr.flags], CWP_MSG_FLAG_REPLY
    jz .next
    mov eax, 1
    jmp .out
.no:
    xor eax, eax
.out:
    add rsp, 8
    ret

; %1: 1 for messages, 2 for records, 3 for both; ROUNDS of them, a turn
; every eight, then B answered
%macro FUZZ 1
    push rbx
    xor ebx, ebx
%%round:
  %if %1 == 3
    mov edi, 4
    call below
    test eax, eax
    jz %%input
  %endif
  %if %1 != 2
    call message
  %endif
  %if %1 == 3
    jmp %%sent
%%input:
  %endif
  %if %1 != 1
    call record
  %endif
%%sent:
    test ebx, 31
    jnz %%no_objects
    call objects
%%no_objects:
    test ebx, 7
    jnz %%no_turn
    call turn
%%no_turn:
    inc ebx
    cmp ebx, ROUNDS
    jb %%round
    call turn
    pop rbx
    call b_answered
    test eax, eax
    jz .fail
%endmacro

; Random messages only; most of them reach the dispatcher (the client is
; not cut off early, which would make the rest of the case empty)
tf_wire:
    sub rsp, 8
    FUZZ 1
    cmp qword [rel handled], ROUNDS / 2
    jb .fail
    PASS

; Random input records only
tf_input:
    sub rsp, 8
    FUZZ 2
    PASS

; Both, a quarter of them records
tf_mixed:
    sub rsp, 8
    FUZZ 3
    PASS

; a fresh small arena in small_arena -> rdi = it
small_fresh:
    sub rsp, 8
    lea rdi, [rel small_arena]
    lea rsi, [rel small_heap]
    mov edx, SMALL_HEAP
    call arena_init
    lea rdi, [rel small_arena]
    add rsp, 8
    ret

; esi = how many bytes, rdi = where: each one random
%macro SCRIBBLE 2                       ; buffer, its length
    mov edi, 16
    call below
    lea r12d, [rax + 1]
%%byte:
    mov edi, %2
    call below
    mov r13d, eax
    mov edi, 256
    call below
    lea rcx, [rel %1]
    mov [rcx + r13], al
    dec r12d
    jnz %%byte
%endmacro

tf_edid:
    push rbx
    push r12
    push r13
    mov qword [rel reached], 0
    mov ebx, PARSE_ROUNDS
.round:
    lea rdi, [rel edid_buf]
    lea rsi, [rel edid_seed]
    mov ecx, 128
    rep movsb
    SCRIBBLE edid_buf, 128
    mov edi, 4
    call below
    test eax, eax
    jz .parse                           ; a quarter keep a wrong sum
    lea rsi, [rel edid_buf]
    xor eax, eax
    xor ecx, ecx
.sum:
    add al, [rsi + rcx]
    inc ecx
    cmp ecx, 127
    jb .sum
    neg al
    mov [rsi + 127], al
.parse:
    lea rdi, [rel edid_buf]
    lea rsi, [rel edid_out]
    call edid_parse
    test rax, rax
    jnz .next
    inc qword [rel reached]
    call small_fresh                    ; a mode from the backend's arena
    mov [rel fake_backend + Backend.arena], rdi
    lea rax, [rel fake_backend]
    mov [rel fake_output + Output.backend], rax
    lea rdi, [rel edid_buf]
    lea rsi, [rel fake_output]
    call edid_find_preferred_mode
.next:
    dec ebx
    jnz .round
    xor eax, eax                        ; most read through
    cmp qword [rel reached], PARSE_ROUNDS / 3
    setb al
    pop r13
    pop r12
    pop rbx
    ret

tf_icc:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov qword [rel reached], 0
    mov ebx, PARSE_ROUNDS
.round:
    lea rdi, [rel icc_buf]
    lea rsi, [rel icc_seed]
    mov ecx, icc_seed_len
    rep movsb
    SCRIBBLE icc_buf, icc_seed_len
    mov edi, 2                          ; half: a tag's offset or size too
    call below
    test eax, eax
    jz .cut
    mov ecx, [rel icc_buf + 128]
    bswap ecx
    cmp ecx, 64
    ja .cut
    test ecx, ecx
    jz .cut
    mov edi, ecx
    call below
    lea r12, [rax + rax * 2]            ; entry x 12, + 4 or 8
    shl r12, 2
    mov edi, 2
    call below
    lea r12, [r12 + rax * 4 + 132 + 4]
    call random
    mov edi, 3                          ; small, near the end, or any
    mov r13, rax
    call below
    test eax, eax
    jnz .large
    and r13d, 0x3FF
    jmp .tagged
.large:
    cmp eax, 1
    jne .tagged
    mov eax, icc_seed_len
    and r13d, 0x3F
    sub eax, r13d
    mov r13d, eax
.tagged:
    bswap r13d
    lea rcx, [rel icc_buf]
    mov [rcx + r12], r13d
.cut:
    mov r14d, icc_seed_len              ; a quarter cut short
    mov edi, 4
    call below
    test eax, eax
    jnz .build
    mov edi, icc_seed_len
    call below
    mov r14d, eax
.build:
    call small_fresh
    lea rsi, [rel icc_buf]
    mov edx, r14d
    call icc_transform_build
    test rax, rax
    jz .next
    inc qword [rel reached]
    mov r12, rax
    lea rsi, [rel icc_image]            ; 4x4 of random pixels
    mov qword [rsi + PixBuf.width], 4
    mov qword [rsi + PixBuf.height], 4
    mov qword [rsi + PixBuf.stride], 16
    lea rax, [rel icc_pixels]
    mov [rsi + PixBuf.data], rax
    xor r13d, r13d
.pixel:
    call random
    lea rcx, [rel icc_pixels]
    mov [rcx + r13 * 4], eax
    inc r13d
    cmp r13d, 16
    jb .pixel
    mov rdi, r12
    lea rsi, [rel icc_image]
    call icc_transform_pixbuf
.next:
    dec ebx
    jnz .round
    xor eax, eax                        ; enough made a transform
    cmp qword [rel reached], PARSE_ROUNDS / 20
    setb al
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

tf_config:
    push rbx
    push r12
    push r13
    push r14
    sub rsp, 8
    mov qword [rel reached], 0
    mov ebx, PARSE_ROUNDS
.round:
    lea rdi, [rel conf_buf]
    lea rsi, [rel conf_seed]
    mov ecx, conf_seed_len
    rep movsb
    SCRIBBLE conf_buf, conf_seed_len
    mov r14d, conf_seed_len             ; a quarter cut short
    mov edi, 4
    call below
    test eax, eax
    jnz .parse
    mov edi, conf_seed_len
    call below
    mov r14d, eax
.parse:
    lea rdi, [rel conf_buf]
    mov esi, r14d
    lea rdx, [rel conf_schema]
    lea rcx, [rel conf_out]
    lea r8, [rel conf_result]
    call config_parse
    test rax, rax
    jnz .next
    inc qword [rel reached]
.next:
    dec ebx
    jnz .round
    xor eax, eax                        ; enough without a mistake
    cmp qword [rel reached], PARSE_ROUNDS / 20
    setb al
    add rsp, 8
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

section .rodata
; a settings file of every kind of line, and a schema of every kind of key
conf_seed:
    db "# settings", 13, 10
    db "name = canvas  ; inline", 10
    db "count = -12", 10
    db "[a]", 10
    db 9, "flag = yes", 13, 10
    db "mode = slow", 10
    db "[ b ]", 10
    db 'text = "q"\
	#"', 10
    db "level = 9000", 10
conf_seed_len equ $ - conf_seed
conf_modes: db "fast", 0, "slow", 0, 0
conf_default: db "x", 0
align 8
conf_schema:
    dq 6
    CONFIG_KEY "", "name", CONFIG_STRING, 0, 16, 0, conf_default
    CONFIG_KEY "", "count", CONFIG_INT, 16, -100, 100, 0
    CONFIG_KEY "a", "flag", CONFIG_BOOL, 24, 0, 0, 0
    CONFIG_KEY "a", "mode", CONFIG_ENUM, 32, conf_modes, 0, 0
    CONFIG_KEY "b", "text", CONFIG_STRING, 40, 32, 0, conf_default
    CONFIG_KEY "b", "level", CONFIG_INT, 72, 0, 10000, 1

; a monitor's EDID 1.4 block: a 1920x1080 preferred timing (148.5 MHz),
; a name descriptor; and the RGB profile of test_icc (P3 colorants; para
; 2, a table and a gamma curve)
edid_seed:
    db 0x00, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x56, 0x8B, 0x34, 0x12, 0x2A, 0x00, 0x00, 0x00
    db 0x0A, 0x24, 0x01, 0x04, 0x80, 0x3C, 0x22, 0x78, 0x0A, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x3A, 0x80, 0x18, 0x71, 0x38, 0x2D, 0x40, 0x58, 0x2C
    db 0x45, 0x00, 0x10, 0x09, 0x00, 0x00, 0x00, 0x1E, 0x00, 0x00, 0x00, 0xFC, 0x00, 0x55, 0x54, 0x4B
    db 0x41, 0x52, 0x53, 0x48, 0x41, 0x0A, 0x20, 0x20, 0x20, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4F
icc_seed:
    db 0x00, 0x00, 0x01, 0xD8, 0x00, 0x00, 0x00, 0x00, 0x02, 0x10, 0x00, 0x00, 0x6D, 0x6E, 0x74, 0x72
    db 0x52, 0x47, 0x42, 0x20, 0x58, 0x59, 0x5A, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x61, 0x63, 0x73, 0x70, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0xF6, 0xD6, 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0xD3, 0x2D, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x08, 0x64, 0x65, 0x73, 0x63, 0x00, 0x00, 0x00, 0xE4, 0x00, 0x00, 0x00, 0x60
    db 0x77, 0x74, 0x70, 0x74, 0x00, 0x00, 0x01, 0x44, 0x00, 0x00, 0x00, 0x14, 0x72, 0x58, 0x59, 0x5A
    db 0x00, 0x00, 0x01, 0x58, 0x00, 0x00, 0x00, 0x14, 0x67, 0x58, 0x59, 0x5A, 0x00, 0x00, 0x01, 0x6C
    db 0x00, 0x00, 0x00, 0x14, 0x62, 0x58, 0x59, 0x5A, 0x00, 0x00, 0x01, 0x80, 0x00, 0x00, 0x00, 0x14
    db 0x72, 0x54, 0x52, 0x43, 0x00, 0x00, 0x01, 0x94, 0x00, 0x00, 0x00, 0x1C, 0x67, 0x54, 0x52, 0x43
    db 0x00, 0x00, 0x01, 0xB0, 0x00, 0x00, 0x00, 0x18, 0x62, 0x54, 0x52, 0x43, 0x00, 0x00, 0x01, 0xC8
    db 0x00, 0x00, 0x00, 0x10, 0x64, 0x65, 0x73, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05
    db 0x74, 0x65, 0x73, 0x74, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x00, 0x58, 0x59, 0x5A, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF6, 0xD6
    db 0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0xD3, 0x2D, 0x58, 0x59, 0x5A, 0x20, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x83, 0xDF, 0x00, 0x00, 0x3D, 0xBF, 0xFF, 0xFF, 0xFF, 0xBB, 0x58, 0x59, 0x5A, 0x20
    db 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x4A, 0xBF, 0x00, 0x00, 0xB1, 0x37, 0x00, 0x00, 0x0A, 0xB9
    db 0x58, 0x59, 0x5A, 0x20, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x28, 0x38, 0x00, 0x00, 0x11, 0x0B
    db 0x00, 0x00, 0xC8, 0xB9, 0x70, 0x61, 0x72, 0x61, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02, 0x00, 0x00
    db 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0xE6, 0x66, 0x00, 0x00, 0x19, 0x9A, 0x00, 0x00, 0x0C, 0xCD
    db 0x63, 0x75, 0x72, 0x76, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x00, 0x00, 0x0B, 0xB8
    db 0x3A, 0x98, 0x9C, 0x40, 0xFF, 0xFF, 0x00, 0x00, 0x63, 0x75, 0x72, 0x76, 0x00, 0x00, 0x00, 0x00
    db 0x00, 0x00, 0x00, 0x01, 0x01, 0xCD, 0x00, 0x00
icc_seed_len equ $ - icc_seed

section .bss
alignb 16
server:         resb Server_size
arena:          resb Arena_size
pair_a:         resb ChannelPair_size
pair_b:         resb ChannelPair_size
hdr:            resb MsgHdr_size
ans_hdr:        resb MsgHdr_size
seed:           resq 1
handled:        resq 1                  ; requests the server took
handle_next:    resd 1
handles:        resd HANDLES            ; replies' first dwords
alignb 16
payload:        resb PAYLOAD_MAX
ans:            resb 4096
alignb 16
heap:           resb HEAP_SIZE
alignb 16
small_arena:    resb Arena_size
reached:        resq 1                  ; mutants a parser took
small_heap:     resb SMALL_HEAP
edid_buf:       resb 128
edid_out:       resb 512
fake_output:    resb Output_size
fake_backend:   resb Backend_size
icc_buf:        resb 4096
icc_image:      resb PixBuf_size
icc_pixels:     resd 16
conf_buf:       resb 256
conf_out:       resb 80
conf_result:    resb ConfigResult_size
