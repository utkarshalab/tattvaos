; UXFS command adapter. Single console owns these bounded buffers.
%include "storage/uxfs/volume.inc"
%include "apps/vcs/include/diff.inc"
%include "apps/vcs/include/client.inc"
%include "apps/vcs/include/server.inc"
bits 64
default rel
extern uxv_ready,fs_resolve,ush_streq,diff_files,frontend_write,frontend_write_str
extern uxv_normalize,uxv_find,uxv_free,uxv_commit
extern vcs_repo_init,vcs_history,vcs_history_signed,vcs_ref,vcs_checkout,vcs_stage,vcs_merge,vcs_rebase,vcs_identity
extern vcs_policy,vcs_verify_all
extern vcs_pick
extern vcs_repo_diff
extern vcs_blame
extern vcs_stash
extern vcs_bisect
extern bridge_git_export,bridge_git_export_history,bridge_git_import
extern vcs_bundle_export,vcs_bundle_seal,vcs_bundle_open,vcs_bundle_publish
extern vcs_remote
%ifdef VCS_NETWORK_NATIVE
extern vcs_sync_client_begin,vcs_sync_client_step,vcs_sync_client_close
extern vcs_sync_server_begin,vcs_sync_server_step,vcs_sync_server_rearm,vcs_sync_server_close
extern vcs_sync_plan_head_digest,vcs_sync_policy_ids
extern vcs_stream_send_begin,vcs_stream_receive_begin,vcs_stream_step
extern vcs_sync_plan,vcs_sync_repository_policy,vcs_sync_policy_ids
extern git_upload_server_begin,git_upload_server_step,git_upload_server_rearm
extern git_upload_server_close
extern ush_yield_hook,vcs_repo_head
%endif
section .bss
alignb 8
request: resb vcs_diff_request_size
scratch: resb VCS_DIFF_SCRATCH
alignb 8
records: resb 512*vcs_diff_record_size
rendered: resb 4096*4+2
commit_message: resb 216
commit_seed: resq 1
restore_path: resb 240
patch_payload: resb 3936
patch_frame: resb 4096
%ifdef VCS_NETWORK_NATIVE
net_client: resb vcs_client_size
net_server: resb vcs_server_size
net_ids: resq 64
net_count: resq 1
net_seed: resq 1
net_ref: resq 1
net_operation: resd 1
net_ip: resd 1
net_port: resd 1
%endif
section .rodata
diff_name: db 'diff',0
init_name: db 'init',0
status_name: db 'status',0
commit_name: db 'commit',0
log_name: db 'log',0
show_name: db 'show',0
blame_name: db 'blame',0
stash_name: db 'stash',0
bisect_name: db 'bisect',0
git_name: db 'git',0
export_history_name: db 'export-history',0
start_name: db 'start',0
good_name: db 'good',0
bad_name: db 'bad',0
list_name: db 'list',0
pop_name: db 'pop',0
drop_name: db 'drop',0
restore_name: db 'restore',0
branch_name: db 'branch',0
tag_name: db 'tag',0
refs_name: db 'refs',0
checkout_name: db 'checkout',0
add_name: db 'add',0
reset_name: db 'reset',0
staged_name: db 'staged',0
check_name: db 'check',0
merge_name: db 'merge',0
conflicts_name: db 'conflicts',0
resolve_name: db 'resolve',0
rebase_name: db 'rebase',0
identity_name: db 'identity',0
sign_name: db 'sign',0
verify_name: db 'verify',0
policy_name: db 'policy',0
cherry_pick_name: db 'cherry-pick',0
revert_name: db 'revert',0
patch_name: db 'patch',0
export_name: db 'export',0
inspect_name: db 'inspect',0
import_name: db 'import',0
apply_name: db 'apply',0
remote_name: db 'remote',0
remove_name: db 'remove',0
fetch_name: db 'fetch',0
push_name: db 'push',0
clone_name: db 'clone',0
serve_name: db 'serve',0
clients_option: db '--clients',0
signatures_option: db '--signatures',0
staged_option: db '--staged',0
sign_option: db '--sign',0
require_signed_name: db 'require-signed',0
allow_unsigned_name: db 'allow-unsigned',0
rotate_option: db '--rotate',0
revoke_option: db '--revoke',0
continue_option: db '--continue',0
delete_option: db '-d',0
force_option: db '--force',0
all_option: db '--all',0
abort_option: db '--abort',0
head_name: db 'HEAD',0
message_option: db '-m',0
file_option: db '-F',0
oneline_option: db '--oneline',0
message_error: db 'vcs: message must be 1..215 bytes without NUL; use commit TEXT, repeated -m TEXT, or -F FILE',10,0
history_error: db 'vcs: repository operation failed (missing/corrupt metadata, limits, or I/O); remount after I/O failure',10,0
dot: db '.',0
initialized: db 'vcs: initialized repository',10,0
existing: db 'vcs: repository already initialized',10,0
init_error: db 'vcs: init failed (directory, metadata conflict, capacity, or I/O); remount after I/O failure',10,0
help_name: db '--help',0
help_word: db 'help',0
repo_diff_usage: db 'Repository diff: vcs diff | vcs diff --staged | vcs diff ID1 ID2',10,0
patch_usage: db 'Patch: vcs patch export ID FILE SEED_FILE | inspect FILE | import FILE [SEED_FILE] | apply FILE [SEED_FILE]',10,0
remote_usage: db 'Remote: vcs remote | remote add NAME IPV4 PORT | remote remove NAME',10,0
network_usage: db 'Network: vcs fetch|push|clone REMOTE SEED_FILE [REF] | vcs serve PORT SEED_FILE | vcs git serve PORT [ID|BRANCH] [--clients COUNT]',10,0
network_native_only: db 'vcs: networking is available only in native TattvaOS',10,0
patch_exported: db 'Exported signed patch',10,0
git_exported: db 'Exported Git fast-import stream',10,0
git_imported: db 'Imported Git fast-import snapshot',10,0
patch_valid: db 'Patch signature and objects valid',10,0
patch_imported: db 'Imported commit ',0
usage: db 'Usage: vcs diff FILE1 FILE2',10,'       vcs init [DIRECTORY]',10,'       vcs status',10,'       vcs check [--signatures]',10,'       vcs add PATH... | --all',10,'       vcs reset PATH... | --all',10,'       vcs staged',10,'       vcs commit "MESSAGE"',10,'       vcs commit --sign SEED_FILE "MESSAGE"',10,'       vcs commit -m "TITLE" [-m "BODY" ...]',10,'       vcs commit -F FILE',10,'       vcs log [--oneline]',10,'       vcs show [HEAD|16-HEX-ID]',10,'       vcs blame FILE',10,'       vcs stash [MESSAGE] | list | apply | pop | drop',10,'       vcs stash --sign SEED_FILE [MESSAGE]',10,'       vcs bisect start GOOD BAD',10,'       vcs bisect good|bad|status|reset',10,'       vcs git export ID|BRANCH FILE',10,'       vcs git export-history ID|BRANCH FILE',10,'       vcs git import FILE [SEED_FILE]',10,'       vcs restore PATH',10,'       vcs checkout ID|BRANCH --force',10,'       vcs branch|tag NAME [ID]',10,'       vcs branch|tag -d NAME',10,'       vcs refs',10,'       vcs merge ID|BRANCH',10,'       vcs conflicts',10,'       vcs resolve PATH',10,'       vcs merge --continue MESSAGE [--sign SEED_FILE]',10,'       vcs merge --abort',10,'       vcs rebase ID|BRANCH [--sign SEED_FILE]',10,'       vcs rebase --continue [--sign SEED_FILE]',10,'       vcs rebase --abort',10,'       vcs identity [NAME SEED_FILE]',10,'       vcs identity --rotate NAME SEED_FILE',10,'       vcs identity --revoke NAME',10,'       vcs policy [require-signed|allow-unsigned]',10,'       vcs sign [HEAD|ID] SEED_FILE',10,'       vcs verify [HEAD|ID]',10,'       vcs cherry-pick|revert ID [--sign SEED_FILE]',10,'       vcs cherry-pick|revert --continue [--sign SEED_FILE]',10,'       vcs cherry-pick|revert --abort',10,'Exit: 0 success/identical, 1 different, 2 error.',10,0
bad: db 'vcs: invalid arguments or files; run vcs --help',10,0
limit: db 'vcs: diff supports at most 256 lines per file',10,0
header: db '--- FILE1',10,'+++ FILE2',10,0
no_newline: db 10,'\ No newline at end of file',10,0
prefixes: db ' -+'
hex: db '0123456789abcdef'
section .text
global cmd_vcs
cmd_vcs:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov r12,rsi
 mov r13,rdi
 cmp rdi,1
 je .help
 mov rdi,[r12+8]
 lea rsi,[diff_name]
 call ush_streq
 test eax,eax
 jz .diff_command
 mov rdi,[r12+8]
 lea rsi,[init_name]
 call ush_streq
 test eax,eax
 jz .init
 mov rdi,[r12+8]
 lea rsi,[status_name]
 call ush_streq
 test eax,eax
 jz .status
 mov rdi,[r12+8]
 lea rsi,[commit_name]
 call ush_streq
 test eax,eax
 jz .commit
 mov rdi,[r12+8]
 lea rsi,[log_name]
 call ush_streq
 test eax,eax
 jz .log
 mov rdi,[r12+8]
 lea rsi,[show_name]
 call ush_streq
 test eax,eax
 jz .show
 mov rdi,[r12+8]
 lea rsi,[blame_name]
 call ush_streq
 test eax,eax
 jz .blame
 mov rdi,[r12+8]
 lea rsi,[stash_name]
 call ush_streq
 test eax,eax
 jz .stash
 mov rdi,[r12+8]
 lea rsi,[bisect_name]
 call ush_streq
 test eax,eax
 jz .bisect
 mov rdi,[r12+8]
 lea rsi,[git_name]
 call ush_streq
 test eax,eax
 jz .git
 mov rdi,[r12+8]
 lea rsi,[restore_name]
 call ush_streq
 test eax,eax
 jz .restore
 mov rdi,[r12+8]
 lea rsi,[branch_name]
 call ush_streq
 test eax,eax
 jz .branch
 mov rdi,[r12+8]
 lea rsi,[tag_name]
 call ush_streq
 test eax,eax
 jz .tag
 mov rdi,[r12+8]
 lea rsi,[refs_name]
 call ush_streq
 test eax,eax
 jz .refs
 mov rdi,[r12+8]
 lea rsi,[checkout_name]
 call ush_streq
 test eax,eax
 jz .checkout
 mov rdi,[r12+8]
 lea rsi,[add_name]
 call ush_streq
 test eax,eax
 jz .add
 mov rdi,[r12+8]
 lea rsi,[reset_name]
 call ush_streq
 test eax,eax
 jz .reset
 mov rdi,[r12+8]
 lea rsi,[staged_name]
 call ush_streq
 test eax,eax
 jz .staged
 mov rdi,[r12+8]
 lea rsi,[check_name]
 call ush_streq
 test eax,eax
 jz .check
 mov rdi,[r12+8]
 lea rsi,[merge_name]
 call ush_streq
 test eax,eax
 jz .merge
 mov rdi,[r12+8]
 lea rsi,[conflicts_name]
 call ush_streq
 test eax,eax
 jz .conflicts
 mov rdi,[r12+8]
 lea rsi,[resolve_name]
 call ush_streq
 test eax,eax
 jz .resolve
 mov rdi,[r12+8]
 lea rsi,[rebase_name]
 call ush_streq
 test eax,eax
 jz .rebase
 mov rdi,[r12+8]
 lea rsi,[identity_name]
 call ush_streq
 test eax,eax
 jz .identity
 mov rdi,[r12+8]
 lea rsi,[sign_name]
 call ush_streq
 test eax,eax
 jz .sign
 mov rdi,[r12+8]
 lea rsi,[verify_name]
 call ush_streq
 test eax,eax
 jz .verify
 mov rdi,[r12+8]
 lea rsi,[policy_name]
 call ush_streq
 test eax,eax
 jz .policy
 mov rdi,[r12+8]
 lea rsi,[cherry_pick_name]
 call ush_streq
 test eax,eax
 jz .cherry_pick
 mov rdi,[r12+8]
 lea rsi,[revert_name]
 call ush_streq
 test eax,eax
 jz .revert
 mov rdi,[r12+8]
 lea rsi,[patch_name]
 call ush_streq
 test eax,eax
 jz .patch
 mov rdi,[r12+8]
 lea rsi,[remote_name]
 call ush_streq
 test eax,eax
 jz .remote
 mov rdi,[r12+8]
 lea rsi,[fetch_name]
 call ush_streq
 test eax,eax
 jz .fetch
 mov rdi,[r12+8]
 lea rsi,[push_name]
 call ush_streq
 test eax,eax
 jz .push
 mov rdi,[r12+8]
 lea rsi,[clone_name]
 call ush_streq
 test eax,eax
 jz .clone
 mov rdi,[r12+8]
 lea rsi,[serve_name]
 call ush_streq
 test eax,eax
 jz .serve
 mov rdi,r13
 cmp rdi,2
 jne .arguments
 mov rdi,[r12+8]
 lea rsi,[help_name]
 call ush_streq
 test eax,eax
 jz .help
 mov rdi,[r12+8]
 lea rsi,[help_word]
 call ush_streq
 test eax,eax
 jz .help
 jmp .bad
