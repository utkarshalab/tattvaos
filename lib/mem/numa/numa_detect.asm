; =============================================================================
; Tattva OS — lib/mem/numa/numa_detect.asm
; =============================================================================
; ACPI SRAT (Static Resource Affinity Table) parser.
; Maps physical memory range boundaries to Node IDs.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit)
; =============================================================================

%ifndef LIB_MEM_NUMA_NUMA_DETECT_ASM
%define LIB_MEM_NUMA_NUMA_DETECT_ASM

[BITS 64]

; Early NUMA discovery may only dereference the loader's guaranteed contiguous
; identity map.  Sparse high-memory mappings deliberately exclude ACPI/NVS
; pages, so high firmware tables are rejected until an explicit ACPI mapper
; exists.  Work is capped independently of the mapped aperture.
NUMA_ACPI_MAX_TABLE_BYTES equ 0x100000
NUMA_ACPI_MAX_RSDP_BYTES  equ 4096
NUMA_ACPI_MAX_ROOT_ENTRIES equ 4096
NUMA_ACPI_MAX_CANDIDATES   equ 16

section .text

; External symbols


; -----------------------------------------------------------------------------
; numa_detect_init — detects NUMA nodes and memory affinities via ACPI SRAT
; Input:  none
; Output: none
; -----------------------------------------------------------------------------
global numa_detect_init
numa_detect_init:
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    push r10
    push r11
    push r12
    push r13
    push r14
    push r15

    ; Initialize table address holders to 0
    xor r14, r14                    ; R14 = SRAT physical address
    xor r15, r15                    ; R15 = SLIT physical address
    xor r12, r12                    ; R12 = HMAT physical address (unused
                                     ; elsewhere in this walk — see below)

    mov rdi, [boot_info_ptr]
    test rdi, rdi
    jz .parse_tables

    ; 1. Load RSDP address from BootInfo (offset 24)
    mov r13, [rdi + BOOT_INFO_ACPI_RSDP_OFF]
    test r13, r13
    jz .parse_tables

    ; ACPI 1.0 guarantees the first 20 bytes.  Prove accessibility before the
    ; first signature byte is touched, then validate the legacy checksum.
    mov rdi, r13
    mov ecx, 20
    call numa_acpi_low_span
    jc .parse_tables

    ; Verify RSDP signature "RSD PTR "
    mov rbx, [r13]
    mov rcx, 0x2052545020445352     ; "RSD PTR "
    cmp rbx, rcx
    jne .parse_tables
    mov rdi, r13
    mov ecx, 20
    call numa_acpi_checksum_ok
    test eax, eax
    jz .parse_tables

    ; 2. Determine revision
    movzx eax, byte [r13 + 15]      ; Revision
    cmp al, 2
    jb .use_rsdt                    ; ACPI 1.0 -> Use RSDT

    ; ACPI 2.0+ fields are not readable until the fixed extended header and
    ; its bounded declared length have both been validated.
    mov rdi, r13
    mov ecx, 36
    call numa_acpi_low_span
    jc .use_rsdt
    mov r10d, [r13 + 20]            ; RSDP Length
    cmp r10d, 36
    jb .use_rsdt
    cmp r10d, NUMA_ACPI_MAX_RSDP_BYTES
    ja .use_rsdt
    mov rdi, r13
    mov ecx, r10d
    call numa_acpi_low_span
    jc .use_rsdt
    call numa_acpi_checksum_ok
    test eax, eax
    jz .use_rsdt

    ; ACPI 2.0+ -> Use XSDT if non-zero
    mov rdi, [r13 + 24]             ; XsdtAddress
    test rdi, rdi
    jz .use_rsdt

    call numa_acpi_sdt_valid
    jc .use_rsdt

    ; XSDT Table walking
    cmp dword [rdi], 0x54445358     ; "XSDT"
    jne .use_rsdt

    ; Parse XSDT
    mov r10, rax                    ; validated XSDT Length
    sub r10, 36
    test r10, 7
    jnz .use_rsdt
    shr r10, 3                      ; number of 64-bit pointers
    cmp r10, NUMA_ACPI_MAX_ROOT_ENTRIES
    ja .use_rsdt
    lea rbx, [rdi + 36]             ; first pointer
    xor rcx, rcx                    ; entry index
    xor r11d, r11d                  ; relevant-table validation attempts

