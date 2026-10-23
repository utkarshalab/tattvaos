%ifndef GUARD_UNET_CORE_SYS_AVX512_CHECKSUM_ASM
%define GUARD_UNET_CORE_SYS_AVX512_CHECKSUM_ASM
; =============================================================================
; Utkarsha OS — unet/core/sys/avx512_checksum.asm
; =============================================================================
; AVX-512 Optimized Internet Checksum (RFC 1071)
;
; Provides vectorized checksum computation for:
;   - IPv4 header checksum
;   - TCP/UDP checksum with pseudo-header
;   - Batch checksum verification
;
; Method: widen each 64-byte block's 16-bit words to dwords (VPMOVZXWD) and
; accumulate with VPADDD; fold once at the end.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (AVX-512F)
; =============================================================================

%include "lib/unet/unet.inc"

; Every function below except avx512_checksum_supported executes AVX-512F
; instructions. Call avx512_checksum_supported once and fall back to
; ip_checksum_calc (lib/unet/core/l3/ip.asm) when it returns 0.
;
; Sums are of little-endian 16-bit words, like ip_checksum_calc: the
; ones'-complement sum does not depend on byte order (RFC 1071), so the
; complement of the folded sum can be stored on the wire as it is.

section .text

global avx512_checksum_supported
global avx512_csum_partial
global avx512_ipv4_checksum
global avx512_tcp_udp_checksum
global avx512_batch_verify_ipv4
global avx512_batch_verify_tcp_udp
global avx512_fold_checksum

; =============================================================================
; avx512_checksum_supported — Can the AVX-512 checksum routines run here?
; Output: EAX = 1 if the CPU has AVX-512F and the OS has enabled the ZMM
;         register state (XCR0 bits 1, 2, 5, 6, 7), 0 otherwise
; =============================================================================
align 64
avx512_checksum_supported:
    push rbx

    xor ecx, ecx
    mov eax, 1
    cpuid
    bt ecx, 27              ; OSXSAVE: XGETBV is usable
    jnc .no

    mov eax, 7
    xor ecx, ecx
    cpuid
    bt ebx, 16              ; AVX512F
    jnc .no

    xor ecx, ecx
    xgetbv
    and eax, 0xE6
    cmp eax, 0xE6           ; SSE, AVX, opmask, ZMM_Hi256, Hi16_ZMM
    jne .no

    mov eax, 1
    pop rbx
    ret
.no:
    xor eax, eax
    pop rbx
    ret

; =============================================================================
; avx512_csum_partial — Ones'-complement sum of a buffer
; Input: RDI = data, ESI = length in bytes
; Output: EAX = folded 16-bit sum (same result as ip_checksum_calc)
; Clobbers: RCX, RDX, RSI, RDI, ZMM0-ZMM2
; =============================================================================
align 64
avx512_csum_partial:
    vpxord zmm0, zmm0, zmm0         ; 16 dword accumulators
    mov ecx, esi
    shr ecx, 6                      ; 64-byte blocks
    jz .tail

.block:
    vpmovzxwd zmm1, [rdi]           ; words 0-15  -> dwords
    vpmovzxwd zmm2, [rdi + 32]      ; words 16-31 -> dwords
    vpaddd zmm0, zmm0, zmm1
    vpaddd zmm0, zmm0, zmm2
    add rdi, 64
    dec ecx
    jnz .block
    ; Each lane gains at most 2 * 0xFFFF per block, so 32 bits hold any
    ; buffer below 2 GiB without carry loss.

.tail:
    ; Reduce the 16 lanes to one 64-bit value in RAX
    vextracti64x4 ymm1, zmm0, 1
    vpmovzxdq zmm0, ymm0
    vpmovzxdq zmm1, ymm1
    vpaddq zmm0, zmm0, zmm1         ; 8 qwords
    vextracti64x4 ymm1, zmm0, 1
    vpaddq ymm0, ymm0, ymm1         ; 4 qwords
    vextracti128 xmm1, ymm0, 1
    vpaddq xmm0, xmm0, xmm1         ; 2 qwords
    vpsrldq xmm1, xmm0, 8
    vpaddq xmm0, xmm0, xmm1
    vmovq rdx, xmm0
    vzeroupper

    ; The last (length mod 64) bytes go through the scalar routine
    and esi, 63
    jz .fold_rdx
    push rdx
    call ip_checksum_calc           ; EAX = folded sum of the tail
    pop rdx
    add rdx, rax

