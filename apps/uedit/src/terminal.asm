; Standalone native VT terminal session over caller-supplied callbacks.
; Resizable UTF-8 scalar viewport, 4-column tabs; one serialized session.
%include "inc/uedit.inc"
bits 64
default rel
section .bss
global uedit_active
uedit_active: resq 1
context: resb uedit_context_size
session_io: resq 1
session_label: resq 1
message: resq 1
quit_pending: resq 1
escape: resq 1
parameter: resq 1
report_stage: resq 1
report_rows: resq 1
reported_columns: resq 1
reported_rows: resq 1
cursor_row: resq 1
cursor_column: resq 1
columns: resq 1
rows: resq 1
body_rows: resq 1
body_columns: resq 1
mode: resq 1
query_length: resq 1
replace_length: resq 1
query: resb 256
replace_text: resb 256
pending_byte: resq 1
utf_bytes: resb 8
frame: resb 65536
decimal: resb 32
section .rodata
size_query: db 27,'[18t'
size_query_length: equ $-size_query
enter_screen: db 27,'[?1049h',27,'[2J',27,'[H',27,'[18t'
enter_size: equ $-enter_screen
leave_screen: db 27,'[?25h',27,'[?1049l'
leave_size: equ $-leave_screen
draw_begin: db 27,'[?25l',27,'[H',27,'[2K',0
draw_begin_size: equ $-draw_begin-1
csi: db 27,'[',0
row_column: db ';1H',27,'[2K',0
show_cursor: db 'H',27,'[?25h',0
log_row: db 27,'[24;1H',27,'[2K'
log_size: equ $-log_row
footer_hint: db 'Ctrl-S Save | Ctrl-Q Quit | ',0
footer_hint_size: equ $-footer_hint-1
title: db 'Uedit ',0
modified: db ' *',0
line_text: db '  Ln ',0
column_text: db ' Col ',0
size_text: db '  ',0
capacity_text: db '/4096',0
footer: db 27,'[24;1H',27,'[2K','Ctrl-S Save | Ctrl-Q Quit | ',0
ready: db 'Ready',0
saved: db 'Saved',0
save_failed: db 'Save failed; changes retained',0
full: db 'File limit: 4096 bytes',0
unsupported: db 'Invalid UTF-8/control key',0
search_prompt: db 'Find: ',0
replace_prompt: db 'Replace with: ',0
replace_options: db 'Replace: Ctrl-R one | Ctrl-A all | Ctrl-C cancel',0
found: db 'Found | Ctrl-N next',0
not_found: db 'Text not found',0
changed: db 'Replaced',0
undone: db 'Undo',0
redone: db 'Redo',0
selection_text: db 'Selection: Ctrl-B mark | Ctrl-C copy | Ctrl-X cut | Ctrl-V paste',0
reverse: db 27,'[7m',0
normal: db 27,'[0m',0
small_terminal: db 'Resize terminal (20x4 minimum)',0
confirm: db 'Unsaved changes! Ctrl-Q again discards',0
cancelled: db 'Quit cancelled',0
closed: db 'Uedit closed.',10
closed_size: equ $-closed
lost_input: db 'Uedit: input closed; unsaved changes were not saved.',10
lost_size: equ $-lost_input
section .text
extern uedit_load,uedit_key,uedit_locate,uedit_line_start,ue_page_rows
extern ue_decode,ue_width,ue_prev
extern ue_reset,ue_saved,ue_dirty,ue_action,ue_undo,ue_redo,ue_find,ue_change,ue_anchor
global uedit_run,uedit_redraw,uedit_log_begin
; (io*,initial bytes,length,label,new_file) -> 0 quit, 1 input failure, -1 bad text/io.
uedit_run:
 push rbx
 push r12
 push r13
 push r14
 push r15
 cmp qword [uedit_active],0
 jne .invalid
 test rcx,rcx
 jz .invalid
 test rdi,rdi
 jz .invalid
 cmp qword [rdi+uedit_io.read],0
 je .invalid
 cmp qword [rdi+uedit_io.write],0
 je .invalid
 cmp qword [rdi+uedit_io.save],0
 je .invalid
 mov r12,rdi
 mov r13,rcx
 mov r14,r8
 lea rdi,[context]
 call uedit_load
 test rax,rax
 js .invalid
 mov [session_io],r12
 mov [session_label],r13
 test r14,r14
 jz .loaded
 mov qword [context+uedit_context.dirty],1
