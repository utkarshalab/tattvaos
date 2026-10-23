%ifndef GUARD_UNET_UNET_ASM
%define GUARD_UNET_UNET_ASM
; =============================================================================
; Utkarsha OS — unet/unet.asm
; =============================================================================
; Master Network Stack Engine & Universal Protocol Dispatcher.
;
; Consolidates all 39 single-word pure domain sub-systems across unet/:
;   - Core (l2/, l3/, l4/, sys/, link/), HTTP, DNS, Mail, Proxy, Identity, Security,
;     SSH, VPN, PQC, Cloud, SDN, CNI, Routing, HA, HPC, HFT, Fintech, SCADA, Telecom,
;     Optical, Space, Wireless, Automotive, Avionics, Video, VoIP, Gaming, SAN,
;     CGNAT, QoS, AI, eBPF, Mesh, Anon, Drivers, Services, Tools, Include, Tests.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "lib/unet/unet.inc"
%include "lib/unet/include/unet_abi.inc"
%include "lib/unet/tools/tools.inc"

section .text

global unet_init
global unet_poll
global unet_shutdown

align 64
unet_init:
    push rbp
    mov rbp, rsp

    call pktbuf_init
    call eth_init
    call arp_init
    call pmtud_init
    call ip_init
    call ipv6_init
    call udp_init
    call tcp_init
    call socket_table_init
    call http1_init

    ; Initialize batch RX/TX API
    call batch_rx_init
    call batch_tx_init

    ; Static config until a real DHCP client exists (unet/services/dhcp.asm
    ; is still a stub) — QEMU's default usermode network (`-netdev user`)
    ; hands out 10.0.2.15/24 with a gateway at 10.0.2.2, so that's what's
    ; hardcoded here rather than something that only works on a real LAN.
    mov edi, 0x0F02000A              ; 10.0.2.15, network byte order
    mov esi, 0x00FFFFFF              ; 255.255.255.0, network byte order
    mov edx, 0x0202000A              ; 10.0.2.2, network byte order
    call unet_ip_configure

    ; Register every NIC driver this stack has, then probe the PCI bus once.
    ; A driver whose hardware isn't present just never gets its probe_fn
    ; called — e1000_present stays 0 and net_link_transmit/unet_poll no-op.
    call e1000_register_driver
    call pci_enumerate

    xor eax, eax
    pop rbp
    ret

align 64
unet_poll:
    push rbp
    mov rbp, rsp
    call e1000_poll
    ; Advance timer wheel (1ms tick)
    mov rdi, timer_wheel
    call timer_wheel_tick
    pop rbp
    ret

align 64
unet_shutdown:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; Master Protocol Suite Includes (All Pure Domain Directories)
; -----------------------------------------------------------------------------

; 1. Core Stack (l2/, l3/, l4/, sys/, link/)
%include "lib/unet/core/sys/pktbuf.asm"
%include "lib/unet/core/l2/eth.asm"
%include "lib/unet/core/l2/arp.asm"
%include "lib/unet/core/l2/mac.asm"
%include "lib/unet/core/l3/ip.asm"
%include "lib/unet/core/l3/ipv6_tcp.asm"
%include "lib/unet/core/l3/ipv4_pmtud.asm"
%include "lib/unet/core/l3/icmp.asm"
%include "lib/unet/core/l3/igmp.asm"
%include "lib/unet/core/l4/udp.asm"
%include "lib/unet/core/l4/tcp_rack.asm"
%include "lib/unet/core/l4/tcp.asm"
%include "lib/unet/core/l4/tcp_bbrv2.asm"
%include "lib/unet/core/l4/tcp_cubic.asm"
%include "lib/unet/core/l4/tcp_syncookie.asm"
%include "lib/unet/core/l4/tcp_ecn.asm"
%include "lib/unet/core/l4/tcp_fastopen.asm"
%include "lib/unet/core/l4/tcp_ao.asm"
%include "lib/unet/core/l4/tcp_tls.asm"
%include "lib/unet/core/l4/mptcp.asm"
%include "lib/unet/core/l4/sctp.asm"
%include "lib/unet/core/l4/quic.asm"
%include "lib/unet/core/sys/net_batch.asm"
%include "lib/unet/core/sys/avx512_checksum.asm"
%include "lib/unet/core/sys/avx512_parser.asm"
%include "lib/unet/core/sys/socket.asm"
%include "lib/unet/core/sys/epoll.asm"
%include "lib/unet/core/sys/unet_api.asm"

