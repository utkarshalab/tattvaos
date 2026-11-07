; ============================================================================
; Clipboard — Copy and Paste (cw_clipboard)
; ============================================================================
; Two selections, 0 the clipboard and 1 the primary selection, each offered
; by one owner in up to CLIP_TYPES types (inc/struct_offsets.inc). Nothing is
; copied until a paste: clipboard_receive gives it a serial and asks the
; owner (send); the owner's data requests are passed on to the one pasting as
; data events, CLIP_CHUNK bytes at a time, until done, or cancelled past
; CLIP_MAX or when the owner goes. Only the client with the keyboard, or a
; trusted one, offers or pastes, so a client in the background cannot read
; what another copied. The client with the keyboard hears what is offered
; when it gets the keyboard and whenever the offer changes.
;
; The server itself can hold data (clipboard_set, for a remote viewer's
; text): its owner is 0, and a paste is answered at once from the copy in
; ClipOffer.held.
;
; Selection CLIP_DRAG is a drag's (data/dnd.asm): dnd_start offers it, not
; offer; nobody is told of it when the keyboard moves; the client it was
; dropped on may paste it, keyboard or not.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/caps.inc"
%include "inc/cwp.inc"
%include "inc/cwp_ops.inc"
%include "inc/struct_offsets.inc"

extern arena_alloc
extern sync_event

section .text

; ---------------------------------------------------------------------------
; clipboard_init
;   IN:  rdi = server*, rsi = arena
;   OUT: rax = 0, -ENOMEM
; ---------------------------------------------------------------------------
global clipboard_init
clipboard_init:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov rdi, r12
    mov esi, ClipboardState_size
    call arena_alloc
    test rax, rax
    jz .oom
    mov r13, rax
    mov rdi, rax
    xor eax, eax
    mov ecx, ClipboardState_size
    rep stosb
    mov dword [r13 + ClipboardState.next_serial], 1
%assign s 0
%rep CLIP_DRAG                          ; room for the server's own copy
    mov rdi, r12
    mov esi, CLIP_MAX
    call arena_alloc
    test rax, rax
    jz .oom
    mov [r13 + ClipboardState.offers + s * ClipOffer_size + ClipOffer.held], rax
%assign s s + 1
%endrep
    mov [rbx + Server.clipboard], r13
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13
.oom:
    mov rax, -(ENOMEM)
    jmp .out

; ---------------------------------------------------------------------------
; clipboard_offer
;   A client offers a selection's data: offer(selection, count, types)
;   IN:  rdi = server*, rsi = client*, rdx = the payload (136 bytes)
;   OUT: rax = 0, -EINVAL, -EPERM without the keyboard
; ---------------------------------------------------------------------------
global clipboard_offer
clipboard_offer:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rax, -(EINVAL)
    cmp dword [r13], CLIP_DRAG          ; a drag's is dnd_start's to offer
    jae .out
    cmp dword [r13 + 4], CLIP_TYPES
    ja .out
    mov rdi, rbx
    mov rsi, r12
    mov edx, [r13]
    call may_use
    mov rcx, rax
    mov rax, -(EPERM)
    test ecx, ecx
    jz .out
    mov eax, [r13]
    call offer_of
    mov [rax + ClipOffer.owner], r12
    mov ecx, [r13 + 4]
    mov [rax + ClipOffer.count], ecx
    mov dword [rax + ClipOffer.held_len], 0
    lea rdi, [rax + ClipOffer.types]
    lea rsi, [r13 + 8]
    mov ecx, CLIP_TYPES * CLIP_TYPE_LEN
    rep movsb
    call end_types
    mov rdi, rbx
    mov esi, [r13]
    call tell_focused
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; clipboard_set
;   The server's own data on the clipboard (a remote viewer's text): any
;   owner's offer goes
;   IN:  rdi = server*, rsi = (unused), rdx = type, rcx = its length,
;        r8 = data, r9 = its length
;   OUT: rax = 0, -EINVAL, -ECLIP_SIZE past CLIP_MAX
; ---------------------------------------------------------------------------
global clipboard_set
clipboard_set:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rdx
    mov r13, rcx
    mov r14, r8
    mov r15, r9
    mov rax, -(EINVAL)
    mov rcx, [rbx + Server.clipboard]
    test rcx, rcx
    jz .out
    test r13, r13
    jz .out
    cmp r13, CLIP_TYPE_LEN - 1
    ja .out
    mov rax, -(ECLIP_SIZE)
    cmp r15, CLIP_MAX
    ja .out
    xor eax, eax                        ; the clipboard
    call offer_of
    mov qword [rax + ClipOffer.owner], 0
    mov dword [rax + ClipOffer.count], 1
    mov [rax + ClipOffer.held_len], r15d
    push rax
    push rax                            ; 16-byte aligned
    lea rdi, [rax + ClipOffer.types]    ; its one type
    xor eax, eax
    mov ecx, CLIP_TYPES * CLIP_TYPE_LEN
    rep stosb
    mov rax, [rsp]
    lea rdi, [rax + ClipOffer.types]
    mov rsi, r12
    mov rcx, r13
    rep movsb
    mov rax, [rsp]
    mov rdi, [rax + ClipOffer.held]     ; and its data
    mov rsi, r14
    mov rcx, r15
    rep movsb
    pop rax
    pop rax
    mov rdi, rbx
    xor esi, esi
    call tell_focused
    xor eax, eax