.diff_command:
 cmp r13,2
 je .diff_working
 cmp r13,3
 je .diff_staged_check
 cmp r13,4
 jne .bad
 mov rdi,[r12+16]
 call parse_commit_id
 jc .arguments
 mov r14,rax
 mov rdi,[r12+24]
 call parse_commit_id
 jc .arguments
 mov rdx,rax
 mov rsi,r14
 mov edi,2
 jmp .repo_diff_call
.diff_staged_check:
 mov rdi,[r12+16]
 lea rsi,[staged_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov edi,1
 xor esi,esi
 xor edx,edx
 jmp .repo_diff_call
.diff_working:
 xor edi,edi
 xor esi,esi
 xor edx,edx
.repo_diff_call:
 lea rcx,[frontend_write]
 call vcs_repo_diff
 cmp eax,1
 jbe .done
 lea rdi,[history_error]
 jmp .error
.arguments:
 mov rdi,r13
 cmp rdi,4
 jne .bad
 mov rdi,[r12+8]
 lea rsi,[diff_name]
 call ush_streq
 test eax,eax
 jnz .bad
 cmp qword [uxv_ready],1
 jne .bad
 mov rdi,[r12+16]
 call fs_resolve
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 lea rdx,[rax+UV_DATA]
 mov [request+vcs_diff_request.old],rdx
 mov rdx,[rax+UV_SIZE]
 mov [request+vcs_diff_request.old_size],rdx
 mov rdi,[r12+24]
 call fs_resolve
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 lea rdx,[rax+UV_DATA]
 mov [request+vcs_diff_request.new],rdx
 mov rdx,[rax+UV_SIZE]
 mov [request+vcs_diff_request.new_size],rdx
 lea rax,[scratch]
 mov [request+vcs_diff_request.scratch],rax
 mov qword [request+vcs_diff_request.scratch_size],VCS_DIFF_SCRATCH
 lea rax,[records]
 mov [request+vcs_diff_request.output],rax
 mov qword [request+vcs_diff_request.capacity],512
 lea rdi,[request]
 call diff_files
 test eax,eax
 jnz .limit
 mov r13,rdx
 lea rbx,[records]
 xor ecx,ecx
.scan:
 cmp rcx,r13
 jae .identical
 mov rax,rcx
 shl rax,5
 cmp qword [rbx+rax],0
 jne .changed
 inc rcx
 jmp .scan
.changed:
 lea rdi,[header]
 call frontend_write_str
.emit:
 mov rax,[rbx+vcs_diff_record.kind]
 lea rdx,[prefixes]
 mov dl,[rdx+rax]
 lea rdi,[rendered]
 mov [rdi],dl
 inc rdi
 mov rsi,[request+vcs_diff_request.old]
 add rsi,[rbx+vcs_diff_record.old_offset]
 cmp eax,VCS_DIFF_INSERT
 jne .bytes
 mov rsi,[request+vcs_diff_request.new]
 add rsi,[rbx+vcs_diff_record.new_offset]
.bytes:
 mov rcx,[rbx+vcs_diff_record.length]
 mov r14,rcx
 mov r15,rsi
 lea r8,[hex]
.byte:
 lodsb
 cmp al,10
 je .literal
 cmp al,32
 jb .escape
 cmp al,126
 ja .escape
 cmp al,92
 je .escape
.literal:
 stosb
 jmp .next
.escape:
 mov byte [rdi],92
 mov byte [rdi+1],'x'
 movzx edx,al
 shr edx,4
 mov dl,[r8+rdx]
 mov [rdi+2],dl
 and eax,15
 mov al,[r8+rax]
 mov [rdi+3],al
 add rdi,4
.next:
 loop .byte
 mov rsi,rdi
 lea rdi,[rendered]
 sub rsi,rdi
 call frontend_write
 cmp byte [r15+r14-1],10
 je .next_record
 lea rdi,[no_newline]
 call frontend_write_str
.next_record:
 add rbx,vcs_diff_record_size
 dec r13
 jnz .emit
 mov eax,1
 jmp .done
.help:
 lea rdi,[repo_diff_usage]
 call frontend_write_str
 lea rdi,[patch_usage]
 call frontend_write_str
 lea rdi,[remote_usage]
 call frontend_write_str
 lea rdi,[network_usage]
 call frontend_write_str
 lea rdi,[usage]
 call frontend_write_str
.identical:
 xor eax,eax
 jmp .done
.init:
 cmp r13,3
 ja .bad
 lea rdi,[dot]
 cmp r13,2
 je .init_call
 mov rdi,[r12+16]
.init_call:
 call vcs_repo_init
 test eax,eax
 jnz .init_bad
 lea rdi,[initialized]
 test rdx,rdx
 jz .init_print
 lea rdi,[existing]
.init_print:
 call frontend_write_str
 xor eax,eax
 jmp .done
.init_bad:
 lea rdi,[init_error]
 jmp .error
.status:
 cmp r13,2
 jne .bad
 xor edi,edi
 xor esi,esi
 jmp .history
.log:
 cmp r13,2
 je .log_full
 cmp r13,3
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[oneline_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov edi,3
 xor esi,esi
 jmp .history
.log_full:
 mov edi,2
 xor esi,esi
 jmp .history
.show:
 cmp r13,2
 je .show_head
 cmp r13,3
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[head_name]
 call ush_streq
 test eax,eax
 jz .show_head
 mov rdi,[r12+16]
 call parse_commit_id
 jc .bad
 mov rsi,rax
 mov edi,4
 jmp .history
.show_head:
 xor esi,esi
 mov edi,4
 jmp .history
.blame:
 cmp r13,3
 jne .bad
 cmp qword [uxv_ready],1
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[restore_path]
 call uxv_normalize
 test rax,rax
 js .bad
 lea rdi,[restore_path]
 lea rsi,[frontend_write]
 call vcs_blame
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.stash:
 cmp r13,2
 je .stash_save_default
 cmp r13,3
 je .stash_one
 mov rdi,[r12+16]
 lea rsi,[sign_option]
 call ush_streq
 test eax,eax
 jnz .bad
 cmp r13,4
 je .stash_signed_default
 cmp r13,5
 jne .bad
 mov rdi,[r12+24]
 call seed_file
 test rax,rax
 jz .bad
 mov rdx,rax
 mov rsi,[r12+32]
 jmp .stash_save
.stash_signed_default:
 mov rdi,[r12+24]
 call seed_file
 test rax,rax
 jz .bad
 mov rdx,rax
 xor esi,esi
 jmp .stash_save
.stash_one:
 mov rdi,[r12+16]
 lea rsi,[sign_option]
 call ush_streq
 test eax,eax
 jz .bad
 mov rdi,[r12+16]
 lea rsi,[list_name]
 call ush_streq
 test eax,eax
 jz .stash_list
 mov rdi,[r12+16]
 lea rsi,[apply_name]
 call ush_streq
 test eax,eax
 jz .stash_apply
 mov rdi,[r12+16]
 lea rsi,[pop_name]
 call ush_streq
 test eax,eax
 jz .stash_pop
 mov rdi,[r12+16]
 lea rsi,[drop_name]
 call ush_streq
 test eax,eax
 jz .stash_drop
 mov rsi,[r12+16]
 xor edx,edx
 jmp .stash_save
.stash_save_default:
 xor esi,esi
 xor edx,edx
.stash_save:
 xor edi,edi
 jmp .stash_call
.stash_list:
 mov edi,1
 jmp .stash_no_args
.stash_apply:
 mov edi,2
 jmp .stash_no_args
.stash_pop:
 mov edi,3
 jmp .stash_no_args
.stash_drop:
 mov edi,4
.stash_no_args:
 xor esi,esi
 xor edx,edx
.stash_call:
 lea rcx,[frontend_write]
 call vcs_stash
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.bisect:
 cmp r13,3
 je .bisect_action
 cmp r13,5
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[start_name]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rdi,[r12+24]
 call resolve_commitish
 jc .bad
 mov r14,rax
 mov rdi,[r12+32]
 call resolve_commitish
 jc .bad
 mov rdx,rax
 mov rsi,r14
 xor edi,edi
 jmp .bisect_call
.bisect_action:
 mov rdi,[r12+16]
 lea rsi,[good_name]
 call ush_streq
 test eax,eax
 jz .bisect_good
 mov rdi,[r12+16]
 lea rsi,[bad_name]
 call ush_streq
 test eax,eax
 jz .bisect_bad
 mov rdi,[r12+16]
 lea rsi,[status_name]
 call ush_streq
 test eax,eax
 jz .bisect_status
 mov rdi,[r12+16]
 lea rsi,[reset_name]
 call ush_streq
 test eax,eax
 jnz .bad
 mov edi,4
 jmp .bisect_no_args
.bisect_good:
 mov edi,1
 jmp .bisect_no_args
.bisect_bad:
 mov edi,2
 jmp .bisect_no_args
.bisect_status:
 mov edi,3
.bisect_no_args:
 xor esi,esi
 xor edx,edx
.bisect_call:
 lea rcx,[frontend_write]
 call vcs_bisect
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.git:
 mov rdi,[r12+16]
 lea rsi,[serve_name]
 call ush_streq
 test eax,eax
 jz .git_serve
 xor r15d,r15d
 mov rdi,[r12+16]
 lea rsi,[export_name]
 call ush_streq
 test eax,eax
 jz .git_export
 mov rdi,[r12+16]
 lea rsi,[export_history_name]
 call ush_streq
 test eax,eax
 jnz .git_import_check
 mov r15d,1
.git_export:
 cmp r13,5
 jne .bad
 mov rdi,[r12+24]
 call resolve_commitish
 jc .bad
 mov r14,rax
 mov rdi,r14
 lea rsi,[patch_frame]
 mov edx,4096
 test r15d,r15d
 jnz .git_export_history
 call bridge_git_export
 jmp .git_export_result
.git_export_history:
 call bridge_git_export_history
.git_export_result:
 test eax,eax
 jnz .patch_failed
 mov r14,rdx
 mov rdi,[r12+32]
 lea rsi,[restore_path]
 call uxv_normalize
 test rax,rax
 js .patch_failed
 lea rdi,[restore_path]
 call uxv_find
 test rax,rax
 jnz .git_export_existing
 call uxv_free
 test rax,rax
 jz .patch_failed
.git_export_existing:
 cmp qword [rax+UV_TYPE],1
 jne .patch_failed
 mov rbx,rax
 mov rdi,rbx
 call patch_clear_node
 mov rdi,rbx
 lea rsi,[restore_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov [rbx+UV_SIZE],r14
 lea rdi,[rbx+UV_DATA]
 lea rsi,[patch_frame]
 mov rcx,r14
 rep movsb
 call uxv_commit
 test rax,rax
 js .patch_failed
 lea rdi,[git_exported]
 call frontend_write_str
 xor eax,eax
 jmp .done
.git_serve:
%ifdef VCS_NETWORK_NATIVE
 cmp r13,4
 jb .bad
 cmp r13,7
 ja .bad
 mov rdi,[r12+24]
 call parse_port_arg
 test eax,eax
 jnz .bad
 mov r14d,edx
 mov qword [net_count],1
 mov r15,[vcs_repo_head]
 cmp r13,4
 je .git_serve_commit
 cmp r13,6
 je .git_serve_clients
 mov rdi,[r12+32]
 call resolve_commitish
 jc .bad
 mov r15,rax
.git_serve_clients:
 cmp r13,6
 jb .git_serve_commit
 mov rax,r13
 sub rax,2
 mov rdi,[r12+rax*8]
 lea rsi,[clients_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rax,r13
 dec rax
 mov rdi,[r12+rax*8]
 call parse_port_arg
 test eax,eax
 jnz .bad
 test edx,edx
 jz .bad
 mov [net_count],rdx
.git_serve_commit:
 test r15,r15
 jz .patch_failed
 xor edi,edi
 mov esi,r14d
 mov rdx,r15
 call git_upload_server_begin
 test eax,eax
 jnz .patch_failed
.git_serve_wait:
 call git_upload_server_step
 cmp eax,VCS_XFER_AGAIN
 jne .git_serve_done
 call .network_yield
 test eax,eax
 jz .git_serve_wait
.git_serve_done:
 test eax,eax
 jnz .git_serve_fail
 dec qword [net_count]
 jz .git_serve_close
 call git_upload_server_rearm
 test eax,eax
 jnz .git_serve_fail
 jmp .git_serve_wait
.git_serve_close:
 call git_upload_server_close
 jmp .done
.git_serve_fail:
 push rax
 call git_upload_server_close
 pop rax
 jmp .patch_failed
%else
 lea rdi,[network_native_only]
 jmp .error
%endif
.git_import_check:
 mov rdi,[r12+16]
 lea rsi,[import_name]
 call ush_streq
 test eax,eax
 jnz .bad
 cmp r13,4
 jb .bad
 cmp r13,5
 ja .bad
 xor r15d,r15d
 cmp r13,4
 je .git_import_file
 mov rdi,[r12+32]
 call seed_file
 test rax,rax
 jz .bad
 mov r15,rax
.git_import_file:
 mov rdi,[r12+24]
 call fs_resolve
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rsi,[rax+UV_SIZE]
 lea rdi,[rax+UV_DATA]
 mov rdx,r15
 lea rcx,[frontend_write]
 call bridge_git_import
 test eax,eax
 jnz .patch_failed
 lea rdi,[git_imported]
 call frontend_write_str
 xor eax,eax
 jmp .done
.restore:
 cmp r13,3
 jne .bad
 cmp qword [uxv_ready],1
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[restore_path]
 call uxv_normalize
 test rax,rax
 js .bad
 mov edi,5
 lea rsi,[restore_path]
 jmp .history
.refs:
 cmp r13,2
 jne .bad
 mov edi,2
 xor esi,esi
 xor edx,edx
 jmp .ref_call
.branch:
 xor r14d,r14d
 jmp .ref
.tag:
 mov r14d,1
.ref:
 cmp r13,2
 je .refs
 cmp r13,3
 jb .bad
 mov rdi,[r12+16]
 lea rsi,[delete_option]
 call ush_streq
 test eax,eax
 jz .ref_delete
 cmp r13,4
 ja .bad
 mov rsi,[r12+16]
 xor edx,edx
 cmp r13,3
 je .ref_create
 mov rdi,[r12+24]
 call parse_commit_id
 jc .bad
 mov rdx,rax
.ref_create:
 mov rdi,r14
 jmp .ref_call
.ref_delete:
 cmp r13,4
 jne .bad
 lea rdi,[r14+3]
 mov rsi,[r12+24]
 xor edx,edx
.ref_call:
 lea rcx,[frontend_write]
 call vcs_ref
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.checkout:
 cmp r13,4
 jne .bad
 mov rdi,[r12+24]
 lea rsi,[force_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rdi,[r12+16]
 call parse_commit_id
 jnc .checkout_id
 mov edi,5
 mov rsi,[r12+16]
 xor edx,edx
 lea rcx,[frontend_write]
 call vcs_ref
 test eax,eax
 jnz .history_failed
 mov rax,rdx
 mov rdx,[r12+16]
 jmp .checkout_call
.checkout_id:
 xor edx,edx
.checkout_call:
 mov rdi,rax
 lea rsi,[frontend_write]
 call vcs_checkout
 test eax,eax
 jz .done
.history_failed:
 lea rdi,[history_error]
 jmp .error
.add:
 cmp r13,3
 jb .bad
 cmp r13,3
 jne .add_paths
 mov rdi,[r12+16]
 lea rsi,[all_option]
 call ush_streq
 test eax,eax
 jnz .add_paths
 mov edi,4
 xor esi,esi
 xor edx,edx
 jmp .stage_call
.add_paths:
 xor edi,edi
 lea rsi,[r13-2]
 lea rdx,[r12+16]
 jmp .stage_call
.reset:
 cmp r13,3
 jb .bad
 cmp r13,3
 jne .reset_paths
 mov rdi,[r12+16]
 lea rsi,[all_option]
 call ush_streq
 test eax,eax
 jnz .reset_paths
 mov edi,3
 xor esi,esi
 xor edx,edx
 jmp .stage_call
.reset_paths:
 mov edi,1
 lea rsi,[r13-2]
 lea rdx,[r12+16]
 jmp .stage_call
.staged:
 cmp r13,2
 jne .bad
 mov edi,2
 xor esi,esi
 xor edx,edx
 jmp .stage_call
.check:
 cmp r13,2
 je .check_integrity
 cmp r13,3
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[signatures_option]
 call ush_streq
 test eax,eax
 jnz .bad
 lea rdi,[frontend_write]
 call vcs_verify_all
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.check_integrity:
 mov edi,6
 xor esi,esi
 jmp .history
.stage_call:
 lea rcx,[frontend_write]
 call vcs_stage
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.conflicts:
 cmp r13,2
 jne .bad
 xor r15d,r15d
 mov edi,1
 xor esi,esi
 jmp .merge_call
.resolve:
 cmp r13,3
 jne .bad
 xor r15d,r15d
 mov edi,2
 mov rsi,[r12+16]
 jmp .merge_call
.merge:
 xor r15d,r15d
 cmp r13,3
 je .merge_start
 cmp r13,6
 je .merge_signed_continue
 cmp r13,4
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[continue_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov edi,3
 mov rsi,[r12+24]
 jmp .merge_call
.merge_signed_continue:
 mov rdi,[r12+16]
 lea rsi,[continue_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rdi,[r12+32]
 lea rsi,[sign_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rdi,[r12+40]
 call seed_file
 test rax,rax
 jz .bad
 mov r15,rax
 mov edi,3
 mov rsi,[r12+24]
 jmp .merge_call
.merge_start:
 mov rdi,[r12+16]
 lea rsi,[abort_option]
 call ush_streq
 test eax,eax
 jnz .merge_target
 mov edi,4
 xor esi,esi
 jmp .merge_call
.merge_target:
 mov rdi,[r12+16]
 call parse_commit_id
 jnc .merge_id
 mov edi,5
 mov rsi,[r12+16]
 xor edx,edx
 lea rcx,[frontend_write]
 call vcs_ref
 test eax,eax
 jnz .history_failed
 mov rax,rdx
.merge_id:
 xor edi,edi
 mov rsi,rax
.merge_call:
 lea rdx,[frontend_write]
 mov rcx,r15
 call vcs_merge
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.rebase:
 xor r15d,r15d
 cmp r13,3
 je .rebase_plain
 cmp r13,5
 jne .bad
 mov rdi,[r12+24]
 lea rsi,[sign_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rdi,[r12+32]
 call seed_file
 test rax,rax
 jz .bad
 mov r15,rax
.rebase_plain:
 mov rdi,[r12+16]
 lea rsi,[continue_option]
 call ush_streq
 test eax,eax
 jnz .rebase_start
 mov edi,1
 xor esi,esi
 jmp .rebase_call
.rebase_start:
 mov rdi,[r12+16]
 lea rsi,[abort_option]
 call ush_streq
 test eax,eax
 jnz .rebase_target
 mov edi,2
 xor esi,esi
 jmp .rebase_call
.rebase_target:
 mov rdi,[r12+16]
 call parse_commit_id
 jnc .rebase_id
 mov edi,5
 mov rsi,[r12+16]
 xor edx,edx
 lea rcx,[frontend_write]
 call vcs_ref
 test eax,eax
 jnz .history_failed
 mov rax,rdx
.rebase_id:
 xor edi,edi
 mov rsi,rax
.rebase_call:
 lea rdx,[frontend_write]
 mov rcx,r15
 call vcs_rebase
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.identity:
 cmp r13,2
 je .identity_show
 cmp r13,4
 je .identity_register_or_revoke
 cmp r13,5
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[rotate_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rdi,[r12+32]
 call seed_file
 test rax,rax
 jz .bad
 mov rdx,rax
 mov edi,4
 mov rsi,[r12+24]
 jmp .identity_call
.identity_register_or_revoke:
 mov rdi,[r12+16]
 lea rsi,[revoke_option]
 call ush_streq
 test eax,eax
 jnz .identity_register
 mov edi,5
 mov rsi,[r12+24]
 xor edx,edx
 jmp .identity_call
.identity_register:
 mov rdi,[r12+24]
 call seed_file
 test rax,rax
 jz .bad
 mov rdx,rax
 mov edi,1
 mov rsi,[r12+16]
 jmp .identity_call
.identity_show:
 xor edi,edi
 xor esi,esi
 xor edx,edx
 jmp .identity_call
.sign:
 cmp r13,3
 je .sign_head
 cmp r13,4
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[head_name]
 call ush_streq
 test eax,eax
 jz .sign_named_head
 mov rdi,[r12+16]
 call parse_commit_id
 jc .bad
 mov r14,rax
 jmp .sign_seed
.sign_named_head:
 xor r14d,r14d
.sign_seed:
 mov rdi,[r12+24]
 jmp .sign_resolve
.sign_head:
 xor r14d,r14d
 mov rdi,[r12+16]
.sign_resolve:
 call seed_file
 test rax,rax
 jz .bad
 mov rdx,rax
 mov edi,2
 mov rsi,r14
 jmp .identity_call
.verify:
 cmp r13,2
 je .verify_head
 cmp r13,3
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[head_name]
 call ush_streq
 test eax,eax
 jz .verify_head
 mov rdi,[r12+16]
 call parse_commit_id
 jc .bad
 mov rsi,rax
 jmp .verify_call
.verify_head:
 xor esi,esi
.verify_call:
 mov edi,3
 xor edx,edx
.identity_call:
 lea r8,[frontend_write]
 call vcs_identity
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.policy:
 cmp r13,2
 je .policy_show
 cmp r13,3
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[require_signed_name]
 call ush_streq
 test eax,eax
 jz .policy_require
 mov rdi,[r12+16]
 lea rsi,[allow_unsigned_name]
 call ush_streq
 test eax,eax
 jnz .bad
 mov edi,2
 jmp .policy_call
.policy_require:
 mov edi,1
 jmp .policy_call
.policy_show:
 xor edi,edi
.policy_call:
 lea rsi,[frontend_write]
 call vcs_policy
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.cherry_pick:
 xor r14d,r14d
 jmp .pick
.revert:
 mov r14d,1
.pick:
 xor r15d,r15d
 cmp r13,3
 je .pick_argument
 cmp r13,5
 jne .bad
 mov rdi,[r12+24]
 lea rsi,[sign_option]
 call ush_streq
 test eax,eax
 jnz .bad
 mov rdi,[r12+32]
 call seed_file
 test rax,rax
 jz .bad
 mov r15,rax
.pick_argument:
 mov rdi,[r12+16]
 lea rsi,[continue_option]
 call ush_streq
 test eax,eax
 jz .pick_continue
 mov rdi,[r12+16]
 lea rsi,[abort_option]
 call ush_streq
 test eax,eax
 jz .pick_abort
 mov rdi,[r12+16]
 call parse_commit_id
 jc .bad
 mov rsi,rax
 mov rdi,r14
 jmp .pick_call
.pick_continue:
 mov edi,2
 xor esi,esi
 jmp .pick_call
.pick_abort:
 test r15,r15
 jnz .bad
 mov edi,3
 xor esi,esi
.pick_call:
 lea rdx,[frontend_write]
 mov rcx,r15
 call vcs_pick
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.fetch:
%ifdef VCS_NETWORK_NATIVE
 mov dword [net_operation],1
 jmp .network_receive
%else
 jmp .network_unsupported
%endif
.clone:
%ifdef VCS_NETWORK_NATIVE
 mov dword [net_operation],3
 jmp .network_receive
%else
 jmp .network_unsupported
%endif
.push:
%ifdef VCS_NETWORK_NATIVE
 mov dword [net_operation],2
 jmp .network_push
%else
 jmp .network_unsupported
%endif
.serve:
%ifdef VCS_NETWORK_NATIVE
 jmp .network_serve
%else
 jmp .network_unsupported
%endif
.network_unsupported:
 lea rdi,[network_native_only]
 jmp .error
%ifdef VCS_NETWORK_NATIVE
.network_arguments:
 cmp r13,4
 jb .network_args_bad
 cmp r13,5
 ja .network_args_bad
 mov rdi,[r12+24]
 call seed_file
 test rax,rax
 jz .network_args_bad
 mov [net_seed],rax
 mov qword [net_ref],0
 cmp r13,5
 jne .network_remote
 mov rax,[r12+32]
 mov [net_ref],rax
.network_remote:
 mov edi,3
 mov rsi,[r12+16]
 xor edx,edx
 xor ecx,ecx
 lea r8,[frontend_write]
 call vcs_remote
 test eax,eax
 jnz .network_args_done
 mov [net_ip],edx
 mov [net_port],ecx
.network_args_done:
 ret
.network_args_bad:
 mov eax,VCS_ERR_USAGE
 ret
.network_receive:
 call .network_arguments
 test eax,eax
 jnz .patch_failed
 xor edi,edi
 xor esi,esi
 lea rdx,[net_ids]
 mov ecx,64
 call vcs_sync_plan
 test eax,eax
 jnz .patch_failed
 cmp dword [net_operation],3
 jne .network_receive_have
 test r8,r8
 jnz .patch_failed
.network_receive_have:
 push qword 0
 push qword [net_seed]
 lea rdi,[net_client]
 mov esi,[net_operation]
 mov edx,[net_ip]
 mov ecx,[net_port]
 cmp dword [net_operation],3
 je .network_clone_digest
 lea r8,[vcs_sync_plan_head_digest]
 jmp .network_receive_call
.network_clone_digest:
 xor r8d,r8d
.network_receive_call:
 mov r9,[net_ref]
 call vcs_sync_client_begin
 add rsp,16
 test eax,eax
 jnz .patch_failed
 call .network_client_wait
 test eax,eax
 jnz .patch_failed
 mov rbx,[net_client+vcs_client.bundle_count]
 xor r15d,r15d
.network_receive_bundle:
 cmp r15,rbx
 jae .network_client_done
 mov edi,[net_client+vcs_client.fd]
 mov esi,[net_operation]
 mov rdx,[net_seed]
 call vcs_stream_receive_begin
 test eax,eax
 jnz .network_client_fail
 call .network_stream_wait
 test eax,eax
 jnz .network_client_fail
 inc r15
 jmp .network_receive_bundle
.network_client_done:
 lea rdi,[net_client]
 call vcs_sync_client_close
 xor eax,eax
 jmp .done
.network_client_fail:
 push rax
 lea rdi,[net_client]
 call vcs_sync_client_close
 pop rax
 jmp .patch_failed
.network_push:
 call .network_arguments
 test eax,eax
 jnz .patch_failed
 ; Advertisement round: obtain the remote head digest.
 push qword 0
 push qword [net_seed]
 lea rdi,[net_client]
 mov esi,2
 mov edx,[net_ip]
 mov ecx,[net_port]
 xor r8d,r8d
 mov r9,[net_ref]
 call vcs_sync_client_begin
 add rsp,16
 test eax,eax
 jnz .patch_failed
 call .network_client_wait
 test eax,eax
 jnz .network_client_fail
 lea rdi,[net_client]
 call vcs_sync_client_close
 lea rdi,[net_client+vcs_client.head_digest]
 mov rsi,[net_ref]
 lea rdx,[net_ids]
 mov ecx,64
 call vcs_sync_plan
 test eax,eax
 jnz .patch_failed
 mov [net_count],rdx
 test rdx,rdx
 jz .done
 ; Declared upload round.
 push qword [net_count]
 push qword [net_seed]
 lea rdi,[net_client]
 mov esi,2
 mov edx,[net_ip]
 mov ecx,[net_port]
 lea r8,[net_client+vcs_client.head_digest]
 mov r9,[net_ref]
 call vcs_sync_client_begin
 add rsp,16
 test eax,eax
 jnz .patch_failed
 call .network_client_wait
 test eax,eax
 jnz .network_client_fail
 xor r15d,r15d
.network_push_bundle:
 cmp r15,[net_count]
 jae .network_client_done
 mov edi,[net_client+vcs_client.fd]
 lea rax,[net_ids]
 mov rsi,[rax+r15*8]
 mov edx,2
 mov rcx,[net_seed]
 call vcs_stream_send_begin
 test eax,eax
 jnz .network_client_fail
 call .network_stream_wait
 test eax,eax
 jnz .network_client_fail
 inc r15
 jmp .network_push_bundle
.network_serve:
 cmp r13,4
 jne .bad
 mov rdi,[r12+16]
 call parse_port_arg
 test eax,eax
 jnz .bad
 mov r14d,edx
 mov rdi,[r12+24]
 call seed_file
 test rax,rax
 jz .bad
 mov [net_seed],rax
 lea rdi,[net_server]
 xor esi,esi
 mov edx,r14d
 mov rcx,rax
 lea r8,[vcs_sync_repository_policy]
 call vcs_sync_server_begin
 test eax,eax
 jnz .patch_failed
.network_server_wait:
 lea rdi,[net_server]
 call vcs_sync_server_step
 cmp eax,1
 jne .network_server_ready
 call .network_yield
 test eax,eax
 jz .network_server_wait
 jmp .network_server_fail
.network_server_ready:
 test eax,eax
 jnz .network_server_fail
 mov eax,[net_server+vcs_server.operation]
 cmp eax,2
 je .network_server_receive
 mov rbx,[net_server+vcs_server.outgoing_count]
 xor r15d,r15d
.network_server_send_loop:
 cmp r15,rbx
 jae .network_server_done
 mov edi,[net_server+vcs_server.client]
 lea rax,[vcs_sync_policy_ids]
 mov rsi,[rax+r15*8]
 mov edx,[net_server+vcs_server.operation]
 mov rcx,[net_seed]
 call vcs_stream_send_begin
 test eax,eax
 jnz .network_server_fail
 call .network_stream_wait
 test eax,eax
 jnz .network_server_fail
 inc r15
 jmp .network_server_send_loop
.network_server_receive:
 mov rbx,[net_server+vcs_server.incoming_count]
 test rbx,rbx
 jnz .network_server_recv_start
 lea rdi,[net_server]
 call vcs_sync_server_rearm
 test eax,eax
 jnz .network_server_fail
 jmp .network_server_wait
.network_server_recv_start:
 xor r15d,r15d
.network_server_recv_loop:
 cmp r15,rbx
 jae .network_server_done
 mov edi,[net_server+vcs_server.client]
 mov esi,2
 mov rdx,[net_seed]
 call vcs_stream_receive_begin
 test eax,eax
 jnz .network_server_fail
 call .network_stream_wait
 test eax,eax
 jnz .network_server_fail
 inc r15
 jmp .network_server_recv_loop
.network_server_done:
 lea rdi,[net_server]
 call vcs_sync_server_close
 xor eax,eax
 jmp .done
.network_server_fail:
 push rax
 lea rdi,[net_server]
 call vcs_sync_server_close
 pop rax
 jmp .patch_failed
.network_client_wait:
 lea rdi,[net_client]
 call vcs_sync_client_step
 cmp eax,1
 jne .network_wait_done
 call .network_yield
 test eax,eax
 jz .network_client_wait
.network_wait_done:
 ret
.network_stream_wait:
 call vcs_stream_step
 cmp eax,1
 jne .network_stream_done
 call .network_yield
 test eax,eax
 jz .network_stream_wait
.network_stream_done:
 ret
.network_yield:
 mov rax,[ush_yield_hook]
 test rax,rax
 jz .network_yield_bad
 call rax
 xor eax,eax
 ret
.network_yield_bad:
 mov eax,VCS_ERR_IO
 ret
parse_port_arg:
 xor edx,edx
 xor ecx,ecx
.net_port_digit:
 movzx eax,byte [rdi]
 test al,al
 jz .net_port_end
 cmp al,'0'
 jb .net_port_bad
 cmp al,'9'
 ja .net_port_bad
 imul edx,edx,10
 sub al,'0'
 movzx eax,al
 add edx,eax
 cmp edx,65535
 ja .net_port_bad
 inc rdi
 inc ecx
 cmp ecx,5
 jbe .net_port_digit
.net_port_bad: mov eax,1
 ret
.net_port_end:
 test ecx,ecx
 jz .net_port_bad
 test edx,edx
 jz .net_port_bad
 xor eax,eax
 ret
%endif
.remote:
 cmp r13,2
 je .remote_list
 cmp r13,4
 je .remote_remove
 cmp r13,6
 jne .bad
 mov rdi,[r12+16]
 lea rsi,[add_name]
 call ush_streq
 test eax,eax
 jnz .bad
 mov edi,1
 mov rsi,[r12+24]
 mov rdx,[r12+32]
 mov rcx,[r12+40]
 lea r8,[frontend_write]
 jmp .remote_call
.remote_remove:
 mov rdi,[r12+16]
 lea rsi,[remove_name]
 call ush_streq
 test eax,eax
 jnz .bad
 mov edi,2
 mov rsi,[r12+24]
 xor edx,edx
 xor ecx,ecx
 lea r8,[frontend_write]
 jmp .remote_call
.remote_list:
 xor edi,edi
 xor esi,esi
 xor edx,edx
 xor ecx,ecx
 lea r8,[frontend_write]
.remote_call:
 call vcs_remote
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.patch:
 cmp r13,4
 jb .bad
 mov rdi,[r12+16]
 lea rsi,[export_name]
 call ush_streq
 test eax,eax
 jz .patch_export
 mov rdi,[r12+16]
 lea rsi,[inspect_name]
 call ush_streq
 test eax,eax
 jz .patch_inspect
 mov rdi,[r12+16]
 lea rsi,[import_name]
 call ush_streq
 test eax,eax
 jz .patch_import
 mov rdi,[r12+16]
 lea rsi,[apply_name]
 call ush_streq
 test eax,eax
 jz .patch_apply
 jmp .bad
.patch_export:
 cmp r13,6
 jne .bad
 mov rdi,[r12+24]
 call parse_commit_id
 jc .bad
 mov r14,rax
 mov rdi,[r12+40]
 call seed_file
 test rax,rax
 jz .bad
 mov r15,rax
 mov rdi,r14
 lea rsi,[patch_payload]
 mov edx,3936
 call vcs_bundle_export
 test eax,eax
 jnz .patch_failed
 mov r14,rdx
 lea rdi,[patch_frame]
 mov esi,4096
 lea rdx,[patch_payload]
 mov rcx,r14
 mov r8d,4
 mov r9,r15
 call vcs_bundle_seal
 test eax,eax
 jnz .patch_failed
 mov r14,rdx
 mov rdi,[r12+32]
 lea rsi,[restore_path]
 call uxv_normalize
 test rax,rax
 js .patch_failed
 lea rdi,[restore_path]
 call uxv_find
 test rax,rax
 jnz .patch_export_existing
 call uxv_free
 test rax,rax
 jz .patch_failed
.patch_export_existing:
 cmp qword [rax+UV_TYPE],1
 jne .patch_failed
 mov rbx,rax
 mov rdi,rbx
 call patch_clear_node
 mov rdi,rbx
 lea rsi,[restore_path]
 mov ecx,240
 rep movsb
 mov qword [rbx+UV_TYPE],1
 mov [rbx+UV_SIZE],r14
 lea rdi,[rbx+UV_DATA]
 lea rsi,[patch_frame]
 mov rcx,r14
 rep movsb
 call uxv_commit
 test rax,rax
 js .patch_failed
 lea rdi,[patch_exported]
 call frontend_write_str
 xor eax,eax
 jmp .done
.patch_inspect:
 cmp r13,4
 jne .bad
 mov r15d,1
 jmp .patch_open
.patch_import:
 cmp r13,5
 ja .bad
 xor r15d,r15d
 jmp .patch_open
.patch_apply:
 cmp r13,5
 ja .bad
 mov r15d,2
.patch_open:
 xor r14d,r14d
 cmp r13,5
 jne .patch_file
 mov rdi,[r12+32]
 call seed_file
 test rax,rax
 jz .bad
 mov r14,rax
.patch_file:
 cmp qword [uxv_ready],1
 jne .patch_failed
 mov rdi,[r12+24]
 call fs_resolve
 test rax,rax
 jz .patch_failed
 cmp qword [rax+UV_TYPE],1
 jne .patch_failed
 mov rsi,[rax+UV_SIZE]
 cmp rsi,4096
 ja .patch_failed
 lea rdi,[rax+UV_DATA]
 call vcs_bundle_open
 test eax,eax
 jnz .patch_failed
 cmp r8d,4
 jne .patch_failed
 cmp r15d,1
 jne .patch_publish
 lea rdi,[patch_valid]
 call frontend_write_str
 xor eax,eax
 jmp .done
.patch_publish:
 mov rdi,rdx
 mov rsi,rcx
 mov rdx,r14
 call vcs_bundle_publish
 test eax,eax
 jnz .patch_failed
 mov rbx,rdx
 cmp r15d,2
 je .patch_apply_commit
 lea rdi,[patch_imported]
 call frontend_write_str
 mov rdi,rbx
 call patch_print_id
 xor eax,eax
 jmp .done
.patch_apply_commit:
 xor edi,edi
 mov rsi,rbx
 lea rdx,[frontend_write]
 mov rcx,r14
 call vcs_pick
 test eax,eax
 jnz .patch_failed
 xor eax,eax
 jmp .done
.patch_failed:
 lea rdi,[history_error]
 jmp .error
.commit:
 cmp r13,3
 jb .bad
 mov rdi,[r12+16]
 lea rsi,[sign_option]
 call ush_streq
 test eax,eax
 jz .commit_signed
 mov rdi,[r12+16]
 lea rsi,[file_option]
 call ush_streq
 test eax,eax
 jz .commit_file
 mov rdi,[r12+16]
 lea rsi,[message_option]
 call ush_streq
 test eax,eax
 jz .commit_paragraphs
 cmp r13,3
 jne .bad
 mov edi,1
 mov rsi,[r12+16]
 jmp .history
.commit_signed:
 cmp r13,5
 jb .bad
 mov rdi,[r12+24]
 call seed_file
 test rax,rax
 jz .bad
 mov [commit_seed],rax
 mov rdi,[r12+32]
 lea rsi,[file_option]
 call ush_streq
 test eax,eax
 jz .signed_file
 mov rdi,[r12+32]
 lea rsi,[message_option]
 call ush_streq
 test eax,eax
 jz .signed_paragraphs
 cmp r13,5
 jne .bad
 mov rdi,[r12+32]
 jmp .signed_call
.signed_file:
 cmp r13,6
 jne .bad
 mov rdi,[r12+40]
 call fs_resolve
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rcx,[rax+UV_SIZE]
 test rcx,rcx
 jz .message_bad
 cmp rcx,215
 ja .message_bad
 lea rsi,[rax+UV_DATA]
 lea rdi,[commit_message]
.signed_file_copy:
 lodsb
 test al,al
 jz .message_bad
 stosb
 loop .signed_file_copy
 mov byte [rdi],0
 lea rdi,[commit_message]
 jmp .signed_call
.signed_paragraphs:
 mov r14d,4
 xor r15d,r15d
.signed_paragraph:
 lea rax,[r14+1]
 cmp rax,r13
 jae .bad
 mov rdi,[r12+r14*8]
 lea rsi,[message_option]
 call ush_streq
 test eax,eax
 jnz .bad
 lea rbx,[commit_message]
 cmp r14,4
 je .signed_paragraph_text
 cmp r15,213
 ja .message_bad
 mov word [rbx+r15],0x0a0a
 add r15,2
.signed_paragraph_text:
 mov rsi,[r12+r14*8+8]
.signed_paragraph_copy:
 lodsb
 test al,al
 jz .signed_paragraph_done
 cmp r15,215
 jae .message_bad
 mov [rbx+r15],al
 inc r15
 jmp .signed_paragraph_copy
.signed_paragraph_done:
 add r14,2
 cmp r14,r13
 jb .signed_paragraph
 mov byte [rbx+r15],0
 lea rdi,[commit_message]
.signed_call:
 mov rsi,[commit_seed]
 lea rdx,[frontend_write]
 call vcs_history_signed
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.commit_file:
 cmp r13,4
 jne .bad
 cmp qword [uxv_ready],1
 jne .bad
 mov rdi,[r12+24]
 call fs_resolve
 test rax,rax
 jz .bad
 cmp qword [rax+UV_TYPE],1
 jne .bad
 mov rcx,[rax+UV_SIZE]
 test rcx,rcx
 jz .message_bad
 cmp rcx,215
 ja .message_bad
 lea rsi,[rax+UV_DATA]
 lea rdi,[commit_message]
.file_copy:
 lodsb
 test al,al
 jz .message_bad
 stosb
 loop .file_copy
 mov byte [rdi],0
 jmp .message_ready
.commit_paragraphs:
 mov r14d,2
 xor r15d,r15d
.paragraph:
 lea rax,[r14+1]
 cmp rax,r13
 jae .bad
 mov rdi,[r12+r14*8]
 lea rsi,[message_option]
 call ush_streq
 test eax,eax
 jnz .bad
 lea rbx,[commit_message]
 cmp r14,2
 je .paragraph_text
 cmp r15,213
 ja .message_bad
 mov word [rbx+r15],0x0a0a
 add r15,2
.paragraph_text:
 mov rsi,[r12+r14*8+8]
.paragraph_copy:
 lodsb
 test al,al
 jz .paragraph_done
 cmp r15,215
 jae .message_bad
 mov [rbx+r15],al
 inc r15
 jmp .paragraph_copy
.paragraph_done:
 add r14,2
 cmp r14,r13
 jb .paragraph
 mov byte [rbx+r15],0
.message_ready:
 lea rsi,[commit_message]
 mov edi,1
 jmp .history
.message_bad:
 lea rdi,[message_error]
 jmp .error
.history:
 lea rdx,[frontend_write]
 call vcs_history
 test eax,eax
 jz .done
 lea rdi,[history_error]
 jmp .error
.bad:
 lea rdi,[bad]
 jmp .error
.limit:
 lea rdi,[limit]
.error:
 call frontend_write_str
 mov eax,2
.done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret
; Resolve an explicit 16-digit ID or a local branch name. CF reports failure.
resolve_commitish:
 push rbx
 mov rbx,rdi
 call parse_commit_id
 jnc .resolved
 mov edi,5
 mov rsi,rbx
 xor edx,edx
 lea rcx,[frontend_write]
 call vcs_ref
 test eax,eax
 jnz .failed
 mov rax,rdx
.resolved:
 clc
 pop rbx
 ret
.failed:
 stc
 pop rbx
 ret
; Exactly 16 lowercase/uppercase hexadecimal digits, nonzero.
parse_commit_id:
 xor eax,eax
 xor ecx,ecx
.id_digit:
 movzx edx,byte [rdi+rcx]
 test edx,edx
 jz .id_end
 cmp ecx,16
 jae .id_bad
 cmp dl,'0'
 jb .id_bad
 cmp dl,'9'
 jbe .id_number
 or dl,32
 cmp dl,'a'
 jb .id_bad
 cmp dl,'f'
 ja .id_bad
 sub dl,'a'-10
 jmp .id_add
.id_number:
 sub dl,'0'
.id_add:
 shl rax,4
 or al,dl
 inc ecx
 jmp .id_digit
.id_end:
 cmp ecx,16
 jne .id_bad
 test rax,rax
 jz .id_bad
 clc
 ret
.id_bad:
 stc
 ret
; RDI = path. Returns the 32-byte seed data pointer or zero.
seed_file:
 cmp qword [uxv_ready],1
 jne .seed_bad
 call fs_resolve
 test rax,rax
 jz .seed_bad
 cmp qword [rax+UV_TYPE],1
 jne .seed_bad
 cmp qword [rax+UV_SIZE],32
 jne .seed_bad
 add rax,UV_DATA
 ret
.seed_bad:
 xor eax,eax
 ret

patch_clear_node:
 xor eax,eax
 mov ecx,UV_NODE/8
 rep stosq
 ret

patch_print_id:
 lea rsi,[rendered]
 mov ecx,16
 lea rdx,[hex]
.patch_id_digit:
 rol rdi,4
 mov rax,rdi
 and eax,15
 mov al,[rdx+rax]
 mov [rsi],al
 inc rsi
 loop .patch_id_digit
 mov byte [rsi],10
 lea rdi,[rendered]
 mov esi,17
 jmp frontend_write
section .note.GNU-stack noalloc noexec nowrite progbits
