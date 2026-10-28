%ifndef VCS_GIT_COMMIT_INC
%define VCS_GIT_COMMIT_INC

%define GIT_COMMIT_HASH_SIZE 32
%define GIT_COMMIT_MESSAGE_MAX 215

struc git_commit_request
 .tree: resq 1
 .parent: resq 1
 .message: resq 1
 .message_len: resq 1
 .output: resq 1
 .capacity: resq 1
 .hash: resq 1
endstruc

%endif
