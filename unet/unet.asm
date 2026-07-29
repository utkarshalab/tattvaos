; =============================================================================
; Tattva OS — unet/unet.asm
; =============================================================================
; Master Network Stack Engine & Universal Protocol Dispatcher.
;
; Consolidates all 39 single-word pure domain sub-systems across unet/:
;   - Core (l2/, l3/, l4/, sys/, link/), HTTP, DNS, Mail, Proxy, Identity, Security,
;     SSH, VPN, PQC, Cloud, SDN, CNI, Routing, HA, HPC, HFT, Fintech, SCADA, Telecom,
;     Optical, Space, Wireless, Automotive, Avionics, Video, VoIP, Gaming, SAN,
;     CGNAT, QoS, AI, eBPF, Mesh, Anon, Drivers, Tools, Include, Tests.
;
; Author:  Utkarsha Labs
; Target:  x86-64 (64-bit NASM)
; =============================================================================

%include "unet/unet.inc"
%include "unet/tools/tools.inc"

section .text

global unet_init
global unet_poll
global unet_shutdown

align 32
unet_init:
    push rbp
    mov rbp, rsp
    call pktbuf_init
    call eth_init
    call ip_init
    call ipv6_init
    call udp_init
    call tcp_init
    call socket_table_init
    call http1_init
    call e1000_init
    xor eax, eax
    pop rbp
    ret

align 32
unet_poll:
    push rbp
    mov rbp, rsp
    call e1000_poll
    call tcp_timer_tick
    pop rbp
    ret

align 32
unet_shutdown:
    push rbp
    mov rbp, rsp
    xor eax, eax
    pop rbp
    ret

; -----------------------------------------------------------------------------
; Master Protocol Suite Includes (39 Single-Word Pure Domain Directories)
; -----------------------------------------------------------------------------
%include "unet/core/sys/pktbuf.asm"
%include "unet/core/l2/eth.asm"
%include "unet/core/l2/arp.asm"
%include "unet/core/l3/ip.asm"
%include "unet/core/l3/ipv6.asm"
%include "unet/core/l4/udp.asm"
%include "unet/core/l4/tcp.asm"
%include "unet/core/l4/tcp_bbr.asm"
%include "unet/core/l4/mptcp.asm"
%include "unet/core/l4/sctp.asm"
%include "unet/core/sys/avx512_parser.asm"
%include "unet/core/sys/socket.asm"
%include "unet/core/sys/epoll.asm"

; Core Hardware Link & DMA Ring Management Subdirectory
%include "unet/core/link/net_link.asm"
%include "unet/core/link/net_ring.asm"
%include "unet/core/link/pci.asm"
%include "unet/core/link/recycle.asm"
%include "unet/core/link/ring.asm"
%include "unet/core/link/rss.asm"
%include "unet/core/link/sbuf.asm"
%include "unet/core/link/loan.asm"

%include "unet/qos/fq_codel.asm"
%include "unet/qos/tbf.asm"
%include "unet/qos/slb.asm"
%include "unet/qos/ebpf_maglev.asm"

%include "unet/hpc/infiniband.asm"
%include "unet/hpc/slingshot.asm"
%include "unet/hpc/gpudirect.asm"
%include "unet/hpc/mpi_collectives.asm"
%include "unet/hpc/cxl.asm"
%include "unet/hpc/dragonfly.asm"
%include "unet/hpc/roce.asm"

%include "unet/hft/fix.asm"
%include "unet/hft/itch.asm"
%include "unet/hft/ouch.asm"
%include "unet/hft/solarflare.asm"
%include "unet/hft/fpga_bypass.asm"

%include "unet/fintech/swift.asm"
%include "unet/fintech/iso20022.asm"
%include "unet/fintech/fast_protocol.asm"

%include "unet/scada/modbus.asm"
%include "unet/scada/dnp3.asm"
%include "unet/scada/iec104.asm"
%include "unet/scada/iec61850.asm"

%include "unet/telecom/pfcp.asm"
%include "unet/telecom/diameter.asm"

%include "unet/optical/otn.asm"
%include "unet/optical/dwdm.asm"
%include "unet/optical/pon.asm"

%include "unet/space/ccsds.asm"
%include "unet/space/dvb_s2x.asm"
%include "unet/space/dtn.asm"
%include "unet/space/cfdp.asm"
%include "unet/space/ltp.asm"
%include "unet/space/dvb_rcs2.asm"
%include "unet/space/laser_mesh.asm"

%include "unet/wireless/wifi6e.asm"
%include "unet/wireless/bluetooth.asm"
%include "unet/wireless/zigbee.asm"
%include "unet/wireless/capwap.asm"
%include "unet/wireless/eap_tls.asm"
%include "unet/wireless/wpa3_sae.asm"
%include "unet/wireless/lorawan.asm"

%include "unet/automotive/can_eth.asm"
%include "unet/automotive/someip.asm"
%include "unet/automotive/doip.asm"
%include "unet/automotive/avb_tsn.asm"
%include "unet/automotive/doip_uds.asm"
%include "unet/automotive/t1_phy.asm"

