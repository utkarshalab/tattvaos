%ifndef GUARD_UNET_UNET_ASM
%define GUARD_UNET_UNET_ASM
; =============================================================================
; Tattva OS — unet/unet.asm
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

%include "unet/unet.inc"
%include "unet/include/unet_abi.inc"
%include "unet/tools/tools.inc"

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
    call ip_init
    call ipv6_init
    call udp_init
    call tcp_init
    call socket_table_init
    call http1_init

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
    call tcp_timer_tick
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
%include "unet/core/sys/pktbuf.asm"
%include "unet/core/l2/eth.asm"
%include "unet/core/l2/arp.asm"
%include "unet/core/l2/mac.asm"
%include "unet/core/l3/ip.asm"
%include "unet/core/l3/ipv6.asm"
%include "unet/core/l3/icmp.asm"
%include "unet/core/l3/igmp.asm"
%include "unet/core/l4/udp.asm"
%include "unet/core/l4/tcp.asm"
%include "unet/core/l4/tcp_bbr.asm"
%include "unet/core/l4/mptcp.asm"
%include "unet/core/l4/sctp.asm"
%include "unet/core/l4/quic.asm"
%include "unet/core/sys/avx512_parser.asm"
%include "unet/core/sys/socket.asm"
%include "unet/core/sys/epoll.asm"
%include "unet/core/sys/unet_api.asm"

; Core Hardware Link & DMA Ring Management
%include "unet/core/link/net_link.asm"
%include "unet/core/link/net_ring.asm"
%include "unet/core/link/pci.asm"
%include "unet/core/link/recycle.asm"
%include "unet/core/link/ring.asm"
%include "unet/core/link/rss.asm"
%include "unet/core/link/sbuf.asm"
%include "unet/core/link/loan.asm"

; 2. DNS Engine
%include "unet/dns/dns.asm"
%include "unet/dns/dnssec.asm"
%include "unet/dns/doh.asm"
%include "unet/dns/doq.asm"
%include "unet/dns/dot.asm"
%include "unet/dns/mdns.asm"

; 3. Mail Protocols
%include "unet/mail/smtp.asm"
%include "unet/mail/pop3.asm"
%include "unet/mail/imap.asm"
%include "unet/mail/dkim.asm"
%include "unet/mail/spf_dmarc.asm"

; 4. Routing Protocols
%include "unet/routing/bgp.asm"
%include "unet/routing/ospf.asm"
%include "unet/routing/isis.asm"
%include "unet/routing/evpn.asm"
%include "unet/routing/netns.asm"
%include "unet/routing/pim_dm.asm"
%include "unet/routing/pim_sm.asm"
%include "unet/routing/vrf_manager.asm"

; 5. SDN (Software-Defined Networking)
%include "unet/sdn/geneve.asm"
%include "unet/sdn/gre.asm"
%include "unet/sdn/ipip.asm"
%include "unet/sdn/l2tp.asm"
%include "unet/sdn/mpls.asm"
%include "unet/sdn/nvgre.asm"
%include "unet/sdn/vxlan.asm"
%include "unet/sdn/wireguard.asm"

; 6. CNI (Container Network Interface)
%include "unet/cni/calico.asm"
%include "unet/cni/cilium.asm"
%include "unet/cni/flannel.asm"
%include "unet/cni/kube_proxy.asm"
%include "unet/cni/weave.asm"

; 7. CGNAT (Carrier-Grade NAT)
%include "unet/cgnat/cgnat.asm"
%include "unet/cgnat/ds_lite.asm"
%include "unet/cgnat/nat444.asm"
%include "unet/cgnat/nat64.asm"
%include "unet/cgnat/nptv6.asm"
%include "unet/cgnat/pcp.asm"

; 8. SCADA & Industrial Control
%include "unet/scada/modbus_tcp.asm"
%include "unet/scada/dnp3.asm"
%include "unet/scada/iec61850.asm"
%include "unet/scada/dlms_cosem.asm"

; 9. SAN (Storage Area Network)
%include "unet/san/iscsi.asm"
%include "unet/san/nvme_of_rdma.asm"
%include "unet/san/nvme_of_tcp.asm"
%include "unet/san/fcoe.asm"
%include "unet/san/fip.asm"
%include "unet/san/nfs42.asm"
%include "unet/san/smb3.asm"
%include "unet/san/webdav.asm"

