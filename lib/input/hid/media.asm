; =============================================================================
; Utkarsha OS — lib/input/hid/media.asm — media, volume and system keys
; =============================================================================
; The keys keyboards send outside the boot report, in Consumer Control and
; System Control collections, for every HID transport:
;
;   hid_media_prepare(desc, media)  keep what is needed of a parsed report
;                       descriptor: its Consumer and System Control input
;                       fields (8 at most) and their usages (64 at most).
;                       EAX = fields kept; 0 when there is nothing for it.
;                       The descriptor can be thrown away after this.
;   hid_media_report(media, report, len)    key events for what changed
;   hid_media_key(usage)    page << 16 | usage → keycode, or 0
;
; Both layouts devices use are read: an array of usage numbers (one per
; key held) and a variable bit per usage. A report only changes the keys
; of its own report ID.
; =============================================================================

%ifndef LIB_INPUT_HID_MEDIA_ASM
%define LIB_INPUT_HID_MEDIA_ASM

%define HID_MEDIA_FIELDS    8
%define HID_MEDIA_USAGES    64
%define HID_MEDIA_DOWN      8       ; keys held at once

%define HID_APP_CONSUMER    0x000C0001
%define HID_APP_SYSTEM      0x00010080

struc hid_media
    .dev:           resd 1          ; lib/input device ID
    .uses_ids:      resd 1
    .nfields:       resd 1
    .nusages:       resd 1
    .fields:        resb HID_MEDIA_FIELDS * hid_field_size
    .usages:        resd HID_MEDIA_USAGES
    .down_id:       resb HID_MEDIA_DOWN ; report ID of each key held
    .down_key:      resb HID_MEDIA_DOWN ; its keycode (0: free)
endstruc

section .bss
global hid_media_unknown
hid_media_unknown:  resd 1          ; usages with no keycode

section .rodata
; Consumer page usage → keycode, by usage
align 4
hid_consumer_keys:
    dw 0x0030
    db 116                          ; power
    db 0
    dw 0x0032
    db 142                          ; sleep
    db 0
    dw 0x0040
    db 139                          ; menu
    db 0
    dw 0x006F
    db 225                          ; brightness up
    db 0
    dw 0x0070
    db 224                          ; brightness down
    db 0
    dw 0x00B0
    db 207                          ; play
    db 0
    dw 0x00B1
    db 201                          ; pause
    db 0
    dw 0x00B3
    db 208                          ; fast forward
    db 0
    dw 0x00B4
    db 168                          ; rewind
    db 0
    dw 0x00B5
    db 163                          ; next track
    db 0
    dw 0x00B6
    db 165                          ; previous track
    db 0
    dw 0x00B7
    db 166                          ; stop
    db 0
    dw 0x00B8
    db 161                          ; eject
    db 0
    dw 0x00CD
    db 164                          ; play/pause
    db 0
    dw 0x00E2
    db 113                          ; mute
    db 0
    dw 0x00E9
    db 115                          ; volume up
    db 0
    dw 0x00EA
    db 114                          ; volume down
    db 0
    dw 0x0183
    db 226                          ; media player
    db 0
    dw 0x018A
    db 155                          ; mail
    db 0
    dw 0x0192
    db 140                          ; calculator
    db 0
    dw 0x0194
    db 144                          ; files
    db 0
    dw 0x0196
    db 150                          ; web browser
    db 0
    dw 0x019E
    db 152                          ; lock the screen
    db 0
    dw 0x0221
    db 217                          ; search
    db 0
    dw 0x0223
    db 172                          ; home
    db 0
    dw 0x0224
    db 158                          ; back
    db 0
    dw 0x0225
    db 159                          ; forward
    db 0
    dw 0x0226
    db 128                          ; stop (browser)
    db 0
    dw 0x0227
    db 173                          ; refresh
    db 0
    dw 0x022A
    db 156                          ; bookmarks
    db 0
hid_consumer_keys_end:

section .text

; -----------------------------------------------------------------------------
; hid_media_key — EDI = page << 16 | usage → EAX = keycode, or 0
; -----------------------------------------------------------------------------
global hid_media_key
hid_media_key:
    mov eax, edi
    shr eax, 16
    cmp eax, 0x0C
    je .consumer
    cmp eax, 0x01
    jne .none
    ; Generic Desktop, System Control: power down, sleep, wake up
    movzx eax, di
    cmp eax, 0x81
    je .power
    cmp eax, 0x82
    je .sleep
    cmp eax, 0x83
    jne .none
    mov eax, 143
    ret