.xsdt_loop:
    cmp rcx, r10
    jae .parse_tables

    mov rsi, [rbx + rcx * 8]         ; 64-bit physical address of table
    test rsi, rsi
    jz .xsdt_next

    mov rdi, rsi
    call numa_acpi_sdt_candidate
    jc .xsdt_next

    ; Check table signature
    cmp eax, 0x54415253             ; "SRAT"
    jne .xsdt_check_slit
    test r14, r14
    jnz .xsdt_next
    inc r11
    cmp r11, NUMA_ACPI_MAX_CANDIDATES
    ja .parse_tables
    call numa_acpi_sdt_valid
    jc .xsdt_next
    mov r14, rsi
    jmp .xsdt_next
.xsdt_check_slit:
    cmp eax, 0x54494C53             ; "SLIT"
    jne .xsdt_check_hmat
    test r15, r15
    jnz .xsdt_next
    inc r11
    cmp r11, NUMA_ACPI_MAX_CANDIDATES
    ja .parse_tables
    call numa_acpi_sdt_valid
    jc .xsdt_next
    mov r15, rsi
    jmp .xsdt_next
.xsdt_check_hmat:
    cmp eax, 0x54414D48              ; "HMAT"
    jne .xsdt_next
    test r12, r12
    jnz .xsdt_next
    inc r11
    cmp r11, NUMA_ACPI_MAX_CANDIDATES
    ja .parse_tables
    call numa_acpi_sdt_valid
    jc .xsdt_next
    mov r12, rsi

.xsdt_next:
    inc rcx
    jmp .xsdt_loop

.use_rsdt:
    ; RSDT Table walking
    mov edi, dword [r13 + 16]       ; RsdtAddress is always a 32-bit pointer
    test rdi, rdi
    jz .parse_tables

    call numa_acpi_sdt_valid
    jc .parse_tables

    cmp dword [rdi], 0x54445352     ; "RSDT"
    jne .parse_tables

    ; Parse RSDT
    mov r10, rax                    ; validated RSDT Length
    sub r10, 36
    test r10, 3
    jnz .parse_tables
    shr r10, 2                      ; number of 32-bit pointers
    cmp r10, NUMA_ACPI_MAX_ROOT_ENTRIES
    ja .parse_tables
    lea rbx, [rdi + 36]             ; first pointer
    xor rcx, rcx
    xor r11d, r11d                  ; relevant-table validation attempts

.rsdt_loop:
    cmp rcx, r10
    jae .parse_tables

    mov esi, dword [rbx + rcx * 4] ; 32-bit physical address of table
    test rsi, rsi
    jz .rsdt_next

    mov rdi, rsi
    call numa_acpi_sdt_candidate
    jc .rsdt_next

    ; Check table signature
    cmp eax, 0x54415253             ; "SRAT"
    jne .rsdt_check_slit
    test r14, r14
    jnz .rsdt_next
    inc r11
    cmp r11, NUMA_ACPI_MAX_CANDIDATES
    ja .parse_tables
    call numa_acpi_sdt_valid
    jc .rsdt_next
    mov r14, rsi
    jmp .rsdt_next
.rsdt_check_slit:
    cmp eax, 0x54494C53             ; "SLIT"
    jne .rsdt_check_hmat
    test r15, r15
    jnz .rsdt_next
    inc r11
    cmp r11, NUMA_ACPI_MAX_CANDIDATES
    ja .parse_tables
    call numa_acpi_sdt_valid
    jc .rsdt_next
    mov r15, rsi
    jmp .rsdt_next
.rsdt_check_hmat:
    cmp eax, 0x54414D48              ; "HMAT"
    jne .rsdt_next
    test r12, r12
    jnz .rsdt_next
    inc r11
    cmp r11, NUMA_ACPI_MAX_CANDIDATES
    ja .parse_tables
    call numa_acpi_sdt_valid
    jc .rsdt_next
    mov r12, rsi

.rsdt_next:
    inc rcx
    jmp .rsdt_loop

.parse_tables:
    ; Export the located table addresses so other subsystems (lib/hw/unuma's
    ; SRAT CPU-affinity parse) can reuse them without re-walking RSDP ->
    ; XSDT/RSDT themselves. 0 means "not found", same as the fallback paths
    ; below take.
    mov [numa_srat_phys_addr], r14
    mov [numa_slit_phys_addr], r15
    mov [numa_hmat_phys_addr], r12

    ; =========================================================================
    ; 1. Parse SRAT
    ; =========================================================================
    test r14, r14
    jz .srat_fallback

    mov rdi, r14
    mov r10d, [rdi + 4]             ; SRAT Length
    cmp r10d, 48
    jbe .srat_fallback

    lea r11, [rdi + 48]             ; current entry pointer
    mov r12, rdi
    add r12, r10                    ; end of table
    jc .srat_fallback
    xor r13, r13                    ; range index count = 0