; 10. Space Protocols
%include "unet/space/ccsds.asm"
%include "unet/space/cfdp.asm"
%include "unet/space/dtn.asm"
%include "unet/space/dvb_rcs2.asm"
%include "unet/space/dvb_s2x.asm"
%include "unet/space/laser_mesh.asm"
%include "unet/space/ltp.asm"

; 11. SSH Subsystem
%include "unet/ssh/ssh_transport.asm"
%include "unet/ssh/ssh_auth.asm"
%include "unet/ssh/ssh_connection.asm"
%include "unet/ssh/sftp.asm"

; 12. Security Subsystem
%include "unet/security/firewall.asm"
%include "unet/security/ddos.asm"
%include "unet/security/ipsec.asm"
%include "unet/security/nitro.asm"
%include "unet/security/noise_protocol.asm"
%include "unet/security/pattern_matcher.asm"
%include "unet/security/qkd.asm"
%include "unet/security/qrng_entropy.asm"
%include "unet/security/ssh_server.asm"
%include "unet/security/tls13_session.asm"
%include "unet/security/tpm2.asm"
%include "unet/security/ztna.asm"

; 13. Network Services
%include "unet/services/dhcp.asm"
%include "unet/services/ntp.asm"
%include "unet/services/syslog.asm"
%include "unet/services/ipfix.asm"
%include "unet/services/matter.asm"
%include "unet/services/mqtt.asm"
%include "unet/services/opcua.asm"
%include "unet/services/radius.asm"
%include "unet/services/snmpv3.asm"
%include "unet/services/tacacs.asm"

; 14. Anonymity Networks
%include "unet/anon/tor_cell.asm"
%include "unet/anon/i2p_garlic.asm"
%include "unet/anon/freenet.asm"
%include "unet/anon/lokinet.asm"
%include "unet/anon/mixnet.asm"
%include "unet/anon/nym.asm"
%include "unet/anon/obfs4.asm"
%include "unet/anon/shadowsocks.asm"

; 15. Telecom Core 5G/LTE
%include "unet/telecom/diameter.asm"
%include "unet/telecom/pfcp.asm"

; 16. QoS & Traffic Shaping
%include "unet/qos/fq_codel.asm"
%include "unet/qos/tbf.asm"
%include "unet/qos/slb.asm"
%include "unet/qos/ebpf_maglev.asm"

; 17. AI Networking
%include "unet/ai/ml_ids.asm"
%include "unet/ai/autonomous_qos.asm"
%include "unet/ai/graph_neural_net.asm"
%include "unet/ai/predictive_te.asm"
%include "unet/ai/reinforce_route.asm"

; 18. HPC & RDMA
%include "unet/hpc/infiniband.asm"
%include "unet/hpc/slingshot.asm"
%include "unet/hpc/gpudirect.asm"
%include "unet/hpc/mpi_collectives.asm"
%include "unet/hpc/rdma_cm.asm"
%include "unet/hpc/roce.asm"

; 19. High-Frequency Trading (HFT)
%include "unet/hft/fix.asm"
%include "unet/hft/itch.asm"
%include "unet/hft/itch_mcast.asm"
%include "unet/hft/ouch.asm"
%include "unet/hft/ouch_soup.asm"
%include "unet/hft/pouch.asm"

; 20. Fintech & Banking
%include "unet/fintech/iso8583.asm"
%include "unet/fintech/swift.asm"
%include "unet/fintech/iso20022.asm"

; 21. Optical Networking
%include "unet/optical/dwdm.asm"
%include "unet/optical/g709.asm"
%include "unet/optical/flex_ethernet.asm"
%include "unet/optical/coherent.asm"
%include "unet/optical/pon.asm"

; 22. Wireless Stack
%include "unet/wireless/wifi6e.asm"
%include "unet/wireless/bluetooth.asm"
%include "unet/wireless/zigbee.asm"
%include "unet/wireless/capwap.asm"
%include "unet/wireless/eap_tls.asm"
%include "unet/wireless/wpa3_sae.asm"
%include "unet/wireless/lorawan.asm"

; 23. Automotive Stack
%include "unet/automotive/can_eth.asm"
%include "unet/automotive/someip.asm"
%include "unet/automotive/doip.asm"
%include "unet/automotive/doip_uds.asm"
%include "unet/automotive/avb_tsn.asm"
%include "unet/automotive/t1_phy.asm"

; 24. Avionics Stack
%include "unet/avionics/afdx.asm"
%include "unet/avionics/mil1553.asm"
%include "unet/avionics/spacefire.asm"
%include "unet/avionics/stanag.asm"

