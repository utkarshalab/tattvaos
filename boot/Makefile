# =============================================================================
# Tattva OS Kernel Build Makefile
# Target: x86-64 Flat Binary Image
# =============================================================================

ASM = nasm
KERNEL_DIR = .

all: kernel.bin

kernel.bin: $(KERNEL_DIR)/entry.asm \
                          $(KERNEL_DIR)/../unet/unet.inc \
                          $(KERNEL_DIR)/../unet/core/pktbuf.asm \
                          $(KERNEL_DIR)/../lib/time/nts.asm \
                          $(KERNEL_DIR)/../lib/time/gnss.asm \
                          $(KERNEL_DIR)/../lib/time/ptp.asm \
                          $(KERNEL_DIR)/../lib/time/timezones.asm \
                          $(KERNEL_DIR)/../lib/time/leap_seconds.asm \
                          $(KERNEL_DIR)/../lib/time/timer_wheel.asm \
                          $(KERNEL_DIR)/../lib/time/clock_drift.asm \
                          $(KERNEL_DIR)/../unet/core/eth.asm \
                          $(KERNEL_DIR)/../unet/core/arp.asm \
                          $(KERNEL_DIR)/../unet/core/ip.asm \
                          $(KERNEL_DIR)/../unet/core/ipv6.asm \
                          $(KERNEL_DIR)/../unet/core/udp.asm \
                          $(KERNEL_DIR)/../unet/core/tcp.asm \
                          $(KERNEL_DIR)/../unet/core/socket.asm \
                          $(KERNEL_DIR)/../unet/http/http1.asm \
                          $(KERNEL_DIR)/../unet/drivers/e1000.asm \
                          $(KERNEL_DIR)/../unet/core/avx512_parser.asm \
                          $(KERNEL_DIR)/../unet/ai/ml_ids.asm \
                          $(KERNEL_DIR)/../unet/ai/reinforce_route.asm \
                          $(KERNEL_DIR)/../unet/ai/predictive_te.asm \
                          $(KERNEL_DIR)/../unet/ai/graph_neural_net.asm \
                          $(KERNEL_DIR)/../unet/ai/autonomous_qos.asm \
                          $(KERNEL_DIR)/../unet/drivers/sriov.asm \
                          $(KERNEL_DIR)/../unet/security/ztna.asm \
                          $(KERNEL_DIR)/../unet/pqc/qkd_km.asm \
                          $(KERNEL_DIR)/../unet/ssh/ssh_transport.asm \
                          $(KERNEL_DIR)/../unet/ssh/ssh_auth.asm \
                          $(KERNEL_DIR)/../unet/ssh/ssh_connection.asm \
                          $(KERNEL_DIR)/../unet/ssh/sftp.asm \
                          $(KERNEL_DIR)/../unet/mail/smtp.asm \
                          $(KERNEL_DIR)/../unet/mail/imap.asm \
                          $(KERNEL_DIR)/../unet/mail/pop3.asm \
                          $(KERNEL_DIR)/../unet/mail/dkim.asm \
                          $(KERNEL_DIR)/../unet/mail/spf_dmarc.asm \
                          $(KERNEL_DIR)/../unet/ebpf/smartnic_offload.asm \
                          $(KERNEL_DIR)/../unet/hpc/roce.asm \
                          $(KERNEL_DIR)/../unet/optical/flex_ethernet.asm \
                          $(KERNEL_DIR)/../unet/ha/carp.asm \
                          $(KERNEL_DIR)/../unet/scada/modbus_tcp.asm \
                          $(KERNEL_DIR)/../unet/telecom/pfcp.asm \
                          $(KERNEL_DIR)/../unet/san/nfs42.asm \
                          $(KERNEL_DIR)/../unet/pqc/pqc_tls13.asm \
                          $(KERNEL_DIR)/../unet/identity/webauthn.asm \
                          $(KERNEL_DIR)/../unet/services/snmpv3.asm \
                          $(KERNEL_DIR)/../unet/security/noise_protocol.asm \
                          $(KERNEL_DIR)/../unet/http/http3_datagram.asm \
                          $(KERNEL_DIR)/../unet/anon/lokinet.asm \
                          $(KERNEL_DIR)/../unet/cgnat/pcp.asm \
                          $(KERNEL_DIR)/../unet/cloud/vswitch.asm \
                          $(KERNEL_DIR)/../unet/wireless/lorawan.asm \
                          $(KERNEL_DIR)/../unet/hft/ouch_soup.asm \
                          $(KERNEL_DIR)/../unet/scada/dlms_cosem.asm \
                          $(KERNEL_DIR)/../unet/vpn/wireguard_blake2s.asm \
                          $(KERNEL_DIR)/../unet/tools/diag/tcpdump_asm.asm \
                          $(KERNEL_DIR)/../unet/tools/diag/netstat_asm.asm \
                          $(KERNEL_DIR)/../unet/tools/bench/iperf_asm.asm \
                          $(KERNEL_DIR)/../unet/tools/diag/ping.asm \
                          $(KERNEL_DIR)/../unet/tools/telecom/dhcpclient.asm \
                          $(KERNEL_DIR)/../unet/tools/telecom/lookup.asm \
                          $(KERNEL_DIR)/../unet/tools/app/http_client.asm \
                          $(KERNEL_DIR)/../unet/tools/app/ssh_client.asm \
                          $(KERNEL_DIR)/../unet/tools/security/wireguard_test.asm \
                          $(KERNEL_DIR)/../unet/tests/tcp_state_test.asm \
                          $(KERNEL_DIR)/../unet/tests/pqc_bench.asm \
                          $(KERNEL_DIR)/../unet/unet.asm

	$(ASM) -f bin $(KERNEL_DIR)/entry.asm -o $(KERNEL_DIR)/kernel.bin

clean:
	rm -f $(KERNEL_DIR)/kernel.bin
