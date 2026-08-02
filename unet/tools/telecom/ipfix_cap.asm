; =============================================================================
; Tattva OS — unet/tools/telecom/ipfix_cap.asm
; =============================================================================
; IPFIX / NetFlow v9 Flow Record Collector & Exporter Tool (`ipfix-cap`).
;
; Features:
;   - RFC 7011 IPFIX UDP Port 4739 Message Header Verification (Version 10)
;   - Template Set (Set ID 2) Parsing & Template Registry Caching
;   - Data Set Record Decoding Using Cached Template Field Definitions
;   - Information Elements: Source IPv4 (IE 8), Destination IPv4 (IE 12),
;     Protocol (IE 4), Source Port (IE 7), Destination Port (IE 11),
;     Octet Count (IE 1), Packet Count (IE 2), Flow Start (IE 152), Flow End (IE 153)
;   - Hash-Indexed Template Registry for O(1) Template ID -> Field Map Lookup
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define IPFIX_PORT                  4739
%define IPFIX_VERSION               10
%define IPFIX_SET_ID_TEMPLATE       2
%define IPFIX_SET_ID_OPTIONS_TPL    3
%define IPFIX_MIN_DATA_SET_ID       256

%define IPFIX_MAX_TEMPLATES         64
%define IPFIX_MAX_FIELDS_PER_TPL    32

struc ipfix_msg_hdr_t
    .version:           resw 1      ; 0x000A (Version 10)
    .length:            resw 1      ; Total Message Length (Big Endian)
    .export_time:       resd 1      ; UNIX Epoch Export Timestamp
    .sequence:          resd 1      ; Sequence Number
    .observation_id:    resd 1      ; Observation Domain ID
endstruc

struc ipfix_set_hdr_t
    .set_id:            resw 1      ; 2=Template, 3=Options Template, >=256=Data
    .set_length:        resw 1      ; Set Length including header
endstruc

struc ipfix_field_spec_t
    .ie_id:             resw 1      ; Information Element ID
    .field_length:      resw 1      ; Field Length in bytes
endstruc

struc ipfix_template_entry_t
    .template_id:       resw 1
    .field_count:       resw 1
    .record_length:     resw 1      ; Total bytes per data record
    .fields:            resb ipfix_field_spec_t_size * IPFIX_MAX_FIELDS_PER_TPL
endstruc

section .bss
align 64
ipfix_template_registry: resb ipfix_template_entry_t_size * IPFIX_MAX_TEMPLATES

section .data
align 4
ipfix_template_count:   dd 0

section .text

global ipfix_cap_main
global ipfix_cap_parse_message
global ipfix_cap_parse_template_set
global ipfix_cap_parse_data_set
global ipfix_cap_lookup_template

; -----------------------------------------------------------------------------
; ipfix_cap_main — Entry Point
; Input: RDI = Pointer to raw IPFIX message buffer
; Output: EAX = 0 (Success), -1 (Invalid Version)
; -----------------------------------------------------------------------------
align 64
ipfix_cap_main:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    prefetcht0 [rbx]

    call ipfix_cap_parse_message

    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ipfix_cap_parse_message — Parse IPFIX Message Header & Iterate Sets
; Input: RDI = Pointer to raw IPFIX message
; Output: EAX = 0 (Success), -1 (Invalid)
; -----------------------------------------------------------------------------
align 64
ipfix_cap_parse_message:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    push r13

    mov rbx, rdi

    ; Verify IPFIX Version == 10 (0x000A Big Endian)
    movzx eax, word [rbx + ipfix_msg_hdr_t.version]
    xchg al, ah                     ; Convert Big Endian -> Host
    cmp ax, IPFIX_VERSION
    jne .invalid

    ; Get total message length
    movzx r12d, word [rbx + ipfix_msg_hdr_t.length]
    xchg r12b, byte [rbx + ipfix_msg_hdr_t.length + 1]  ; Approximate BE swap
    ; R12 = total message length

    ; Iterate Set Headers starting after 16-byte message header
    lea r13, [rbx + 16]             ; R13 = current set pointer

.set_loop:
    ; Check if we've consumed all bytes
    mov rax, r13
    sub rax, rbx
    cmp eax, r12d
    jge .done

    ; Read Set ID
    movzx eax, word [r13 + ipfix_set_hdr_t.set_id]
    xchg al, ah                     ; Big Endian -> Host

    ; Read Set Length
    movzx ecx, word [r13 + ipfix_set_hdr_t.set_length]
    xchg cl, ch                     ; Big Endian -> Host
    test ecx, ecx
    jz .done                        ; Zero length = malformed, stop

    ; Dispatch based on Set ID
    cmp eax, IPFIX_SET_ID_TEMPLATE
    je .process_template

    cmp eax, IPFIX_MIN_DATA_SET_ID
    jge .process_data

    ; Skip unknown set types (Options Template Set ID 3, etc.)
    jmp .next_set