.out:
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; clipboard_receive
;   A paste: receive(selection, type)
;   IN:  rdi = server*, rsi = client*, rdx = the payload (36 bytes)
;   OUT: rax = the paste's serial, -EINVAL, -EPERM without the keyboard,
;        -ENOENT with nothing offered, -ECLIP_MIME for a type not offered,
;        -EBUSY with too many under way; edx = 1 if the server holds the
;        data (clipboard_send_held sends it, after the serial is answered)
; ---------------------------------------------------------------------------
global clipboard_receive
clipboard_receive:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rax, -(EINVAL)
    cmp dword [r13], CLIP_SELECTIONS
    jae .out
    mov rdi, rbx
    mov rsi, r12
    mov edx, [r13]
    call may_use
    mov rcx, rax
    mov rax, -(EPERM)
    test ecx, ecx
    jz .out
    mov eax, [r13]
    call offer_of
    mov r14, rax
    mov rax, -(ENOENT)
    cmp dword [r14 + ClipOffer.count], 0
    je .out
    mov rdi, r14                        ; a type offered?
    lea rsi, [r13 + 4]
    call type_offered
    test eax, eax
    jz .no_type
    mov rax, [rbx + Server.clipboard]   ; its serial, never 0
    mov ecx, [rax + ClipboardState.next_serial]
    lea edx, [rcx + 1]
    test edx, edx
    jnz .serial
    mov edx, 1
.serial:
    mov [rax + ClipboardState.next_serial], edx
    mov [rsp - 8], ecx                  ; (red zone: kept across no call)
    cmp qword [r14 + ClipOffer.owner], 0
    je .held
    lea rdi, [rax + ClipboardState.transfers]   ; a free slot
    mov edx, CLIP_TRANSFERS
.slot:
    cmp dword [rdi + ClipTransfer.serial], 0
    je .found
    add rdi, ClipTransfer_size
    dec edx
    jnz .slot
    mov rax, -(EBUSY)
    jmp .out
.found:
    mov ecx, [rsp - 8]
    mov [rdi + ClipTransfer.serial], ecx
    mov dword [rdi + ClipTransfer.sent], 0
    mov [rdi + ClipTransfer.receiver], r12
    mov rax, [r14 + ClipOffer.owner]
    mov [rdi + ClipTransfer.owner], rax
    sub rsp, 48                         ; send(serial, type) to the owner
    mov [rsp], ecx
    lea rdi, [rsp + 4]
    lea rsi, [r13 + 4]
    mov ecx, CLIP_TYPE_LEN
    rep movsb
    mov byte [rsp + 4 + CLIP_TYPE_LEN - 1], 0
    mov rdi, [r14 + ClipOffer.owner]
    mov esi, CWP_OBJ_CLIPBOARD
    mov edx, CLIPBOARD_EV_SEND
    mov rcx, rsp
    mov r8d, 4 + CLIP_TYPE_LEN
    call sync_event
    mov eax, [rsp]
    add rsp, 48
    xor edx, edx
    jmp .out
