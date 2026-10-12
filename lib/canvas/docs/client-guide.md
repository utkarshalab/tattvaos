# Canvas Client Guide (C33) — Writing a Canvas Client

Link `build/lib/canvas_client.o`. No libc required.

## Minimal Window

```asm
mov rdi, CLIENT_CAP_DISPLAY | CLIENT_CAP_BUFFER | CLIENT_CAP_SURFACE | CLIENT_CAP_PRESENT | CLIENT_CAP_SHELL
call canvas_connect          ; rax = conn
mov rbx, rax
mov rdi, rbx
call canvas_surface_create   ; eax = surface
; ... create buffer, attach, damage, commit
mov rdi, rbx
mov esi, eax
call canvas_toplevel_create
; event loop
.loop:
    sub rsp, 24
    mov rdi, rbx
    mov rsi, rsp
    call canvas_event_poll
    add rsp, 24
    jmp .loop
```

## Rules

1. **No round trips on the hot path.** Create/attach/damage/commit/frame
   are fire-and-forget. Never block the frame on a reply.
2. **Double-buffer.** Keep 2+ buffers in a pool; never draw into a buffer
   the server still holds (wait for release first).
3. **Damage honestly.** Report exactly what changed; over-damage costs
   composition time, under-damage shows stale pixels.
4. **Ack configures.** Apply the size/state from `configure` and ack the
   serial, or the server will keep the old geometry.
5. **One frame callback at a time.** Request the next callback only after
   the previous one fires to pace with vblank.
6. **Clipboard is mediated.** Offer MIME types; transfer on demand; respect
   the 1 MB default limit.
7. **Check your caps.** Privileged interfaces return errors without grants —
   design your app to work sandboxed first.

## Debugging

- Run your client under `canvas-record`, then `canvas-replay` the session.
- `input_test` / `clipboard_test` show canonical event/clipboard handling.
- `bench_latency` shows how to pace commits with presentation feedback.
