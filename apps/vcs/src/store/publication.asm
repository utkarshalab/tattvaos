; Recoverable object/ownership/root publication state machine.
%include "include/vcs.inc"
%include "include/object_store.inc"
%include "include/object_index.inc"
%include "include/superblock.inc"
%include "include/ownership.inc"
%include "include/ref_catalog.inc"
%include "include/commit_object.inc"
%define VCS_PUBLICATION_IMPLEMENTATION
%include "include/publication.inc"
bits 64
default rel

extern vcs_object_id,vcs_object_index_root_verify,vcs_object_index_find
extern vcs_ownership_edge_validate,vcs_ownership_catalog_validate
extern vcs_ownership_root_verify
extern vcs_ref_root_verify,vcs_ref_key_hash
extern vcs_commit_ownership_edges
extern vcs_superblock_verify,vcs_superblock_select_latest
extern sha256_hash

section .rodata
publication_envelope_magic: db 'UVCSOBJ3'
publication_extent_magic:   db 'UVCSEXT1'

section .text
global vcs_publication_commit

; RDI=vcs_publication. The backend owns durable allocation and root switching.
vcs_publication_commit:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,200
 test rdi,rdi
 jz .usage
 mov rbx,rdi
 mov rbp,[rbx+vcs_publication.backend]
 test rbp,rbp
 jz .usage
 mov rax,[rbx+vcs_publication.root]
 test rax,rax
 jz .usage
 cmp qword [rbx+vcs_publication.root_length],VCS_SUPERBLOCK_BYTES
 jne .corrupt
 mov rdx,[rbx+vcs_publication.root_length]
 add rax,rdx
 jc .space
 cmp qword [rbx+vcs_publication.tx_sequence],0
 je .corrupt
 cmp qword [rbx+vcs_publication.generation],0
 je .corrupt
 mov rdi,[rbx+vcs_publication.root]
 call vcs_superblock_verify
 test eax,eax
 jnz .done
 mov rax,[rbx+vcs_publication.root]
 mov rdx,[rbx+vcs_publication.generation]
 cmp [rax+vcs_superblock.generation],rdx
 jne .corrupt
 mov rax,[rbx+vcs_publication.tx_sequence]
 cmp rax,-1
 je .corrupt
 inc rax
 mov rdx,[rbx+vcs_publication.root]
 cmp [rdx+vcs_superblock.next_transaction],rax
 jne .corrupt
 ; Genesis has no predecessor. Every later publication must advance exactly
 ; one validated repository generation and consume its next transaction.
 mov rax,[rbx+vcs_publication.generation]
 cmp rax,1
 jne .transition_required
 cmp qword [rbx+vcs_publication.previous_root],0
 jne .corrupt
 cmp qword [rbx+vcs_publication.tx_sequence],1
 jne .corrupt
 jmp .transition_valid
.transition_required:
 mov r12,[rbx+vcs_publication.previous_root]
 test r12,r12
 jz .usage
 mov rdi,r12
 call vcs_superblock_verify
 test eax,eax
 jnz .done
 mov rax,[rbx+vcs_publication.generation]
 dec rax
 cmp [r12+vcs_superblock.generation],rax
 jne .corrupt
 mov rax,[rbx+vcs_publication.tx_sequence]
 cmp [r12+vcs_superblock.next_transaction],rax
 jne .corrupt
 mov [rsp+104+vcs_superblock_select.first],r12
 mov rax,[rbx+vcs_publication.root]
 mov [rsp+104+vcs_superblock_select.second],rax
 mov qword [rsp+104+vcs_superblock_select.result],0
 mov qword [rsp+104+vcs_superblock_select.result_generation],0
 lea rdi,[rsp+104]
 call vcs_superblock_select_latest
 test eax,eax
 jnz .done
 mov rax,[rbx+vcs_publication.root]
 cmp [rsp+104+vcs_superblock_select.result],rax
 jne .corrupt
