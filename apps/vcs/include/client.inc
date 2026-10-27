%ifndef VCS_CLIENT_INC
%define VCS_CLIENT_INC

%define VC_CONNECTING    0
%define VC_SEND_REQUEST  1
%define VC_RECV_RESPONSE 2
%define VC_READY         3
%define VC_FAILED        4

struc vcs_client
 .phase: resd 1
 .operation: resd 1
 .fd: resd 1
 .reserved: resd 1
 .seed: resq 1
 .bundle_count: resq 1
 .send_count: resq 1
 .request: resb 96
 .response: resb 96
 .head_digest: resb 32
 .transfer: resb 512
endstruc

%endif
