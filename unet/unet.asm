; =============================================================================
; Tattva OS — unet/unet.asm
; =============================================================================
; Master Network Stack Engine & Universal Protocol Dispatcher.
;
; Consolidates all 39 single-word pure domain sub-systems across unet/:
;   - Core (with link/), HTTP, DNS, Mail, Proxy, Identity, Security, SSH, VPN, PQC,
;     Cloud, SDN, CNI, Routing, HA, HPC, HFT, Fintech, SCADA, Telecom, Optical, Space,
;     Wireless, Automotive, Avionics, Video, VoIP, Gaming, SAN, CGNAT, QoS, AI,
;     eBPF, Mesh, Anon, Drivers, Tools, Include, Tests.
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
%include "unet/core/pktbuf.asm"
%include "unet/core/eth.asm"
%include "unet/core/arp.asm"
%include "unet/core/ip.asm"
%include "unet/core/ipv6.asm"
%include "unet/core/udp.asm"
%include "unet/core/tcp.asm"
%include "unet/core/tcp_bbr.asm"
%include "unet/core/mptcp.asm"
%include "unet/core/sctp.asm"
%include "unet/core/avx512_parser.asm"
%include "unet/core/socket.asm"
%include "unet/core/epoll.asm"

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
%include "unet/hft/ouch_soup.asm"

%include "unet/fintech/iso20022.asm"
%include "unet/fintech/swift.asm"
%include "unet/fintech/iso8583.asm"

%include "unet/automotive/doip.asm"
%include "unet/automotive/someip.asm"
%include "unet/automotive/can_eth.asm"
%include "unet/automotive/t1_phy.asm"
%include "unet/automotive/avb_tsn.asm"
%include "unet/automotive/doip_uds.asm"

%include "unet/avionics/afdx.asm"
%include "unet/avionics/stanag.asm"
%include "unet/avionics/spacefire.asm"
%include "unet/avionics/mil1553.asm"

%include "unet/space/dvb_s2x.asm"
%include "unet/space/dvb_rcs2.asm"
%include "unet/space/laser_mesh.asm"
%include "unet/space/ccsds.asm"
%include "unet/space/dtn.asm"
%include "unet/space/cfdp.asm"
%include "unet/space/ltp.asm"

%include "unet/wireless/wifi6e.asm"
%include "unet/wireless/bluetooth.asm"
%include "unet/wireless/zigbee.asm"
%include "unet/wireless/capwap.asm"
%include "unet/wireless/eap_tls.asm"
%include "unet/wireless/wpa3_sae.asm"
%include "unet/wireless/lorawan.asm"

%include "unet/optical/pon.asm"
%include "unet/optical/coherent.asm"
%include "unet/optical/g709.asm"
%include "unet/optical/dwdm.asm"
%include "unet/optical/flex_ethernet.asm"

%include "unet/mesh/babel.asm"
%include "unet/mesh/batman.asm"
%include "unet/mesh/yggdrasil.asm"
%include "unet/mesh/tailscale.asm"
%include "unet/mesh/hyperspace.asm"

%include "unet/anon/tor_cell.asm"
%include "unet/anon/i2p_garlic.asm"
%include "unet/anon/lokinet.asm"

%include "unet/cni/cilium.asm"
%include "unet/cni/calico.asm"
%include "unet/cni/kube_proxy.asm"

%include "unet/voip/sip.asm"
%include "unet/voip/sdp.asm"
%include "unet/voip/rtp.asm"
%include "unet/voip/srtp.asm"
%include "unet/voip/codecs.asm"
%include "unet/voip/ice_stun.asm"

%include "unet/telecom/diameter.asm"
%include "unet/telecom/pfcp.asm"

%include "unet/video/srt.asm"
%include "unet/video/rtmp.asm"
%include "unet/video/hls_dash.asm"
%include "unet/video/webrtc_sfu.asm"
%include "unet/video/rtp_av1.asm"
%include "unet/video/rtp_hevc.asm"
%include "unet/video/rtp_h264.asm"
%include "unet/video/moq.asm"

%include "unet/gaming/e2s.asm"
%include "unet/gaming/raknet.asm"

%include "unet/cgnat/cgnat.asm"
%include "unet/cgnat/nat64.asm"
%include "unet/cgnat/ds_lite.asm"
%include "unet/cgnat/pcp.asm"

%include "unet/cloud/aws_tgw.asm"
%include "unet/cloud/azure_express.asm"
%include "unet/cloud/gcp_interconnect.asm"
%include "unet/cloud/vswitch.asm"

