; Arena-backed open-addressed byte-string map.
%include "inc/abi.inc"
%include "inc/macros.inc"
%include "inc/errors.inc"

%define M_ENTRIES 0
%define M_CAP 8
%define M_MASK 16
%define M_COUNT 24
%define M_ARENA 32
%define E_KEY 0
%define E_LEN 8
%define E_HASH 16
%define E_VALUE 24
%define E_SIZE 32
%define TOMBSTONE -1
extern fnv1a_hash

section .text
global map_init
map_init:
    PROLOGUE_SAVE rbx, r12, r13
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    test rbx,rbx
    jz .bad
    test r12,r12
    jz .bad
    cmp r13,16
    jae .round
    mov r13,16
.round:
    mov rax,r13
    dec rax
    test rax,r13
    jz .alloc
    bsr rcx,r13
    inc ecx
    mov r13,1
    shl r13,cl
.alloc:
    mov rdi,r12
    mov rsi,r13
    shl rsi,5
    call arena_alloc
    test rax,rax
    jz .oom
    mov [rbx+M_ENTRIES],rax
    mov [rbx+M_CAP],r13
    lea rcx,[r13-1]
    mov [rbx+M_MASK],rcx
    mov qword [rbx+M_COUNT],0
    mov [rbx+M_ARENA],r12
    mov rdi,rax
    xor esi,esi
    mov rdx,r13
    shl rdx,5
    call memset
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13
    ret
.bad: mov rax,-EINVAL
    EPILOGUE_RESTORE rbx,r12,r13
    ret
.oom: mov rax,-ENOMEM
    EPILOGUE_RESTORE rbx,r12,r13
    ret

; Probe. IN map,key,len,hash. OUT rax=entry*, rdx=1 found/0 insertion.
map_probe:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    mov rax,r14
    and rax,[rbx+M_MASK]
    mov rcx,[rbx+M_CAP]
    xor r15d,r15d
.loop:
    test rcx,rcx
    jz .full
    mov rdx,rax
    shl rdx,5
    add rdx,[rbx+M_ENTRIES]
    mov rdi,[rdx+E_KEY]
    test rdi,rdi
    jz .empty
    cmp rdi,TOMBSTONE
    je .tomb
    cmp [rdx+E_HASH],r14
    jne .next
    cmp [rdx+E_LEN],r13
    jne .next
    push rcx
    push rax
    push rdx
    mov rsi,r12
    mov rcx,r13
    repe cmpsb
    pop rdx
    pop rax
    pop rcx
    je .found
.next:
    inc rax
    and rax,[rbx+M_MASK]
    dec rcx
    jmp .loop
.tomb:
    test r15,r15
    cmovz r15,rdx
    jmp .next
.empty:
    test r15,r15
    cmovnz rdx,r15
    mov rax,rdx
    xor edx,edx
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.found:
    mov rax,rdx
    mov edx,1
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.full:
    mov rax,r15
    xor edx,edx
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

; Rehash into a table twice as large.
map_grow:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,[rbx+M_ENTRIES]
    mov r13,[rbx+M_CAP]
    mov r14,r13
    shl r14,1
    jc .oom
    mov rdi,[rbx+M_ARENA]
    mov rsi,r14
    shl rsi,5
    call arena_alloc
    test rax,rax
    jz .oom
    mov r15,rax
    mov rdi,r15
    xor esi,esi
    mov rdx,r14
    shl rdx,5
    call memset
    mov [rbx+M_ENTRIES],r15
    mov [rbx+M_CAP],r14
    lea rax,[r14-1]
    mov [rbx+M_MASK],rax
    xor ecx,ecx
.rehash:
    cmp rcx,r13
    jae .ok
    mov rax,rcx
    shl rax,5
    lea r15,[r12+rax]
    mov rsi,[r15+E_KEY]
    test rsi,rsi
    jz .next
    cmp rsi,TOMBSTONE
    je .next
    push rcx
    mov rdi,rbx
    mov rdx,[r15+E_LEN]
    mov rcx,[r15+E_HASH]
    call map_probe
    mov rcx,[rsp]
    mov rdi,rax
    mov rsi,r15
    mov rdx,E_SIZE
    call memcopy
    pop rcx
.next: inc rcx
    jmp .rehash
.ok: xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.oom: mov rax,-ENOMEM
    EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret

global map_put
map_put:
    PROLOGUE_SAVE rbx,r12,r13,r14,r15
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov r14,rcx
    test r12,r12
    jz .bad
    mov rax,[rbx+M_COUNT]
    inc rax
    shl rax,2
    mov rcx,[rbx+M_CAP]
    imul rcx,rcx,3
    cmp rax,rcx
    jbe .hash
    mov rdi,rbx
    call map_grow
    test rax,rax
    js .out
.hash:
    mov rdi,r12
    mov rsi,r13
    call fnv1a_hash
    mov r15,rax
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    mov rcx,r15
    call map_probe
    test rax,rax
    jz .oom
    test rdx,rdx
    jnz .value
    mov [rax+E_KEY],r12
    mov [rax+E_LEN],r13
    mov [rax+E_HASH],r15
    inc qword [rbx+M_COUNT]
.value: mov [rax+E_VALUE],r14
    xor eax,eax
.out: EPILOGUE_RESTORE rbx,r12,r13,r14,r15
    ret
.bad: mov rax,-EINVAL
    jmp .out
.oom: mov rax,-ENOMEM
    jmp .out

global map_get
map_get:
    PROLOGUE_SAVE rbx,r12,r13
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov rdi,r12
    mov rsi,r13
    call fnv1a_hash
    mov rcx,rax
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call map_probe
    test rdx,rdx
    jz .none
    mov rax,[rax+E_VALUE]
    EPILOGUE_RESTORE rbx,r12,r13
    ret
.none: xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13
    ret

global map_remove
map_remove:
    PROLOGUE_SAVE rbx,r12,r13
    mov rbx,rdi
    mov r12,rsi
    mov r13,rdx
    mov rdi,r12
    mov rsi,r13
    call fnv1a_hash
    mov rcx,rax
    mov rdi,rbx
    mov rsi,r12
    mov rdx,r13
    call map_probe
    test rdx,rdx
    jz .missing
    mov qword [rax+E_KEY],TOMBSTONE
    mov qword [rax+E_VALUE],0
    dec qword [rbx+M_COUNT]
    xor eax,eax
    EPILOGUE_RESTORE rbx,r12,r13
    ret
.missing: mov rax,-ENOENT
    EPILOGUE_RESTORE rbx,r12,r13
    ret

global map_count
map_count: mov rax,[rdi+M_COUNT]
    ret
global map_clear
map_clear:
    PROLOGUE_SAVE rbx
    mov rbx,rdi
    mov rdi,[rbx+M_ENTRIES]
    xor esi,esi
    mov rdx,[rbx+M_CAP]
    shl rdx,5
    call memset
    mov qword [rbx+M_COUNT],0
    xor eax,eax
    EPILOGUE_RESTORE rbx
    ret
section .data
global map_version
map_version: dq 0x010100