.transition_valid:
 mov rax,[rbx+vcs_publication.index_root]
 test rax,rax
 jz .usage
 mov rdx,[rbx+vcs_publication.generation]
 cmp [rax+vcs_object_index_root.generation],rdx
 jne .corrupt
 mov rdi,rax
 call vcs_object_index_root_verify
 test eax,eax
 jnz .done
 mov rax,[rbx+vcs_publication.index_root]
 mov rdi,[rax+vcs_object_index_root.records]
 mov rsi,[rax+vcs_object_index_root.record_count]
 mov rdx,[rbx+vcs_publication.tx_sequence]
 call validate_index_transactions_publication
 test eax,eax
 jnz .done
 mov rax,[rbx+vcs_publication.ownership_root]
 test rax,rax
 jz .usage
 mov rdx,[rbx+vcs_publication.generation]
 cmp [rax+vcs_ownership_root.generation],rdx
 jne .corrupt
 mov rdi,rax
 call vcs_ownership_root_verify
 test eax,eax
 jnz .done
 mov rax,[rbx+vcs_publication.ref_root]
 test rax,rax
 jz .usage
 mov rdx,[rbx+vcs_publication.generation]
 cmp [rax+vcs_ref_root.generation],rdx
 jne .corrupt
 mov rdi,rax
 call vcs_ref_root_verify
 test eax,eax
 jnz .done
 ; A born repository HEAD must resolve to a commit in this exact authenticated
 ; index generation. An unborn repository encodes all 32 bytes as zero.
 mov rax,[rbx+vcs_publication.root]
 mov rdx,[rax+vcs_superblock.head]
 or rdx,[rax+vcs_superblock.head+8]
 or rdx,[rax+vcs_superblock.head+16]
 or rdx,[rax+vcs_superblock.head+24]
 jz .head_valid
 mov rcx,[rbx+vcs_publication.index_root]
 mov rdx,[rcx+vcs_object_index_root.records]
 mov [rsp+56+vcs_object_index_lookup.records],rdx
 mov rdx,[rcx+vcs_object_index_root.record_count]
 mov [rsp+56+vcs_object_index_lookup.record_count],rdx
 lea rdx,[rax+vcs_superblock.head]
 mov [rsp+56+vcs_object_index_lookup.object_id],rdx
 mov qword [rsp+56+vcs_object_index_lookup.result],0
 lea rdi,[rsp+56]
 call vcs_object_index_find
 test eax,eax
 jnz .corrupt
 mov rax,[rsp+56+vcs_object_index_lookup.result]
 cmp dword [rax+vcs_object_index_record.object_type],VCS_OBJ_COMMIT
 jne .corrupt
.head_valid:
 mov rax,[rbx+vcs_publication.root]
 lea rdi,[rax+vcs_superblock.object_index_root]
 mov rax,[rbx+vcs_publication.index_root]
 mov rsi,[rax+vcs_object_index_root.root_hash]
 call ids_equal_publication
 test eax,eax
 jz .corrupt
 mov rax,[rbx+vcs_publication.root]
 lea rdi,[rax+vcs_superblock.ref_root]
 mov rax,[rbx+vcs_publication.ref_root]
 mov rsi,[rax+vcs_ref_root.root_hash]
 call ids_equal_publication
 test eax,eax
 jz .corrupt
 mov rax,[rbx+vcs_publication.root]
 lea rdi,[rax+vcs_superblock.ownership_root]
 mov rax,[rbx+vcs_publication.ownership_root]
 mov rsi,[rax+vcs_ownership_root.root_hash]
 call ids_equal_publication
 test eax,eax
 jz .corrupt
 mov rdi,rbx
 call validate_ref_targets_publication
 test eax,eax
 jnz .done
 cmp qword [rbp+vcs_publish_backend.begin],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.put_object],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.put_edge],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.stage_root],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.flush],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.publish],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.abort],0
 je .usage
 cmp qword [rbp+vcs_publish_backend.poison],0
 je .usage
 mov r12,[rbx+vcs_publication.object_count]
 test r12,r12
 jz .objects_pointer_ok
 cmp qword [rbx+vcs_publication.objects],0
 je .usage
 mov rax,r12
 mov ecx,vcs_publish_object_size
 mul rcx
 test rdx,rdx
 jnz .space
 add rax,[rbx+vcs_publication.objects]
 jc .space
.objects_pointer_ok:
 ; Sum the complete physical write set before inspecting object bytes. The
 ; backend can therefore reserve all extent blocks before starting storage.
 mov qword [rsp+168],0
 xor ecx,ecx
.count_extents:
 cmp rcx,r12
 jae .extent_total_valid
 mov rax,rcx
 imul rax,vcs_publish_object_size
 add rax,[rbx+vcs_publication.objects]
 mov rdx,[rax+vcs_publish_object.extent_count]
 add [rsp+168],rdx
 jc .space
 inc rcx
 jmp .count_extents
.extent_total_valid:
 mov r13,[rbx+vcs_publication.edge_count]
 test r13,r13
 jz .edges_pointer_ok
 cmp qword [rbx+vcs_publication.edges],0
 je .usage
 mov rax,r13
 mov ecx,vcs_ownership_edge_size
 mul rcx
 test rdx,rdx
 jnz .space
 add rax,[rbx+vcs_publication.edges]
 jc .space
.edges_pointer_ok:
 test r12,r12
 jz .transaction_owner_valid
 mov rax,[rbx+vcs_publication.transaction_owner]
 test rax,rax
 jz .usage
 mov rdx,[rax]
 or rdx,[rax+8]
 or rdx,[rax+16]
 or rdx,[rax+24]
 jz .corrupt
.transaction_owner_valid:
 mov qword [rsp+32],0
