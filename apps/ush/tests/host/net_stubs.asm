; Host-only resolution for native unet entry points. Network commands are
; compiled out of host Ush; native-object link checks still need symbols.
bits 64
section .text
global unet_socket,unet_bind,unet_listen,unet_accept,unet_connect
global unet_get_state,unet_send,unet_recv,unet_close
unet_socket:
unet_bind:
unet_listen:
unet_accept:
unet_connect:
unet_get_state:
unet_send:
unet_recv:
 mov rax,-1
 ret
unet_close:
 xor eax,eax
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
