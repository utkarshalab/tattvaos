; =============================================================================
; Utkarsha OS — lib/ugfx/2d/svg_xml.asm
; =============================================================================
; The XML layer of the SVG reader: tags and attributes, and the small string
; helpers the other SVG files share.
;
;   ugfx_svg_xml_next(xml)      next start or end tag -> 1 start, 2 end, 0 end
;                               of input (or a tag left open)
;   ugfx_svg_xml_attr(xml, at)  next attribute of the current start tag
;                               -> 1 (name and value ranges), 0 none left
;   ugfx_svg_xml_text_end(xml, name, length)
;                               where the element just started ends: the
;                               '<' of its closing tag (for <style> text)
;   ugfx_svg_lookup(text, end, table)   -> id or -1 in a length-prefixed table
;   ugfx_svg_trim(text, end)            -> trimmed (whitespace, !important)
;   ugfx_svg_same(a, a_end, b, b_end)   -> ZF set when equal
;
; Comments, processing instructions, DOCTYPE and CDATA sections are skipped
; between tags; a '>' inside a quoted attribute value does not end a tag.
; Element and attribute names are taken as written (no namespaces).
; =============================================================================

%include "ugfx.inc"

section .text

; rdi = from, rsi = end, edx = up to 4 bytes to find, ecx = their count
;   -> rax = just past them, or end
xml_skip_past:
.at:
    lea rax, [rdi + rcx]
    cmp rax, rsi
    ja .end
    xor r8d, r8d
.cmp:
    cmp r8d, ecx
    jae .found
    mov r9d, edx
    push rcx
    lea ecx, [r8 * 8]
    shr r9d, cl
    pop rcx
    cmp [rdi + r8], r9b
    jne .next
    inc r8d
    jmp .cmp
.next:
    inc rdi
    jmp .at
.found:
    lea rax, [rdi + rcx]
    ret
.end:
    mov rax, rsi
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_xml_next — rdi = UgfxSvgXml* -> eax = 1 start tag, 2 end tag,
;   0 none left. Start tags set name / name_end / attrs / tag_end / self;
;   end tags set name / name_end. cur moves past the tag.
; -----------------------------------------------------------------------------
global ugfx_svg_xml_next
ugfx_svg_xml_next:
    push rbx
    mov rbx, rdi
.token:
    mov rdi, [rbx + UgfxSvgXml_cur]
    mov rsi, [rbx + UgfxSvgXml_end]
.find_lt:
    cmp rdi, rsi
    jae .none
    cmp byte [rdi], '<'
    je .lt
    inc rdi
    jmp .find_lt
.lt:
    lea rax, [rdi + 1]
    cmp rax, rsi
    jae .none
    movzx eax, byte [rdi + 1]
    cmp al, '!'
    je .bang
    cmp al, '?'
    je .pi
    cmp al, '/'
    je .end_tag
    jmp .start_tag
.bang:
    ; <!-- ... -->, <![CDATA[ ... ]]>, else to '>'
    lea rax, [rdi + 4]
    cmp rax, rsi
    ja .bang_plain
    cmp word [rdi + 2], '--'
    jne .bang_cdata
    lea rdi, [rdi + 4]
    mov edx, '-->'
    mov ecx, 3
    jmp .skip
.bang_cdata:
    lea rax, [rdi + 9]
    cmp rax, rsi
    ja .bang_plain
    cmp dword [rdi + 2], '[CDA'
    jne .bang_plain
    lea rdi, [rdi + 9]
    mov edx, ']]>'
    mov ecx, 3
    jmp .skip
.bang_plain:
    inc rdi
    mov edx, '>'
    mov ecx, 1
    jmp .skip
.pi:
    lea rdi, [rdi + 2]
    mov edx, '?>'
    mov ecx, 2
.skip:
    call xml_skip_past
    mov [rbx + UgfxSvgXml_cur], rax
    jmp .token
.end_tag:
    lea rdi, [rdi + 2]
    mov [rbx + UgfxSvgXml_name], rdi
