bits 64
default rel
extern git_tree_plan,git_tree_collect_entries,git_tree_hash_entries
extern git_tree_emit_entries,git_pack_finish
global tree_plan_probe,tree_collect_probe,tree_hash_probe,tree_emit_probe
global tree_finish_probe,tree_probe_status,tree_probe_value

section .bss
tree_probe_status: resq 1
tree_probe_value: resq 1

section .text
tree_plan_probe:
 call git_tree_plan
 jmp capture
tree_collect_probe:
 call git_tree_collect_entries
 jmp capture
tree_hash_probe:
 call git_tree_hash_entries
 jmp capture
tree_emit_probe:
 call git_tree_emit_entries
 jmp capture
tree_finish_probe:
 call git_pack_finish
capture:
 mov [tree_probe_status],rax
 mov [tree_probe_value],rdx
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