.validate_objects:
 mov r14,[rsp+32]
 cmp r14,r12
 jae .validate_edges_begin
 mov rax,r14
 imul rax,vcs_publish_object_size
 add rax,[rbx+vcs_publication.objects]
 mov [rsp+40],rax
 mov r15d,[rax+vcs_publish_object.type]
 test r15d,r15d
 jz .corrupt
 cmp r15d,10
 ja .corrupt
 cmp dword [rax+vcs_publish_object.flags],0
 jne .corrupt
 mov rcx,[rax+vcs_publish_object.length]
 test rcx,rcx
 jz .object_payload_ok
 cmp qword [rax+vcs_publish_object.payload],0
 je .usage
 mov rdx,[rax+vcs_publish_object.payload]
 add rdx,rcx
 jc .space
.object_payload_ok:
 mov edi,r15d
 mov rsi,[rax+vcs_publish_object.payload]
 mov rdx,rcx
 lea rcx,[rsp]
 call vcs_object_id
 test eax,eax
 jnz .done
 mov rax,[rsp+40]
 lea rdi,[rsp]
 lea rsi,[rax+vcs_publish_object.id]
 call ids_equal_publication
 test eax,eax
 jz .corrupt
 cmp r15d,VCS_OBJ_COMMIT
 jne .object_commit_valid
 mov rdi,rbx
 mov rsi,[rsp+40]
 call validate_staged_commit_publication
 test eax,eax
 jnz .done
.object_commit_valid:
 ; The staged set is canonical, scalable, and duplicate-free without an
 ; auxiliary allocation: callers provide strict unsigned ID order.
 test r14,r14
 jz .object_order_valid
 mov rsi,[rsp+40]
 lea rdi,[rsi-vcs_publish_object_size]
 call ids_compare_publication
 cmp eax,-1
 jne .corrupt
.object_order_valid:
 ; Validate the complete physical envelope that the backend will place at the
 ; authenticated locator. The canonical payload ID was already recomputed.
 mov rax,[rsp+40]
 mov r10,[rax+vcs_publish_object.envelope_header]
 test r10,r10
 jz .usage
 mov [rsp+48],r10
 mov rdx,[publication_envelope_magic]
 cmp [r10],rdx
 jne .corrupt
 cmp word [r10+8],1
 jne .corrupt
 cmp word [r10+10],VCS_OBJECT_ENVELOPE_BYTES
 jne .corrupt
 movzx edx,word [r10+12]
 cmp edx,[rax+vcs_publish_object.type]
 jne .corrupt
 cmp word [r10+14],1
 jne .corrupt
 cmp qword [r10+16],0
 jne .corrupt
 mov rdx,[rax+vcs_publish_object.length]
 cmp [r10+24],rdx
 jne .corrupt
 mov rcx,rdx
 add rcx,VCS_OBJECT_EXTENT_PAYLOAD-1
 jc .space
 xor edx,edx
 mov rax,rcx
 mov ecx,VCS_OBJECT_EXTENT_PAYLOAD
 div rcx
 cmp [r10+32],rax
 jne .corrupt
 mov rax,[rsp+40]
 lea rdi,[rax+vcs_publish_object.id]
 lea rsi,[r10+40]
 call ids_equal_publication
 test eax,eax
 jz .corrupt
 mov rax,[rsp+40]
 cmp qword [rax+vcs_publish_object.length],0
 je .empty_envelope
 cmp qword [r10+72],0
 je .corrupt
 jmp .envelope_locator_valid
.empty_envelope:
 cmp qword [r10+72],0
 jne .corrupt
.envelope_locator_valid:
 mov rax,[rbx+vcs_publication.tx_sequence]
 cmp [r10+80],rax
 jne .corrupt
 cmp qword [r10+120],0
 jne .corrupt
 mov rdi,r10
 mov esi,88
 lea rdx,[rsp+136]
 call sha256_hash
 mov r10,[rsp+48]
 lea rdi,[rsp+136]
 lea rsi,[r10+88]
 call ids_equal_publication
 test eax,eax
 jz .corrupt
 mov rdi,[rsp+40]
 call validate_extents_publication
 test eax,eax
 jnz .done
 ; Every staged immutable object must already exist in the authenticated index
 ; generation with the same canonical type and length.
 mov rax,[rbx+vcs_publication.index_root]
 mov rdx,[rax+vcs_object_index_root.records]
 mov [rsp+56+vcs_object_index_lookup.records],rdx
 mov rdx,[rax+vcs_object_index_root.record_count]
 mov [rsp+56+vcs_object_index_lookup.record_count],rdx
 mov rax,[rsp+40]
 lea rdx,[rax+vcs_publish_object.id]
 mov [rsp+56+vcs_object_index_lookup.object_id],rdx
 mov qword [rsp+56+vcs_object_index_lookup.result],0
 lea rdi,[rsp+56]
 call vcs_object_index_find
 test eax,eax
 jnz .corrupt
 mov rdx,[rsp+56+vcs_object_index_lookup.result]
 mov rax,[rsp+40]
 mov ecx,[rax+vcs_publish_object.type]
 cmp ecx,[rdx+vcs_object_index_record.object_type]
 jne .corrupt
 mov rcx,[rax+vcs_publish_object.length]
 cmp rcx,[rdx+vcs_object_index_record.payload_length]
 jne .corrupt
 mov rcx,[rax+vcs_publish_object.envelope]
 test rcx,rcx
 jz .corrupt
 cmp rcx,[rdx+vcs_object_index_record.envelope]
 jne .corrupt
 mov rcx,[rbx+vcs_publication.tx_sequence]
 cmp rcx,[rdx+vcs_object_index_record.transaction]
 jne .corrupt
 inc qword [rsp+32]
 jmp .validate_objects
