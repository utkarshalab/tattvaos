; =============================================================================
; Tattva OS — unet/tools/diag/tcpdump_asm.asm
; =============================================================================
; Packet Capture (net tcpdump / PCAP) Tool with Direct UXFS Storage Streaming.
;
; Delegates:
;   - Raw PCAP File Logging           -> storage/uxfs/journal/ & storage/uxfs/uxfs.asm
;   - High-Precision Cycle Timestamp  -> lib/time/tsc.asm (`rdtsc_get_cycles`)
;   - In-NIC Hardware Filter Offload  -> unet/ebpf/smartnic_offload.asm
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"

%define PCAP_MAGIC_NUMBER           0xA1B2C3D4
%define PCAP_VERSION_MAJOR          2
%define PCAP_VERSION_MINOR          4

struc pcap_file_hdr_t
    .magic:             resd 1      ; 0xA1B2C3D4
    .version_major:     resw 1      ; 2
    .version_minor:     resw 1      ; 4
    .thiszone:          resd 1      ; GMT offset
    .sigfigs:           resd 1      ; Accuracy
    .snaplen:           resd 1      ; Max packet capture length (65535)
    .network:           resd 1      ; Data Link Type (1 = Ethernet)
endstruc

section .text

global net_tcpdump_handler
global tcpdump_write_pcap_ufs

extern uxfs_write_file
extern rdtsc_get_cycles

align 32
net_tcpdump_handler:
    push rbp
    mov rbp, rsp
    ; Parse CLI arguments ("net tcpdump -i eth0 -w /var/log/pcap/capture.pcap")
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; tcpdump_write_pcap_ufs — Stream Captured Packet Header + Payload to UXFS File
; Input: RDI = Pointer to net_pkt_t, RSI = Target File Path
; -----------------------------------------------------------------------------
align 32
tcpdump_write_pcap_ufs:
    push rbp
    mov rbp, rsp
    push rbx

    mov rbx, rdi
    ; Fetch hardware nanosecond cycle timestamp from lib/time/tsc.asm
    call rdtsc_get_cycles

    ; Stream PCAP packet record directly into UXFS storage journal log
    call uxfs_write_file

    pop rbx
    pop rbp
    ret