.end_name:
    cmp rdi, rsi
    jae .end_named
    movzx eax, byte [rdi]
    cmp al, ' '
    jbe .end_named
    cmp al, '>'
    je .end_named
    inc rdi
    jmp .end_name
.end_named:
    mov [rbx + UgfxSvgXml_name_end], rdi
    mov edx, '>'
    mov ecx, 1
    call xml_skip_past
    mov [rbx + UgfxSvgXml_cur], rax
    mov eax, 2
    pop rbx
    ret
.start_tag:
    inc rdi
    mov [rbx + UgfxSvgXml_name], rdi
.name:
    cmp rdi, rsi
    jae .none
    movzx eax, byte [rdi]
    cmp al, ' '
    jbe .name_end
    cmp al, '/'
    je .name_end
    cmp al, '>'
    je .name_end
    inc rdi
    jmp .name
.name_end:
    mov [rbx + UgfxSvgXml_name_end], rdi
    mov [rbx + UgfxSvgXml_attrs], rdi
    mov r8, rdi                         ; attributes start
    ; the tag's end, quotes respected
    xor ecx, ecx                        ; open quote
.tag_scan:
    cmp rdi, rsi
    jae .none                           ; unterminated tag: stop
    movzx eax, byte [rdi]
    test ecx, ecx
    jnz .in_quote
    cmp al, '>'
    je .tag_end
    cmp al, '"'
    je .quote
    cmp al, 39
    je .quote
    inc rdi
    jmp .tag_scan
.quote:
    mov ecx, eax
    inc rdi
    jmp .tag_scan
.in_quote:
    cmp eax, ecx
    jne .quoted_byte
    xor ecx, ecx
.quoted_byte:
    inc rdi
    jmp .tag_scan
.tag_end:
    lea rax, [rdi + 1]
    mov [rbx + UgfxSvgXml_cur], rax
    mov dword [rbx + UgfxSvgXml_self], 0
    cmp rdi, r8
    jbe .tag_closed
    cmp byte [rdi - 1], '/'
    jne .tag_closed
    mov dword [rbx + UgfxSvgXml_self], 1
    dec rdi
.tag_closed:
    mov [rbx + UgfxSvgXml_tag_end], rdi
    mov eax, 1
    pop rbx
    ret
.none:
    mov rax, [rbx + UgfxSvgXml_end]
    mov [rbx + UgfxSvgXml_cur], rax
    xor eax, eax
    pop rbx
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_xml_attr — rdi = const UgfxSvgXml* (a start tag), rsi =
;   UgfxSvgAttr* (cur = 0 to start) -> eax = 1 with name / name_end /
;   val / val_end set, 0 when no attribute is left (or one has no value)
; -----------------------------------------------------------------------------
global ugfx_svg_xml_attr
ugfx_svg_xml_attr:
    mov r9, rsi
    mov rsi, [rdi + UgfxSvgXml_tag_end]
    mov rax, [r9 + UgfxSvgAttr_cur]
    test rax, rax
    jnz .from
    mov rax, [rdi + UgfxSvgXml_attrs]
.from:
    mov rdi, rax
.ws:
    cmp rdi, rsi
    jae .none
    cmp byte [rdi], ' '
    ja .name
    inc rdi
    jmp .ws
.name:
    mov [r9 + UgfxSvgAttr_name], rdi
.name_scan:
    cmp rdi, rsi
    jae .none
    movzx eax, byte [rdi]
    cmp al, '='
    je .name_end
    cmp al, ' '
    jbe .name_end
    inc rdi
    jmp .name_scan
.name_end:
    mov [r9 + UgfxSvgAttr_name_end], rdi
.eq:
    cmp rdi, rsi
    jae .none
    movzx eax, byte [rdi]
    inc rdi
    cmp al, '='
    je .quote
    cmp al, ' '
    jbe .eq
    jmp .none                           ; a name without a value: stop