.validate_edges_begin:
 mov rdi,[rbx+vcs_publication.edges]
 mov rsi,r13
 call vcs_ownership_catalog_validate
 test eax,eax
 jnz .done
 mov qword [rsp+32],0
.validate_edges:
 mov r14,[rsp+32]
 cmp r14,r13
 jae .begin
 mov rax,r14
 imul rax,vcs_ownership_edge_size
 mov rdi,[rbx+vcs_publication.edges]
 add rdi,rax
 mov [rsp+40],rdi
 call vcs_ownership_edge_validate
 test eax,eax
 jnz .done
 ; Every staged edge must be present in the authenticated complete candidate
 ; ownership generation, not merely in the backend insertion batch.
 mov rax,[rbx+vcs_publication.ownership_root]
 mov rdi,[rax+vcs_ownership_root.records]
 mov rsi,[rax+vcs_ownership_root.record_count]
 mov rdx,[rsp+40]
 call ownership_edge_find_publication
 test rax,rax
 jz .corrupt
 mov rdx,[rsp+40]
 mov ecx,[rdx+vcs_ownership_edge.child_type]
 cmp ecx,[rax+vcs_ownership_edge.child_type]
 jne .corrupt
 ; Every child named by a staged ownership edge must exist with the declared
 ; immutable type in the same authenticated index generation.
 mov rax,[rbx+vcs_publication.index_root]
 mov rdx,[rax+vcs_object_index_root.records]
 mov [rsp+56+vcs_object_index_lookup.records],rdx
 mov rdx,[rax+vcs_object_index_root.record_count]
 mov [rsp+56+vcs_object_index_lookup.record_count],rdx
 mov rax,[rsp+40]
 lea rdx,[rax+vcs_ownership_edge.child_id]
 mov [rsp+56+vcs_object_index_lookup.object_id],rdx
 mov qword [rsp+56+vcs_object_index_lookup.result],0
 lea rdi,[rsp+56]
 call vcs_object_index_find
 test eax,eax
 jnz .corrupt
 mov rdx,[rsp+56+vcs_object_index_lookup.result]
 mov rax,[rsp+40]
 mov ecx,[rax+vcs_ownership_edge.child_type]
 cmp ecx,[rdx+vcs_object_index_record.object_type]
 jne .corrupt
 ; Immutable object owners are object IDs too. Other owner kinds use
 ; namespace-specific durable keys and are validated by their catalogs.
 cmp dword [rax+vcs_ownership_edge.owner_kind],VCS_OWNER_IMMUTABLE
 jne .edge_membership_valid
 lea rdx,[rax+vcs_ownership_edge.owner_key]
 mov [rsp+56+vcs_object_index_lookup.object_id],rdx
 mov qword [rsp+56+vcs_object_index_lookup.result],0
 lea rdi,[rsp+56]
 call vcs_object_index_find
 test eax,eax
 jnz .corrupt
.edge_membership_valid:
 inc qword [rsp+32]
 jmp .validate_edges
.begin:
 ; Every newly staged object remains owned by this transaction until the root
 ; publication makes its durable owners authoritative. Both arrays are sorted,
 ; so one monotonic merge proves exact pin coverage without allocation.
 mov qword [rsp+88],0               ; staged object index
 mov qword [rsp+96],0               ; ownership edge index
.pin_object_loop:
 mov r8,[rsp+88]
 cmp r8,r12
 jae .pins_valid
 mov rax,r8
 imul rax,vcs_publish_object_size
 add rax,[rbx+vcs_publication.objects]
 mov [rsp+40],rax
.pin_edge_loop:
 mov r9,[rsp+96]
 cmp r9,r13
 jae .corrupt
 mov rax,r9
 imul rax,vcs_ownership_edge_size
 add rax,[rbx+vcs_publication.edges]
 mov [rsp+48],rax
 lea rdi,[rax+vcs_ownership_edge.child_id]
 mov rsi,[rsp+40]
 call ids_compare_publication
 test eax,eax
 js .pin_advance_edge
 jg .corrupt
 mov rax,[rsp+48]
 cmp dword [rax+vcs_ownership_edge.owner_kind],VCS_OWNER_TRANSACTION
 jne .pin_advance_edge
 mov rcx,[rsp+40]
 mov edx,[rcx+vcs_publish_object.type]
 cmp edx,[rax+vcs_ownership_edge.child_type]
 jne .pin_advance_edge
 lea rdi,[rax+vcs_ownership_edge.owner_key]
 mov rsi,[rbx+vcs_publication.transaction_owner]
 call ids_equal_publication
 test eax,eax
 jz .pin_advance_edge
 inc qword [rsp+96]
 inc qword [rsp+88]
 jmp .pin_object_loop