.loaded:
 lea rdi,[context]
 mov rsi,r14
 call ue_reset
 mov qword [mode],0
 mov qword [pending_byte],-1
 mov qword [query_length],0
 mov qword [replace_length],0
 lea rax,[ready]
 mov [message],rax
 mov qword [quit_pending],0
 mov qword [escape],0
 mov qword [parameter],0
 mov qword [reported_columns],80
 mov qword [reported_rows],24
 mov qword [uedit_active],1
 lea rdi,[enter_screen]
 mov esi,enter_size
 call [r12+uedit_io.write]
.redraw:
 call uedit_redraw
.input:
 call read_key
 cmp rax,-2
 je .redraw
 test rax,rax
 js .input_closed
 cmp qword [mode],0
 jne .prompt_key
 cmp rax,17                    ; Ctrl-Q, twice if dirty
 je .quit
 cmp qword [quit_pending],0
 je .key
 mov qword [quit_pending],0
 lea rcx,[cancelled]
 mov [message],rcx
.key:
 cmp rax,19                    ; Ctrl-S
 je .save
 cmp rax,3
 jne .not_cancel
 cmp qword [ue_anchor],-1
 jne .edit
 jmp .redraw
.not_cancel:
 cmp rax,26
 je .undo
 cmp rax,25
 je .redo
 cmp rax,6
 je .search
 cmp rax,14
 je .next_match
 cmp rax,18
 je .replace
 cmp rax,2
 je .selection
 cmp rax,24
 je .selection
 cmp rax,22
 je .selection
 cmp rax,12                    ; Ctrl-L also requests UART terminal geometry
 je .refresh
 .edit:
 lea rdi,[context]
 mov rsi,rax
 call ue_action
 cmp rax,-2
 je .full
 test rax,rax
 js .unsupported
 cmp rax,1
 jne .redraw
 lea rax,[ready]
 mov [message],rax
 jmp .redraw
.full:
 lea rax,[full]
 mov [message],rax
 jmp .redraw
.unsupported:
 lea rax,[unsupported]
 mov [message],rax
 jmp .redraw

.refresh:
 lea rdi,[size_query]
 mov esi,size_query_length
 call [r12+uedit_io.write]
 jmp .redraw
.selection:
 lea rcx,[selection_text]
 mov [message],rcx
 jmp .edit
.undo:
 lea rdi,[context]
 call ue_undo
 lea rax,[undone]
 mov [message],rax
 jmp .redraw
.redo:
 lea rdi,[context]
 call ue_redo
 lea rax,[redone]
 mov [message],rax
 jmp .redraw
.search:
 mov qword [mode],1
 mov qword [query_length],0
 lea rax,[search_prompt]
 mov [message],rax
 jmp .redraw
.replace:
 cmp qword [query_length],0
 je .search
 mov qword [mode],2
 mov qword [replace_length],0
 lea rax,[replace_prompt]
 mov [message],rax
 jmp .redraw
.next_match:
 lea rdi,[context]
 mov rcx,[context+uedit_context.cursor]
 inc rcx
 jmp .find
.find_first:
 mov rcx,[context+uedit_context.cursor]
.find:
 lea rdi,[context]
 lea rsi,[query]
 mov rdx,[query_length]
 call ue_find
 lea rcx,[not_found]
 test rax,rax
 js .found_message
 mov [context+uedit_context.cursor],rax
 mov qword [context+uedit_context.goal],-1
 mov qword [ue_anchor],-1
 lea rcx,[found]
.found_message:
 mov [message],rcx
 jmp .redraw
