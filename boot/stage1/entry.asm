; =============================================================================
; Tattva OS — boot/stage1/entry.asm
; =============================================================================
; MBR bootloader entry point.
; BIOS loads this to 0x7C00, executes from here.
; Must fit in 446 bytes total with all includes.
;
; Responsibilities:
;   1. Initialize segment registers + stack
;   2. Save boot drive number (DL)
;   3. Relocate self to 0x0600 (free up 0x7C00 for stage2 stack)
;   4. Enable A20 line (fast method only, stage2 handles fallbacks)
;   5. Load stage2 from disk to 0x8000
;   6. Verify stage2 magic number
;   7. Jump to stage2
;
; Memory layout at entry:
;   0x0000 - 0x04FF   BIOS data area (do not touch)
;   0x0500 - 0x05FF   free
;   0x0600 - 0x07FF   we relocate here
;   0x7C00 - 0x7DFF   BIOS loaded us here (512 bytes)
;   0x7E00 - 0x7FFF   free
;   0x8000 - 0xFFFF   stage2 loads here
;
; Author:  Utkarsha Labs
; Target:  x86-64, BIOS boot, real mode (16-bit)
; Syntax:  NASM
; =============================================================================

[BITS 16]
[ORG 0x7C00]

; -----------------------------------------------------------------------------
; includes — constants and storage first
; -----------------------------------------------------------------------------
%include "config.asm"

; =============================================================================
; entry — first instruction the CPU executes after BIOS handoff
; =============================================================================
entry:
    ; -------------------------------------------------------------------------
    ; STEP 1: Initialize segment registers and stack
    ; -------------------------------------------------------------------------
    ; BIOS leaves registers in undefined state.
    ; Must initialize BEFORE anything else.
    ; Works in QEMU without this. Fails on real hardware without this.
    ; -------------------------------------------------------------------------
    cli                             ; disable interrupts during setup
    cld                             ; Clear direction flag for string copy operations

    xor ax, ax                      ; ax = 0
    mov ds, ax                      ; data segment = 0x0000
    mov es, ax                      ; extra segment = 0x0000
    mov ss, ax                      ; stack segment = 0x0000
    mov sp, STACK_REAL              ; stack pointer = 0x7C00
                                    ; stack grows DOWN from here
                                    ; safe: we relocate MBR before using stack heavily

    ; -------------------------------------------------------------------------
    ; STEP 2: Save boot drive number from DL
    ; -------------------------------------------------------------------------
    ; BIOS puts boot drive number in DL at entry.
    ; ANY INT call can overwrite DL.
    ; Save it to memory IMMEDIATELY — before any INT call of any kind.
    ; This is the #1 cause of bootloaders failing on real hardware.
    ; -------------------------------------------------------------------------
    mov [boot_drive], dl            ; save drive number now

    ; -------------------------------------------------------------------------
    ; STEP 3: Relocate MBR from 0x7C00 to 0x0600
    ; -------------------------------------------------------------------------
    ; Why: BIOS loads stage2 to 0x8000. Stage2 needs stack space below 0x8000.
    ;      If MBR stays at 0x7C00, the stack would collide with it.
    ;      Relocating to 0x0600 frees the 0x7C00-0x7FFF region for the stack.
    ;
    ; How: Copy 512 bytes from 0x7C00 to 0x0600.
    ;      Far jump to relocated code.
    ; -------------------------------------------------------------------------
    mov si, 0x7C00                  ; source: current MBR location
    mov di, STAGE1_RELOC            ; dest:   0x0600
    mov cx, 512                     ; copy 512 bytes (full MBR)
    rep movsb                       ; copy SI → DI, decrement CX

    ; NASM labels include ORG 0x7C00, so a direct jump to relocated_entry
    ; would silently jump back into the original sector.  Translate the
    ; label to its offset inside the copy before making the far jump.
    jmp 0x0000:(STAGE1_RELOC + relocated_entry - $$)