.srat_entry_loop:
    cmp r11, r12
    jae .srat_done

    mov rax, r12
    sub rax, r11                    ; bytes remaining in the SRAT
    jc .srat_fallback
    cmp rax, 2
    jb .srat_fallback               ; truncated subtable header

    movzx eax, byte [r11]           ; Type
    movzx ecx, byte [r11 + 1]       ; Length
    cmp ecx, 2
    jb .srat_fallback
    mov rdx, r11
    add rdx, rcx
    jc .srat_fallback
    cmp rdx, r12
    ja .srat_fallback               ; declared subtable crosses table end

    cmp eax, 1                      ; Type 1 = Memory Affinity
    jne .next_srat_entry
    cmp ecx, 40
    jne .next_srat_entry

    mov edx, [r11 + 28]             ; Flags
    test dl, 1                      ; Enabled
    jz .next_srat_entry

    mov r8, [r11 + 8]               ; Base address
    mov r9, [r11 + 16]              ; Length
    test r9, r9
    jz .next_srat_entry

    ; SRAT can describe memory that the bootstrap root cannot address.  Keep
    ; node-local allocators inside the PMM's already validated bitmap span.
    mov rbp, r8
    add rbp, r9                      ; raw exclusive end
    jc .next_srat_entry
    add r8, 4095
    jc .next_srat_entry
    and r8, -4096
    and rbp, -4096
    mov rax, [phys_state + phys_state_t.max_phys_addr]
    cmp r8, rax
    jae .next_srat_entry
    cmp rbp, rax
    jbe .srat_extent_ready
    mov rbp, rax
.srat_extent_ready:
    cmp rbp, r8
    jbe .next_srat_entry
    mov r9, rbp
    sub r9, r8                      ; clipped, page-aligned length

    ; Type-1 Memory Affinity stores one contiguous 32-bit proximity domain.
    mov r14d, [r11 + 2]

    ; Reject overlapping affinities instead of letting two node-local
    ; allocators publish the same PFN.  SRAT order is not trusted.
    xor r10d, r10d
.validate_srat_range:
    cmp r10, r13
    jae .store_srat_range
    mov rax, r10
    imul rax, numa_range_t_size
    lea r15, [numa_ranges + rax]
    mov rdi, [r15 + numa_range_t.base]
    mov rsi, [r15 + numa_range_t.length]
    add rsi, rdi
    jc .srat_fallback
    cmp r8, rsi
    jae .next_validated_range
    cmp rdi, rbp
    jb .srat_fallback
.next_validated_range:
    inc r10
    jmp .validate_srat_range

    ; Store range
.store_srat_range:
    cmp r13, NUMA_MAX_RANGES
    jae .srat_fallback              ; never publish a truncated ownership map

    mov rax, r13
    imul rax, numa_range_t_size
    lea r15, [numa_ranges + rax]

    mov [r15 + numa_range_t.base], r8
    mov [r15 + numa_range_t.length], r9
    mov [r15 + numa_range_t.node_id], r14d
    mov [r15 + numa_range_t.flags], edx
    inc r13

.next_srat_entry:
    add r11, rcx
    jmp .srat_entry_loop

.srat_done:
    test r13, r13
    jz .srat_fallback
    mov [numa_range_count], r13

    ; A partial SRAT cannot become allocator authority: pages omitted from its
    ; affinities would remain globally free but unreachable/unfreeable after
    ; node-local bitmaps go live.  Ranges are already non-overlapping, so the
    ; sum of their canonical type-1 E820 intersections must equal every page
    ; currently managed by the PMM.
    xor r8d, r8d
    xor r9d, r9d
.validate_srat_coverage:
    cmp r8, r13
    jae .srat_coverage_done
    mov rax, r8
    imul rax, numa_range_t_size
    lea rdx, [numa_ranges + rax]
    mov rdi, [rdx + numa_range_t.base]
    mov rsi, [rdx + numa_range_t.length]
    add rsi, rdi
    jc .srat_fallback
    shr rdi, 12
    shr rsi, 12
    call numa_count_usable_pages
    add r9, rax
    jc .srat_fallback
    inc r8
    jmp .validate_srat_coverage
.srat_coverage_done:
    cmp r9, [phys_state + phys_state_t.total_pages]
    jne .srat_fallback

    ; Node descriptors and the distance matrix are fixed-size.  Establish a
    ; safe count from SRAT even when firmware supplies no SLIT table.
    xor r8d, r8d
    xor r9d, r9d                    ; highest node ID + 1
