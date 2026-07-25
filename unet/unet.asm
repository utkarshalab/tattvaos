; =============================================================================
; Tattva OS — unet/unet.asm
; =============================================================================
; Master unet (Unikernel Network Stack Engine) Dispatcher API (`unet_init`,
; `unet_poll`, `unet_shutdown`).
;
; Single-pass NASM included subsystem handler linking all unet sub-modules.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM flat binary)
; =============================================================================

%include "unet/unet.inc"
%include "crypto/ucrypt/guards/ct_guard.asm"

; -----------------------------------------------------------------------------
; unet Child Subsystem NASM Includes
; -----------------------------------------------------------------------------
%include "unet/mem/pktbuf.asm"
%include "unet/core/eth.asm"
%include "unet/core/arp.asm"
%include "unet/core/ip.asm"
%include "unet/core/ipv6.asm"
%include "unet/core/udp.asm"
%include "unet/core/tcp.asm"
%include "unet/core/tcp_bbr.asm"
%include "unet/core/mptcp.asm"
%include "unet/core/sctp.asm"
%include "unet/hpc/infiniband.asm"
%include "unet/hpc/slingshot.asm"
%include "unet/hpc/gpudirect.asm"
%include "unet/hpc/mpi_collectives.asm"
%include "unet/hpc/cxl.asm"
%include "unet/hpc/dragonfly.asm"
%include "unet/quantum/qsp.asm"
%include "unet/quantum/qbb84.asm"
%include "unet/hft/fix.asm"
%include "unet/hft/itch.asm"
%include "unet/hft/ouch.asm"
%include "unet/fintech/iso20022.asm"
%include "unet/fintech/swift.asm"
%include "unet/automotive/doip.asm"
%include "unet/automotive/someip.asm"
%include "unet/automotive/can_eth.asm"
%include "unet/auto_eth/t1_phy.asm"
%include "unet/auto_eth/avb_tsn.asm"
%include "unet/avionics/afdx.asm"
%include "unet/avionics/stanag.asm"
%include "unet/avionics/spacefire.asm"
%include "unet/underwater/janus.asm"
%include "unet/underwater/dmac.asm"
%include "unet/laser/free_space.asm"
%include "unet/laser/pat.asm"
%include "unet/satcom/dvb_s2x.asm"
%include "unet/satcom/dvb_rcs2.asm"
%include "unet/space_dtn/ccsds.asm"
%include "unet/space_dtn/dtn.asm"
%include "unet/wireless/wifi6e.asm"
%include "unet/wireless/bluetooth.asm"
%include "unet/wireless/zigbee.asm"
%include "unet/wlan/capwap.asm"
%include "unet/wlan/eap_tls.asm"
%include "unet/optical/pon.asm"
%include "unet/optical/coherent.asm"
%include "unet/otn/g709.asm"
%include "unet/otn/dwdm.asm"
%include "unet/mesh/babel.asm"
%include "unet/mesh/batman.asm"
%include "unet/mesh/yggdrasil.asm"
%include "unet/mesh/tailscale.asm"
%include "unet/anon/tor_cell.asm"
%include "unet/anon/i2p_garlic.asm"
%include "unet/cni/cilium.asm"
%include "unet/cni/calico.asm"
%include "unet/cni/kube_proxy.asm"
%include "unet/tsn/tas.asm"
%include "unet/voip/sip.asm"
%include "unet/voip/sdp.asm"
%include "unet/voip/rtp.asm"
%include "unet/voip/srtp.asm"
%include "unet/voip/codecs.asm"
%include "unet/voip/ice_stun.asm"
%include "unet/telecom/diameter.asm"
%include "unet/video/srt.asm"
%include "unet/video/rist.asm"
%include "unet/video/ndi.asm"
%include "unet/video_rtp/rtp_av1.asm"
%include "unet/video_rtp/rtp_hevc.asm"
%include "unet/video_rtp/rtp_h264.asm"
%include "unet/media/moq.asm"
%include "unet/gaming/e2s.asm"
%include "unet/gaming/raknet.asm"
%include "unet/exchange/itch_mcast.asm"
%include "unet/exchange/pouch.asm"
%include "unet/cgnat/cgnat.asm"
%include "unet/cgnat/nat64.asm"
%include "unet/cgnat/ds_lite.asm"
%include "unet/cloud/aws_tgw.asm"
%include "unet/cloud/azure_express.asm"
%include "unet/cloud/gcp_interconnect.asm"
%include "unet/qrng/qrng_entropy.asm"
%include "unet/ai_route/reinforce_route.asm"
%include "unet/fcoe/fcoe.asm"
%include "unet/fcoe/fip.asm"
%include "unet/scada/dnp3.asm"
%include "unet/scada/iec61850.asm"
%include "unet/tester/pktgen.asm"
%include "unet/tester/latency_meter.asm"
%include "unet/time/nts.asm"
%include "unet/time/gnss.asm"
%include "unet/fs_net/smb3.asm"
%include "unet/fs_net/webdav.asm"
%include "unet/vpn/openvpn.asm"
%include "unet/vpn/sstp.asm"
%include "unet/vpn/l2tp_ipsec.asm"
%include "unet/pqc_net/pqc_wireguard.asm"
%include "unet/pqc_net/pqc_macsec.asm"
%include "unet/lb/slb.asm"
%include "unet/lb/consistent_hash.asm"
%include "unet/lb/weighted_rr.asm"
%include "unet/dpi/pattern_matcher.asm"
%include "unet/dpi/suricata_engine.asm"
%include "unet/dpi/proto_detector.asm"
%include "unet/vrf/vrf_manager.asm"
%include "unet/vrf/netns.asm"
%include "unet/multicast/pim_sm.asm"
%include "unet/multicast/pim_dm.asm"
%include "unet/routing/bgp.asm"
%include "unet/routing/evpn.asm"
%include "unet/routing/ospf.asm"
%include "unet/ha/vrrp.asm"
%include "unet/ha/hsrp.asm"
%include "unet/ha/pacemaker.asm"
%include "unet/socket/socket.asm"
%include "unet/epoll/epoll.asm"
%include "unet/security/tls13_session.asm"
%include "unet/security/ssh_server.asm"
%include "unet/security/ipsec.asm"
%include "unet/security/qkd.asm"
%include "unet/security/firewall.asm"
%include "unet/security/ddos.asm"
%include "unet/hsm/tpm2.asm"
%include "unet/hsm/nitro.asm"
%include "unet/http/http1.asm"
%include "unet/http/http2.asm"
%include "unet/http/http3.asm"
%include "unet/http/qpack.asm"
%include "unet/http/websocket.asm"
%include "unet/http/webtransport.asm"
%include "unet/http/ohttp.asm"
%include "unet/http/connect_udp.asm"
%include "unet/http/sse.asm"
%include "unet/http/grpc.asm"
%include "unet/proxy/reverse_proxy.asm"
%include "unet/proxy/socks5.asm"
%include "unet/proxy/forward_proxy.asm"
%include "unet/dns/dns.asm"
%include "unet/dns/dnssec.asm"
%include "unet/dns/mdns.asm"
%include "unet/dns/doh.asm"
%include "unet/dns/dot.asm"
%include "unet/identity/spiffe.asm"
%include "unet/identity/oauth2.asm"
%include "unet/services/radius.asm"
%include "unet/services/tacacs.asm"
%include "unet/services/syslog.asm"
%include "unet/services/dhcp.asm"
%include "unet/services/ntp.asm"
%include "unet/services/ipfix.asm"
%include "unet/services/mqtt.asm"
%include "unet/services/matter.asm"
%include "unet/services/opcua.asm"
%include "unet/storage_net/nvme_of_tcp.asm"
%include "unet/storage_net/iscsi.asm"
%include "unet/ebpf/ebpf.asm"
%include "unet/ebpf/dpdk.asm"
%include "unet/sdn/gre.asm"
%include "unet/sdn/nvgre.asm"
%include "unet/sdn/l2tp.asm"
%include "unet/sdn/ipip.asm"
%include "unet/sdn/wireguard.asm"
%include "unet/sdn/vxlan.asm"
%include "unet/drivers/e1000.asm"
%include "unet/drivers/igb.asm"
%include "unet/drivers/ixgbe.asm"
%include "unet/drivers/i40e.asm"
%include "unet/drivers/ice.asm"
%include "unet/drivers/mlx4.asm"
%include "unet/drivers/mlx5.asm"
%include "unet/drivers/broadcom_bnxt.asm"
%include "unet/drivers/realtek_r8169.asm"
%include "unet/drivers/marvell_octeon.asm"
%include "unet/drivers/solarflare_sfc.asm"
%include "unet/drivers/chelsio_cxgb4.asm"
%include "unet/drivers/napatech.asm"
%include "unet/drivers/pensando_ionic.asm"
%include "unet/drivers/virtio_net.asm"
%include "unet/drivers/vmxnet3.asm"
%include "unet/drivers/ena.asm"
%include "unet/drivers/gve.asm"
%include "unet/drivers/usb_eth.asm"
%include "unet/drivers/quectel_5g.asm"
%include "unet/drivers/ath11k.asm"
%include "unet/drivers/microchip_lan9514.asm"
%include "unet/drivers/intel_e100.asm"
%include "unet/drivers/3com_3c905.asm"
%include "unet/drivers/ne2000.asm"
%include "unet/diag/pcap.asm"
%include "unet/diag/traceroute.asm"
%include "unet/diag/sctp_diag.asm"
%include "unet/rdma/roce.asm"
%include "unet/tests/net_fuzz.asm"