.prompt_key:
 cmp eax,3
 je .prompt_cancel
 cmp qword [mode],3
 je .replace_choice
 cmp eax,10
 je .prompt_enter
 cmp eax,UE_BACKSPACE
 je .prompt_delete
 ; Encode the key in a temporary context so prompt input shares validation.
 mov r13,rax
 sub rsp,UE_CONTEXT_ALLOC
 mov rdi,rsp
 xor eax,eax
 mov ecx,uedit_context_size/8
 rep stosq
 mov rdi,rsp
 mov rsi,r13
 call uedit_key
 cmp rax,1
 jne .prompt_done
 mov rcx,[rsp+uedit_context.length]
 cmp qword [mode],1
 jne .replacement_buffer
 lea rdi,[query]
 lea rdx,[query_length]
 jmp .prompt_append
.replacement_buffer:
 lea rdi,[replace_text]
 lea rdx,[replace_length]
.prompt_append:
 mov rax,[rdx]
 add rax,rcx
 cmp rax,255
 ja .prompt_done
 add rdi,[rdx]
 mov [rdx],rax
 lea rsi,[rsp+uedit_context.data]
 rep movsb
.prompt_done:
 add rsp,UE_CONTEXT_ALLOC
 jmp .redraw
.prompt_delete:
 lea rdi,[query]
 lea r13,[query_length]
 cmp qword [mode],1
 je .prompt_previous
 lea rdi,[replace_text]
 lea r13,[replace_length]
.prompt_previous:
 mov rsi,[r13]
 call ue_prev
 mov [r13],rax
 jmp .redraw
.prompt_enter:
 cmp qword [mode],1
 jne .replacement_enter
 mov qword [mode],0
 jmp .find_first
.replacement_enter:
 mov qword [mode],3
 lea rax,[replace_options]
 mov [message],rax
 jmp .redraw
.replace_choice:
 xor r9d,r9d
 cmp eax,18
 je .do_replace
 cmp eax,UE_HOME
 jne .redraw
 mov r9d,1
.do_replace:
 lea rdi,[context]
 lea rsi,[query]
 mov rdx,[query_length]
 lea rcx,[replace_text]
 mov r8,[replace_length]
 call ue_change
 mov qword [mode],0
 cmp rax,-2
 je .full
 lea rcx,[not_found]
 test rax,rax
 jz .replace_message
 lea rcx,[changed]
.replace_message:
 mov [message],rcx
 jmp .redraw
.prompt_cancel:
 mov qword [mode],0
 lea rax,[cancelled]
 mov [message],rax
 jmp .redraw

.save:
 lea rdi,[context+uedit_context.data]
 mov rsi,[context+uedit_context.length]
 call [r12+uedit_io.save]
 test rax,rax
 jnz .save_failed
 lea rdi,[context]
 call ue_saved
 mov qword [context+uedit_context.dirty],0
 lea rax,[saved]
 mov [message],rax
 jmp .redraw
.save_failed:
 lea rax,[save_failed]
 mov [message],rax
 jmp .redraw
.quit:
 cmp qword [context+uedit_context.dirty],0
 je .quit_now
 cmp qword [quit_pending],1
 je .quit_now
 mov qword [quit_pending],1
 lea rax,[confirm]
 mov [message],rax
 jmp .redraw
.quit_now:
 xor ebx,ebx
 jmp .leave
.input_closed:
 mov ebx,1
.leave:
 mov qword [uedit_active],0
 lea rdi,[leave_screen]
 mov esi,leave_size
 call [r12+uedit_io.write]
 lea rdi,[closed]
 mov esi,closed_size
 test ebx,ebx
 jz .exit_message
 cmp qword [context+uedit_context.dirty],0
 je .exit_message
 lea rdi,[lost_input]
 mov esi,lost_size
.exit_message:
 call [r12+uedit_io.write]
 mov eax,ebx
 jmp .done
.invalid:
 mov rax,-1
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; Decode basic VT CSI/SS3. Unknown/modified sequences are swallowed as a unit.
read_key:
 push rbx
 push r13
 sub rsp,8
.read:
 mov rax,[pending_byte]
 cmp rax,-1
 je .callback
 mov qword [pending_byte],-1
 jmp .received
.callback:
 mov rax,[session_io]
 call [rax+uedit_io.read]