.derive_node_count:
    cmp r8, r13
    jae .node_count_ready
    mov rax, r8
    imul rax, numa_range_t_size
    lea rdx, [numa_ranges + rax]
    mov eax, [rdx + numa_range_t.node_id]
    cmp eax, NUMA_MAX_NODES
    jae .srat_fallback
    inc rax
    cmp r9, rax
    cmovb r9, rax
    inc r8
    jmp .derive_node_count
.node_count_ready:
    test r9, r9
    jz .srat_fallback
    mov [numa_node_count], r9
    mov rsi, msg_numa_srat_ok
    call uart_print_str
    jmp .parse_slit

.srat_fallback:
    mov rdx, [phys_state + phys_state_t.max_phys_addr]
    test rdx, rdx
    jnz .srat_fallback_store
    mov rdx, 0x100000000            ; default 4GB

.srat_fallback_store:
    lea r15, [numa_ranges]
    mov qword [r15 + numa_range_t.base], 0
    mov [r15 + numa_range_t.length], rdx
    mov dword [r15 + numa_range_t.node_id], 0
    mov dword [r15 + numa_range_t.flags], 1

    mov qword [numa_range_count], 1
    mov qword [numa_node_count], 1
    mov qword [numa_srat_phys_addr], 0
    mov qword [numa_slit_phys_addr], 0
    mov qword [numa_hmat_phys_addr], 0
    mov rsi, msg_numa_srat_fallback
    call uart_print_str
    jmp .default_distances

.parse_slit:
    ; =========================================================================
    ; 2. Parse SLIT
    ; =========================================================================
    mov r15, [numa_slit_phys_addr]
    test r15, r15
    jz .slit_fallback

    mov rdi, r15
    mov r10d, [rdi + 4]             ; SLIT Length
    cmp r10d, 44
    jbe .slit_fallback
    mov ebp, r10d

    ; Read Number of System Localities (64-bit at offset 36)
    mov r10, [rdi + 36]
    test r10, r10
    jz .slit_fallback

    ; The distance matrix must fit completely inside the ACPI table.
    mov rax, r10
    mul r10
    test rdx, rdx
    jnz .slit_fallback
    add rax, 44
    jc .slit_fallback
    cmp rax, rbp
    ja .slit_fallback

    mov r9, r10
    cmp r9, NUMA_MAX_NODES
    jbe .count_ok
    mov r9, NUMA_MAX_NODES
.count_ok:
    cmp r9, [numa_node_count]
    jb .slit_fallback               ; matrix omits a memory proximity domain
    mov [numa_node_count], r9

    ; Copy submatrix row by row
    xor rcx, rcx                    ; row index i = 0
.row_loop:
    cmp rcx, r9
    jae .slit_done

    ; Calculate source row address: rdi + 44 + rcx * r10
    mov rax, rcx
    imul rax, r10
    lea rsi, [rdi + 44 + rax]

    ; Calculate dest row address: numa_distance_matrix + rcx * r9
    mov rax, rcx
    imul rax, r9
    lea rdx, [numa_distance_matrix + rax]

    ; Copy r9 bytes
    xor r8, r8                      ; col index j = 0
.col_loop:
    cmp r8, r9
    jae .next_row
    mov al, [rsi + r8]
    cmp al, NUMA_DEFAULT_LOCAL_DISTANCE
    jb .slit_fallback               ; ACPI reserves distance values 0..9
    cmp rcx, r8
    jne .store_distance
    cmp al, NUMA_DEFAULT_LOCAL_DISTANCE
    jne .slit_fallback              ; every diagonal distance must be 10
.store_distance:
    mov [rdx + r8], al
    inc r8
    jmp .col_loop

.next_row:
    inc rcx
    jmp .row_loop

.slit_done:
    ; Every stored proximity domain must index the accepted SLIT submatrix.
    ; Sparse/out-of-range firmware IDs fall back safely instead of indexing
    ; beyond numa_nodes or the distance matrix.
    xor r8d, r8d
.validate_node_ids:
    cmp r8, [numa_range_count]
    jae .slit_valid
    mov rax, r8
    imul rax, numa_range_t_size
    lea rdx, [numa_ranges + rax]
    mov eax, [rdx + numa_range_t.node_id]
    cmp rax, r9
    jae .slit_fallback
    inc r8
    jmp .validate_node_ids

.slit_valid:
    mov rsi, msg_numa_slit_ok
    call uart_print_str
    jmp .exit

.slit_fallback:
    ; SRAT remains authoritative without SLIT.  Use conservative local/remote
    ; defaults over the already-bounded SRAT node set.
    mov qword [numa_slit_phys_addr], 0
    mov rsi, msg_numa_slit_fallback
    call uart_print_str

