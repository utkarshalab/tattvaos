; ============================================================================
; JPEG Progressive — SOF2 decoding (MED-20)
; ============================================================================
; A progressive JPEG sends its coefficients in several scans: the DC ones
; first, then bands of AC ones, each maybe a few high bits first and the
; lower ones in later scans (successive approximation). Every component's
; coefficients are kept for the whole image (Prog.coef, natural order, not
; dequantized) while the markers are walked: tables and restart intervals
; may come between scans. Each scan is one of four kinds (ITU T.81 G.1.2):
; DC first (Huffman difference, shifted up by Al) and DC refine (one bit),
; interleaved or not; AC first (a band Ss..Se, runs of empty blocks as
; EOBRUN) and AC refine (one more bit of each coefficient already nonzero,
; new ones of +-1 << Al), one component only. At EOI (or the data's end)
; each block is dequantized and transformed into its component's plane and
; the rows emitted as baseline colour ones are (jpeg_emit_rows).

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/image.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern jpeg_bits_init
extern jpeg_bits_get
extern jpeg_receive_extend
extern jpeg_expect_restart
extern jpeg_huff_decode_stream
extern jpeg_read_dqt
extern jpeg_read_dht
extern jpeg_idct8x8
extern jpeg_place_block
extern jpeg_emit_rows

%define HUFF_MAX_SYMS   272             ; HuffTable's symbol count: 0 empty

struc Prog
    .reader:    resb 32                 ; JpegBitReader
    .image:     resq 1
    .coef:      resq 3                  ; int16[64] a block, by component
    .block:     resq 1                  ; the block being decoded
    .dc:        resq 4                  ; by scan component
    .ac:        resq 4
    .bw:        resd 3                  ; blocks a row of a component's grid
    .cbw:       resd 3                  ; its own blocks across and down
    .cbh:       resd 3
    .pred:      resd 3                  ; DC predictors
    .comp:      resd 4                  ; the frame component of each
    .ncomp:     resd 1                  ; components in this scan
    .ss:        resd 1
    .se:        resd 1
    .ah:        resd 1
    .al:        resd 1
    .eobrun:    resd 1
    .mcux:      resd 1
    .mcuy:      resd 1
    .units:     resd 1                  ; MCUs (blocks alone) decoded
    .total:     resd 1                  ; in this scan
    .rst:       resd 1                  ; the restart marker due
    .sc:        resd 1                  ; the scan component decoding
    .by:        resd 1
    .bx:        resd 1
    .k:         resd 1
    .r:         resd 1
    .s:         resd 1
    .temp:      resw 64
    .planes:    resb 3 * JpegPlane_size
endstruc

section .text

; ---------------------------------------------------------------------------
; jpeg_decode_progressive
;   Every scan of a progressive JPEG whose frame jpeg_scan_markers read
;   IN:  rdi = JpegImage* (its pixbuf made), rsi = data, rdx = length
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global jpeg_decode_progressive
jpeg_decode_progressive:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8
    mov r14, rdi
    mov r12, rsi
    mov r13, rdx
    mov rdi, [r14 + JpegImage.arena]
    mov esi, Prog_size
    call arena_alloc
    test rax, rax
    jz .oom
    js .oom
    mov rbx, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, Prog_size
    rep stosb
    mov [rbx + Prog.image], r14
    call setup
    test rax, rax
    jnz .out
    mov r15d, 2                         ; past SOI
.marker:
    lea rax, [r15 + 2]
    cmp rax, r13
    ja .finish                          ; no EOI: what has come
    cmp byte [r12 + r15], 0xFF
    jne .bad
    movzx eax, byte [r12 + r15 + 1]
    cmp eax, 0xFF                       ; fill
    jne .marked
    inc r15
    jmp .marker
.marked:
    cmp eax, 0xD9
    je .finish
    cmp eax, 0xD8
    je .alone
    cmp eax, 0x01
    je .alone
    mov ecx, eax
    and ecx, 0xF8
    cmp ecx, 0xD0
    je .alone
    lea rdx, [r15 + 4]
    cmp rdx, r13
    ja .finish
    movzx ecx, word [r12 + r15 + 2]
    rol cx, 8
    cmp ecx, 2
    jb .bad
    lea rdx, [r15 + rcx + 2]
    cmp rdx, r13
    ja .bad
    mov [rsp], ecx                      ; its length
    cmp eax, 0xDB
    je .dqt
    cmp eax, 0xC4
    je .dht
    cmp eax, 0xDD
    je .dri
    cmp eax, 0xDA
    je .sos
.skip:
    mov ecx, [rsp]
    lea r15, [r15 + rcx + 2]
    jmp .marker
.alone:
    add r15, 2
    jmp .marker
.dqt:
    mov rdi, r14
    lea rsi, [r12 + r15]
    mov edx, [rsp]
    call jpeg_read_dqt
    test rax, rax
    jnz .out
    jmp .skip
.dht:
    mov rdi, r14
    lea rsi, [r12 + r15]
    mov edx, [rsp]
    call jpeg_read_dht
    test rax, rax
    jnz .out
    jmp .skip
.dri:
    cmp dword [rsp], 4
    jne .bad
    movzx eax, word [r12 + r15 + 4]
    rol ax, 8
    mov [r14 + JpegImage.restart], eax
    jmp .skip
.sos:
    lea rsi, [r12 + r15]
    mov edx, [rsp]
    call scan_header
    test rax, rax
    jnz .out
    mov ecx, [rsp]
    lea r15, [r15 + rcx + 2]            ; its entropy-coded data
    lea rdi, [rbx + Prog.reader]
    lea rsi, [r12 + r15]
    mov rdx, r13
    sub rdx, r15
    call jpeg_bits_init
    call scan
    test rax, rax
    jnz .out
.past:                                  ; on to the marker after the data
    cmp r15, r13
    jae .finish
    cmp byte [r12 + r15], 0xFF
    je .ff
    inc r15
    jmp .past
.ff:
    lea rax, [r15 + 1]
    cmp rax, r13
    jae .finish
    movzx eax, byte [r12 + r15 + 1]
    test eax, eax                       ; a stuffed 0xFF
    jz .data
    cmp eax, 0xFF                       ; fill before a marker
    je .fill
    mov ecx, eax
    and ecx, 0xF8
    cmp ecx, 0xD0                       ; a restart: still the scan's
    jne .marker
.data:
    add r15, 2
    jmp .past
.fill:
    inc r15
    jmp .past
.finish:
    call finish
    jmp .out
.bad:
    mov rax, -EINVAL
    jmp .out
.oom:
    mov rax, -ENOMEM
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; Local: rbx = Prog throughout
; ---------------------------------------------------------------------------

; each component's grids, coefficients (zeroed) and plane -> rax
setup:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r14, [rbx + Prog.image]
    movzx r13d, byte [r14 + JpegImage.components]
    cmp r13d, 1
    jne .factors
    mov byte [r14 + JpegImage.component_h], 1  ; one component: never
    mov byte [r14 + JpegImage.component_v], 1  ; interleaved, its own grid
    mov byte [r14 + JpegImage.max_h], 1
    mov byte [r14 + JpegImage.max_v], 1
.factors:
    movzx ecx, byte [r14 + JpegImage.max_h]
    shl ecx, 3
    mov eax, [r14 + JpegImage.width]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    mov [rbx + Prog.mcux], eax
    movzx ecx, byte [r14 + JpegImage.max_v]
    shl ecx, 3
    mov eax, [r14 + JpegImage.height]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    mov [rbx + Prog.mcuy], eax
    xor r15d, r15d
.component:
    cmp r15d, r13d
    jae .done
    imul eax, r15d, JpegPlane_size
    lea r12, [rbx + Prog.planes + rax]
    movzx eax, byte [r14 + JpegImage.component_h + r15]
    mov [r12 + JpegPlane.h], al
    movzx eax, byte [r14 + JpegImage.component_v + r15]
    mov [r12 + JpegPlane.v], al
    movzx eax, byte [r14 + JpegImage.max_h]
    mov [r12 + JpegPlane.max_h], al
    movzx eax, byte [r14 + JpegImage.max_v]
    mov [r12 + JpegPlane.max_v], al
    movzx eax, byte [r12 + JpegPlane.h] ; the grid: MCU columns x h
    imul eax, [rbx + Prog.mcux]
    mov [rbx + Prog.bw + r15 * 4], eax
    shl eax, 3
    mov [r12 + JpegPlane.stride], eax
    movzx eax, byte [r12 + JpegPlane.h] ; its own width, rounded up
    imul eax, [r14 + JpegImage.width]
    movzx ecx, byte [r12 + JpegPlane.max_h]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    mov [r12 + JpegPlane.width], eax
    add eax, 7
    shr eax, 3
    mov [rbx + Prog.cbw + r15 * 4], eax
    movzx eax, byte [r12 + JpegPlane.v]
    imul eax, [r14 + JpegImage.height]
    movzx ecx, byte [r12 + JpegPlane.max_v]
    add eax, ecx
    dec eax
    xor edx, edx
    div ecx
    mov [r12 + JpegPlane.height], eax
    add eax, 7
    shr eax, 3
    mov [rbx + Prog.cbh + r15 * 4], eax
    movzx eax, byte [r12 + JpegPlane.v] ; blocks: the grid's, 128 bytes
    imul eax, [rbx + Prog.mcuy]
    mov ecx, [rbx + Prog.bw + r15 * 4]
    imul rax, rcx
    shl rax, 7
    mov [rsp], rax
    mov rdi, [r14 + JpegImage.arena]
    mov rsi, rax
    call arena_alloc
    test rax, rax
    jz .oom
    js .oom
    mov [rbx + Prog.coef + r15 * 8], rax
    mov rdi, rax
    mov rcx, [rsp]
    shr rcx, 3
    xor eax, eax
    rep stosq
    mov rsi, [rsp]                      ; the plane: as many samples, int16
    mov rdi, [r14 + JpegImage.arena]
    call arena_alloc
    test rax, rax
    jz .oom
    js .oom
    mov [r12 + JpegPlane.data], rax
    inc r15d
    jmp .component
.done:
    xor eax, eax
    jmp .out
.oom:
    mov rax, -ENOMEM
.out:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; rsi = an SOS marker, edx = its length: the scan's components, tables, band
; and bits -> rax
scan_header:
    mov r8, [rbx + Prog.image]
    movzx r9d, byte [rsi + 4]           ; components in the scan
    test r9d, r9d
    jz .bad
    movzx eax, byte [r8 + JpegImage.components]
    cmp r9d, eax
    ja .bad
    lea eax, [r9 + r9 + 6]
    cmp edx, eax
    jne .bad
    mov [rbx + Prog.ncomp], r9d
    xor ecx, ecx
.component:
    cmp ecx, r9d
    jae .band
    movzx eax, byte [rsi + rcx * 2 + 5] ; its id: which frame component
    xor edx, edx
.find:
    movzx r10d, byte [r8 + JpegImage.components]
    cmp edx, r10d
    jae .bad
    cmp al, [r8 + JpegImage.component_id + rdx]
    je .found
    inc edx
    jmp .find
.found:
    mov [rbx + Prog.comp + rcx * 4], edx
    movzx eax, byte [rsi + rcx * 2 + 6]
    mov r10d, eax
    shr eax, 4                          ; DC table
    and r10d, 15                        ; AC table
    cmp eax, 3
    ja .bad
    cmp r10d, 3
    ja .bad
    imul eax, eax, JPEG_HUFF_TABLE_SIZE
    add rax, [r8 + JpegImage.htables]
    mov [rbx + Prog.dc + rcx * 8], rax
    add r10d, 4
    imul r10d, r10d, JPEG_HUFF_TABLE_SIZE
    add r10, [r8 + JpegImage.htables]
    mov [rbx + Prog.ac + rcx * 8], r10
    inc ecx
    jmp .component
.band:
    lea r10, [rsi + r9 * 2 + 5]
    movzx eax, byte [r10]
    mov [rbx + Prog.ss], eax
    movzx ecx, byte [r10 + 1]
    mov [rbx + Prog.se], ecx
    cmp ecx, 63
    ja .bad
    cmp eax, ecx
    ja .bad
    test eax, eax
    jnz .ac_band
    test ecx, ecx                       ; DC: alone, any components
    jnz .bad
    jmp .bits
.ac_band:
    cmp r9d, 1                          ; AC: one component
    jne .bad
.bits:
    movzx eax, byte [r10 + 2]
    mov ecx, eax
    shr eax, 4
    and ecx, 15
    cmp eax, 13
    ja .bad
    cmp ecx, 13
    ja .bad
    mov [rbx + Prog.ah], eax
    mov [rbx + Prog.al], ecx
    ; the tables it will use, there
    cmp dword [rbx + Prog.ss], 0
    jne .ac_table
    test eax, eax                       ; DC refines read no table
    jnz .ready
    xor ecx, ecx
.dc_table:
    cmp ecx, r9d
    jae .ready
    mov rax, [rbx + Prog.dc + rcx * 8]
    cmp dword [rax + HUFF_MAX_SYMS], 0
    je .bad
    inc ecx
    jmp .dc_table
.ac_table:
    mov rax, [rbx + Prog.ac]
    cmp dword [rax + HUFF_MAX_SYMS], 0
    je .bad
.ready:
    xor eax, eax
    mov [rbx + Prog.eobrun], eax
    mov [rbx + Prog.pred], eax
    mov [rbx + Prog.pred + 4], eax
    mov [rbx + Prog.pred + 8], eax
    mov [rbx + Prog.units], eax
    mov [rbx + Prog.rst], eax
    mov eax, [rbx + Prog.mcux]          ; MCUs, or the component's blocks
    imul eax, [rbx + Prog.mcuy]
    cmp r9d, 1
    ja .total
    mov ecx, [rbx + Prog.comp]
    mov eax, [rbx + Prog.cbw + rcx * 4]
    imul eax, [rbx + Prog.cbh + rcx * 4]
.total:
    mov [rbx + Prog.total], eax
    xor eax, eax
    ret
.bad:
    mov rax, -EINVAL
    ret

; the scan's MCUs (its blocks, for one component), restarts between them
; -> rax
scan:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    xor r15d, r15d                      ; the unit
.unit:
    cmp r15d, [rbx + Prog.total]
    jae .done
    cmp dword [rbx + Prog.ncomp], 1
    ja .mcu
    mov ecx, [rbx + Prog.comp]          ; one block, in the component's own
    mov eax, r15d                       ; raster
    xor edx, edx
    div dword [rbx + Prog.cbw + rcx * 4]
    imul eax, [rbx + Prog.bw + rcx * 4] ; y x grid width + x
    add eax, edx
    shl rax, 7
    add rax, [rbx + Prog.coef + rcx * 8]
    mov [rbx + Prog.block], rax
    mov dword [rbx + Prog.sc], 0
    call block
    test rax, rax
    jnz .out
    jmp .counted
.mcu:                                   ; each component's v x h blocks
    mov eax, r15d
    xor edx, edx
    div dword [rbx + Prog.mcux]
    mov r13d, eax                       ; MCU y
    mov r14d, edx                       ; MCU x
    mov dword [rbx + Prog.sc], 0
.component:
    mov eax, [rbx + Prog.sc]
    cmp eax, [rbx + Prog.ncomp]
    jae .counted
    mov r12d, [rbx + Prog.comp + rax * 4]
    mov dword [rbx + Prog.by], 0
.block_y:
    imul ecx, r12d, JpegPlane_size
    movzx eax, byte [rbx + Prog.planes + JpegPlane.v + rcx]
    cmp [rbx + Prog.by], eax
    jae .next_component
    mov dword [rbx + Prog.bx], 0
.block_x:
    imul ecx, r12d, JpegPlane_size
    movzx r8d, byte [rbx + Prog.planes + JpegPlane.h + rcx]
    cmp [rbx + Prog.bx], r8d
    jae .next_y
    movzx r9d, byte [rbx + Prog.planes + JpegPlane.v + rcx]
    mov eax, r13d                       ; (MCU y x v + y) x grid width
    imul eax, r9d
    add eax, [rbx + Prog.by]
    imul eax, [rbx + Prog.bw + r12 * 4]
    mov edx, r14d                       ; + MCU x x h + x
    imul edx, r8d
    add edx, [rbx + Prog.bx]
    add eax, edx
    shl rax, 7
    add rax, [rbx + Prog.coef + r12 * 8]
    mov [rbx + Prog.block], rax
    call block
    test rax, rax
    jnz .out
    inc dword [rbx + Prog.bx]
    jmp .block_x
.next_y:
    inc dword [rbx + Prog.by]
    jmp .block_y
.next_component:
    inc dword [rbx + Prog.sc]
    jmp .component
.counted:
    inc r15d
    mov rax, [rbx + Prog.image]
    mov ecx, [rax + JpegImage.restart]
    test ecx, ecx
    jz .unit
    mov eax, r15d
    xor edx, edx
    div ecx
    test edx, edx
    jnz .unit
    cmp r15d, [rbx + Prog.total]        ; never after the last
    jae .unit
    lea rdi, [rbx + Prog.reader]
    mov esi, [rbx + Prog.rst]
    call jpeg_expect_restart
    test rax, rax
    jnz .out
    inc dword [rbx + Prog.rst]
    and dword [rbx + Prog.rst], 7
    xor eax, eax
    mov [rbx + Prog.eobrun], eax
    mov [rbx + Prog.pred], eax
    mov [rbx + Prog.pred + 4], eax
    mov [rbx + Prog.pred + 8], eax
    jmp .unit
.done:
    xor eax, eax
.out:
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret

; reader -> rax = the next symbol of table %1 (a Prog field, indexed by rcx)
%macro HUFF 1
    mov rdi, %1
    lea rsi, [rbx + Prog.reader]
    call jpeg_huff_decode_stream
    test rax, rax
    js .out
%endmacro
; rax = the next %1 bits
%macro BITS 1
    lea rdi, [rbx + Prog.reader]
    mov esi, %1
    call jpeg_bits_get
    test rax, rax
    js .out
%endmacro

; one block of the scan: [Prog.block], scan component [Prog.sc] -> rax
block:
    sub rsp, 8
    cmp dword [rbx + Prog.ss], 0
    jne .ac
    cmp dword [rbx + Prog.ah], 0
    jne .dc_refine
    mov ecx, [rbx + Prog.sc]            ; DC first: the difference, added
    HUFF [rbx + Prog.dc + rcx * 8]
    cmp eax, 11
    ja .bad
    lea rdi, [rbx + Prog.reader]
    mov esi, eax
    call jpeg_receive_extend
    test edx, edx
    jnz .out
    mov ecx, [rbx + Prog.sc]
    mov ecx, [rbx + Prog.comp + rcx * 4]
    add eax, [rbx + Prog.pred + rcx * 4]
    mov [rbx + Prog.pred + rcx * 4], eax
    mov ecx, [rbx + Prog.al]
    shl eax, cl
    cmp eax, -32768
    jl .bad
    cmp eax, 32767
    jg .bad
    mov rdx, [rbx + Prog.block]
    mov [rdx], ax
    jmp .done
.dc_refine:                             ; one more bit of the DC
    BITS 1
    test eax, eax
    jz .done
    mov ecx, [rbx + Prog.al]
    mov eax, 1
    shl eax, cl
    mov rdx, [rbx + Prog.block]
    or [rdx], ax
    jmp .done
.ac:
    cmp dword [rbx + Prog.ah], 0
    jne .ac_refine
    call ac_first
    jmp .out
.ac_refine:
    call ac_refine
    jmp .out
.done:
    xor eax, eax
    jmp .out
.bad:
    mov rax, -EINVAL
.out:
    add rsp, 8
    ret

; AC first: the band's coefficients, or one block of an end-of-band run
ac_first:
    sub rsp, 8
    cmp dword [rbx + Prog.eobrun], 0
    je .start
    dec dword [rbx + Prog.eobrun]
    jmp .done
.start:
    mov eax, [rbx + Prog.ss]
    mov [rbx + Prog.k], eax
.symbol:
    mov eax, [rbx + Prog.k]
    cmp eax, [rbx + Prog.se]
    ja .done
    HUFF [rbx + Prog.ac]
    mov ecx, eax
    shr ecx, 4                          ; r
    and eax, 15                         ; s
    jnz .value
    cmp ecx, 15
    je .zeros
    mov eax, 1                          ; an end-of-band run of 2^r + r bits
    shl eax, cl
    mov [rbx + Prog.eobrun], eax
    test ecx, ecx
    jz .run_read
    BITS ecx
    add [rbx + Prog.eobrun], eax
.run_read:
    dec dword [rbx + Prog.eobrun]       ; this block one of them
    jmp .done
.zeros:                                 ; sixteen zeros
    add dword [rbx + Prog.k], 16
    jmp .symbol
.value:
    add [rbx + Prog.k], ecx
    cmp dword [rbx + Prog.k], 63
    ja .bad
    lea rdi, [rbx + Prog.reader]
    mov esi, eax
    call jpeg_receive_extend
    test edx, edx
    jnz .out
    mov ecx, [rbx + Prog.al]
    shl eax, cl
    mov ecx, [rbx + Prog.k]
    lea rdx, [rel zigzag]
    movzx ecx, byte [rdx + rcx]
    mov rdx, [rbx + Prog.block]
    mov [rdx + rcx * 2], ax
    inc dword [rbx + Prog.k]
    jmp .symbol
.done:
    xor eax, eax
    jmp .out
.bad:
    mov rax, -EINVAL
.out:
    add rsp, 8
    ret

; AC refine: a bit more of each coefficient already nonzero in the band,
; new ones (+-1 << Al) at the zeros the runs count; in an end-of-band run
; only the bits of those already nonzero
ac_refine:
    sub rsp, 8
    mov eax, [rbx + Prog.ss]
    mov [rbx + Prog.k], eax
    cmp dword [rbx + Prog.eobrun], 0
    jne .tail
.symbol:
    mov eax, [rbx + Prog.k]
    cmp eax, [rbx + Prog.se]
    ja .done
    HUFF [rbx + Prog.ac]
    mov ecx, eax
    shr ecx, 4
    mov [rbx + Prog.r], ecx
    and eax, 15
    jz .no_value
    cmp eax, 1                          ; new ones are only ever +-1
    jne .bad
    BITS 1
    mov ecx, [rbx + Prog.al]
    mov edx, 1
    shl edx, cl
    test eax, eax
    jnz .signed
    neg edx
.signed:
    mov [rbx + Prog.s], edx
    jmp .advance
.no_value:
    mov dword [rbx + Prog.s], 0
    cmp ecx, 15                         ; sixteen zeros passed
    je .advance
    mov eax, 1                          ; an end-of-band run
    shl eax, cl
    mov [rbx + Prog.eobrun], eax
    test ecx, ecx
    jz .tail
    BITS ecx
    add [rbx + Prog.eobrun], eax
    jmp .tail
.advance:                               ; to the r+1th zero, refining the
    mov ecx, [rbx + Prog.k]             ; nonzero ones passed
    lea rdx, [rel zigzag]
    movzx ecx, byte [rdx + rcx]
    mov rdx, [rbx + Prog.block]
    cmp word [rdx + rcx * 2], 0
    je .zero
    call refine
    test rax, rax
    jnz .out
    jmp .next
.zero:
    dec dword [rbx + Prog.r]
    js .place
.next:
    inc dword [rbx + Prog.k]
    mov eax, [rbx + Prog.k]
    cmp eax, [rbx + Prog.se]
    jbe .advance
.place:
    mov eax, [rbx + Prog.s]
    test eax, eax
    jz .placed
    mov ecx, [rbx + Prog.k]
    cmp ecx, 63
    jbe .in_block
    mov ecx, 63
.in_block:
    lea rdx, [rel zigzag]
    movzx ecx, byte [rdx + rcx]
    mov rdx, [rbx + Prog.block]
    mov [rdx + rcx * 2], ax
.placed:
    inc dword [rbx + Prog.k]
    jmp .symbol
.tail:                                  ; this block in an end-of-band run
    mov eax, [rbx + Prog.k]
    cmp eax, [rbx + Prog.se]
    ja .tail_done
    mov ecx, eax
    lea rdx, [rel zigzag]
    movzx ecx, byte [rdx + rcx]
    mov rdx, [rbx + Prog.block]
    cmp word [rdx + rcx * 2], 0
    je .tail_next
    call refine
    test rax, rax
    jnz .out
.tail_next:
    inc dword [rbx + Prog.k]
    jmp .tail
.tail_done:
    dec dword [rbx + Prog.eobrun]
.done:
    xor eax, eax
    jmp .out
.bad:
    mov rax, -EINVAL
.out:
    add rsp, 8
    ret

; rdx = block, rcx = a nonzero coefficient's index in it: its next bit; a
; 1 moves it away from 0 by 1 << Al, unless that bit is set -> rax
refine:
    push rcx
    push rdx
    sub rsp, 8
    BITS 1
    add rsp, 8
    pop rdx
    pop rcx
    test eax, eax
    jz .done
    movsx eax, word [rdx + rcx * 2]
    push rcx
    mov ecx, [rbx + Prog.al]
    mov r8d, 1
    shl r8d, cl
    pop rcx
    test eax, r8d
    jnz .done
    test eax, eax
    jns .up
    neg r8d
.up:
    add eax, r8d
    mov [rdx + rcx * 2], ax
.done:
    xor eax, eax
    ret
.out:
    add rsp, 24
    ret

; every block dequantized and transformed into its plane, then the rows
; -> rax
finish:
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r14, [rbx + Prog.image]
    xor r15d, r15d                      ; component
.component:
    movzx eax, byte [r14 + JpegImage.components]
    cmp r15d, eax
    jae .rows
    mov dword [rbx + Prog.by], 0
.block_y:
    mov eax, [rbx + Prog.by]
    cmp eax, [rbx + Prog.cbh + r15 * 4]
    jae .next_component
    mov dword [rbx + Prog.bx], 0
.block_x:
    mov eax, [rbx + Prog.bx]
    cmp eax, [rbx + Prog.cbw + r15 * 4]
    jae .next_y
    mov eax, [rbx + Prog.by]
    imul eax, [rbx + Prog.bw + r15 * 4]
    add eax, [rbx + Prog.bx]
    shl rax, 7
    mov rsi, [rbx + Prog.coef + r15 * 8]
    add rsi, rax
    lea rdi, [rbx + Prog.temp]
    mov ecx, 16
    rep movsq
    lea rdi, [rbx + Prog.temp]
    movzx eax, byte [r14 + JpegImage.component_qt + r15]
    shl eax, 8
    mov rsi, [r14 + JpegImage.qtables]
    add rsi, rax
    call jpeg_idct8x8
    imul eax, r15d, JpegPlane_size
    lea r12, [rbx + Prog.planes + rax]
    mov rdi, [r12 + JpegPlane.data]
    lea rsi, [rbx + Prog.temp]
    mov edx, [rbx + Prog.bx]
    mov ecx, [rbx + Prog.by]
    mov r8d, [r12 + JpegPlane.stride]
    call jpeg_place_block
    inc dword [rbx + Prog.bx]
    jmp .block_x
.next_y:
    inc dword [rbx + Prog.by]
    jmp .block_y
.next_component:
    inc r15d
    jmp .component
.rows:
    mov rdi, r14
    lea rsi, [rbx + Prog.planes]
    call jpeg_emit_rows
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    ret

section .rodata
; a band's index -> the coefficient's in the block
zigzag:
    db 0, 1, 8, 16, 9, 2, 3, 10
    db 17, 24, 32, 25, 18, 11, 4, 5
    db 12, 19, 26, 33, 40, 48, 41, 34
    db 27, 20, 13, 6, 7, 14, 21, 28
    db 35, 42, 49, 56, 57, 50, 43, 36
    db 29, 22, 15, 23, 30, 37, 44, 51
    db 58, 59, 52, 45, 38, 31, 39, 46
    db 53, 60, 61, 54, 47, 55, 62, 63

section .data
global jpeg_progressive_version
jpeg_progressive_version: dq 0x010000