.power:
    mov eax, 116
    ret
.sleep:
    mov eax, 142
    ret
.consumer:
    lea rcx, [rel hid_consumer_keys]
    lea rdx, [rel hid_consumer_keys_end]
.find:
    cmp rcx, rdx
    jae .none
    cmp [rcx], di
    je .found
    add rcx, 4
    jmp .find
.found:
    movzx eax, byte [rcx + 2]
    ret
.none:
    xor eax, eax
    ret

; -----------------------------------------------------------------------------
; hid_media_prepare
; Input:  RDI = hid_desc* (parsed), RSI = hid_media* to fill
; Output: EAX = fields kept
; -----------------------------------------------------------------------------
global hid_media_prepare
hid_media_prepare:
    push rbx
    push r12
    push r13
    push r14
    mov rbx, rdi
    mov r12, rsi
    ; from zero, keeping the device ID
    mov r14d, [r12 + hid_media.dev]
    mov rdi, r12
    mov ecx, hid_media_size
    xor eax, eax
    rep stosb
    mov [r12 + hid_media.dev], r14d
    mov eax, [rbx + hid_desc.uses_ids]
    mov [r12 + hid_media.uses_ids], eax
    xor r13d, r13d                      ; field
.field:
    cmp r13d, [rbx + hid_desc.field_count]
    jae .done
    cmp dword [r12 + hid_media.nfields], HID_MEDIA_FIELDS
    jae .done
    mov eax, r13d
    imul eax, eax, hid_field_size
    lea rsi, [rbx + hid_desc.fields + rax]
    inc r13d
    cmp byte [rsi + hid_field.kind], HID_INPUT
    jne .field
    test word [rsi + hid_field.flags], HID_F_CONST
    jnz .field
    mov eax, [rsi + hid_field.application]
    cmp eax, HID_APP_CONSUMER
    je .keep
    cmp eax, HID_APP_SYSTEM
    jne .field
.keep:
    ; its usages fit?
    movzx ecx, word [rsi + hid_field.usage_count]
    mov eax, [r12 + hid_media.nusages]
    add eax, ecx
    cmp eax, HID_MEDIA_USAGES
    ja .field
    ; the field, then its usages after the ones already kept
    mov eax, [r12 + hid_media.nfields]
    imul eax, eax, hid_field_size
    lea rdi, [r12 + hid_media.fields + rax]
    push rsi
    push rdi
    mov ecx, hid_field_size
    rep movsb
    pop rdi
    pop rsi
    movzx ecx, word [rsi + hid_field.usage_count]
    movzx edx, word [rsi + hid_field.usage_list]
    mov eax, [r12 + hid_media.nusages]
    mov [rdi + hid_field.usage_list], ax    ; now an index into media.usages
.usage:
    test ecx, ecx
    jz .kept
    mov r8d, [rbx + hid_desc.usages + rdx * 4]
    mov r9d, [r12 + hid_media.nusages]
    mov [r12 + hid_media.usages + r9 * 4], r8d
    inc dword [r12 + hid_media.nusages]
    inc edx
    dec ecx
    jmp .usage
.kept:
    inc dword [r12 + hid_media.nfields]
    jmp .field
.done:
    mov eax, [r12 + hid_media.nfields]
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

; hid_media_usage — the usage at index ECX of field RSI (media RBX); for a
; range, usage_min + index up to usage_max. EAX = usage, or 0 past the end
hid_media_usage:
    movzx eax, word [rsi + hid_field.usage_count]
    test eax, eax
    jz .range
    cmp ecx, eax
    jb .listed
    xor eax, eax
    ret
.listed:
    movzx eax, word [rsi + hid_field.usage_list]
    add eax, ecx
    mov eax, [rbx + hid_media.usages + rax * 4]
    ret
.range:
    mov eax, [rsi + hid_field.usage_min]
    add eax, ecx
    cmp eax, [rsi + hid_field.usage_max]
    jbe .out
    xor eax, eax
.out:
    ret

; -----------------------------------------------------------------------------
; hid_media_report
; Input:  RDI = hid_media*, RSI = report, EDX = its length
; -----------------------------------------------------------------------------
global hid_media_report
hid_media_report:
    push rbx
    push r12
    push r13
    push r14
    push r15
    push rbp
    sub rsp, 24                         ; the keys this report holds (16)
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    xor ebp, ebp                        ; report ID
    cmp dword [rbx + hid_media.uses_ids], 0
    je .payload
    test r13d, r13d
    jz .out
    movzx ebp, byte [r12]
    inc r12
    dec r13d
