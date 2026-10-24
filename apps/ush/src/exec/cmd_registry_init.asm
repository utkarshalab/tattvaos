; Only implemented commands are registered; old builtin scaffolds are not linked.
%include "inc/cmd_registry.inc"
bits 64
default rel
extern exec_register_command,cmd_registry_root
extern cmd_echo,cmd_help,cmd_exit,cmd_true,cmd_false,cmd_status,cmd_env
extern cmd_export,cmd_unset,cmd_history,cmd_calc,cmd_version
extern cmd_pwd,cmd_ls,cmd_cd,cmd_cat,cmd_touch,cmd_mkdir,cmd_cp,cmd_mv,cmd_write
extern cmd_rm,cmd_rmdir,cmd_stat,cmd_df,cmd_du,cmd_append,cmd_head,cmd_tail,cmd_wc,cmd_grep,cmd_find,cmd_hexdump,cmd_clear,cmd_uptime,cmd_sleep,cmd_shutdown,cmd_reboot
extern cmd_uedit
section .rodata
%macro NAME 3
 %1_name: db %2,0
 %1_help: db %3,0
%endmacro
NAME echo,'echo','echo [-n] [arguments...]'
NAME help,'help','List implemented commands'
NAME exit,'exit','exit [0..255]'
NAME true,'true','Return success'
NAME false,'false','Return failure'
NAME status,'status','Show previous command status (also $? expansion)'
NAME env,'env','List shell variables'
NAME export,'export','export [NAME=VALUE ...]'
NAME unset,'unset','unset NAME [NAME ...]'
NAME history,'history','history [-c]'
NAME calc,'calc','calc [mode] "expression"; no arguments enters calculator'
NAME version,'version','Show shell version'
NAME pwd,'pwd','Print working directory'
NAME ls,'ls','ls [directory]'
NAME cd,'cd','cd [directory]'
NAME cat,'cat','cat FILE'
NAME touch,'touch','touch FILE - create empty file, preserve existing contents'
NAME mkdir,'mkdir','mkdir DIRECTORY'
NAME cp,'cp','cp SOURCE DEST - regular files, no overwrite'
NAME mv,'mv','mv SOURCE DEST - files/directories, no overwrite'
NAME write,'write','write FILE TEXT - replace file contents'
NAME rm,'rm','rm FILE - delete a regular file'
NAME rmdir,'rmdir','rmdir DIRECTORY - remove an empty directory'
NAME stat,'stat','stat PATH - show type, byte size and path'
NAME df,'df','Show used/free records and logical data bytes'
NAME du,'du','du [PATH] - logical bytes in a file or directory tree'
NAME append,'append','append FILE TEXT - append or create'
NAME head,'head','head [-n COUNT] FILE - first lines (default 10)'
NAME tail,'tail','tail [-n COUNT] FILE - last lines (default 10)'
NAME wc,'wc','wc FILE - newline, word and byte counts'
NAME grep,'grep','grep TEXT FILE - literal matching lines'
NAME find,'find','find [DIR [NAME]] - exact basename search'
NAME hexdump,'hexdump','hexdump FILE - hex and printable ASCII'
NAME clear,'clear','Clear VT terminal display'
NAME uptime,'uptime','Show seconds since system boot'
NAME sleep,'sleep','sleep SECONDS - 0..86400, yields to scheduler'
NAME shutdown,'shutdown','Flush storage and power off the native guest'
NAME reboot,'reboot','Flush storage and reboot the native guest'
NAME uedit,'uedit','uedit FILE - terminal text editor, Ctrl-S save / Ctrl-Q quit'
section .data
%macro ENTRY 4
%1_entry:
 istruc cmd_entry_t
 at cmd_entry_t.magic, dd 0x434d4401
 at cmd_entry_t.name, dq %1_name
 at cmd_entry_t.handler, dq %2
 at cmd_entry_t.help, dq %1_help
 at cmd_entry_t.flags, dd CMD_FLAG_BUILTIN
 at cmd_entry_t.min_args, dd %3
 at cmd_entry_t.max_args, dd %4
 iend
%endmacro
ENTRY echo,cmd_echo,1,256
ENTRY help,cmd_help,1,1
ENTRY exit,cmd_exit,1,2
ENTRY true,cmd_true,1,1
ENTRY false,cmd_false,1,1
ENTRY status,cmd_status,1,1
ENTRY env,cmd_env,1,1
ENTRY export,cmd_export,1,256
ENTRY unset,cmd_unset,2,256
ENTRY history,cmd_history,1,2
ENTRY calc,cmd_calc,1,3
ENTRY version,cmd_version,1,1
ENTRY pwd,cmd_pwd,1,1
ENTRY ls,cmd_ls,1,2
ENTRY cd,cmd_cd,1,2
ENTRY cat,cmd_cat,2,2
ENTRY touch,cmd_touch,2,2
ENTRY mkdir,cmd_mkdir,2,2
ENTRY cp,cmd_cp,3,3
ENTRY mv,cmd_mv,3,3
ENTRY write,cmd_write,3,3
ENTRY rm,cmd_rm,2,2
ENTRY rmdir,cmd_rmdir,2,2
ENTRY stat,cmd_stat,2,2
ENTRY df,cmd_df,1,1
ENTRY du,cmd_du,1,2
ENTRY append,cmd_append,3,3
ENTRY head,cmd_head,2,4
ENTRY tail,cmd_tail,2,4
ENTRY wc,cmd_wc,2,2
ENTRY grep,cmd_grep,3,3
ENTRY find,cmd_find,1,3
ENTRY hexdump,cmd_hexdump,2,2
ENTRY clear,cmd_clear,1,1
ENTRY uptime,cmd_uptime,1,1
ENTRY sleep,cmd_sleep,2,2
ENTRY shutdown,cmd_shutdown,1,1
ENTRY reboot,cmd_reboot,1,1
ENTRY uedit,cmd_uedit,2,2
section .data.rel.ro
entries: dq uedit_entry,rm_entry,rmdir_entry,stat_entry,df_entry,du_entry,append_entry,head_entry,tail_entry,wc_entry,grep_entry,find_entry,hexdump_entry,clear_entry,uptime_entry,sleep_entry,shutdown_entry,reboot_entry,pwd_entry,ls_entry,cd_entry,cat_entry,touch_entry,mkdir_entry,cp_entry,mv_entry,write_entry,version_entry,calc_entry,history_entry,unset_entry,export_entry,env_entry,status_entry,false_entry,true_entry,exit_entry,help_entry,echo_entry
entries_end:
section .text
global cmd_registry_init
cmd_registry_init:
 push rbx
 mov qword [cmd_registry_root],0
 lea rbx,[entries]
.loop:
 mov rdi,[rbx]
 call exec_register_command
 add rbx,8
 lea rax,[entries_end]
 cmp rbx,rax
 jb .loop
 pop rbx
 ret
section .note.GNU-stack noalloc noexec nowrite progbits