.quote:
    cmp rdi, rsi
    jae .none
    movzx ecx, byte [rdi]
    inc rdi
    cmp cl, '"'
    je .value
    cmp cl, 39
    je .value
    cmp cl, ' '
    jbe .quote
    jmp .none
.value:
    mov [r9 + UgfxSvgAttr_val], rdi
.value_scan:
    cmp rdi, rsi
    jae .none
    cmp [rdi], cl
    je .value_end
    inc rdi
    jmp .value_scan
.value_end:
    mov [r9 + UgfxSvgAttr_val_end], rdi
    inc rdi
    mov [r9 + UgfxSvgAttr_cur], rdi
    mov eax, 1
    ret
.none:
    mov [r9 + UgfxSvgAttr_cur], rsi
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_xml_text_end — rdi = const UgfxSvgXml* (just after a start tag),
;   rsi = element name, edx = its length -> rax = the '<' of "</name", or
;   the end of input
; -----------------------------------------------------------------------------
global ugfx_svg_xml_text_end
ugfx_svg_xml_text_end:
    mov r8, [rdi + UgfxSvgXml_cur]
    mov r9, [rdi + UgfxSvgXml_end]
.at:
    lea rax, [r8 + rdx + 2]
    cmp rax, r9
    ja .end
    cmp word [r8], '</'
    jne .next
    xor ecx, ecx
.cmp:
    cmp ecx, edx
    jae .found
    mov al, [rsi + rcx]
    cmp al, [r8 + rcx + 2]
    jne .next
    inc ecx
    jmp .cmp
.next:
    inc r8
    jmp .at
.found:
    mov rax, r8
    ret
.end:
    mov rax, r9
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_lookup — rdi = text, rsi = its end, rdx = table of (u8 length,
;   bytes, u8 id) ending with 0 -> eax = id or -1 (exact match)
; -----------------------------------------------------------------------------
global ugfx_svg_lookup
ugfx_svg_lookup:
    mov r8, rsi
    sub r8, rdi                         ; length
.entry:
    movzx ecx, byte [rdx]
    test ecx, ecx
    jz .none
    cmp rcx, r8
    jne .next
    xor r9d, r9d
.byte:
    cmp r9d, ecx
    jae .hit
    movzx eax, byte [rdi + r9]
    cmp al, [rdx + 1 + r9]
    jne .next
    inc r9d
    jmp .byte
.hit:
    movzx eax, byte [rdx + 1 + rcx]
    ret
.next:
    lea rdx, [rdx + rcx + 2]
    jmp .entry
.none:
    mov eax, -1
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_trim — rdi / rsi -> trimmed of whitespace and a trailing
;   "!important"
; -----------------------------------------------------------------------------
global ugfx_svg_trim
ugfx_svg_trim:
.front:
    cmp rdi, rsi
    jae .done
    movzx eax, byte [rdi]
    cmp al, ' '
    ja .back
    inc rdi
    jmp .front
.back:
    cmp rsi, rdi
    jbe .done
    movzx eax, byte [rsi - 1]
    cmp al, ' '
    ja .important
    dec rsi
    jmp .back
.important:
    mov rax, rsi
    sub rax, rdi
    cmp rax, 10
    jb .done
    cmp byte [rsi - 10], '!'
    jne .done
    sub rsi, 10
    jmp .back
.done:
    ret

; -----------------------------------------------------------------------------
; ugfx_svg_same — rdi / rsi = text a, rdx / rcx = text b -> ZF = 1 when the
;   bytes are equal
; -----------------------------------------------------------------------------
global ugfx_svg_same
ugfx_svg_same:
    mov rax, rsi
    sub rax, rdi
    mov r8, rcx
    sub r8, rdx
    cmp rax, r8
    jne .done
    xor r8d, r8d
.byte:
    cmp r8, rax
    jae .done                           ; equal: ZF from the cmp
    mov cl, [rdi + r8]
    cmp cl, [rdx + r8]
    jne .done
    inc r8
    jmp .byte
.done:
    ret

section .data
global ugfx_svg_xml_version
ugfx_svg_xml_version: dq 0x010000