.received:
 test rax,rax
 js .done
 cmp eax,27
 je .escape
 cmp eax,32
 jb .control
 mov rbx,[escape]
 cmp ebx,1
 je .prefix
 cmp ebx,2
 jae .sequence
 cmp eax,127
 je .backspace
 cmp eax,128
 jae .utf8
 jmp .done
.utf8:
 mov [utf_bytes],al
 mov ebx,1
 cmp eax,0xc2
 jb .invalid_utf8
 mov r13d,2
 cmp eax,0xe0
 jb .utf_read
 mov r13d,3
 cmp eax,0xf0
 jb .utf_read
 mov r13d,4
 cmp eax,0xf4
 ja .invalid_utf8
.utf_read:
 mov rax,[session_io]
 call [rax+uedit_io.read]
 cmp rax,-2
 je .utf_read
 test rax,rax
 js .done
 cmp eax,0x80
 jb .pushback
 cmp eax,0xbf
 ja .pushback
 lea rcx,[utf_bytes]
 mov [rcx+rbx],al
 inc ebx
 cmp ebx,r13d
 jb .utf_read
 lea rdi,[utf_bytes]
 mov rsi,rbx
 call ue_decode
 test eax,eax
 js .invalid_done
 add eax,UE_UNICODE
 jmp .done
.pushback:
 mov [pending_byte],rax
.invalid_utf8:
.invalid_done:
 mov eax,0x1fffff
 jmp .done
.control:
 mov qword [escape],0
 cmp eax,13
 je .newline
 cmp eax,8
 je .backspace
 cmp eax,4
 je .delete
 cmp eax,1
 je .home
 cmp eax,5
 je .end
 jmp .done
.newline: mov eax,10
 jmp .done
.escape:
 mov qword [escape],1
 jmp .read
.prefix:
 mov qword [escape],0
 cmp eax,'['
 je .csi
 cmp eax,'O'
 je .ss3
 jmp .done
 .csi:
 mov qword [report_stage],0
 mov qword [escape],2
 mov qword [parameter],0
 jmp .read
.ss3:
 mov qword [report_stage],0
 mov qword [escape],3
 mov qword [parameter],0
 jmp .read
.sequence:
 cmp eax,'0'
 jb .final
 cmp eax,'9'
 ja .final
 cmp qword [parameter],-1
 je .read
 imul rcx,[parameter],10
 sub eax,'0'
 add rcx,rax
 cmp rcx,999
 jbe .parameter
 mov rcx,-1
.parameter:
 mov [parameter],rcx
 jmp .read
.final:
 cmp eax,0x40
 jb .modified
 cmp eax,0x7e
 ja .modified
 mov qword [escape],0
 mov rcx,[parameter]
 cmp rcx,-1
 je .read
 cmp eax,'t'
 je .size_report
 cmp qword [report_stage],0
 jne .read
 cmp eax,'~'
 je .tilde
 cmp rcx,1
 ja .read
 cmp eax,'A'
 je .up
 cmp eax,'B'
 je .down
 cmp eax,'C'
 je .right
 cmp eax,'D'
 je .left
 cmp eax,'H'
 je .home
 cmp eax,'F'
 je .end
 jmp .read
.size_report:
 cmp qword [report_stage],2
 jne .read
 test rcx,rcx
 jz .read
 mov rdx,[report_rows]
 test rdx,rdx
 jz .read
 mov [reported_columns],rcx
 mov [reported_rows],rdx
 mov rax,-2
 jmp .done
.modified:
 cmp eax,';'
 jne .reject_sequence
 cmp qword [report_stage],0
 jne .second_size
 cmp qword [parameter],8
 jne .reject_sequence
 mov qword [report_stage],1
 mov qword [parameter],0
 jmp .read
.second_size:
 cmp qword [report_stage],1
 jne .reject_sequence
 mov rcx,[parameter]
 mov [report_rows],rcx
 mov qword [report_stage],2
 mov qword [parameter],0
 jmp .read
.reject_sequence:
 mov qword [parameter],-1
 jmp .read