; Core Hardware Link & DMA Ring Management
%include "lib/unet/core/link/net_link.asm"
%include "lib/unet/core/link/net_ring.asm"
%include "lib/unet/core/link/pci.asm"
%include "lib/unet/core/link/recycle.asm"
%include "lib/unet/core/link/ring.asm"
%include "lib/unet/core/link/rss.asm"
%include "lib/unet/core/link/sbuf.asm"
%include "lib/unet/core/link/loan.asm"

; 2. DNS Engine
%include "lib/unet/dns/dns.asm"
%include "lib/unet/dns/dnssec.asm"
%include "lib/unet/dns/doh.asm"
%include "lib/unet/dns/doq.asm"
%include "lib/unet/dns/dot.asm"
%include "lib/unet/dns/mdns.asm"

; 3. Mail Protocols
%include "lib/unet/mail/smtp.asm"
%include "lib/unet/mail/pop3.asm"
%include "lib/unet/mail/imap.asm"
%include "lib/unet/mail/dkim.asm"
%include "lib/unet/mail/spf_dmarc.asm"

; 4. Routing Protocols
%include "lib/unet/routing/bgp.asm"
%include "lib/unet/routing/ospf.asm"
%include "lib/unet/routing/isis.asm"
%include "lib/unet/routing/evpn.asm"
%include "lib/unet/routing/netns.asm"
%include "lib/unet/routing/pim_dm.asm"
%include "lib/unet/routing/pim_sm.asm"
%include "lib/unet/routing/vrf_manager.asm"

; 5. SDN (Software-Defined Networking)
%include "lib/unet/sdn/geneve.asm"
%include "lib/unet/sdn/gre.asm"
%include "lib/unet/sdn/ipip.asm"
%include "lib/unet/sdn/l2tp.asm"
%include "lib/unet/sdn/mpls.asm"
%include "lib/unet/sdn/nvgre.asm"
%include "lib/unet/sdn/vxlan.asm"
%include "lib/unet/sdn/wireguard.asm"

; 6. CNI (Container Network Interface)
%include "lib/unet/cni/calico.asm"
%include "lib/unet/cni/cilium.asm"
%include "lib/unet/cni/flannel.asm"
%include "lib/unet/cni/kube_proxy.asm"
%include "lib/unet/cni/weave.asm"

; 7. CGNAT (Carrier-Grade NAT)
%include "lib/unet/cgnat/cgnat.asm"
%include "lib/unet/cgnat/ds_lite.asm"
%include "lib/unet/cgnat/nat444.asm"
%include "lib/unet/cgnat/nat64.asm"
%include "lib/unet/cgnat/nptv6.asm"
%include "lib/unet/cgnat/pcp.asm"

; 8. SCADA & Industrial Control
%include "lib/unet/scada/modbus_tcp.asm"
%include "lib/unet/scada/dnp3.asm"
%include "lib/unet/scada/iec61850.asm"
%include "lib/unet/scada/dlms_cosem.asm"

; 9. SAN (Storage Area Network)
%include "lib/unet/san/iscsi.asm"
%include "lib/unet/san/nvme_of_rdma.asm"
%include "lib/unet/san/nvme_of_tcp.asm"
%include "lib/unet/san/fcoe.asm"
%include "lib/unet/san/fip.asm"
%include "lib/unet/san/nfs42.asm"
%include "lib/unet/san/smb3.asm"
%include "lib/unet/san/webdav.asm"

; 10. Space Protocols
%include "lib/unet/space/ccsds.asm"
%include "lib/unet/space/cfdp.asm"
%include "lib/unet/space/dtn.asm"
%include "lib/unet/space/dvb_rcs2.asm"
%include "lib/unet/space/dvb_s2x.asm"
%include "lib/unet/space/laser_mesh.asm"
%include "lib/unet/space/ltp.asm"

; 11. SSH Subsystem
%include "lib/unet/ssh/ssh_transport.asm"
%include "lib/unet/ssh/ssh_auth.asm"
%include "lib/unet/ssh/ssh_connection.asm"
%include "lib/unet/ssh/sftp.asm"

; 12. Security Subsystem
%include "lib/unet/security/firewall.asm"
%include "lib/unet/security/ddos.asm"
%include "lib/unet/security/ipsec.asm"
%include "lib/unet/security/nitro.asm"
%include "lib/unet/security/noise_protocol.asm"
%include "lib/unet/security/pattern_matcher.asm"
%include "lib/unet/security/qkd.asm"
%include "lib/unet/security/qrng_entropy.asm"
%include "lib/unet/security/ssh_server.asm"
%include "lib/unet/security/tls13_session.asm"
%include "lib/unet/security/tpm2.asm"
%include "lib/unet/security/ztna.asm"