.pin_advance_edge:
 inc qword [rsp+96]
 jmp .pin_edge_loop
.pins_valid:
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_NONE
 mov rdi,[rbp+vcs_publish_backend.context]
 mov rsi,[rbx+vcs_publication.tx_sequence]
 mov rdx,r12
 mov rcx,[rsp+168]
 mov r8,r13
 call [rbp+vcs_publish_backend.begin]
 test eax,eax
 jnz .callback_done
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_BEGUN
 mov qword [rsp+32],0
.put_objects:
 mov r14,[rsp+32]
 cmp r14,r12
 jae .objects_done
 mov rax,r14
 imul rax,vcs_publish_object_size
 mov rsi,[rbx+vcs_publication.objects]
 add rsi,rax
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.put_object]
 test eax,eax
 jnz .abort_with_status
 inc qword [rsp+32]
 jmp .put_objects
.objects_done:
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_OBJECTS
 mov qword [rsp+32],0
.put_edges:
 mov r14,[rsp+32]
 cmp r14,r13
 jae .edges_done
 mov rax,r14
 imul rax,vcs_ownership_edge_size
 mov rsi,[rbx+vcs_publication.edges]
 add rsi,rax
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.put_edge]
 test eax,eax
 jnz .abort_with_status
 inc qword [rsp+32]
 jmp .put_edges
.edges_done:
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_OWNERSHIP
 mov rdi,[rbp+vcs_publish_backend.context]
 mov rsi,[rbx+vcs_publication.root]
 mov rdx,[rbx+vcs_publication.root_length]
 mov rcx,[rbx+vcs_publication.generation]
 mov rax,[rbx+vcs_publication.index_root]
 mov r8,[rax+vcs_object_index_root.root_hash]
 mov rax,[rbx+vcs_publication.ownership_root]
 mov r9,[rax+vcs_ownership_root.root_hash]
 mov rax,[rbx+vcs_publication.ref_root]
 mov rax,[rax+vcs_ref_root.root_hash]
 sub rsp,16
 mov [rsp],rax
 call [rbp+vcs_publish_backend.stage_root]
 add rsp,16
 test eax,eax
 jnz .abort_with_status
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_ROOT
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.flush]
 test eax,eax
 jnz .abort_with_status
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_FLUSHED
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.publish]
 test eax,eax
 jnz .publish_ambiguous
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_COMMITTED
 xor eax,eax
 jmp .done
.abort_with_status:
 mov [rsp+48],rax
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.abort]
 test eax,eax
 jnz .abort_failed
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_ABORTED
 mov rax,[rsp+48]
 jmp .callback_done
.abort_failed:
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.poison]
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_POISONED
 mov eax,VCS_ERR_IO
 jmp .done
.publish_ambiguous:
 mov rdi,[rbp+vcs_publish_backend.context]
 call [rbp+vcs_publish_backend.poison]
 mov qword [rbx+vcs_publication.result_phase],VCS_PUBLISH_POISONED
 mov eax,VCS_ERR_IO
 jmp .done
.callback_done:
 cmp eax,VCS_ERR_UNSUPPORTED
 jbe .done
 mov eax,VCS_ERR_IO
 jmp .done
.space:
 mov eax,VCS_ERR_NO_MEM
 jmp .done
.usage:
 mov eax,VCS_ERR_USAGE
 jmp .done
.corrupt:
 mov eax,VCS_ERR_CORRUPT
.done:
 add rsp,200
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=validated index records, RSI=count, RDX=candidate transaction sequence.
; Reject authenticated entries that claim publication by a future transaction.
validate_index_transactions_publication:
 xor ecx,ecx
.index_transaction_loop:
 cmp rcx,rsi
 jae .index_transactions_ok
 mov rax,rcx
 shl rax,6
 add rax,rdi
 cmp [rax+vcs_object_index_record.transaction],rdx
 ja .index_transactions_corrupt
 inc rcx
 jmp .index_transaction_loop
.index_transactions_ok:
 xor eax,eax
 ret
.index_transactions_corrupt:
 mov eax,VCS_ERR_CORRUPT
 ret

ids_equal_publication:
 mov rax,[rdi]
 xor rax,[rsi]
 mov rcx,[rdi+8]
 xor rcx,[rsi+8]
 or rax,rcx
 mov rcx,[rdi+16]
 xor rcx,[rsi+16]
 or rax,rcx
 mov rcx,[rdi+24]
 xor rcx,[rsi+24]
 or rax,rcx
 setz al
 movzx eax,al
 ret

