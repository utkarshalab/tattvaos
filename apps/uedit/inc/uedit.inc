%ifndef UEDIT_INC
%define UEDIT_INC
%define UE_CAPACITY 4096
%define UE_ROWS 22
%define UE_COLUMNS 78
struc uedit_context
 .length: resq 1
 .cursor: resq 1
 .top: resq 1
 .left: resq 1
 .goal: resq 1
 .crlf: resq 1
 .dirty: resq 1
 .data: resb UE_CAPACITY
endstruc
%define UE_CONTEXT_ALLOC ((uedit_context_size+15)&~15)
%define UE_LEFT 256
%define UE_RIGHT 257
%define UE_UP 258
%define UE_DOWN 259
%define UE_HOME 260
%define UE_END 261
%define UE_DELETE 262
%define UE_BACKSPACE 263
%define UE_PAGEUP 264
%define UE_PAGEDOWN 265
%define UE_UNICODE 0x200000
; Terminal callback table. SysV; one serialized app instance.
struc uedit_io
 .read: resq 1                  ; fn()->byte or negative EOF/I/O failure
 .write: resq 1                 ; fn(rdi=bytes,rsi=length)->void, consume now
 .save: resq 1                  ; fn(rdi=data,rsi=length)->0 or negative error
 .size: resq 1                  ; optional fn(&columns,&rows), defaults 80x24
endstruc
%endif
