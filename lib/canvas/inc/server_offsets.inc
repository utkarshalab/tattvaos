; ============================================================================
; Server Structure Offsets — Central Definition
; All Server struct field offsets in one place
; ============================================================================

%ifndef __SERVER_OFFSETS_INC__
%define __SERVER_OFFSETS_INC__

; Core server fields
%define Server.client_registry      0
%define Server.next_client_id       8
%define Server.arena                16

; Output management (from output/output.asm)
%define Server.outputs              0x80
%define Server.output_count         0x88
%define Server.layout_bounds        0x90

; DPMS (from output/dpms.asm)
%define Server.dpms_state           0x90
%define Server.dpms_timeout         0x94
%define Server.dpms_suspend_timeout 0x98
%define Server.dpms_off_timeout     0x9C

; PCI/Framebuffer (from backend/native/native_pci.asm)
%define Server.fb_base              0x100
%define Server.fb_size              0x108
%define Server.mmio_base            0x110
%define Server.mmio_size            0x118
%define Server.pci_dev              0x120
%define Server.irq                  0x128
%define Server.arena                0x130  ; duplicate, same value

; Accessibility
%define Server.a11y_tree            0x140
%define Server.a11y_events          0x148
%define Server.a11y_reader_hooks    0x150
%define Server.magnifier            0x158
%define Server.sticky_keys          0x160

; Seat/Input
%define Server.default_seat         0x170
%define Server.focus                0x178
%define Server.seat_count           0x180
%define Server.seats                0x188

; Surface/Buffer
%define Server.surface_table        0x190
%define Server.buffer_table         0x198
%define Server.fence_table          0x1A0
%define Server.timeline_table       0x1A8
%define Server.region_table         0x1B0

; Capabilities
%define Server.caps                 0x1B8

; Extend this compatibility view only when a subsystem cannot include the
; generated canonical offsets.

%endif ; __SERVER_OFFSETS_INC__