%include "unet/ai/reinforce_route.asm"
%include "unet/ai/ml_ids.asm"
%include "unet/ai/predictive_te.asm"
%include "unet/ai/graph_neural_net.asm"
%include "unet/ai/autonomous_qos.asm"

%include "unet/scada/dnp3.asm"
%include "unet/scada/iec61850.asm"
%include "unet/scada/modbus_tcp.asm"
%include "unet/scada/dlms_cosem.asm"

%include "lib/time/nts.asm"
%include "lib/time/gnss.asm"

%include "unet/san/nvme_of_tcp.asm"
%include "unet/san/iscsi.asm"
%include "unet/san/nvme_of_rdma.asm"
%include "unet/san/smb3.asm"
%include "unet/san/webdav.asm"
%include "unet/san/nfs42.asm"
%include "unet/san/fcoe.asm"
%include "unet/san/fip.asm"

%include "unet/vpn/openvpn.asm"
%include "unet/vpn/sstp.asm"
%include "unet/vpn/l2tp_ipsec.asm"
%include "unet/vpn/wireguard_blake2s.asm"

%include "unet/pqc/pqc_wireguard.asm"
%include "unet/pqc/pqc_macsec.asm"
%include "unet/pqc/pqc_tls13.asm"
%include "unet/pqc/qkd_km.asm"

%include "unet/routing/bgp.asm"
%include "unet/routing/evpn.asm"
%include "unet/routing/ospf.asm"
%include "unet/routing/isis.asm"
%include "unet/routing/vrf_manager.asm"
%include "unet/routing/netns.asm"
%include "unet/routing/pim_sm.asm"
%include "unet/routing/pim_dm.asm"

%include "unet/ha/vrrp.asm"
%include "unet/ha/hsrp.asm"
%include "unet/ha/pacemaker.asm"
%include "unet/ha/carp.asm"

%include "unet/security/tls13_session.asm"
%include "unet/security/ssh_server.asm"
%include "unet/security/ipsec.asm"
%include "unet/security/qkd.asm"
%include "unet/security/firewall.asm"
%include "unet/security/ddos.asm"
%include "unet/security/ztna.asm"
%include "unet/security/noise_protocol.asm"
%include "unet/security/tpm2.asm"
%include "unet/security/nitro.asm"

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
%include "unet/http/http3_datagram.asm"

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
%include "unet/identity/kerberos.asm"
%include "unet/identity/webauthn.asm"

%include "unet/services/radius.asm"
%include "unet/services/tacacs.asm"
%include "unet/services/syslog.asm"
%include "unet/services/dhcp.asm"
%include "unet/services/ntp.asm"
%include "unet/services/ipfix.asm"
%include "unet/services/mqtt.asm"
%include "unet/services/matter.asm"
%include "unet/services/opcua.asm"
%include "unet/services/snmpv3.asm"

%include "unet/ebpf/ebpf.asm"
%include "unet/ebpf/dpdk.asm"
%include "unet/ebpf/smartnic_offload.asm"

%include "unet/sdn/gre.asm"
%include "unet/sdn/nvgre.asm"
%include "unet/sdn/l2tp.asm"
%include "unet/sdn/ipip.asm"
%include "unet/sdn/wireguard.asm"
%include "unet/sdn/vxlan.asm"
%include "unet/sdn/geneve.asm"
%include "unet/sdn/mpls.asm"

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
%include "unet/drivers/sriov.asm"

; -----------------------------------------------------------------------------
; Master `net` CLI Registration & Dispatcher (10 Single-Word Category Folders)
; -----------------------------------------------------------------------------
%include "unet/tools/tools.asm"

; diag/
%include "unet/tools/diag/ping.asm"
%include "unet/tools/diag/traceroute.asm"
%include "unet/tools/diag/tcpdump_asm.asm"
%include "unet/tools/diag/netstat_asm.asm"
%include "unet/tools/diag/ss_tool.asm"
%include "unet/tools/diag/mtr.asm"
%include "unet/tools/diag/latency_meter.asm"

; bench/
%include "unet/tools/bench/iperf_asm.asm"
%include "unet/tools/bench/pktgen.asm"
%include "unet/tools/bench/dpdk_pktgen.asm"
%include "unet/tools/bench/rdma_perftest.asm"
%include "unet/tools/bench/quic_bench.asm"
%include "unet/tools/bench/hft_bench.asm"

; route/
%include "unet/tools/route/route_tool.asm"
%include "unet/tools/route/arp_tool.asm"
%include "unet/tools/route/ndp.asm"
%include "unet/tools/route/bridge.asm"
%include "unet/tools/route/bgp_view.asm"
%include "unet/tools/route/ospf_view.asm"
%include "unet/tools/route/subnet_manager.asm"
%include "unet/tools/route/sr_v6_top.asm"
%include "unet/tools/route/netns_exec.asm"
%include "unet/tools/route/carp_test.asm"
%include "unet/tools/route/lacp_test.asm"

