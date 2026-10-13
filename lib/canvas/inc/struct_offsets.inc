; ============================================================================
; Common Struct Offsets — Seat, Pointer, Focus, Surface, Buffer, etc.
; ============================================================================

%ifndef __STRUCT_OFFSETS_INC__
%define __STRUCT_OFFSETS_INC__

; Seat
%define Seat.capabilities    0
%define Seat.pointer         8
%define Seat.keyboard        16
%define Seat.touch           24
%define Seat.name            32
%define Seat_size            40

; Pointer
%define Pointer.x            0
%define Pointer.y            8
%define Pointer.serial       16
%define Pointer.seat         24
%define Pointer_size         32

; Focus
%define Focus.surface        0
%define Focus.serial         8
%define Focus.seat           16
%define Focus_size           24

; Surface
%define Surface.current      0
%define Surface.pending      8
%define Surface.width        16
%define Surface.height       24
%define Surface.format       32
%define Surface.buffer       40
%define Surface.damage       48
%define Surface_size         56

; SurfaceState
%define SurfaceState.buffer  0
%define SurfaceState.damage  8
%define SurfaceState.pending 16
%define SurfaceState.buf_x   24
%define SurfaceState.buf_y   32
%define SurfaceState_size    40

; Buffer
%define Buffer.base          0
%define Buffer.size          8
%define Buffer.format        16
%define Buffer.width         24
%define Buffer.height        32
%define Buffer.stride        40
%define Buffer.state         48
%define Buffer.client_id     56
%define Buffer.gpu_bo        64
%define Buffer_size          72

; Client
%define Client.id            0
%define Client.caps          8
%define Client.trust_profile 16
%define Client.quota         24
%define Client.ratelimit     32
%define Client.obj_table     40
%define Client.last_ping     48
%define Client.ping_serial   56
%define Client.verified      64
%define Client_size          72

; Output
%define Output.x             0
%define Output.y             8
%define Output.width         16
%define Output.height        24
%define Output.connected     32
%define Output.controller    40
%define Output.crtc_index    48
%define Output.edid          56
%define Output.hpd_irq       64
%define Output.hpd_register  72
%define Output.i2c_bus       80
%define Output.current_surface 88
%define Output.current_mode  96
%define Output.surfaces      104
%define Output.toplevels     112
%define Output.hotplug_callback 120
%define Output.next          128
%define Output.stride        136
%define Output_size          144

; Controller
%define Controller.state         0
%define Controller.mmio_base     8
%define Controller.outputs       16
%define Controller.size          24

; Backend
%define Backend.state         0
%define Backend.server        8
%define Backend.capabilities  16
%define Backend.size          24

; Mode (extended)
%define Mode.hsync_width     96
%define Mode.vsync_width     104
%define Mode.hborder         112
%define Mode.vborder         120
%define Mode.width_mm        128
%define Mode.height_mm       136
%define Mode_size            144

; Mode flags
%define MODE_FLAG_HSYNC_POSITIVE   (1 << 0)
%define MODE_FLAG_VSYNC_POSITIVE   (1 << 1)
%define MODE_FLAG_INTERLACED       (1 << 2)
%define MODE_FLAG_DBLSCAN          (1 << 3)
%define MODE_FLAG_CSYNC            (1 << 4)
%define MODE_FLAG_PCSYNC           (1 << 5)

; Mode
%define Mode.width           0
%define Mode.height          8
%define Mode.htotal          16
%define Mode.hsync_start     24
%define Mode.hsync_end       32
%define Mode.hblank          40
%define Mode.vtotal          48
%define Mode.vsync_start     56
%define Mode.vsync_end       64
%define Mode.vblank          72
%define Mode.pixel_clock     80
%define Mode.flags           88
%define Mode.hsync_width     96
%define Mode.vsync_width     104
%define Mode.hborder         112
%define Mode.vborder         120
%define Mode.width_mm        128
%define Mode.height_mm       136
%define Mode_size            144

%endif ; __STRUCT_OFFSETS_INC__