; 25. Cloud Overlay & Gateways
%include "unet/cloud/vxlan.asm"
%include "unet/cloud/geneve.asm"
%include "unet/cloud/gre.asm"
%include "unet/cloud/nvgre.asm"
%include "unet/cloud/aws_tgw.asm"
%include "unet/cloud/azure_express.asm"
%include "unet/cloud/gcp_interconnect.asm"
%include "unet/cloud/vswitch.asm"

; 26. eBPF & SmartNIC Acceleration
%include "unet/ebpf/ebpf.asm"
%include "unet/ebpf/dpdk.asm"
%include "unet/ebpf/smartnic_offload.asm"

; 27. Video Streaming
%include "unet/video/srt.asm"
%include "unet/video/rtmp.asm"
%include "unet/video/hls_dash.asm"
%include "unet/video/webrtc_sfu.asm"
%include "unet/video/rtp_av1.asm"
%include "unet/video/rtp_hevc.asm"
%include "unet/video/rtp_h264.asm"
%include "unet/video/moq.asm"

; 28. VoIP & Telephony
%include "unet/voip/sip.asm"
%include "unet/voip/sdp.asm"
%include "unet/voip/rtp.asm"
%include "unet/voip/srtp.asm"
%include "unet/voip/codecs.asm"
%include "unet/voip/ice_stun.asm"

; 29. Gaming Stack
%include "unet/gaming/raknet.asm"
%include "unet/gaming/e2s.asm"

; 30. Mesh Networks
%include "unet/mesh/hyperspace.asm"
%include "unet/mesh/tailscale.asm"
%include "unet/mesh/yggdrasil.asm"
%include "unet/mesh/babel.asm"
%include "unet/mesh/batman.asm"

; 31. Proxy & Tunneling
%include "unet/proxy/socks5.asm"
%include "unet/proxy/reverse_proxy.asm"
%include "unet/proxy/forward_proxy.asm"

; 32. Identity Protocols
%include "unet/identity/kerberos.asm"
%include "unet/identity/oauth2.asm"
%include "unet/identity/spiffe.asm"
%include "unet/identity/webauthn.asm"

; 33. VPN & Encrypted Tunnels
%include "unet/vpn/wireguard_blake2s.asm"
%include "unet/vpn/openvpn.asm"
%include "unet/vpn/sstp.asm"
%include "unet/vpn/l2tp_ipsec.asm"

; 34. Post-Quantum Cryptography (PQC)
%include "unet/pqc/pqc_wireguard.asm"
%include "unet/pqc/pqc_macsec.asm"
%include "unet/pqc/qkd_km.asm"

; 35. High Availability (HA)
%include "unet/ha/vrrp.asm"
%include "unet/ha/carp.asm"

; 36. HTTP Core
%include "unet/http/http1.asm"
%include "unet/http/http2.asm"

; 37. Hardware Network Drivers (26 Network NIC Drivers)
%include "unet/drivers/intel_e100.asm"
%include "unet/drivers/e1000.asm"
%include "unet/drivers/igb.asm"
%include "unet/drivers/ixgbe.asm"
%include "unet/drivers/i40e.asm"
%include "unet/drivers/ice.asm"
%include "unet/drivers/mlx4.asm"
%include "unet/drivers/mlx5.asm"
%include "unet/drivers/broadcom_bnxt.asm"
%include "unet/drivers/chelsio_cxgb4.asm"
%include "unet/drivers/solarflare_sfc.asm"
%include "unet/drivers/pensando_ionic.asm"
%include "unet/drivers/virtio_net.asm"
%include "unet/drivers/vmxnet3.asm"
%include "unet/drivers/ena.asm"
%include "unet/drivers/gve.asm"
%include "unet/drivers/sriov.asm"
%include "unet/drivers/napatech.asm"
%include "unet/drivers/marvell_octeon.asm"
%include "unet/drivers/ath11k.asm"
%include "unet/drivers/quectel_5g.asm"
%include "unet/drivers/realtek_r8169.asm"
%include "unet/drivers/3com_3c905.asm"
%include "unet/drivers/ne2000.asm"
%include "unet/drivers/microchip_lan9514.asm"
%include "unet/drivers/usb_eth.asm"

; 38. Test Suite
%include "unet/tests/net_fuzz.asm"
%include "unet/tests/pqc_bench.asm"
%include "unet/tests/tcp_state_test.asm"

; 39. Master Diagnostic & CLI Tool Dispatcher (90 Tools)
%include "unet/tools/tools.asm"

%endif ; GUARD_UNET_UNET_ASM