%include "unet/avionics/afdx.asm"
%include "unet/avionics/mil1553.asm"
%include "unet/avionics/spacefire.asm"
%include "unet/avionics/stanag.asm"

%include "unet/video/srt.asm"
%include "unet/video/rtmp.asm"
%include "unet/video/hls_dash.asm"
%include "unet/video/webrtc_sfu.asm"
%include "unet/video/rtp_av1.asm"
%include "unet/video/rtp_hevc.asm"
%include "unet/video/rtp_h264.asm"
%include "unet/video/moq.asm"

%include "unet/voip/sip.asm"
%include "unet/voip/sdp.asm"
%include "unet/voip/rtp.asm"
%include "unet/voip/srtp.asm"
%include "unet/voip/codecs.asm"
%include "unet/voip/ice_stun.asm"

%include "unet/gaming/raknet.asm"
%include "unet/gaming/gaffer.asm"
%include "unet/gaming/quake_net.asm"

%include "unet/san/iscsi.asm"
%include "unet/san/fcoe.asm"
%include "unet/san/nvme_of.asm"
%include "unet/san/smb3.asm"
%include "unet/san/nfs4.asm"

%include "unet/cgnat/nat64.asm"
%include "unet/cgnat/nptv6.asm"
%include "unet/cgnat/nat444.asm"

%include "unet/ai/rdma_gpudirect.asm"
%include "unet/ai/nccl_transport.asm"

%include "unet/ebpf/smartnic_offload.asm"

%include "unet/mesh/yggdrasil.asm"
%include "unet/mesh/babel.asm"
%include "unet/mesh/batman.asm"

%include "unet/anon/tor_cell.asm"
%include "unet/anon/i2p_garlic.asm"
%include "unet/anon/lokinet.asm"
%include "unet/anon/mixnet.asm"
%include "unet/anon/shadowsocks.asm"
%include "unet/anon/obfs4.asm"
%include "unet/anon/freenet.asm"
%include "unet/anon/nym.asm"

%include "unet/dns/dnssec.asm"
%include "unet/dns/dot_doh.asm"
%include "unet/dns/doq.asm"

%include "unet/services/ntp.asm"
%include "unet/services/dhcp.asm"
%include "unet/services/syslog.asm"
%include "unet/services/radius.asm"
%include "unet/services/snmp.asm"
%include "unet/services/tacacs.asm"
%include "unet/services/ipfix.asm"
%include "unet/services/matter.asm"

%include "unet/identity/oauth2_oidc.asm"
%include "unet/identity/saml2.asm"
%include "unet/identity/spiffe.asm"
%include "unet/identity/did.asm"

%include "unet/security/tls13_session.asm"
%include "unet/security/ipsec.asm"
%include "unet/security/noise_protocol.asm"
%include "unet/security/ztna.asm"
%include "unet/security/macsec.asm"

%include "unet/ssh/ssh_transport.asm"
%include "unet/ssh/ssh_auth.asm"
%include "unet/ssh/ssh_connection.asm"
%include "unet/ssh/sftp.asm"

%include "unet/vpn/wireguard_blake2s.asm"
%include "unet/vpn/openvpn.asm"
%include "unet/vpn/sstp.asm"
%include "unet/vpn/l2tp_ipsec.asm"

%include "unet/pqc/pqc_wireguard.asm"
%include "unet/pqc/pqc_macsec.asm"
%include "unet/pqc/pqc_tls13.asm"

%include "unet/cloud/vxlan.asm"
%include "unet/cloud/geneve.asm"
%include "unet/cloud/gre.asm"
%include "unet/cloud/nvgre.asm"

%include "unet/sdn/openflow.asm"
%include "unet/sdn/p4_runtime.asm"
%include "unet/sdn/srv6.asm"

%include "unet/cni/calico_ebpf.asm"
%include "unet/cni/cilium_bpf.asm"
%include "unet/cni/flannel_overlay.asm"

%include "unet/routing/bgp.asm"
%include "unet/routing/ospf.asm"
%include "unet/routing/isis.asm"

%include "unet/ha/vrrp.asm"
%include "unet/ha/carp.asm"
%include "unet/ha/keepalived.asm"

%include "unet/http/http1.asm"
%include "unet/http/http2.asm"
%include "unet/http/http3.asm"
%include "unet/http/websocket.asm"
%include "unet/http/grpc.asm"

%include "unet/mail/smtp.asm"
%include "unet/mail/imap.asm"
%include "unet/mail/pop3.asm"
%include "unet/mail/dkim.asm"
%include "unet/mail/spf_dmarc.asm"

%include "unet/proxy/socks5.asm"
%include "unet/proxy/haproxy.asm"

%include "unet/drivers/e1000.asm"
%include "unet/drivers/ixgbe.asm"
%include "unet/drivers/mlx5.asm"
%include "unet/drivers/virtio_net.asm"

%include "unet/tools/tools.asm"
%include "unet/tests/tcp_state_test.asm"
%include "unet/tests/pqc_bench.asm"
%include "unet/tests/net_fuzz.asm"
