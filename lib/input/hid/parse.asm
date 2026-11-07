; =============================================================================
; Utkarsha OS — lib/input/hid/parse.asm
; =============================================================================
; HID report descriptors into fields, and values out of reports.
;
;   hid_parse(bytes, len, desc*)           a descriptor → hid_desc
;   hid_report_bits(desc*, id, kind)        how long a report is, in bits
;   hid_find_usage(desc*, kind, usage, &field, &index)
;                                           the variable element with a usage
;   hid_get(report, len, field*, index)     one element's value
;
; Descriptors come from devices and are hostile: every item is checked
; against the descriptor's end, sizes and counts against the limits in
; hid.inc, and every field must fit in a report HID_MAX_REPORT_BITS long.
; hid_parse is not reentrant: one parse at a time.
; =============================================================================

%ifndef LIB_INPUT_HID_PARSE_ASM
%define LIB_INPUT_HID_PARSE_ASM

; the global state, as Push saves it
struc hid_global
    .page:      resd 1
    .lmin:      resd 1
    .lmax:      resd 1          ; signed by its size
    .lmax_raw:  resd 1          ; unsigned, for maxima above the sign bit
    .pmin:      resd 1
    .pmax:      resd 1
    .unit_exp:  resd 1
    .unit:      resd 1
    .size:      resd 1
    .id:        resd 1
    .count:     resd 1
endstruc

section .bss
alignb 8
hid_g:          resb hid_global_size
hid_stack:      resb hid_global_size * HID_MAX_PUSH
hid_sp:         resd 1
hid_lstart:     resd 1          ; first usage of this main item in the list
hid_umin:       resd 1
hid_umax:       resd 1
hid_have_range: resd 1          ; bit 0 minimum seen, bit 1 maximum
hid_depth:      resd 1
hid_coll_stack: resw HID_MAX_DEPTH  ; open collections
hid_app_stack:  resd HID_MAX_DEPTH  ; application usage at each level
hid_app:        resd 1          ; current application usage

section .text

; -----------------------------------------------------------------------------
; hid_local_reset — after each main item
; Needs R15 = desc
; -----------------------------------------------------------------------------
hid_local_reset:
    mov eax, [r15 + hid_desc.usage_count]
    mov [rel hid_lstart], eax
    xor eax, eax
    mov [rel hid_umin], eax
    mov [rel hid_umax], eax
    mov [rel hid_have_range], eax
    ret

; -----------------------------------------------------------------------------
; hid_first_usage — the local usage a collection or field starts with
; Output: EAX
; -----------------------------------------------------------------------------
hid_first_usage:
    mov ecx, [rel hid_lstart]
    cmp ecx, [r15 + hid_desc.usage_count]
    jae .range
    mov eax, [r15 + hid_desc.usages + rcx * 4]
    ret
.range:
    mov eax, [rel hid_umin]
    ret

; -----------------------------------------------------------------------------
; hid_parse — parse a report descriptor
; Input:  RDI = descriptor bytes, ESI = length, RDX = hid_desc to fill
; Output: EAX = 0, -HID_EINVAL (malformed) or -HID_ENOSPC (too big)
; -----------------------------------------------------------------------------
global hid_parse
hid_parse:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi                        ; next item
    mov r13d, esi
    add r13, rdi                        ; end
    mov r15, rdx
    ; an empty description
    mov rdi, r15
    mov ecx, hid_desc_size
    xor eax, eax
    rep stosb
    lea rdi, [rel hid_g]
    mov ecx, hid_global_size
    rep stosb
    mov [rel hid_sp], eax
    mov [rel hid_depth], eax
    mov [rel hid_app], eax
    call hid_local_reset

.item:
    cmp r12, r13
    jae .done
    movzx ebx, byte [r12]               ; prefix
    cmp ebx, 0xFE
    je .long
    mov ecx, ebx
    and ecx, 3
    cmp ecx, 3
    jne .sized
    mov ecx, 4                          ; size code 3 means 4 bytes
.sized:
    lea rax, [r12 + 1 + rcx]
    cmp rax, r13
    ja .bad
    ; the data: unsigned in R14D, signed in EDX
    xor r14d, r14d
    xor edx, edx
    cmp ecx, 1
    je .d1
    cmp ecx, 2
    je .d2
    cmp ecx, 4
    je .d4
    jmp .data