.payload:
    mov qword [rsp], 0
    mov qword [rsp + 8], 0
    xor r14d, r14d                      ; field
.field:
    cmp r14d, [rbx + hid_media.nfields]
    jae .compare
    mov eax, r14d
    imul eax, eax, hid_field_size
    lea r15, [rbx + hid_media.fields + rax]
    inc r14d
    movzx eax, byte [r15 + hid_field.report_id]
    cmp eax, ebp
    jne .field
    xor ecx, ecx                        ; element
.element:
    movzx eax, word [r15 + hid_field.count]
    cmp ecx, eax
    jae .field
    push rcx
    sub rsp, 8
    mov rdi, r12
    mov esi, r13d
    mov rdx, r15
    call hid_get
    add rsp, 8
    pop rcx
    test eax, eax
    jnz .out                            ; cut short: it changes nothing
    test word [r15 + hid_field.flags], HID_F_VARIABLE
    jz .array
    test rdx, rdx
    jz .next_element
    mov rsi, r15
    push rcx
    call hid_media_usage
    pop rcx
    jmp .have_usage
.array:
    movsxd rdx, edx
    movsxd rax, dword [r15 + hid_field.logical_min]
    sub rdx, rax
    js .next_element
    movsxd rax, dword [r15 + hid_field.logical_max]
    movsxd r8, dword [r15 + hid_field.logical_min]
    sub rax, r8
    cmp rdx, rax
    jg .next_element
    mov rsi, r15
    push rcx
    mov ecx, edx
    call hid_media_usage
    pop rcx
.have_usage:
    movzx edx, ax
    test edx, edx
    jz .next_element                    ; usage 0: nothing pressed
    push rcx
    mov edi, eax
    call hid_media_key
    pop rcx
    test eax, eax
    jnz .hold
    inc dword [rel hid_media_unknown]
    jmp .next_element
.hold:
    ; into this report's set, once
    xor edx, edx
.slot:
    cmp edx, 16
    jae .next_element
    cmp [rsp + rdx], al
    je .next_element
    cmp byte [rsp + rdx], 0
    je .put
    inc edx
    jmp .slot
.put:
    mov [rsp + rdx], al
.next_element:
    inc ecx
    jmp .element

.compare:
    ; let go: held from this report ID, not in it now
    xor r14d, r14d
.held:
    cmp r14d, HID_MEDIA_DOWN
    jae .press
    movzx eax, byte [rbx + hid_media.down_key + r14]
    test eax, eax
    jz .held_next
    movzx ecx, byte [rbx + hid_media.down_id + r14]
    cmp ecx, ebp
    jne .held_next
    xor edx, edx
.still:
    cmp edx, 16
    jae .up
    cmp [rsp + rdx], al
    je .held_next
    inc edx
    jmp .still
.up:
    mov byte [rbx + hid_media.down_key + r14], 0
    mov edi, INPUT_KEY
    mov esi, eax
    xor edx, edx
    mov ecx, [rbx + hid_media.dev]
    call input_post_safe
.held_next:
    inc r14d
    jmp .held
.press:
    ; pressed: in it now, not held
    xor r14d, r14d
.new:
    cmp r14d, 16
    jae .out
    movzx eax, byte [rsp + r14]
    inc r14d
    test eax, eax
    jz .new
    xor edx, edx
.down:
    cmp edx, HID_MEDIA_DOWN
    jae .free_slot
    cmp [rbx + hid_media.down_key + rdx], al
    je .new
    inc edx
    jmp .down
.free_slot:
    xor edx, edx
.find_free:
    cmp edx, HID_MEDIA_DOWN
    jae .new                            ; more than eight held: not counted
    cmp byte [rbx + hid_media.down_key + rdx], 0
    je .take
    inc edx
    jmp .find_free
.take:
    mov [rbx + hid_media.down_key + rdx], al
    mov [rbx + hid_media.down_id + rdx], bpl
    mov edi, INPUT_KEY
    mov esi, eax
    mov edx, 1
    mov ecx, [rbx + hid_media.dev]
    call input_post_safe
    jmp .new
.out:
    add rsp, 24
    pop rbp
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

%endif ; LIB_INPUT_HID_MEDIA_ASM