.held:
    mov eax, [rsp - 8]
    mov edx, 1
    jmp .out
.no_type:
    mov rax, -(ECLIP_MIME)
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; clipboard_send_held
;   The server's own data for a paste, as data events, the last done
;   IN:  rdi = server*, rsi = the client pasting, edx = selection,
;        ecx = the paste's serial
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global clipboard_send_held
clipboard_send_held:
    PROLOGUE_SAVE rbx, r12, r13, r14, r15
    sub rsp, 12 + CLIP_CHUNK + 4        ; an event; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    mov r13d, ecx
    mov eax, edx
    call offer_of
    mov r14, [rax + ClipOffer.held]
    mov r15d, [rax + ClipOffer.held_len]
.chunk:
    mov [rsp], r13d
    mov ecx, r15d
    cmp ecx, CLIP_CHUNK
    jbe .last
    mov ecx, CLIP_CHUNK
    mov dword [rsp + 4], 0
    jmp .sized
.last:
    mov dword [rsp + 4], 1
.sized:
    mov [rsp + 8], ecx
    sub r15d, ecx
    lea rdi, [rsp + 12]
    mov rsi, r14
    add r14, rcx
    mov edx, ecx
    rep movsb
    mov rdi, r12
    mov esi, CWP_OBJ_CLIPBOARD
    mov ecx, edx
    mov edx, CLIPBOARD_EV_DATA
    lea r8d, [rcx + 12]
    mov rcx, rsp
    call sync_event
    cmp dword [rsp + 4], 0
    je .chunk
    xor eax, eax
    add rsp, 12 + CLIP_CHUNK + 4
    EPILOGUE_RESTORE rbx, r12, r13, r14, r15

; ---------------------------------------------------------------------------
; clipboard_data
;   The owner's data for a paste: data(serial, done, length, bytes), passed
;   on; past CLIP_MAX in all the paste is cancelled
;   IN:  rdi = server*, rsi = client*, rdx = the payload, ecx = its length
;   OUT: rax = 0, -EINVAL for a bad length, -ENOENT for a paste not its own
; ---------------------------------------------------------------------------
global clipboard_data
clipboard_data:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    mov r13, rdx
    mov rax, -(EINVAL)
    mov r8d, [r13 + 8]
    cmp r8d, CLIP_CHUNK
    ja .out
    lea r9d, [r8 + 12]
    cmp ecx, r9d
    jb .out
    mov rax, [rbx + Server.clipboard]   ; the paste, the client's to answer
    lea r14, [rax + ClipboardState.transfers]
    mov edx, CLIP_TRANSFERS
    mov ecx, [r13]
.find:
    test ecx, ecx
    jz .none
    cmp [r14 + ClipTransfer.serial], ecx
    jne .next
    cmp [r14 + ClipTransfer.owner], r12
    je .found
.next:
    add r14, ClipTransfer_size
    dec edx
    jnz .find
.none:
    mov rax, -(ENOENT)
    jmp .out
.found:
    add [r14 + ClipTransfer.sent], r8d
    cmp dword [r14 + ClipTransfer.sent], CLIP_MAX
    ja .too_much
    mov rdi, [r14 + ClipTransfer.receiver]
    mov esi, CWP_OBJ_CLIPBOARD
    mov edx, CLIPBOARD_EV_DATA
    mov rcx, r13
    lea r8d, [r8 + 12]
    call sync_event
    cmp dword [r13 + 4], 0
    je .kept
    mov dword [r14 + ClipTransfer.serial], 0    ; done
.kept:
    xor eax, eax
    jmp .out
.too_much:
    mov rdi, r14
    call cancel
    xor eax, eax
.out:
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; clipboard_focus_changed
;   A client has the keyboard now: what each selection offers, if anything
;   IN:  rdi = server*, rsi = client* (0: none)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global clipboard_focus_changed
clipboard_focus_changed:
    PROLOGUE_SAVE rbx, r12, r13
    sub rsp, 8                          ; 16-byte aligned
    mov rbx, rdi
    mov r12, rsi
    test r12, r12
    jz .done
    cmp qword [rbx + Server.clipboard], 0
    je .done
    xor r13d, r13d