; =============================================================================
; relocated_entry — continues execution from 0x0600
; Code executes from the 0x0600 copy.  Absolute data addresses intentionally
; continue to reference the original sector at 0x7C00; the stage2 stack cannot
; overwrite the preserved 0x0600 copy used by measured boot.
; =============================================================================
relocated_entry:
    ; -------------------------------------------------------------------------
    ; Re-initialize segments after relocation
    ; CS is now pointing into the 0x0600 region via far jump.
    ; DS/ES/SS still point to 0x0000 which is correct.
    ; Stack is safe — we relocated before heavy stack use.
    ; -------------------------------------------------------------------------
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, STACK_REAL              ; stack at 0x7C00 (MBR region now free)
    sti                             ; relocation is complete; BIOS may use IRQs

    ; -------------------------------------------------------------------------
    ; STEP 4: Quick A20 enable (fast port 0x92 method)
    ; -------------------------------------------------------------------------
    ; We try the fast method here in stage1 for speed.
    ; Stage2 will do full A20 verification + fallbacks.
    ; This handles QEMU and most modern hardware immediately.
    ; -------------------------------------------------------------------------
    in al, 0x92                     ; read port 0x92
    test al, 0x02                   ; check if A20 already enabled
    jnz .a20_done                   ; if bit 1 set, already enabled
    or al, 0x02                     ; set bit 1 (A20 enable)
    and al, 0xFE                    ; clear bit 0 (do not reset system)
    out 0x92, al                    ; write back

.a20_done:
    ; -------------------------------------------------------------------------
    ; STEP 5: Detect LBA support
    ; -------------------------------------------------------------------------
    ; Loading 64 sectors in one legacy CHS request crosses a track boundary
    ; and is not portable.  The x86-64 target therefore requires BIOS EDD and
    ; fails closed when extended disk reads are unavailable.
    ; -------------------------------------------------------------------------
    mov ah, 0x41                    ; INT 13h AH=41h: check LBA extensions
    mov bx, 0x55AA                  ; magic value required by BIOS
    mov dl, [boot_drive]            ; boot drive
    int 0x13                        ; call BIOS
    pushf                           ; restore segments without losing CF
    xor ax, ax                      ; defensive: buggy BIOSes may alter DS/ES
    mov ds, ax
    mov es, ax
    popf
    jc .edd_error                   ; carry set = EDD not supported
    cmp bx, 0xAA55                  ; BIOS should flip magic value
    jne .edd_error                  ; if not flipped, EDD is not real
    test cx, 0x0001                 ; bit 0 advertises extended disk access
    jz .edd_error

    ; -------------------------------------------------------------------------
    ; STEP 6: Load stage2 from disk
    ; -------------------------------------------------------------------------
    ; Stage2 starts at LBA sector 1 (sector after MBR).
    ; We load STAGE2_SECTORS sectors to STAGE2_LOAD (0x8000).
    ; -------------------------------------------------------------------------
    mov byte [disk_retries], DISK_RETRY

.load_lba:
    ; BIOS may replace the DAP count with a partial-transfer count on error.
    ; Every retry starts the complete transfer from LBA 1 again.
    mov word [lba_packet + 2], STAGE2_SECTORS
    mov si, lba_packet              ; point to disk address packet
    mov ah, 0x42                    ; INT 13h AH=42h: extended read
    mov dl, [boot_drive]
    int 0x13
    pushf
    xor ax, ax                      ; restore flat data segments after BIOS
    mov ds, ax
    mov es, ax
    popf
    jnc .load_done

    dec byte [disk_retries]
    jz .disk_error

    ; Reset the same BIOS drive before retrying.  Rebuild every input to the
    ; extended-read call on each iteration instead of trusting BIOS register
    ; preservation after an error.
    xor ax, ax                      ; INT 13h AH=00h: reset disk system
    mov dl, [boot_drive]
    int 0x13
    xor ax, ax
    mov ds, ax
    mov es, ax
    jmp .load_lba

.edd_error:
    mov si, msg_edd_error
    call print_str
    jmp .halt

.disk_error:
    ; print error and halt
    ; E = disk Error
    mov si, msg_disk_error
    call print_str
    jmp .halt