.tilde:
 cmp ecx,3
 je .delete
 cmp ecx,1
 je .home
 cmp ecx,7
 je .home
 cmp ecx,4
 je .end
 cmp ecx,8
 je .end
 cmp ecx,5
 je .pageup
 cmp ecx,6
 je .pagedown
 jmp .read
.up: mov eax,UE_UP
 jmp .done
.down: mov eax,UE_DOWN
 jmp .done
.left: mov eax,UE_LEFT
 jmp .done
.right: mov eax,UE_RIGHT
 jmp .done
.home: mov eax,UE_HOME
 jmp .done
.end: mov eax,UE_END
 jmp .done
.delete: mov eax,UE_DELETE
 jmp .done
.backspace: mov eax,UE_BACKSPACE
 jmp .done
.pageup: mov eax,UE_PAGEUP
 jmp .done
.pagedown: mov eax,UE_PAGEDOWN
.done:
 add rsp,8
 pop r13
 pop rbx
 ret
; Kernel log pairing uses the last row temporarily. log_end redraws all rows
; and the cursor after the complete diagnostic, even if it scrolled the screen.
uedit_log_begin:
 cmp qword [uedit_active],0
 je .inactive
 push r14
 push r15
 sub rsp,8
 lea r14,[frame+65536]
 lea r15,[frame]
 lea rdi,[csi]
 call emit_string
 mov rax,[rows]
 call emit_number
 lea rdi,[row_column]
 call emit_string
 lea rdi,[frame]
 mov rsi,r15
 sub rsi,rdi
 mov rax,[session_io]
 call [rax+uedit_io.write]
 add rsp,8
 pop r15
 pop r14
 ret
.inactive: ret
; Query size on every redraw, including resize events and diagnostic restoration.
uedit_redraw:
 cmp qword [uedit_active],1
 jne .inactive
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rax,[reported_columns]
 mov [columns],rax
 mov rax,[reported_rows]
 mov [rows],rax
 mov rax,[session_io]
 mov rax,[rax+uedit_io.size]
 test rax,rax
 jz .sized
 lea rdi,[columns]
 lea rsi,[rows]
 call rax
.sized:
 ; Bounds keep output/work finite even for a malicious size callback.
 mov rax,[columns]
 mov ecx,240
 cmp rax,rcx
 cmova rax,rcx
 test rax,rax
 jnz .columns_valid
 mov eax,80
.columns_valid:
 mov [columns],rax
 sub rax,2
 mov [body_columns],rax
 mov rax,[rows]
 mov ecx,100
 cmp rax,rcx
 cmova rax,rcx
 test rax,rax
 jnz .rows_valid
 mov eax,24
.rows_valid:
 mov [rows],rax
 sub rax,2
 mov [body_rows],rax
 mov [ue_page_rows],rax
 cmp qword [columns],20
 jb .small
 cmp qword [rows],4
 jb .small
 lea r12,[context]
 mov rdi,r12
 call uedit_locate
 mov [cursor_row],rax
 mov [cursor_column],rdx
 cmp rax,[r12+uedit_context.top]
 jae .bottom
 mov [r12+uedit_context.top],rax
.bottom:
 mov rcx,[r12+uedit_context.top]
 add rcx,[body_rows]
 cmp rax,rcx
 jb .horizontal
 sub rax,[body_rows]
 inc rax
 mov [r12+uedit_context.top],rax
.horizontal:
 cmp rdx,[r12+uedit_context.left]
 jae .right_edge
 xor ecx,ecx
 cmp rdx,[body_columns]
 cmovae rcx,rdx
 mov [r12+uedit_context.left],rcx
.right_edge:
 mov rcx,[r12+uedit_context.left]
 add rcx,[body_columns]
 cmp rdx,rcx
 jb .frame
 sub rdx,[body_columns]
 inc rdx
 mov [r12+uedit_context.left],rdx
.frame:
 lea r15,[frame]
 lea r14,[frame+65536]
 lea rdi,[draw_begin]
 call emit_string
 lea rdi,[title]
 call emit_string
 mov rdi,[session_label]
 mov ecx,8
.label:
 mov al,[rdi]
 test al,al
 jz .label_done
 cmp al,32
 jb .sanitize
 cmp al,126
 jbe .label_byte
