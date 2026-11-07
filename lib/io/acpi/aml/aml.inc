; =============================================================================
; Utkarsha OS — lib/io/acpi/aml/aml.inc
; =============================================================================
; Structures and constants of the AML interpreter. Plan:
; lib/io/acpi/ROADMAP.md §4.2 and Phase 1.
; =============================================================================

%ifndef LIB_IO_ACPI_AML_INC
%define LIB_IO_ACPI_AML_INC

; ---- Errors (negative in EAX) ----------------------------------------------
%define AML_OK              0
%define AML_EBADCODE        1   ; malformed or truncated bytecode
%define AML_ENOMEM          2   ; the interpreter's memory is full
%define AML_ENOTFOUND       3   ; a name that does not exist
%define AML_ETYPE           4   ; an operand of the wrong type
%define AML_EUNSUPPORTED    5   ; an opcode or region space not built yet
%define AML_EBUDGET         6   ; loop, call-depth or nesting limit reached
%define AML_EINDEX          7   ; index outside a buffer, string or package
%define AML_EDIVZERO        8
%define AML_EFATAL          9   ; the bytecode executed Fatal
%define AML_EEXISTS         10  ; a name created twice
%define AML_EARGS           11  ; wrong argument count
%define AML_EDENIED         12  ; the sandbox refused an access

; ---- Value: 16 bytes, everywhere a value is kept -----------------------------
; Types are the ObjectType numbers from the specification (0-16), plus
; internal ones from 0x20.
%define AML_T_UNINIT        0
%define AML_T_INTEGER       1
%define AML_T_STRING        2   ; data = bytes, len = length (no NUL counted)
%define AML_T_BUFFER        3   ; data = bytes, len = length
%define AML_T_PACKAGE       4   ; data = aml_value[len]
%define AML_T_FIELD         5   ; node holds a field unit
%define AML_T_DEVICE        6
%define AML_T_EVENT         7
%define AML_T_METHOD        8
%define AML_T_MUTEX         9
%define AML_T_REGION        10
%define AML_T_POWERRES      11
%define AML_T_PROCESSOR     12
%define AML_T_THERMAL       13
%define AML_T_BUFFIELD      14
%define AML_T_DDBHANDLE     15
%define AML_T_DEBUG         16
%define AML_T_SCOPE         0x20    ; a plain scope (\_SB_ and friends)
%define AML_T_REF           0x21    ; a reference: sub = AML_REF_*, data = target
%define AML_T_ALIAS         0x22    ; data = the node it names
%define AML_T_NAMEREF       0x23    ; an unresolved name in a package: data = AML

%define AML_REF_SLOT        1   ; data = aml_value* (local, arg, element, node value)
%define AML_REF_NODE        2   ; data = node*
%define AML_REF_BYTE        3   ; data = byte* inside a buffer
%define AML_REF_DEBUG       4
%define AML_REF_NONE        5   ; a null target: the result is dropped

struc aml_value
    .type:      resb 1
    .sub:       resb 1
    .pad:       resw 1
    .len:       resd 1
    .data:      resq 1
endstruc                        ; 16 bytes

; ---- Namespace node ---------------------------------------------------------------
%define AML_NODE_NATIVE     (1 << 0)    ; a method built into the interpreter
%define AML_NODE_SERIAL     (1 << 1)    ; a serialized method

struc aml_node
    .name:      resd 1          ; four characters, little-endian
    .flags:     resd 1
    .value:     resb aml_value_size
    .parent:    resq 1
    .child:     resq 1          ; first child
    .next:      resq 1          ; next sibling
    ; per type:
    ;   method:  x0 = body, x1 = body end, x2 low byte = argument count
    ;            (native: x0 = handler)
    ;   region:  x0 = offset, x1 = length, x2 low byte = space
    ;   field:   x0 = region node, x1 = bit offset (low 32) | bit length << 32,
    ;            x2 = access byte
    ;   buffer field: x0 = buffer node, x1 = bit offset | bit length << 32
    .x0:        resq 1
    .x1:        resq 1
    .x2:        resq 1
    .pad:       resq 1
endstruc                        ; 88 bytes

; ---- Method frame (one per call) --------------------------------------------------
%define AML_ARGS            7
%define AML_LOCALS          8

%define AML_F_RETURN        (1 << 0)
%define AML_F_BREAK         (1 << 1)
%define AML_F_CONTINUE      (1 << 2)

struc aml_frame
    .ip:        resq 1          ; next byte to run
    .end:       resq 1          ; end of the current term list
    .scope:     resq 1          ; node names resolve against
    .method:    resq 1          ; the method running (0 while loading)
    .parent:    resq 1          ; calling frame
    .flags:     resd 1          ; AML_F_*
    .depth:     resd 1          ; call depth
    .args:      resb AML_ARGS * aml_value_size
    .locals:    resb AML_LOCALS * aml_value_size
    .ret:       resb aml_value_size
    .created:   resq 1          ; nodes this call created (linked by .pad)
endstruc

%define AML_NODE_EXTERNAL   (1 << 2)    ; declared by External, not defined yet
%define AML_NODE_TEMP       (1 << 3)    ; created by a running method

; field node x2 bits 8-9: which kind of field
%define AML_FIELD_INDEX     (1 << 8)    ; pad = data node, x0 = index node
%define AML_FIELD_BANK      (1 << 9)    ; pad = bank node, x2 >> 16 = value

; ---- Limits ------------------------------------------------------------------
%define AML_MAX_DEPTH       32          ; method calls
%define AML_MAX_LOOPS       1000000     ; While iterations per evaluation
%define AML_STACK_BUDGET    10240       ; bytes of machine stack AML may use
%define AML_MAX_ELEMENTS    65535       ; package elements

%endif ; LIB_IO_ACPI_AML_INC