.selection:
    mov eax, r13d
    call offer_of
    cmp dword [rax + ClipOffer.count], 0
    je .next
    mov rdi, r12
    mov esi, r13d
    call tell
.next:
    inc r13d
    cmp r13d, CLIP_DRAG                 ; not a drag's
    jb .selection
.done:
    xor eax, eax
    add rsp, 8
    EPILOGUE_RESTORE rbx, r12, r13

; ---------------------------------------------------------------------------
; clipboard_client_gone
;   A client going: what it offered goes (the one with the keyboard told),
;   its pastes end, and pastes waiting on it are cancelled
;   IN:  rdi = server*, rsi = client*
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global clipboard_client_gone
clipboard_client_gone:
    PROLOGUE_SAVE rbx, r12, r13, r14
    mov rbx, rdi
    mov r12, rsi
    cmp qword [rbx + Server.clipboard], 0
    je .done
    xor r13d, r13d
.selection:
    mov eax, r13d
    call offer_of
    cmp [rax + ClipOffer.owner], r12
    jne .next_selection
    mov qword [rax + ClipOffer.owner], 0
    mov dword [rax + ClipOffer.count], 0
    cmp r13d, CLIP_DRAG                 ; a drag's: nobody to tell
    je .next_selection
    mov rdi, rbx
    mov esi, r13d
    call tell_focused
.next_selection:
    inc r13d
    cmp r13d, CLIP_SELECTIONS
    jb .selection
    mov rax, [rbx + Server.clipboard]
    cmp [rax + ClipboardState.drop_target], r12
    jne .transfers
    mov qword [rax + ClipboardState.drop_target], 0
.transfers:
    lea r14, [rax + ClipboardState.transfers]
    mov r13d, CLIP_TRANSFERS
.transfer:
    cmp dword [r14 + ClipTransfer.serial], 0
    je .next_transfer
    cmp [r14 + ClipTransfer.receiver], r12
    jne .owner
    mov dword [r14 + ClipTransfer.serial], 0    ; nobody to hear it
    jmp .next_transfer
.owner:
    cmp [r14 + ClipTransfer.owner], r12
    jne .next_transfer
    mov rdi, r14
    call cancel
.next_transfer:
    add r14, ClipTransfer_size
    dec r13d
    jnz .transfer
.done:
    xor eax, eax
    EPILOGUE_RESTORE rbx, r12, r13, r14

; ---------------------------------------------------------------------------
; Local
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; clipboard_take
;   A selection offered by a client, no questions asked (a drag's, from
;   dnd_start): the types, 32 bytes each, ended within them
;   IN:  rdi = server*, rsi = client*, edx = selection, ecx = how many,
;        r8 = the types (CLIP_TYPES x CLIP_TYPE_LEN)
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global clipboard_take
clipboard_take:
    push rbx
    mov rbx, rdi
    mov eax, edx
    call offer_of
    mov [rax + ClipOffer.owner], rsi
    mov [rax + ClipOffer.count], ecx
    mov dword [rax + ClipOffer.held_len], 0
    lea rdi, [rax + ClipOffer.types]
    mov rsi, r8
    mov ecx, CLIP_TYPES * CLIP_TYPE_LEN
    rep movsb
    call end_types
    xor eax, eax
    pop rbx
    ret

; ---------------------------------------------------------------------------
; clipboard_tell
;   What a selection offers, to one client (a drop target, on enter)
;   IN:  rdi = server*, rsi = client*, edx = selection
;   OUT: rax = 0
; ---------------------------------------------------------------------------
global clipboard_tell
clipboard_tell:
    push rbx
    mov rbx, rdi
    mov rdi, rsi
    mov esi, edx
    call tell
    xor eax, eax
    pop rbx
    ret

; rbx = server, eax = selection -> rax = its ClipOffer; rdi, rsi kept
offer_of:
    imul eax, eax, ClipOffer_size
    add rax, [rbx + Server.clipboard]
    add rax, ClipboardState.offers
    ret

