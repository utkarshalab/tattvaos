%ifndef VCS_SERVER_INC
%define VCS_SERVER_INC

%define VS_ACCEPTING    0
%define VS_RECV_REQUEST 1
%define VS_SEND_RESPONSE 2
%define VS_READY        3
%define VS_FAILED       4

struc vcs_server
 .phase: resd 1
 .operation: resd 1
 .listener: resd 1
 .client: resd 1
 .seed: resq 1
 .handler: resq 1
 .incoming_count: resq 1
 .outgoing_count: resq 1
 .status: resq 1
 .request: resb 96
 .response: resb 96
 .transfer: resb 512
endstruc

%endif