.sanitize: mov al,'?'
.label_byte:
 call emit_char
 inc rdi
 dec ecx
 jnz .label
.label_done:
 cmp qword [r12+uedit_context.dirty],0
 je .position
 lea rdi,[modified]
 call emit_string
.position:
 lea rdi,[line_text]
 call emit_string
 mov rax,[cursor_row]
 inc rax
 call emit_number
 lea rdi,[column_text]
 call emit_string
 mov rax,[cursor_column]
 inc rax
 call emit_number
 ; Clip the ASCII title before the next row CSI; no terminal auto-wrap.
 lea rax,[frame]
 add rax,draw_begin_size
 add rax,[columns]
 dec rax
 cmp r15,rax
 cmova r15,rax
 ; Size and filename are intentionally short so small terminals do not wrap.
 xor ebx,ebx
.row:
 lea rdi,[csi]
 call emit_string
 lea rax,[rbx+2]
 call emit_number
 lea rdi,[row_column]
 call emit_string
 mov rsi,[r12+uedit_context.top]
 add rsi,rbx
 mov rdi,r12
 call uedit_line_start
 mov r13,rax
 xor r10d,r10d
.text:
 cmp r13,[r12+uedit_context.length]
 jae .next_row
 lea rdi,[r12+uedit_context.data+r13]
 mov rsi,[r12+uedit_context.length]
 sub rsi,r13
 call ue_decode
 cmp eax,10
 je .next_row
 mov r11,rdx
 cmp eax,9
 je .tab
 call ue_width
 mov r9,rax
 mov rdx,r10
 add rdx,r9
 cmp r10,[r12+uedit_context.left]
 jb .clipped
 mov rcx,[r12+uedit_context.left]
 add rcx,[body_columns]
 cmp rdx,rcx
 ja .clipped
 ; Do not emit a detached combining mark at the viewport's left boundary.
 test r9,r9
 jnz .visible
 cmp r10,[r12+uedit_context.left]
 je .advance
.visible:
 call highlight
 lea rdi,[r12+uedit_context.data+r13]
 mov rcx,r11
.bytes:
 mov al,[rdi]
 call emit_char
 inc rdi
 dec rcx
 jnz .bytes
 call unhighlight
 jmp .advance
.clipped:
 mov rcx,r9
.spaces:
 test rcx,rcx
 jz .advance
 mov rdx,r10
 add rdx,r9
 sub rdx,rcx
 mov al,' '
 call visible_char
 dec rcx
 jmp .spaces
.advance:
 add r10,r9
 add r13,r11
 jmp .width
.tab:
 call highlight
 lea r9,[r10+4]
 and r9,-4
.tab_space:
 mov al,' '
 mov rdx,r10
 call visible_char
 inc r10
 cmp r10,r9
 jb .tab_space
 call unhighlight
 add r13,r11
.width:
 mov rax,[r12+uedit_context.left]
 add rax,[body_columns]
 cmp r10,rax
 jb .text
.next_row:
 inc ebx
 cmp rbx,[body_rows]
 jb .row
 lea rdi,[csi]
 call emit_string
 mov rax,[rows]
 call emit_number
 lea rdi,[row_column]
 call emit_string
 ; Clip the footer by cells; prompts are validated UTF-8 and own their bytes.
 mov rdi,[message]
 mov rcx,[columns]
 dec rcx
 cmp qword [mode],0
 jne .footer_message
 ; Preserve familiar hints on terminals wide enough for them.
 cmp rcx,77
 jb .footer_message
 lea rdi,[footer_hint]
 call emit_string
 sub rcx,footer_hint_size
 mov rdi,[message]
.footer_message:
 call clipped_string
 cmp qword [mode],1
 je .query
 cmp qword [mode],2
 jne .cursor
 lea rsi,[replace_text]
 mov rdx,[replace_length]
 jmp .prompt_text
.query:
 lea rsi,[query]
 mov rdx,[query_length]
.prompt_text:
 call clipped_bytes