; rax = ClipOffer: each type ends in a NUL within its 32 bytes
end_types:
%assign t 0
%rep CLIP_TYPES
    mov byte [rax + ClipOffer.types + t * CLIP_TYPE_LEN + CLIP_TYPE_LEN - 1], 0
%assign t t + 1
%endrep
    ret

; rdi = server, rsi = client, edx = selection -> eax = 1 if it may offer or
; paste: it has the keyboard, or it is trusted, or (a drag's) it was dropped
; on
may_use:
    mov eax, 1
    cmp qword [rsi + Client.trust_profile], TRUST_TRUSTED
    je .out
    cmp edx, CLIP_DRAG
    jne .keyboard
    mov rcx, [rdi + Server.clipboard]
    cmp [rcx + ClipboardState.drop_target], rsi
    je .out
.keyboard:
    xor eax, eax
    mov rcx, [rdi + Server.input_seat]
    test rcx, rcx
    jz .out
    mov rcx, [rcx + InputSeat.keyboard_focus]
    test rcx, rcx
    jz .out
    cmp [rcx + Surface.client], rsi
    sete al
.out:
    ret

; rdi = ClipOffer, rsi = a type (32 bytes, NUL-terminated within them) ->
; eax = 1 if it is one offered
type_offered:
    xor r8d, r8d                        ; which one
.type:
    cmp r8d, [rdi + ClipOffer.count]
    jae .no
    mov eax, r8d
    imul eax, eax, CLIP_TYPE_LEN
    lea r9, [rdi + ClipOffer.types + rax]
    xor ecx, ecx
.char:
    mov al, [rsi + rcx]
    cmp al, [r9 + rcx]
    jne .other
    test al, al
    jz .yes
    inc ecx
    cmp ecx, CLIP_TYPE_LEN
    jb .char
.yes:
    mov eax, 1
    ret
.other:
    inc r8d
    jmp .type
.no:
    xor eax, eax
    ret

; rdi = server, esi = selection: what it offers, to the client with the
; keyboard, if there is one
tell_focused:
    mov rax, [rdi + Server.input_seat]
    test rax, rax
    jz .none
    mov rax, [rax + InputSeat.keyboard_focus]
    test rax, rax
    jz .none
    push rbx                            ; 16-byte aligned
    mov rbx, rdi
    mov rdi, [rax + Surface.client]
    call tell
    pop rbx
.none:
    ret

; rbx = server, rdi = client, esi = selection: offered(selection, count,
; types) to it
tell:
    sub rsp, 8 + CLIP_TYPES * CLIP_TYPE_LEN + 16 ; the event; aligned
    test rdi, rdi
    jz .out
    push rdi
    mov eax, esi
    mov [rsp + 8], esi
    call offer_of
    mov ecx, [rax + ClipOffer.count]
    mov [rsp + 12], ecx
    lea rsi, [rax + ClipOffer.types]
    lea rdi, [rsp + 16]
    mov ecx, CLIP_TYPES * CLIP_TYPE_LEN
    rep movsb
    pop rdi
    mov esi, CWP_OBJ_CLIPBOARD
    mov edx, CLIPBOARD_EV_OFFERED
    mov rcx, rsp
    mov r8d, 8 + CLIP_TYPES * CLIP_TYPE_LEN
    call sync_event
.out:
    add rsp, 8 + CLIP_TYPES * CLIP_TYPE_LEN + 16
    ret

; rdi = ClipTransfer: cancelled(serial) to the one pasting, the slot freed
cancel:
    sub rsp, 24
    mov eax, [rdi + ClipTransfer.serial]
    mov [rsp], eax
    mov dword [rdi + ClipTransfer.serial], 0
    mov rdi, [rdi + ClipTransfer.receiver]
    mov esi, CWP_OBJ_CLIPBOARD
    mov edx, CLIPBOARD_EV_CANCELLED
    mov rcx, rsp
    mov r8d, 4
    call sync_event
    add rsp, 24
    ret

section .data
global clipboard_version
clipboard_version: dq 0x020000