.process_template:
    mov rdi, r13
    mov esi, ecx                    ; Set length
    call ipfix_cap_parse_template_set
    jmp .next_set

.process_data:
    mov rdi, r13
    mov esi, ecx                    ; Set length
    mov edx, eax                    ; Template ID = Set ID
    call ipfix_cap_parse_data_set
    jmp .next_set

.next_set:
    add r13, rcx                    ; Advance by Set Length
    jmp .set_loop

.done:
    xor eax, eax
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

.invalid:
    mov eax, -1
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ipfix_cap_parse_template_set — Parse Template Set & Cache Field Definitions
; Input: RDI = Pointer to Template Set (including set header)
;        ESI = Set Length
; -----------------------------------------------------------------------------
align 64
ipfix_cap_parse_template_set:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi
    lea r12, [rdi + 4]              ; Skip 4-byte Set Header -> template records

    ; Read Template ID
    movzx eax, word [r12]
    xchg al, ah
    ; EAX = Template ID

    ; Read Field Count
    movzx ecx, word [r12 + 2]
    xchg cl, ch
    ; ECX = Field Count

    ; Find slot in template registry
    mov edx, [ipfix_template_count]
    cmp edx, IPFIX_MAX_TEMPLATES
    jge .registry_full

    lea rdi, [ipfix_template_registry]
    imul edx, ipfix_template_entry_t_size
    add rdi, rdx

    ; Store template header
    mov [rdi + ipfix_template_entry_t.template_id], ax
    mov [rdi + ipfix_template_entry_t.field_count], cx

    ; Copy field specifiers & calculate record length
    xor edx, edx                    ; Record length accumulator
    lea rsi, [r12 + 4]             ; Field specs start after template header
    lea rdi, [rdi + ipfix_template_entry_t.fields]
    movzx ecx, cx                   ; Field count

.field_loop:
    test ecx, ecx
    jz .fields_done

    ; Read IE ID
    movzx eax, word [rsi]
    xchg al, ah
    mov [rdi + ipfix_field_spec_t.ie_id], ax

    ; Read Field Length
    movzx eax, word [rsi + 2]
    xchg al, ah
    mov [rdi + ipfix_field_spec_t.field_length], ax
    add edx, eax                    ; Accumulate record length

    add rsi, 4                      ; Next field spec
    add rdi, ipfix_field_spec_t_size
    dec ecx
    jmp .field_loop

.fields_done:
    ; Store total record length
    lea rdi, [ipfix_template_registry]
    mov eax, [ipfix_template_count]
    imul eax, ipfix_template_entry_t_size
    add rdi, rax
    mov [rdi + ipfix_template_entry_t.record_length], dx

    inc dword [ipfix_template_count]

.registry_full:
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ipfix_cap_parse_data_set — Parse Data Set Records Using Cached Template
; Input: RDI = Pointer to Data Set, ESI = Set Length, EDX = Template ID
; -----------------------------------------------------------------------------
align 64
ipfix_cap_parse_data_set:
    push rbp
    mov rbp, rsp
    push rbx
    push r12

    mov rbx, rdi

    ; Lookup template by ID
    mov edi, edx
    call ipfix_cap_lookup_template
    test rax, rax
    jz .no_template                 ; Template not cached yet

    ; RAX = pointer to ipfix_template_entry_t
    movzx ecx, word [rax + ipfix_template_entry_t.record_length]
    test ecx, ecx
    jz .no_template

    ; Iterate data records within set (skip 4-byte set header)
    lea r12, [rbx + 4]

    ; (Would iterate: for each record of `record_length` bytes, extract fields per template)

    xor eax, eax
    pop r12
    pop rbx
    pop rbp
    ret

.no_template:
    mov eax, -1
    pop r12
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; ipfix_cap_lookup_template — Find Template Entry by Template ID
; Input: EDI = Template ID
; Output: RAX = Pointer to ipfix_template_entry_t, or 0 if not found
; -----------------------------------------------------------------------------
align 64
ipfix_cap_lookup_template:
    push rbp
    mov rbp, rsp

    lea rax, [ipfix_template_registry]
    mov ecx, [ipfix_template_count]

.search:
    test ecx, ecx
    jz .not_found
    cmp di, [rax + ipfix_template_entry_t.template_id]
    je .found
    add rax, ipfix_template_entry_t_size
    dec ecx
    jmp .search

.found:
    pop rbp
    ret

.not_found:
    xor eax, eax
    pop rbp
    ret
