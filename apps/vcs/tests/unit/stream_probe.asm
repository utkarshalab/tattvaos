bits 64
default rel
global vcs_bundle_export,vcs_bundle_publish,vcs_sync_send_begin,vcs_sync_receive_begin
global vcs_sync_step,vcs_sync_result,vcs_sync_unet_send,vcs_sync_unet_receive
global vcs_identity_trust_key
global mock_export_status,mock_send_begin,mock_receive_begin,mock_step,mock_result
global mock_result_operation,mock_publish_status,mock_publish_id
global mock_export_calls,mock_send_calls,mock_receive_calls,mock_publish_calls
section .bss
mock_export_status: resq 1
mock_send_begin: resq 1
mock_receive_begin: resq 1
mock_step: resq 1
mock_result: resq 1
mock_result_operation: resq 1
mock_publish_status: resq 1
mock_publish_id: resq 1
mock_export_calls: resq 1
mock_send_calls: resq 1
mock_receive_calls: resq 1
mock_publish_calls: resq 1
mock_payload: resb 128
section .text
vcs_bundle_export:
 inc qword [mock_export_calls]
 mov rax,[mock_export_status]
 mov edx,128
 mov ecx,2
 ret
vcs_bundle_publish:
 inc qword [mock_publish_calls]
 mov rax,[mock_publish_status]
 mov rdx,[mock_publish_id]
 ret
vcs_sync_send_begin:
 inc qword [mock_send_calls]
 mov rax,[mock_send_begin]
 ret
vcs_sync_receive_begin:
 inc qword [mock_receive_calls]
 mov rax,[mock_receive_begin]
 ret
vcs_sync_step:
 mov rax,[mock_step]
 ret
vcs_sync_result:
 mov rax,[mock_result]
 lea rdx,[mock_payload]
 mov ecx,128
 mov r8,[mock_result_operation]
 ret
vcs_sync_unet_send:
 mov rax,-1
 ret
vcs_sync_unet_receive:
 mov rax,-1
 ret
vcs_identity_trust_key:
 mov eax,1
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