.load_done:
    ; -------------------------------------------------------------------------
    ; STEP 7: Verify stage2 magic number
    ; -------------------------------------------------------------------------
    ; Read first 4 bytes of loaded stage2.
    ; Must match STAGE2_MAGIC or we loaded garbage.
    ; -------------------------------------------------------------------------
    mov eax, [STAGE2_LOAD]          ; read first dword of stage2
    cmp eax, STAGE2_MAGIC           ; compare to expected magic
    jne .magic_error                ; mismatch = wrong data loaded

    ; -------------------------------------------------------------------------
    ; STEP 8: Jump to stage2
    ; -------------------------------------------------------------------------
    ; Pass boot_drive in DL (stage2 convention).
    ; Stage2 will re-save it immediately on entry.
    ; -------------------------------------------------------------------------
    mov dl, [boot_drive]            ; restore DL for stage2
    ; This must be an absolute far jump: a near jump assembled under ORG
    ; 0x7C00 would retain the relocation delta while executing at 0x0600.
    jmp 0x0000:(STAGE2_LOAD + 4)    ; jump to 0x8004 (skip magic number)

.magic_error:
    mov si, msg_magic_error
    call print_str
    jmp .halt

.halt:
    cli                             ; disable interrupts
    hlt                             ; halt CPU
    jmp .halt                       ; if NMI wakes us, halt again

; =============================================================================
; print_str — print null-terminated string via BIOS INT 10h and COM1
; Input: SI = pointer to string
; Clobbers: AX, BX, DX, SI
; =============================================================================
print_str:
    call serial_init
    cld                             ; Clear direction flag for lodsb
    mov ah, 0x0E                    ; BIOS teletype output
    mov bh, 0                       ; page 0
    mov bl, 0x07                    ; light grey on black

.loop:
    lodsb                           ; load byte from SI, advance SI
    test al, al                     ; check for null terminator
    jz .done
    push ax                         ; BIOS is not required to preserve AL
    int 0x10                        ; print character
    pop ax
    call serial_putc                ; mirror fatal diagnostics for headless boot
    jmp .loop

.done:
    ret

; Minimal 115200 8-N-1 COM1 setup.  Stage2 initializes the UART again on a
; successful boot; stage1 only needs it on a fatal path.
serial_init:
    mov dx, UART_COM1 + 1
    xor al, al                      ; disable UART interrupts
    out dx, al
    mov dx, UART_COM1 + 3
    mov al, 0x80                    ; enable divisor latch
    out dx, al
    mov dx, UART_COM1
    mov al, UART_BAUD_DIV
    out dx, al
    inc dx
    xor al, al                      ; divisor high byte
    out dx, al
    mov dx, UART_COM1 + 3
    mov al, 0x03                    ; 8 data bits, no parity, 1 stop bit
    out dx, al
    mov dx, UART_COM1 + 2
    mov al, 0xC7                    ; enable and clear FIFO
    out dx, al
    mov dx, UART_COM1 + 4
    mov al, 0x0B                    ; DTR, RTS, OUT2
    out dx, al
    ret

serial_putc:
    push ax
    push cx
    mov cx, 0xFFFF                  ; never hang forever on a faulty UART
    mov dx, UART_COM1 + 5
.wait:
    in al, dx
    test al, 0x20                   ; transmitter holding register empty
    jnz .ready
    loop .wait
    pop cx                          ; timeout: retain the VGA diagnostic
    pop ax
    ret
.ready:
    pop cx
    pop ax
    mov dx, UART_COM1
    out dx, al
    ret

; =============================================================================
; Data
; =============================================================================

; LBA disk address packet for INT 13h AH=42h
align 2
lba_packet:
    db 0x10                         ; packet size = 16 bytes
    db 0x00                         ; reserved, must be 0
    dw STAGE2_SECTORS               ; number of sectors to read
    dw STAGE2_LOAD                  ; memory offset  (0x8000)
    dw 0x0000                       ; memory segment (0x0000)
    dq 0x0000000000000001           ; LBA start sector = 1 (after MBR)

disk_retries:
    db 0

; Error messages (keep short — we are counting bytes)
msg_disk_error:
    db "Disk err", 0x0D, 0x0A, 0

msg_edd_error:
    db "EDD req", 0x0D, 0x0A, 0

msg_magic_error:
    db "Bad magic", 0x0D, 0x0A, 0

; =============================================================================
; includes — signature must be last, pads to exactly 512 bytes
; =============================================================================
%include "boot_drive.asm"
%include "signature.asm"

; =============================================================================
; End of entry.asm
; Total must be exactly 512 bytes after NASM assembles.
; Makefile checks stage1.bin <= 446 bytes (code + data only).
; signature.asm pads to 512 with partition table space + 0x55AA.
; =============================================================================