.default_distances:
    lea rdi, [numa_distance_matrix]
    mov rcx, NUMA_MAX_NODES * NUMA_MAX_NODES
    mov al, 255
    cld
    rep stosb

    mov r9, [numa_node_count]
    xor ecx, ecx
.default_row:
    cmp rcx, r9
    jae .exit
    xor r8d, r8d
.default_col:
    cmp r8, r9
    jae .default_next_row
    mov rax, rcx
    imul rax, r9
    add rax, r8
    mov dl, NUMA_DEFAULT_REMOTE_DISTANCE
    cmp rcx, r8
    jne .default_store
    mov dl, NUMA_DEFAULT_LOCAL_DISTANCE
.default_store:
    mov [numa_distance_matrix + rax], dl
    inc r8
    jmp .default_col
.default_next_row:
    inc rcx
    jmp .default_row

.exit:
    pop r15
    pop r14
    pop r13
    pop r12
    pop r11
    pop r10
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    ret

; -----------------------------------------------------------------------------
; Early ACPI access helpers
; -----------------------------------------------------------------------------
; numa_acpi_low_span — validate [RDI, RDI+RCX) inside the guaranteed direct map
; Output: CF clear when accessible, CF set otherwise.  Preserves registers.
numa_acpi_low_span:
    test rcx, rcx
    jz .bad
    push rax
    mov rax, rdi
    add rax, rcx
    jc .bad_pop
    cmp rax, [phys_state + phys_state_t.direct_map_limit]
    ja .bad_pop
    pop rax
    clc
    ret
.bad_pop:
    pop rax
.bad:
    stc
    ret

; numa_acpi_checksum_ok — return RAX=1 when RCX bytes sum to zero modulo 256.
; The caller must first validate the complete span.
numa_acpi_checksum_ok:
    push rcx
    push rdx
    push rdi
    xor edx, edx
.sum:
    add dl, [rdi]
    inc rdi
    dec rcx
    jnz .sum
    xor eax, eax
    test dl, dl
    sete al
    pop rdi
    pop rdx
    pop rcx
    ret

; numa_acpi_sdt_valid — validate a complete standard ACPI SDT before use.
; Input: RDI = physical/identity address. Output: RAX=length and CF clear, or
; RAX=0 and CF set. Preserves all other registers.
numa_acpi_sdt_valid:
    push rcx
    push rdx
    mov ecx, 36
    call numa_acpi_low_span
    jc .invalid
    mov edx, [rdi + 4]
    cmp edx, 36
    jb .invalid
    cmp edx, NUMA_ACPI_MAX_TABLE_BYTES
    ja .invalid
    mov ecx, edx
    call numa_acpi_low_span
    jc .invalid
    call numa_acpi_checksum_ok
    test eax, eax
    jz .invalid
    mov eax, edx
    pop rdx
    pop rcx
    clc
    ret
.invalid:
    xor eax, eax
    pop rdx
    pop rcx
    stc
    ret

; numa_acpi_sdt_candidate — safely prefilter a child header by signature so
; irrelevant tables do not consume the bounded full-table checksum budget.
; Output: EAX=signature and CF clear for SRAT/SLIT/HMAT, CF set otherwise.
numa_acpi_sdt_candidate:
    push rcx
    mov ecx, 36
    call numa_acpi_low_span
    jc .not_candidate
    mov eax, [rdi]
    cmp eax, 0x54415253             ; "SRAT"
    je .candidate
    cmp eax, 0x54494C53             ; "SLIT"
    je .candidate
    cmp eax, 0x54414D48             ; "HMAT"
    jne .not_candidate
.candidate:
    pop rcx
    clc
    ret
.not_candidate:
    xor eax, eax
    pop rcx
    stc
    ret

; -----------------------------------------------------------------------------
; Messages
; -----------------------------------------------------------------------------
section .data

global numa_srat_phys_addr
global numa_slit_phys_addr
global numa_hmat_phys_addr
numa_srat_phys_addr: dq 0
numa_slit_phys_addr: dq 0
numa_hmat_phys_addr: dq 0

msg_numa_srat_ok:       db "NUMA: ACPI SRAT table parsing successful.", 0x0D, 0x0A, 0
msg_numa_srat_fallback: db "NUMA: SRAT not found or invalid. Defaulting to UMA (Node 0).", 0x0D, 0x0A, 0
msg_numa_slit_ok:       db "NUMA: ACPI SLIT table parsing successful.", 0x0D, 0x0A, 0
msg_numa_slit_fallback: db "NUMA: SLIT not found or invalid. Defaulting to SRAT topology distances.", 0x0D, 0x0A, 0

%endif ; LIB_MEM_NUMA_NUMA_DETECT_ASM