.d1:
    movzx r14d, byte [r12 + 1]
    movsx edx, byte [r12 + 1]
    jmp .data
.d2:
    movzx r14d, word [r12 + 1]
    movsx edx, word [r12 + 1]
    jmp .data
.d4:
    mov r14d, [r12 + 1]
    mov edx, r14d
.data:
    mov r8d, ecx                        ; data size
    lea r12, [r12 + 1 + rcx]
    mov eax, ebx
    shr eax, 2
    and eax, 3                          ; type
    shr ebx, 4                          ; tag
    cmp eax, 0
    je .main
    cmp eax, 1
    je .global
    cmp eax, 2
    je .local
    jmp .item                           ; reserved type: skipped

.long:
    ; 0xFE, data size, tag, data: skipped
    lea rax, [r12 + 3]
    cmp rax, r13
    ja .bad
    movzx ecx, byte [r12 + 1]
    lea rax, [r12 + 3 + rcx]
    cmp rax, r13
    ja .bad
    mov r12, rax
    jmp .item

    ; ---- global items ----
.global:
    lea rdi, [rel hid_g]
    cmp ebx, 0
    je .g_page
    cmp ebx, 1
    je .g_lmin
    cmp ebx, 2
    je .g_lmax
    cmp ebx, 3
    je .g_pmin
    cmp ebx, 4
    je .g_pmax
    cmp ebx, 5
    je .g_uexp
    cmp ebx, 6
    je .g_unit
    cmp ebx, 7
    je .g_size
    cmp ebx, 8
    je .g_id
    cmp ebx, 9
    je .g_count
    cmp ebx, 10
    je .g_push
    cmp ebx, 11
    je .g_pop
    jmp .item
.g_page:
    mov [rdi + hid_global.page], r14d
    jmp .item
.g_lmin:
    mov [rdi + hid_global.lmin], edx
    jmp .item
.g_lmax:
    mov [rdi + hid_global.lmax], edx
    mov [rdi + hid_global.lmax_raw], r14d
    jmp .item
.g_pmin:
    mov [rdi + hid_global.pmin], edx
    jmp .item
.g_pmax:
    mov [rdi + hid_global.pmax], edx
    jmp .item
.g_uexp:
    ; a 4-bit signed nibble in practice
    mov eax, r14d
    and eax, 0x0F
    cmp eax, 8
    jb .uexp_pos
    sub eax, 16
.uexp_pos:
    mov [rdi + hid_global.unit_exp], eax
    jmp .item
.g_unit:
    mov [rdi + hid_global.unit], r14d
    jmp .item
.g_size:
    mov [rdi + hid_global.size], r14d
    jmp .item
.g_id:
    test r14d, r14d
    jz .bad                             ; 0 is not a report ID
    cmp r14d, 255
    ja .bad
    mov [rdi + hid_global.id], r14d
    mov dword [r15 + hid_desc.uses_ids], 1
    jmp .item
.g_count:
    mov [rdi + hid_global.count], r14d
    jmp .item
.g_push:
    mov eax, [rel hid_sp]
    cmp eax, HID_MAX_PUSH
    jae .full
    imul eax, eax, hid_global_size
    lea rdi, [rel hid_stack]
    add rdi, rax
    lea rsi, [rel hid_g]
    mov ecx, hid_global_size
    rep movsb
    inc dword [rel hid_sp]
    jmp .item
.g_pop:
    mov eax, [rel hid_sp]
    test eax, eax
    jz .bad
    dec eax
    mov [rel hid_sp], eax
    imul eax, eax, hid_global_size
    lea rsi, [rel hid_stack]
    add rsi, rax
    lea rdi, [rel hid_g]
    mov ecx, hid_global_size
    rep movsb
    jmp .item

    ; ---- local items ----
.local:
    ; a usage of 4 bytes carries its page; shorter ones take the current
    mov eax, r14d
    cmp r8d, 4
    je .extended
    and eax, 0xFFFF
    mov ecx, [rel hid_g + hid_global.page]
    shl ecx, 16
    or eax, ecx
.extended:
    cmp ebx, 0
    je .l_usage
    cmp ebx, 1
    je .l_min
    cmp ebx, 2
    je .l_max
    jmp .item                           ; designators, strings, delimiters
