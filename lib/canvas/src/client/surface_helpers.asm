; ============================================================================
; Client Surface Helpers — cw_surface requests
; ============================================================================
; Every function takes rdi = conn and leaves it unchanged for the next call.
; Requests without a reply return once written; the server answers a refused
; one with an error event.

%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"
%include "inc/canvas_client.inc"

extern canvas_call
extern canvas_send

section .text

; ---------------------------------------------------------------------------
; canvas_surface_create
;   OUT: rax = the surface's handle, negative error
; ---------------------------------------------------------------------------
global canvas_surface_create
canvas_surface_create:
    push rbx
    mov rbx, rdi
    mov esi, CWP_OBJ_SURFACE
    mov edx, SURFACE_CREATE
    lea rcx, [rbx + CLIENT_WIRE + ClientWire.reply]
    xor r8d, r8d
    call canvas_call
    test rax, rax
    js .out
    mov eax, [rbx + CLIENT_WIRE + ClientWire.reply]
.out:
    pop rbx
    ret

; ---------------------------------------------------------------------------
; canvas_surface_destroy
;   IN:  esi = surface
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_surface_destroy
canvas_surface_destroy:
    sub rsp, 24
    mov [rsp], esi
    mov esi, CWP_OBJ_SURFACE
    mov edx, SURFACE_DESTROY
    mov rcx, rsp
    mov r8d, 4
    call canvas_send
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; canvas_surface_attach
;   IN:  esi = surface, edx = buffer (0: none), ecx = x, r8d = y
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_surface_attach
canvas_surface_attach:
    sub rsp, 40
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov qword [rsp + 16], 0             ; no fences
    mov esi, CWP_OBJ_SURFACE
    mov edx, SURFACE_ATTACH
    mov rcx, rsp
    mov r8d, 24
    call canvas_send
    add rsp, 40
    ret

; ---------------------------------------------------------------------------
; canvas_surface_damage
;   IN:  esi = surface, edx = x, ecx = y, r8d = width, r9d = height
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_surface_damage
canvas_surface_damage:
    sub rsp, 40
    mov [rsp], esi
    mov [rsp + 4], edx
    mov [rsp + 8], ecx
    mov [rsp + 12], r8d
    mov [rsp + 16], r9d
    mov esi, CWP_OBJ_SURFACE
    mov edx, SURFACE_DAMAGE
    mov rcx, rsp
    mov r8d, 20
    call canvas_send
    add rsp, 40
    ret

; ---------------------------------------------------------------------------
; canvas_surface_commit
;   IN:  esi = surface, edx = flags (CLIENT_COMMIT_*)
;   OUT: rax = 0, negative error
; ---------------------------------------------------------------------------
global canvas_surface_commit
canvas_surface_commit:
    sub rsp, 24
    mov [rsp], esi
    mov [rsp + 4], edx
    mov esi, CWP_OBJ_SURFACE
    mov edx, SURFACE_COMMIT
    mov rcx, rsp
    mov r8d, 8
    call canvas_send
    add rsp, 24
    ret

; ---------------------------------------------------------------------------
; canvas_frame_request
;   A frame_done event when the surface's next commit has been shown
;   IN:  esi = surface
;   OUT: rax = the callback's id, negative error
; ---------------------------------------------------------------------------
global canvas_frame_request
canvas_frame_request:
    push rbx
    sub rsp, 16
    mov rbx, rdi
    mov [rsp], esi
    mov esi, CWP_OBJ_SURFACE
    mov edx, SURFACE_FRAME_CALLBACK
    mov rcx, rsp
    mov r8d, 4
    call canvas_call
    test rax, rax
    js .out
    mov eax, [rbx + CLIENT_WIRE + ClientWire.reply]
.out:
    add rsp, 16
    pop rbx
    ret

section .data
global canvas_surface_helpers_version
canvas_surface_helpers_version: dq 0x020000