; 13. Network Services
%include "lib/unet/services/dhcp.asm"
%include "lib/unet/services/ntp.asm"
%include "lib/unet/services/syslog.asm"
%include "lib/unet/services/ipfix.asm"
%include "lib/unet/services/matter.asm"
%include "lib/unet/services/mqtt.asm"
%include "lib/unet/services/opcua.asm"
%include "lib/unet/services/radius.asm"
%include "lib/unet/services/snmpv3.asm"
%include "lib/unet/services/tacacs.asm"

; 14. Anonymity Networks
%include "lib/unet/anon/tor_cell.asm"
%include "lib/unet/anon/i2p_garlic.asm"
%include "lib/unet/anon/freenet.asm"
%include "lib/unet/anon/lokinet.asm"
%include "lib/unet/anon/mixnet.asm"
%include "lib/unet/anon/nym.asm"
%include "lib/unet/anon/obfs4.asm"
%include "lib/unet/anon/shadowsocks.asm"

; 15. Telecom Core 5G/LTE
%include "lib/unet/telecom/diameter.asm"
%include "lib/unet/telecom/pfcp.asm"

; 16. QoS & Traffic Shaping
%include "lib/unet/qos/fq_codel.asm"
%include "lib/unet/qos/tbf.asm"
%include "lib/unet/qos/slb.asm"
%include "lib/unet/qos/ebpf_maglev.asm"

; 17. AI Networking
%include "lib/unet/ai/ml_ids.asm"
%include "lib/unet/ai/autonomous_qos.asm"
%include "lib/unet/ai/graph_neural_net.asm"
%include "lib/unet/ai/predictive_te.asm"
%include "lib/unet/ai/reinforce_route.asm"

; 18. HPC & RDMA
%include "lib/unet/hpc/infiniband.asm"
%include "lib/unet/hpc/slingshot.asm"
%include "lib/unet/hpc/gpudirect.asm"
%include "lib/unet/hpc/mpi_collectives.asm"
%include "lib/unet/hpc/rdma_cm.asm"
%include "lib/unet/hpc/roce.asm"

; 19. High-Frequency Trading (HFT)
%include "lib/unet/hft/fix.asm"
%include "lib/unet/hft/itch.asm"
%include "lib/unet/hft/itch_mcast.asm"
%include "lib/unet/hft/ouch.asm"
%include "lib/unet/hft/ouch_soup.asm"
%include "lib/unet/hft/pouch.asm"

; 20. Fintech & Banking
%include "lib/unet/fintech/iso8583.asm"
%include "lib/unet/fintech/swift.asm"
%include "lib/unet/fintech/iso20022.asm"

; 21. Optical Networking
%include "lib/unet/optical/dwdm.asm"
%include "lib/unet/optical/g709.asm"
%include "lib/unet/optical/flex_ethernet.asm"
%include "lib/unet/optical/coherent.asm"
%include "lib/unet/optical/pon.asm"

; 22. Wireless Stack
%include "lib/unet/wireless/wifi6e.asm"
%include "lib/unet/wireless/bluetooth.asm"
%include "lib/unet/wireless/zigbee.asm"
%include "lib/unet/wireless/capwap.asm"
%include "lib/unet/wireless/eap_tls.asm"
%include "lib/unet/wireless/wpa3_sae.asm"
%include "lib/unet/wireless/lorawan.asm"

; 23. Automotive Stack
%include "lib/unet/automotive/can_eth.asm"
%include "lib/unet/automotive/someip.asm"
%include "lib/unet/automotive/doip.asm"
%include "lib/unet/automotive/doip_uds.asm"
%include "lib/unet/automotive/avb_tsn.asm"
%include "lib/unet/automotive/t1_phy.asm"

; 24. Avionics Stack
%include "lib/unet/avionics/afdx.asm"
%include "lib/unet/avionics/mil1553.asm"
%include "lib/unet/avionics/spacefire.asm"
%include "lib/unet/avionics/stanag.asm"

; 25. Cloud Overlay & Gateways
%include "lib/unet/cloud/vxlan.asm"
%include "lib/unet/cloud/geneve.asm"
%include "lib/unet/cloud/gre.asm"
%include "lib/unet/cloud/nvgre.asm"
%include "lib/unet/cloud/aws_tgw.asm"
%include "lib/unet/cloud/azure_express.asm"
%include "lib/unet/cloud/gcp_interconnect.asm"
%include "lib/unet/cloud/vswitch.asm"