.fold_rdx:
    mov rax, rdx
    jmp avx512_fold_checksum

; =============================================================================
; avx512_fold_checksum — Fold a 64-bit sum to 16 bits (end-around carry)
; Input: RAX = sum
; Output: EAX = folded 16-bit sum
; =============================================================================
align 64
avx512_fold_checksum:
.fold:
    mov rdx, rax
    shr rdx, 16
    jz .done
    movzx eax, ax
    add rax, rdx
    jmp .fold
.done:
    ret

; =============================================================================
; avx512_ipv4_checksum — IPv4 header checksum to store
; Input: RDI = IPv4 header with its checksum field zeroed, ESI = header length
; Output: AX = checksum, ready to store with a 16-bit move
; =============================================================================
align 64
avx512_ipv4_checksum:
    call avx512_csum_partial
    not ax
    ret

; =============================================================================
; avx512_tcp_udp_checksum — TCP/UDP checksum over the IPv4 pseudo-header
; Input: EDI = source IP, ESI = destination IP (network order),
;        RDX = L4 header with its checksum field zeroed, ECX = L4 length
;        (header + payload), R8D = protocol (IP_PROTO_TCP / IP_PROTO_UDP)
; Output: AX = checksum, ready to store with a 16-bit move. For UDP the
;         caller replaces 0 with 0xFFFF (RFC 768).
; TODO: IPv6 pseudo-header (RFC 8200 8.1)
; =============================================================================
align 64
avx512_tcp_udp_checksum:
    push rbx
    push r12
    sub rsp, 24

    mov rbx, rdx                    ; L4 header
    mov r12d, ecx                   ; L4 length

    ; Pseudo-header: src, dst, zero, protocol, length (network order)
    mov [rsp], edi
    mov [rsp + 4], esi
    mov byte [rsp + 8], 0
    mov [rsp + 9], r8b
    mov eax, ecx
    xchg al, ah
    mov [rsp + 10], ax

    lea rdi, [rsp]
    mov esi, 12
    call ip_checksum_calc
    mov [rsp + 16], eax             ; pseudo-header partial

    mov rdi, rbx
    mov esi, r12d
    call avx512_csum_partial
    add eax, [rsp + 16]
    call avx512_fold_checksum
    not ax

    add rsp, 24
    pop r12
    pop rbx
    ret

; =============================================================================
; avx512_batch_verify_ipv4 — Verify a batch of IPv4 header checksums
; Input: RDI = array of IPv4 header pointers, ESI = count (at most 64),
;        RDX = array of header lengths (dwords)
; Output: RAX = bit i set when header i is intact
; =============================================================================
align 64
avx512_batch_verify_ipv4:
    push rbx
    push r12
    push r13
    push r14
    push r15

    mov r12, rdi                    ; header pointers
    mov r13, rdx                    ; lengths
    mov r14d, esi
    cmp r14d, 64
    jbe .count_ok
    mov r14d, 64
.count_ok:
    xor ebx, ebx                    ; index
    xor r15d, r15d                  ; result mask

.loop:
    cmp ebx, r14d
    jae .done
    mov rdi, [r12 + rbx * 8]
    mov esi, [r13 + rbx * 4]
    call avx512_csum_partial        ; checksum field included
    cmp ax, 0xFFFF
    jne .next
    bts r15, rbx
.next:
    inc ebx
    jmp .loop

.done:
    mov rax, r15
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; =============================================================================
; avx512_batch_verify_tcp_udp — Batch Verify TCP/UDP Checksums
; Output: RAX = 0 (no segment verified here)
; TODO: needs a batch layout carrying each segment's pseudo-header; until
; then callers verify segments one at a time with avx512_tcp_udp_checksum.
; =============================================================================
align 64
avx512_batch_verify_tcp_udp:
    xor eax, eax
    ret

%endif ; GUARD_UNET_CORE_SYS_AVX512_CHECKSUM_ASM