section .text

global unet_init
global unet_poll
global unet_shutdown

; -----------------------------------------------------------------------------
; unet_init — Initialize Network Stack Subsystem
; -----------------------------------------------------------------------------
align 32
unet_init:
    push rbp
    mov rbp, rsp

    call pktbuf_init
    call arp_init
    call socket_init
    call e1000_init

    mov eax, 0                      ; Success
    pop rbp
    ret

; -----------------------------------------------------------------------------
; unet_poll — Main zero-copy packet rx/tx polling loop
; -----------------------------------------------------------------------------
align 32
unet_poll:
    push rbp
    mov rbp, rsp
    push rbx

    call e1000_receive_packet
    test rax, rax
    jz .poll_done

    mov rdi, rax
    call eth_parse
    test eax, eax
    jz .poll_done

    cmp ax, UNET_ETH_TYPE_IPV4
    je .handle_ipv4
    cmp ax, UNET_ETH_TYPE_ARP
    je .handle_arp
    jmp .poll_done

.handle_ipv4:
    call ip_parse
    jmp .poll_done

.handle_arp:
    call arp_process_packet
    jmp .poll_done

.poll_done:
    mov eax, 0
    pop rbx
    pop rbp
    ret

; -----------------------------------------------------------------------------
; unet_shutdown — Shutdown Network Subsystem
; -----------------------------------------------------------------------------
align 32
unet_shutdown:
    mov eax, 0                      ; Success
    ret