.l_usage:
    mov ecx, [r15 + hid_desc.usage_count]
    cmp ecx, HID_MAX_USAGES
    jae .full
    mov [r15 + hid_desc.usages + rcx * 4], eax
    inc dword [r15 + hid_desc.usage_count]
    jmp .item
.l_min:
    mov [rel hid_umin], eax
    or dword [rel hid_have_range], 1
    jmp .item
.l_max:
    mov [rel hid_umax], eax
    or dword [rel hid_have_range], 2
    jmp .item

    ; ---- main items ----
.main:
    cmp ebx, 8
    je .field_input
    cmp ebx, 9
    je .field_output
    cmp ebx, 11
    je .field_feature
    cmp ebx, 10
    je .collection
    cmp ebx, 12
    je .end_collection
    call hid_local_reset
    jmp .item
.field_input:
    mov ecx, HID_INPUT
    jmp .field
.field_output:
    mov ecx, HID_OUTPUT
    jmp .field
.field_feature:
    mov ecx, HID_FEATURE
.field:
    call hid_add_field
    test eax, eax
    jnz .out
    call hid_local_reset
    jmp .item

.collection:
    mov eax, [r15 + hid_desc.coll_count]
    cmp eax, HID_MAX_COLLECTIONS
    jae .full
    mov ecx, [rel hid_depth]
    cmp ecx, HID_MAX_DEPTH
    jae .full
    mov r9d, eax                        ; its index
    imul eax, eax, hid_collection_size
    lea rdi, [r15 + hid_desc.collections + rax]
    call hid_first_usage
    mov [rdi + hid_collection.usage], eax
    mov [rdi + hid_collection.type], r14b
    mov word [rdi + hid_collection.parent], 0xFFFF
    mov ecx, [rel hid_depth]
    test ecx, ecx
    jz .no_parent
    lea rdx, [rel hid_coll_stack]
    mov r10w, [rdx + rcx * 2 - 2]
    mov [rdi + hid_collection.parent], r10w
.no_parent:
    lea rdx, [rel hid_app_stack]
    mov r10d, [rel hid_app]
    mov [rdx + rcx * 4], r10d           ; restored at End Collection
    lea rdx, [rel hid_coll_stack]
    mov [rdx + rcx * 2], r9w
    inc dword [rel hid_depth]
    inc dword [r15 + hid_desc.coll_count]
    cmp r14d, 1                         ; an application collection
    jne .coll_done
    mov [rel hid_app], eax
.coll_done:
    call hid_local_reset
    jmp .item
.end_collection:
    mov ecx, [rel hid_depth]
    test ecx, ecx
    jz .bad
    dec ecx
    mov [rel hid_depth], ecx
    lea rdx, [rel hid_app_stack]
    mov eax, [rdx + rcx * 4]
    mov [rel hid_app], eax
    call hid_local_reset
    jmp .item

.done:
    xor eax, eax                        ; collections left open are tolerated
    jmp .out
.full:
    mov eax, -HID_ENOSPC
    jmp .out
.bad:
    mov eax, -HID_EINVAL
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hid_add_field — a main Input, Output or Feature item
; Input:  ECX = kind, R14D = the item's data bits; R15 = desc
; Output: EAX = 0, -HID_EINVAL or -HID_ENOSPC
; -----------------------------------------------------------------------------
hid_add_field:
    push rbx
    push r12
    push r13
    lea rbx, [rel hid_g]
    mov r12d, ecx                       ; kind
    mov eax, [rbx + hid_global.size]
    mov edx, [rbx + hid_global.count]
    test edx, edx
    jz .ok                              ; nothing in it
    test eax, eax
    jz .bad
    cmp eax, 32
    ja .bad
    cmp edx, HID_MAX_REPORT_BITS
    ja .bad
    ; where it goes in its report
    imul eax, edx                       ; its bits
    mov r13d, eax
    mov ecx, [rbx + hid_global.id]
    imul ecx, ecx, 3
    lea ecx, [rcx + r12 - 1]
    lea r8, [r15 + hid_desc.report_bits + rcx * 4]
    mov r9d, [r8]                       ; its offset
    lea eax, [r9 + r13]
    cmp eax, HID_MAX_REPORT_BITS
    ja .bad
    mov [r8], eax
    ; a constant field is padding: it takes room, it is not a field
    test r14d, HID_F_CONST
    jnz .ok
    mov eax, [r15 + hid_desc.field_count]
    cmp eax, HID_MAX_FIELDS
    jae .full
    inc dword [r15 + hid_desc.field_count]
    imul eax, eax, hid_field_size
    lea rdi, [r15 + hid_desc.fields + rax]
    mov eax, [rbx + hid_global.id]
    mov [rdi + hid_field.report_id], al
    mov [rdi + hid_field.kind], r12b
    mov [rdi + hid_field.flags], r14w
    mov [rdi + hid_field.bit_offset], r9d
    mov eax, [rbx + hid_global.size]
    mov [rdi + hid_field.size], ax
    mov eax, [rbx + hid_global.count]
    mov [rdi + hid_field.count], ax
    ; logical range; a maximum below a non-negative minimum was meant
    ; unsigned (a common shortcut in descriptors)
    mov eax, [rbx + hid_global.lmin]
    mov [rdi + hid_field.logical_min], eax
    mov ecx, [rbx + hid_global.lmax]
    test eax, eax
    js .lmax
    cmp ecx, eax
    jge .lmax
    mov ecx, [rbx + hid_global.lmax_raw]