.cursor:
 lea rdi,[csi]
 call emit_string
 mov rax,[cursor_row]
 sub rax,[r12+uedit_context.top]
 add rax,2
 call emit_number
 mov al,';'
 call emit_char
 mov rax,[cursor_column]
 sub rax,[r12+uedit_context.left]
 inc rax
 call emit_number
 lea rdi,[show_cursor]
 call emit_string
 .write_frame:
 lea rdi,[frame]
 mov rsi,r15
 sub rsi,rdi
 mov rax,[session_io]
 call [rax+uedit_io.write]
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
.small:
 lea r15,[frame]
 lea r14,[frame+65536]
 lea rdi,[draw_begin]
 call emit_string
 lea rdi,[small_terminal]
 mov rcx,[columns]
 dec rcx
 call clipped_string
 lea rdi,[csi]
 call emit_string
 mov al,'H'
 call emit_char
 lea rdi,[show_cursor]
 ; show_cursor begins H, already emitted above; emit only its visibility suffix.
 inc rdi
 call emit_string
 jmp .write_frame
.inactive: ret
; Highlight a selected scalar/tab. Helpers keep document scan registers intact.
highlight:
 xor r8d,r8d
 mov rax,[ue_anchor]
 cmp rax,-1
 je .done
 mov rcx,[context+uedit_context.cursor]
 cmp rax,rcx
 jbe .range
 xchg rax,rcx
.range:
 cmp r13,rax
 jb .done
 cmp r13,rcx
 jae .done
 mov r8d,1
 lea rdi,[reverse]
 jmp emit_string
.done: ret
unhighlight:
 test r8d,r8d
 jz .done
 lea rdi,[normal]
 jmp emit_string
.done: ret
clipped_string:
 push rsi
 push rdx
 sub rsp,8
 mov rsi,rdi
 xor edx,edx
.length:
 cmp byte [rsi+rdx],0
 je .emit
 inc rdx
 jmp .length
.emit:
 call clipped_bytes
 add rsp,8
 pop rdx
 pop rsi
 ret
; (rsi UTF-8,rdx bytes,rcx available cells), returns remaining cells in rcx.
clipped_bytes:
 push rbx
 push r12
 push r13
 mov rbx,rsi
 mov r12,rdx
 mov r13,rcx
.loop:
 test r12,r12
 jz .done
 mov rdi,rbx
 mov rsi,r12
 call ue_decode
 cmp eax,9
 je .prompt_tab
 sub rsp,16
 mov [rsp],rdx
 call ue_width
 cmp rax,r13
 mov rdx,[rsp]
 lea rsp,[rsp+16]
 ja .done
 sub r13,rax
 mov rcx,rdx
.emit:
 mov al,[rbx]
 call emit_char
 inc rbx
 dec r12
 dec rcx
 jnz .emit
 jmp .loop
.prompt_tab:
 test r13,r13
 jz .done
 dec r13
 mov al,' '
 call emit_char
 inc rbx
 dec r12
 jmp .loop
.done:
 mov rcx,r13
 pop r13
 pop r12
 pop rbx
 ret
; Helpers preserve r12..r15, and emit_char preserves all registers.
emit_char:
 cmp r15,r14
 jae .full
 mov [r15],al
 inc r15
.full: ret
emit_string:
 sub rsp,8
.next:
 mov al,[rdi]
 test al,al
 jz .done
 call emit_char
 inc rdi
 jmp .next
.done:
 add rsp,8
 ret
emit_number:
 sub rsp,8
 lea rsi,[decimal+32]
 mov r8,rsi
 mov ecx,10
.digit:
 xor edx,edx
 div rcx
 add dl,'0'
 dec rsi
 mov [rsi],dl
 test rax,rax
 jnz .digit
.emit:
 mov al,[rsi]
 call emit_char
 inc rsi
 cmp rsi,r8
 jb .emit
 add rsp,8
 ret
visible_char:
 cmp rdx,[r12+uedit_context.left]
 jb .hidden
 push rcx
 mov rcx,[r12+uedit_context.left]
 add rcx,[body_columns]
 cmp rdx,rcx
 pop rcx
 jae .hidden
 jmp emit_char
.hidden: ret
section .note.GNU-stack noalloc noexec nowrite progbits