; RDI=vcs_publish_object. Validate every allocator locator and staged 4 KiB
; extent against the already authenticated canonical payload and envelope.
validate_extents_publication:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,8
 mov rbx,rdi
 mov rbp,[rbx+vcs_publish_object.length]
 mov r14,[rbx+vcs_publish_object.extent_count]
 mov rax,rbp
 add rax,VCS_OBJECT_EXTENT_PAYLOAD-1
 jc .extent_space
 xor edx,edx
 mov ecx,VCS_OBJECT_EXTENT_PAYLOAD
 div rcx
 cmp r14,rax
 jne .extent_corrupt
 test rbp,rbp
 jz .extent_empty
 mov r12,[rbx+vcs_publish_object.extents]
 mov r13,[rbx+vcs_publish_object.locators]
 test r12,r12
 jz .extent_usage
 test r13,r13
 jz .extent_usage
 mov rax,r14
 mov ecx,VCS_OBJECT_EXTENT_BYTES
 mul rcx
 test rdx,rdx
 jnz .extent_space
 add rax,r12
 jc .extent_space
 mov rax,r14
 mov ecx,8
 mul rcx
 test rdx,rdx
 jnz .extent_space
 add rax,r13
 jc .extent_space
 mov rax,[r13]
 test rax,rax
 jz .extent_corrupt
 mov rcx,[rbx+vcs_publish_object.envelope_header]
 cmp [rcx+72],rax
 jne .extent_corrupt
 xor r14d,r14d
 xor r15d,r15d
.extent_loop:
 cmp r14,[rbx+vcs_publish_object.extent_count]
 jae .extent_complete
 mov rax,[r13+r14*8]
 test rax,rax
 jz .extent_corrupt
 test r14,r14
 jz .extent_unique
 cmp rax,[r13+r14*8-8]
 jbe .extent_corrupt
.extent_unique:
 mov rax,r14
 shl rax,12
 lea r11,[r12+rax]
 mov rax,[publication_extent_magic]
 cmp [r11],rax
 jne .extent_corrupt
 cmp word [r11+8],1
 jne .extent_corrupt
 lea rax,[r14+1]
 cmp rax,[rbx+vcs_publish_object.extent_count]
 sete dl
 movzx edx,dl
 cmp word [r11+10],dx
 jne .extent_corrupt
 mov rax,rbp
 sub rax,r15
 cmp rax,VCS_OBJECT_EXTENT_PAYLOAD
 jbe .extent_size_ready
 mov eax,VCS_OBJECT_EXTENT_PAYLOAD
.extent_size_ready:
 cmp [r11+12],eax
 jne .extent_corrupt
 lea rdi,[rbx+vcs_publish_object.id]
 lea rsi,[r11+16]
 call ids_equal_publication
 test eax,eax
 jz .extent_corrupt
 cmp [r11+48],r14
 jne .extent_corrupt
 lea rax,[r14+1]
 cmp rax,[rbx+vcs_publish_object.extent_count]
 jae .extent_final_link
 mov rax,[r13+rax*8]
 test rax,rax
 jz .extent_corrupt
 cmp [r11+56],rax
 jne .extent_corrupt
 jmp .extent_payload
.extent_final_link:
 cmp qword [r11+56],0
 jne .extent_corrupt
.extent_payload:
 mov ecx,[r11+12]
 lea rdi,[r11+64]
 mov rsi,[rbx+vcs_publish_object.payload]
 add rsi,r15
 repe cmpsb
 jne .extent_corrupt
 mov ecx,VCS_OBJECT_EXTENT_PAYLOAD
 sub ecx,[r11+12]
 xor eax,eax
.extent_padding:
 test rcx,rcx
 jz .extent_next
 cmp byte [rdi],al
 jne .extent_corrupt
 inc rdi
 dec rcx
 jmp .extent_padding
.extent_next:
 mov eax,[r11+12]
 add r15,rax
 inc r14
 jmp .extent_loop
.extent_complete:
 cmp r15,rbp
 jne .extent_corrupt
 xor eax,eax
 jmp .extent_done
.extent_empty:
 test r14,r14
 jnz .extent_corrupt
 xor eax,eax
 jmp .extent_done
.extent_space:
 mov eax,VCS_ERR_NO_MEM
 jmp .extent_done
.extent_usage:
 mov eax,VCS_ERR_USAGE
 jmp .extent_done
.extent_corrupt:
 mov eax,VCS_ERR_CORRUPT
.extent_done:
 add rsp,8
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=canonical ownership records, RSI=count, RDX=target. RAX=record or zero.
ownership_edge_find_publication:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 xor r14d,r14d
.ownership_find_loop:
 cmp r14,r12
 jae .ownership_find_missing
 mov rax,r14
 add rax,r12
 shr rax,1
 mov r15,rax
 imul rax,vcs_ownership_edge_size
 lea rdi,[rbx+rax]
 mov rsi,r13
 call ownership_edge_compare_publication
 test eax,eax
 jz .ownership_find_hit
 js .ownership_find_raise
 mov r12,r15
 jmp .ownership_find_loop
.ownership_find_raise:
 lea r14,[r15+1]
 jmp .ownership_find_loop
