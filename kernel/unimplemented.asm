%ifndef GUARD_KERNEL_UNIMPLEMENTED_ASM
%define GUARD_KERNEL_UNIMPLEMENTED_ASM
; =============================================================================
; Tattva OS - kernel/unimplemented.asm
; =============================================================================
; GENERATED FILE - do not edit by hand.
;   Regenerate with scratchpad/gen_unimpl.py
;
; Symbols that NOTHING in the tree defines. A symbol that is defined but simply
; not %include'd does NOT belong here - the generator wires that file into the
; build instead, because a stub would silently shadow the real implementation.
;
; FUNCTION STUBS FAIL CLOSED. They return 0, which every calling convention in
; this tree reads as failure. A stub returning success would make an
; unimplemented feature look like a working one.
;
; DATA STUBS ARE ZERO-FILLED, so a caller indexing one reads zeros not garbage.
; =============================================================================

[BITS 64]

section .text

; ---- 41 unimplemented functions ----
global aes_ctr_encrypt
aes_ctr_encrypt:
    xor eax, eax
    ret

global dma_alloc_hugepage
dma_alloc_hugepage:
    xor eax, eax
    ret

global dns_parse_query
dns_parse_query:
    xor eax, eax
    ret

global ebpf_maglev_lookup
ebpf_maglev_lookup:
    xor eax, eax
    ret

global ecc_p256_verify
ecc_p256_verify:
    xor eax, eax
    ret

global hkdf_extract_expand
hkdf_extract_expand:
    xor eax, eax
    ret

global http1_parse_request
http1_parse_request:
    xor eax, eax
    ret

global ice_stun_send_binding_request
ice_stun_send_binding_request:
    xor eax, eax
    ret

global is_valid_phys_packet_buffer
is_valid_phys_packet_buffer:
    xor eax, eax
    ret

global itch_parse_message
itch_parse_message:
    xor eax, eax
    ret

global md5_hash
md5_hash:
    xor eax, eax
    ret

global ml_dsa_87_verify
ml_dsa_87_verify:
    xor eax, eax
    ret

global ml_kem_1024_decapsulate
ml_kem_1024_decapsulate:
    xor eax, eax
    ret

global ml_kem_1024_encaps
ml_kem_1024_encaps:
    xor eax, eax
    ret

global net_ring_enqueue_burst
net_ring_enqueue_burst:
    xor eax, eax
    ret

global ouch_send_order
ouch_send_order:
    xor eax, eax
    ret

global quic_close_connection
quic_close_connection:
    xor eax, eax
    ret

global quic_open_stream
quic_open_stream:
    xor eax, eax
    ret

global quic_recv_stream
quic_recv_stream:
    xor eax, eax
    ret

global quic_send_stream
quic_send_stream:
    xor eax, eax
    ret

global rsa_verify_sha256
rsa_verify_sha256:
    xor eax, eax
    ret

global run_all_memory_tests
run_all_memory_tests:
    xor eax, eax
    ret

global sha1_hash
sha1_hash:
    xor eax, eax
    ret

global slab_alloc
slab_alloc:
    xor eax, eax
    ret

global slab_free
slab_free:
    xor eax, eax
    ret

global storage_read_file_page
storage_read_file_page:
    xor eax, eax
    ret

global storage_write_file_page
storage_write_file_page:
    xor eax, eax
    ret

global uhash_sha3
uhash_sha3:
    xor eax, eax
    ret

global utls_client_handshake
utls_client_handshake:
    xor eax, eax
    ret

global utls_recv_record
utls_recv_record:
    xor eax, eax
    ret

global utls_send_record
utls_send_record:
    xor eax, eax
    ret

global utls_server_handshake
utls_server_handshake:
    xor eax, eax
    ret

global uxfs_get_file_size
uxfs_get_file_size:
    xor eax, eax
    ret

global uxfs_read_file
uxfs_read_file:
    xor eax, eax
    ret

global uxfs_write_file
uxfs_write_file:
    xor eax, eax
    ret

global virt_handle_dax_map
virt_handle_dax_map:
    xor eax, eax
    ret

global virt_handle_file_map
virt_handle_file_map:
    xor eax, eax
    ret

global virt_handle_pmem_map
virt_handle_pmem_map:
    xor eax, eax
    ret

global virt_handle_pmem_window_map
virt_handle_pmem_window_map:
    xor eax, eax
    ret


section .bss
alignb 64

; ---- 4 unimplemented data symbols ----
global UCMP_ERR_HEADER_INVALID
UCMP_ERR_HEADER_INVALID: resb 256
global msg_security_err
msg_security_err: resb 256
global tcpdump_capture
tcpdump_capture: resb 256

%endif ; GUARD_KERNEL_UNIMPLEMENTED_ASM