.lmax:
    mov [rdi + hid_field.logical_max], ecx
    mov eax, [rbx + hid_global.pmin]
    mov [rdi + hid_field.physical_min], eax
    mov eax, [rbx + hid_global.pmax]
    mov [rdi + hid_field.physical_max], eax
    mov eax, [rbx + hid_global.unit]
    mov [rdi + hid_field.unit], eax
    mov eax, [rbx + hid_global.unit_exp]
    mov [rdi + hid_field.unit_exp], al
    ; collection and application
    mov word [rdi + hid_field.collection], 0xFFFF
    mov ecx, [rel hid_depth]
    test ecx, ecx
    jz .no_coll
    lea rdx, [rel hid_coll_stack]
    mov ax, [rdx + rcx * 2 - 2]
    mov [rdi + hid_field.collection], ax
.no_coll:
    mov eax, [rel hid_app]
    mov [rdi + hid_field.application], eax
    ; usages: an explicit list, else the range
    mov ecx, [rel hid_lstart]
    mov edx, [r15 + hid_desc.usage_count]
    sub edx, ecx
    mov [rdi + hid_field.usage_list], cx
    mov [rdi + hid_field.usage_count], dx
    test edx, edx
    jz .range
    mov eax, [r15 + hid_desc.usages + rcx * 4]
    mov [rdi + hid_field.usage_min], eax
    lea eax, [rcx + rdx - 1]
    mov eax, [r15 + hid_desc.usages + rax * 4]
    mov [rdi + hid_field.usage_max], eax
    jmp .ok
.range:
    mov eax, [rel hid_umin]
    mov [rdi + hid_field.usage_min], eax
    mov eax, [rel hid_umax]
    test dword [rel hid_have_range], 2
    jnz .max
    mov eax, [rel hid_umin]
.max:
    mov [rdi + hid_field.usage_max], eax
.ok:
    xor eax, eax
    jmp .out
.full:
    mov eax, -HID_ENOSPC
    jmp .out
.bad:
    mov eax, -HID_EINVAL
.out:
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hid_report_bits — a report's length in bits (ID byte not counted)
; Input:  RDI = desc, ESI = report ID (0 when the device uses none),
;         EDX = kind
; Output: EAX = bits, or 0 for a report the descriptor does not define
; -----------------------------------------------------------------------------
global hid_report_bits
hid_report_bits:
    xor eax, eax
    cmp esi, 255
    ja .out
    dec edx
    cmp edx, 2
    ja .out
    imul esi, esi, 3
    add esi, edx
    mov eax, [rdi + hid_desc.report_bits + rsi * 4]
.out:
    ret

; -----------------------------------------------------------------------------
; hid_field_usage — the usage of a variable field's element
; Input:  RDI = desc, RSI = field, EDX = element
; Output: EAX = usage
; -----------------------------------------------------------------------------
global hid_field_usage
hid_field_usage:
    movzx ecx, word [rsi + hid_field.usage_count]
    test ecx, ecx
    jz .range
    cmp edx, ecx
    jb .listed
    lea edx, [rcx - 1]                  ; past the list: the last repeats