.ownership_find_hit:
 mov rax,r15
 imul rax,vcs_ownership_edge_size
 add rax,rbx
 jmp .ownership_find_done
.ownership_find_missing:
 xor eax,eax
.ownership_find_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI/RSI=edges. Compare child ID, owner kind, then owner key.
ownership_edge_compare_publication:
 push rbx
 push r12
 mov rbx,rdi
 mov r12,rsi
 lea rdi,[rdi+vcs_ownership_edge.child_id]
 lea rsi,[rsi+vcs_ownership_edge.child_id]
 call ids_compare_publication
 test eax,eax
 jnz .ownership_compare_done
 mov eax,[rbx+vcs_ownership_edge.owner_kind]
 cmp eax,[r12+vcs_ownership_edge.owner_kind]
 jb .ownership_compare_less
 ja .ownership_compare_greater
 lea rdi,[rbx+vcs_ownership_edge.owner_key]
 lea rsi,[r12+vcs_ownership_edge.owner_key]
 call ids_compare_publication
 jmp .ownership_compare_done
.ownership_compare_less:
 mov eax,-1
 jmp .ownership_compare_done
.ownership_compare_greater:
 mov eax,1
.ownership_compare_done:
 pop r12
 pop rbx
 ret

; RDI=publication, RSI=staged commit. Require every canonical dependency edge
; in both the insertion batch and authenticated candidate ownership catalog.
validate_staged_commit_publication:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,296
 mov rbx,rdi
 mov rbp,rsi
 mov rax,[rbp+vcs_publish_object.payload]
 mov [rsp+vcs_commit_ownership.payload],rax
 mov rax,[rbp+vcs_publish_object.length]
 mov [rsp+vcs_commit_ownership.length],rax
 lea rax,[rbp+vcs_publish_object.id]
 mov [rsp+vcs_commit_ownership.commit_id],rax
 lea rax,[rsp+48]
 mov [rsp+vcs_commit_ownership.edges],rax
 mov qword [rsp+vcs_commit_ownership.edge_capacity],3
 mov qword [rsp+vcs_commit_ownership.result_edges],0
 mov rdi,rsp
 call vcs_commit_ownership_edges
 test eax,eax
 jnz .staged_commit_done
 xor r12d,r12d
.staged_commit_edge_loop:
 cmp r12,[rsp+vcs_commit_ownership.result_edges]
 jae .staged_commit_ok
 mov rax,r12
 imul rax,vcs_ownership_edge_size
 lea r14,[rsp+48+rax]
 mov rax,[rbx+vcs_publication.ownership_root]
 mov rdi,[rax+vcs_ownership_root.records]
 mov rsi,[rax+vcs_ownership_root.record_count]
 mov rdx,r14
 call ownership_edge_find_publication
 test rax,rax
 jz .staged_commit_corrupt
 mov ecx,[r14+vcs_ownership_edge.child_type]
 cmp ecx,[rax+vcs_ownership_edge.child_type]
 jne .staged_commit_corrupt
 xor r13d,r13d
.staged_commit_batch_loop:
 cmp r13,[rbx+vcs_publication.edge_count]
 jae .staged_commit_corrupt
 mov rax,r13
 imul rax,vcs_ownership_edge_size
 add rax,[rbx+vcs_publication.edges]
 mov r15,rax
 mov rdi,rax
 mov rsi,r14
 call ownership_edge_compare_publication
 test eax,eax
 jnz .staged_commit_batch_next
 mov eax,[r15+vcs_ownership_edge.child_type]
 cmp eax,[r14+vcs_ownership_edge.child_type]
 je .staged_commit_edge_found
.staged_commit_batch_next:
 inc r13
 jmp .staged_commit_batch_loop
.staged_commit_edge_found:
 inc r12
 jmp .staged_commit_edge_loop
.staged_commit_ok:
 xor eax,eax
 jmp .staged_commit_done
.staged_commit_corrupt:
 mov eax,VCS_ERR_CORRUPT
.staged_commit_done:
 add rsp,296
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=vcs_publication. Direct refs must resolve to commits in the authenticated
; object index and own them through the authenticated ownership catalog. The
; sole symbolic workspace HEAD names a branch key and adds no second owner.
validate_ref_targets_publication:
 push rbp
 push rbx
 push r12
 push r13
 push r14
 push r15
 sub rsp,88
 mov rbx,rdi
 mov rax,[rbx+vcs_publication.ref_root]
 mov r12,[rax+vcs_ref_root.records]
 mov r13,[rax+vcs_ref_root.record_bytes]
 add r13,r12
 jc .ref_targets_corrupt