; 26. eBPF & SmartNIC Acceleration
%include "lib/unet/ebpf/ebpf.asm"
%include "lib/unet/ebpf/dpdk.asm"
%include "lib/unet/ebpf/smartnic_offload.asm"

; 27. Video Streaming
%include "lib/unet/video/srt.asm"
%include "lib/unet/video/rtmp.asm"
%include "lib/unet/video/hls_dash.asm"
%include "lib/unet/video/webrtc_sfu.asm"
%include "lib/unet/video/rtp_av1.asm"
%include "lib/unet/video/rtp_hevc.asm"
%include "lib/unet/video/rtp_h264.asm"
%include "lib/unet/video/moq.asm"

; 28. VoIP & Telephony
%include "lib/unet/voip/sip.asm"
%include "lib/unet/voip/sdp.asm"
%include "lib/unet/voip/rtp.asm"
%include "lib/unet/voip/srtp.asm"
%include "lib/unet/voip/codecs.asm"
%include "lib/unet/voip/ice_stun.asm"

; 29. Gaming Stack
%include "lib/unet/gaming/raknet.asm"
%include "lib/unet/gaming/e2s.asm"

; 30. Mesh Networks
%include "lib/unet/mesh/hyperspace.asm"
%include "lib/unet/mesh/tailscale.asm"
%include "lib/unet/mesh/yggdrasil.asm"
%include "lib/unet/mesh/babel.asm"
%include "lib/unet/mesh/batman.asm"

; 31. Proxy & Tunneling
%include "lib/unet/proxy/socks5.asm"
%include "lib/unet/proxy/reverse_proxy.asm"
%include "lib/unet/proxy/forward_proxy.asm"

; 32. Identity Protocols
%include "lib/unet/identity/kerberos.asm"
%include "lib/unet/identity/oauth2.asm"
%include "lib/unet/identity/spiffe.asm"
%include "lib/unet/identity/webauthn.asm"

; 33. VPN & Encrypted Tunnels
%include "lib/unet/vpn/wireguard_blake2s.asm"
%include "lib/unet/vpn/openvpn.asm"
%include "lib/unet/vpn/sstp.asm"
%include "lib/unet/vpn/l2tp_ipsec.asm"

; 34. Post-Quantum Cryptography (PQC)
%include "lib/unet/pqc/pqc_wireguard.asm"
%include "lib/unet/pqc/pqc_macsec.asm"
%include "lib/unet/pqc/qkd_km.asm"

; 35. High Availability (HA)
%include "lib/unet/ha/vrrp.asm"
%include "lib/unet/ha/carp.asm"

; 36. HTTP Core
%include "lib/unet/http/http1.asm"
%include "lib/unet/http/http2.asm"

; 37. Hardware Network Drivers (26 Network NIC Drivers)
%include "lib/unet/drivers/intel_e100.asm"
%include "lib/unet/drivers/e1000.asm"
%include "lib/unet/drivers/igb.asm"
%include "lib/unet/drivers/ixgbe.asm"
%include "lib/unet/drivers/i40e.asm"
%include "lib/unet/drivers/ice.asm"
%include "lib/unet/drivers/mlx4.asm"
%include "lib/unet/drivers/mlx5.asm"
%include "lib/unet/drivers/broadcom_bnxt.asm"
%include "lib/unet/drivers/chelsio_cxgb4.asm"
%include "lib/unet/drivers/solarflare_sfc.asm"
%include "lib/unet/drivers/pensando_ionic.asm"
%include "lib/unet/drivers/virtio_net.asm"
%include "lib/unet/drivers/vmxnet3.asm"
%include "lib/unet/drivers/ena.asm"
%include "lib/unet/drivers/gve.asm"
%include "lib/unet/drivers/sriov.asm"
%include "lib/unet/drivers/napatech.asm"
%include "lib/unet/drivers/marvell_octeon.asm"
%include "lib/unet/drivers/ath11k.asm"
%include "lib/unet/drivers/quectel_5g.asm"
%include "lib/unet/drivers/realtek_r8169.asm"
%include "lib/unet/drivers/3com_3c905.asm"
%include "lib/unet/drivers/ne2000.asm"
%include "lib/unet/drivers/microchip_lan9514.asm"
%include "lib/unet/drivers/usb_eth.asm"

; 38. Test Suite
%include "lib/unet/tests/net_fuzz.asm"
%include "lib/unet/tests/pqc_bench.asm"
%include "lib/unet/tests/tcp_state_test.asm"

; 39. Master Diagnostic & CLI Tool Dispatcher (90 Tools)
%include "lib/unet/tools/tools.asm"

%endif ; GUARD_UNET_UNET_ASM