.listed:
    movzx ecx, word [rsi + hid_field.usage_list]
    add ecx, edx
    mov eax, [rdi + hid_desc.usages + rcx * 4]
    ret
.range:
    mov eax, [rsi + hid_field.usage_min]
    add eax, edx
    cmp eax, [rsi + hid_field.usage_max]
    jbe .out
    mov eax, [rsi + hid_field.usage_max]
.out:
    ret

; -----------------------------------------------------------------------------
; hid_find_usage — the variable element carrying a usage
; Input:  RDI = desc, ESI = kind, EDX = usage, RCX = hid_field** out,
;         R8 = u32* element out; the search starts after the field already
;         in *RCX (0 to start at the first), so repeated calls find every
;         one (the fingers of a touchpad report one field each)
; Output: EAX = 1 when found, 0 when there are no more
; -----------------------------------------------------------------------------
global hid_find_usage
hid_find_usage:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov rbx, rdi
    mov r12d, esi
    mov r13d, edx
    mov r14, rcx
    mov r15, r8
    lea rsi, [rbx + hid_desc.fields]
    mov rax, [r14]
    test rax, rax
    jz .start
    lea rsi, [rax + hid_field_size]     ; after the one given
.start:
    mov eax, [rbx + hid_desc.field_count]
    imul eax, eax, hid_field_size
    lea r9, [rbx + hid_desc.fields + rax]   ; end of the fields
.field:
    cmp rsi, r9
    jae .none
    movzx eax, byte [rsi + hid_field.kind]
    cmp eax, r12d
    jne .next
    test word [rsi + hid_field.flags], HID_F_VARIABLE
    jz .next
    movzx ecx, word [rsi + hid_field.count]
    xor edx, edx
.element:
    cmp edx, ecx
    jae .next
    push rcx
    push rdx
    push rsi
    push r9
    mov rdi, rbx
    call hid_field_usage
    pop r9
    pop rsi
    pop rdx
    pop rcx
    cmp eax, r13d
    je .found
    inc edx
    jmp .element
.next:
    add rsi, hid_field_size
    jmp .field
.found:
    mov [r14], rsi
    mov [r15], edx
    mov eax, 1
    jmp .out
.none:
    xor eax, eax
.out:
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; -----------------------------------------------------------------------------
; hid_get — one element's value from a report
; Input:  RDI = report bytes (after the ID byte, if any), ESI = their
;         length, RDX = field, ECX = element
; Output: EAX = 0 with RDX = the value (sign-extended when the field's
;         logical minimum is negative); -HID_ERANGE when the element lies
;         past the report's end
; -----------------------------------------------------------------------------
global hid_get
hid_get:
    push rbx
    mov r8, rdx
    movzx r9d, word [r8 + hid_field.size]
    movzx eax, word [r8 + hid_field.count]
    cmp ecx, eax
    jae .range
    mov eax, ecx
    imul eax, r9d
    add eax, [r8 + hid_field.bit_offset]    ; first bit
    lea edx, [rax + r9]                     ; one past the last
    mov r10d, esi
    shl r10, 3
    cmp rdx, r10
    ja .range
    ; gather the bytes it spans (at most five) into RBX
    mov r10d, eax
    shr r10d, 3                         ; first byte
    lea r11d, [rdx + 7]
    shr r11d, 3                         ; one past the last byte
    xor ebx, ebx
    mov ecx, r11d
.byte:
    cmp ecx, r10d
    jbe .gathered
    dec ecx
    shl rbx, 8
    movzx edx, byte [rdi + rcx]
    or rbx, rdx
    jmp .byte
.gathered:
    mov ecx, eax
    and ecx, 7
    shr rbx, cl
    mov ecx, r9d
    mov rax, -1
    cmp ecx, 64
    jae .masked
    mov eax, 1
    shl rax, cl
    dec rax
.masked:
    and rbx, rax
    ; sign-extend when the field can be negative
    cmp dword [r8 + hid_field.logical_min], 0
    jge .value
    mov ecx, 64
    sub ecx, r9d
    shl rbx, cl
    sar rbx, cl
.value:
    mov rdx, rbx
    xor eax, eax
    pop rbx
    ret
.range:
    mov eax, -HID_ERANGE
    pop rbx
    ret

%endif ; LIB_INPUT_HID_PARSE_ASM