.ref_target_loop:
 cmp r12,r13
 jae .ref_targets_ok
 test word [r12+2],VCS_REF_SYMBOLIC
 jnz .ref_symbolic
 mov rax,[rbx+vcs_publication.index_root]
 mov rdi,[rax+vcs_object_index_root.records]
 mov rsi,[rax+vcs_object_index_root.record_count]
 lea rdx,[r12+16]
 call object_index_find_trusted_publication
 test rax,rax
 jz .ref_targets_corrupt
 cmp dword [rax+vcs_object_index_record.object_type],VCS_OBJ_COMMIT
 jne .ref_targets_corrupt
 mov dword [rsp+vcs_ownership_edge.owner_kind],VCS_OWNER_REF
 mov dword [rsp+vcs_ownership_edge.child_type],VCS_OBJ_COMMIT
 mov qword [rsp+vcs_ownership_edge.flags],0
 mov rdi,r12
 lea rsi,[rsp+vcs_ownership_edge.owner_key]
 call vcs_ref_key_hash
 test eax,eax
 jnz .ref_targets_corrupt
 mov rax,[r12+16]
 mov [rsp+vcs_ownership_edge.child_id],rax
 mov rax,[r12+24]
 mov [rsp+vcs_ownership_edge.child_id+8],rax
 mov rax,[r12+32]
 mov [rsp+vcs_ownership_edge.child_id+16],rax
 mov rax,[r12+40]
 mov [rsp+vcs_ownership_edge.child_id+24],rax
 mov rax,[rbx+vcs_publication.ownership_root]
 mov rdi,[rax+vcs_ownership_root.records]
 mov rsi,[rax+vcs_ownership_root.record_count]
 mov rdx,rsp
 call ownership_edge_find_publication
 test rax,rax
 jz .ref_targets_corrupt
 jmp .ref_target_next
.ref_symbolic:
 mov rax,[rbx+vcs_publication.ref_root]
 mov r15,[rax+vcs_ref_root.records]
.ref_symbolic_scan:
 cmp r15,r13
 jae .ref_targets_corrupt
 cmp byte [r15],VCS_REF_BRANCH
 jne .ref_symbolic_next
 mov rdi,r15
 lea rsi,[rsp+vcs_ownership_edge.owner_key]
 call vcs_ref_key_hash
 test eax,eax
 jnz .ref_targets_corrupt
 lea rdi,[rsp+vcs_ownership_edge.owner_key]
 lea rsi,[r12+16]
 call ids_equal_publication
 test eax,eax
 jz .ref_symbolic_next
 mov rax,[rbx+vcs_publication.root]
 lea rdi,[r15+16]
 lea rsi,[rax+vcs_superblock.head]
 call ids_equal_publication
 test eax,eax
 jz .ref_targets_corrupt
 jmp .ref_target_next
.ref_symbolic_next:
 movzx eax,byte [r15+1]
 add rax,7
 and rax,-8
 add rax,VCS_REF_HEADER
 add r15,rax
 jc .ref_targets_corrupt
 jmp .ref_symbolic_scan
.ref_target_next:
 movzx eax,byte [r12+1]
 add rax,7
 and rax,-8
 add rax,VCS_REF_HEADER
 add r12,rax
 jc .ref_targets_corrupt
 jmp .ref_target_loop
.ref_targets_ok:
 xor eax,eax
 jmp .ref_targets_done
.ref_targets_corrupt:
 mov eax,VCS_ERR_CORRUPT
.ref_targets_done:
 add rsp,88
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 pop rbp
 ret

; RDI=already authenticated index records, RSI=count, RDX=ID.
; RAX=matching record or zero. No repeated full-catalog validation.
object_index_find_trusted_publication:
 push rbx
 push r12
 push r13
 push r14
 push r15
 mov rbx,rdi
 mov r12,rsi
 mov r13,rdx
 xor r14d,r14d
.trusted_index_loop:
 cmp r14,r12
 jae .trusted_index_missing
 mov r15,r14
 add r15,r12
 shr r15,1
 mov rax,r15
 shl rax,6
 lea rdi,[rbx+rax]
 mov rsi,r13
 call ids_compare_publication
 test eax,eax
 jz .trusted_index_hit
 js .trusted_index_raise
 mov r12,r15
 jmp .trusted_index_loop
.trusted_index_raise:
 lea r14,[r15+1]
 jmp .trusted_index_loop
.trusted_index_hit:
 mov rax,r15
 shl rax,6
 add rax,rbx
 jmp .trusted_index_done
.trusted_index_missing:
 xor eax,eax
.trusted_index_done:
 pop r15
 pop r14
 pop r13
 pop r12
 pop rbx
 ret

; RDI/RSI=32-byte IDs. EAX=-1,0,1 for unsigned lexicographic ordering.
ids_compare_publication:
 xor ecx,ecx
.compare_loop:
 movzx eax,byte [rdi+rcx]
 movzx edx,byte [rsi+rcx]
 cmp eax,edx
 jb .compare_less
 ja .compare_greater
 inc ecx
 cmp ecx,32
 jb .compare_loop
 xor eax,eax
 ret
.compare_less:
 mov eax,-1
 ret
.compare_greater:
 mov eax,1
 ret

section .note.GNU-stack noalloc noexec nowrite progbits