; security/
%include "unet/tools/security/wireguard_test.asm"
%include "unet/tools/security/tls_info.asm"
%include "unet/tools/security/pqc_inspect.asm"
%include "unet/tools/security/ipsec_test.asm"
%include "unet/tools/security/ipsec_top.asm"
%include "unet/tools/security/ztna_auth.asm"
%include "unet/tools/security/qkd_keys.asm"
%include "unet/tools/security/macsec_mon.asm"
%include "unet/tools/security/dnssec_check.asm"
%include "unet/tools/security/tor_circuit.asm"

; telecom/
%include "unet/tools/telecom/dhcpclient.asm"
%include "unet/tools/telecom/ntpdate.asm"
%include "unet/tools/telecom/lookup.asm"
%include "unet/tools/telecom/quectel_5g.asm"
%include "unet/tools/telecom/g709_fec_mon.asm"
%include "unet/tools/telecom/ipfix_cap.asm"
%include "unet/tools/telecom/syslog_tail.asm"
%include "unet/tools/telecom/radius_test.asm"
%include "unet/tools/telecom/nat64_ping.asm"
%include "unet/tools/telecom/tailscale_ping.asm"

; hpc/
%include "unet/tools/hpc/ib_diags.asm"
%include "unet/tools/hpc/rocev2_info.asm"
%include "unet/tools/hpc/slingshot_stat.asm"
%include "unet/tools/hpc/cxi_info.asm"
%include "unet/tools/hpc/ebpf_top.asm"
%include "unet/tools/hpc/ptp_diag.asm"
%include "unet/tools/hpc/bfd_test.asm"
%include "unet/tools/hpc/pfc_test.asm"
%include "unet/tools/hpc/ecn_monitor.asm"
%include "unet/tools/hpc/stt_test.asm"

; iot/
%include "unet/tools/iot/mqtt_pub.asm"
%include "unet/tools/iot/mqtt_sub.asm"
%include "unet/tools/iot/coap_client.asm"
%include "unet/tools/iot/coap_observe.asm"
%include "unet/tools/iot/opcua_client.asm"
%include "unet/tools/iot/lorawan_mon.asm"
%include "unet/tools/iot/matter_commission.asm"

; san/
%include "unet/tools/san/nfs_client.asm"
%include "unet/tools/san/iscsi_initiator.asm"
%include "unet/tools/san/nvme_diag.asm"
%include "unet/tools/san/smb_ls.asm"
%include "unet/tools/san/sftp_cli.asm"

; industrial/
%include "unet/tools/industrial/modbus_poll.asm"
%include "unet/tools/industrial/dnp3_control.asm"
%include "unet/tools/industrial/can_dump.asm"
%include "unet/tools/industrial/doip_flash.asm"
%include "unet/tools/industrial/afdx_mon.asm"
%include "unet/tools/industrial/mil1553_mon.asm"
%include "unet/tools/industrial/laser_align.asm"
%include "unet/tools/industrial/cfdp_get.asm"

; app/
%include "unet/tools/app/http_client.asm"
%include "unet/tools/app/ssh_client.asm"
%include "unet/tools/app/grpc_curl.asm"
%include "unet/tools/app/websocket_cat.asm"
%include "unet/tools/app/rtmp_stream.asm"
%include "unet/tools/app/webrtc_ping.asm"
%include "unet/tools/app/swift_msg.asm"
%include "unet/tools/app/fix_fuzzer.asm"
%include "unet/tools/app/imap_test.asm"
%include "unet/tools/app/smtp_test.asm"
%include "unet/tools/app/snmp_get.asm"
%include "unet/tools/app/snmp_walk.asm"
%include "unet/tools/app/tfo_test.asm"
%include "unet/tools/app/vxlan_test.asm"
%include "unet/tools/app/geneve_test.asm"
%include "unet/tools/app/multicast.asm"

%include "unet/tests/tcp_state_test.asm"
%include "unet/tests/pqc_bench.asm"
%include "unet/tests/net_fuzz.asm"

%include "unet/ssh/ssh_transport.asm"
%include "unet/ssh/ssh_auth.asm"
%include "unet/ssh/ssh_connection.asm"
%include "unet/ssh/sftp.asm"

%include "unet/mail/smtp.asm"
%include "unet/mail/imap.asm"
%include "unet/mail/pop3.asm"
%include "unet/mail/dkim.asm"
%include "unet/mail/spf_dmarc.asm"
