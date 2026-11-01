; =============================================================================
; uxpw.asm — uxpw v1 memory-hard password hashing over the dash core.
;
; Frozen spec: lib/crypto/uxpw/uxpw.md. The id-style indexing semantics mirror
; the Argon2 reference (P-H-C phc-winner-argon2, CC0); every primitive is ours:
; dash128 == official XXH3-128 (bit-proven, 536/0 cross-checked).
; Construction is differential-tested against tmp/verify/uxpw_ref.c, which
; calls the official xxHash library for dash256.
;
; House ABI: clobber only SysV-volatile (RAX RCX RDX RSI RDI R8-R11);
; functions needing more push/pop them. Absolute addressing ([label]); the
; build links -no-pie. uxpw.o links with dash.o (global dash_hash256).
;
; uxpw_ctx_t: 10 packed u64 fields (spec §10):
;     0  mem      m' KiB scratch buffer (caller-provided)
;     8  m        requested memory cost, KiB
;     16 t        passes
;     24 p        lanes
;     32 pwd
;     40 pwdlen   0..1024
;     48 salt
;     56 saltlen  8..64
;     64 taglen   16..64
;     72 out      >= taglen bytes (tag written here)
;   (record create/verify wrappers land in a later chunk; uxpw_hash is raw)
;
; Exported: uxpw_hash(RDI = ctx) -> RAX = 0 ok / negative error
;   -1 memory, -2 bad m/t/p, -3 salt range, -4 pwd range, -5 tag range

global uxpw_hash
;
; Fill-loop register plan:
;   r12 = ctx, r13 = pass, r14 = slice, r15 = lane, rbx = lane_len,
;   rbp = seg_len ; i/cur/prev/nblk in stack slots (survive dash calls)
; =============================================================================

%define UXPW_PWDLEN_MAX   1024
%define UXPW_SALT_MAX     64
%define UXPW_TAGLEN_MAX   64
%define UXPW_MPRIME_MAX   4194304              ; 2^22 KiB

; --- local stack layout inside uxpw_hash (rsp 64-byte aligned after `and`) ---
%define UX_T       0                            ; 1024 B: xor-in / fb u / addr scratch / tag X
%define UX_Z       1024                         ; 1024 B: G out / chunk staging
%define UX_ADDR    2048                         ; 1024 B: address block / tag chunks
%define UX_HBUF    3072                         ; 1280 B: H0 build / tag build
%define UX_H0      4352                         ; 32 B: H0
%define UX_MP      4384                         ; mprime KiB
%define UX_LAN     4392                         ; lane_len blocks
%define UX_SEG     4400                         ; seg_len blocks
%define UX_N       4408                         ; H0 encode length
%define UX_START   4416
%define UX_INDEP   4424
%define UX_I       4432
%define UX_CUR     4440
%define UX_PREV    4448
%define UX_NBLK    4456
%define UX_W       4464                         ; pseudo rand source word (j1|j2<<32)
%define UX_RPTR    4472
%define UX_PPTR    4480
%define UX_CPTR    4488
%define UX_TMP     4496                         ; scratch slot (quotients)
%define UX_ANCHOR  4504                         ; frame anchor (rbp is reused
                                                 ;   as seg_len during fill)
;   touched through 4511; allocated 5120 (+ pad below)

section .rodata

align 8
ux_prose_h0:   dq 0x0030680077707875            ; bytes "uxpw\0h0"
ux_prose_addr: dq 0x7264646177707875            ; bytes "uxpwaddr"
ux_prose_tag:  dq 0x6761740077707875            ; bytes "uxpw\0tag"
ux_h0_seed:    dq 0x9E3779B97F4A7C15, 0x1BD1E0F51E0C5B6D
ux_addr_seed:  dq 0xA0761D6478BD642F, 0xE7037ED1A0B428DB
ux_g_seal:     dq 0xBF58476D1CE4E5B9, 0x94D049BB133111EB

section .text

extern dash_hash256

; ----------------------------------------------------------------------------
; ux_addr_gen — generate one 1 KiB address block of the independent stream.
;   RDI = pass, RSI = slice, RDX = lane, RCX = block counter n,
;   R8 = out (128 qword slots), R9 = scratch (>= 48 bytes; may be UX_T)
; Chain: w starts at UX_ADDR_SEED and steps to (v.q0, v.q1) per call; the
; per-step input is prose(8) || pass || slice || lane || n || step (48 B).
; ----------------------------------------------------------------------------
align 16
ux_addr_gen:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 24                          ; w.lo @0, w.hi @8, pad

        mov     r12, rdi                         ; pass
        mov     r13, rsi                         ; slice
        mov     r14, rdx                         ; lane
        mov     r15, rcx                         ; n
        mov     rbx, r8                          ; out cursor
        mov     rbp, r9                          ; scratch
        mov     rax, 0xA0761D6478BD642F          ; w.lo
        mov     [rsp], rax
        mov     rax, 0xE7037ED1A0B428DB          ; w.hi
        mov     [rsp + 8], rax

        mov     rax, [ux_prose_addr]
        mov     [rbp], rax
        mov     rax, r12
        mov     [rbp + 8], rax
        mov     rax, r13
        mov     [rbp + 16], rax
        mov     rax, r14
        mov     [rbp + 24], rax
        mov     rax, r15
        mov     [rbp + 32], rax

        xor     r10, r10                         ; step i
.ag_step:
        mov     rax, r10
        mov     [rbp + 40], rax                  ; step counter

        mov     rdi, rbp
        mov     esi, 48
        mov     rdx, [rsp]                       ; w.lo
        mov     rcx, [rsp + 8]                   ; w.hi
        mov     r8, rbx                          ; out = cursor
        call    dash_hash256

        mov     rax, [rbx]                       ; w = (v.q0, v.q1)
        mov     [rsp], rax
        mov     rax, [rbx + 8]
        mov     [rsp + 8], rax
        add     rbx, 32
        inc     r10
        cmp     r10, 32
        jb      .ag_step

        add     rsp, 24
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; ----------------------------------------------------------------------------
; ux_g — chain-scatter block mixer (spec §7).  RDI = T (in), RSI = Z (out).
; Strictly serial per step; every output qword transitively depends on every
; input qword (forward + backward chains + whole-block dash absorb/seal).
; ----------------------------------------------------------------------------
align 16
global ux_g              ; internal; exported for differential probes/tests
ux_g:
        push    rbx
        push    rbp
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 8                           ; keep rsp 16-aligned at calls

        mov     r12, rdi                         ; T
        mov     r13, rsi                         ; Z

        ; ---- absorb: 16 stripes of 64 bytes, chain (v.q0, v.q1) ----
        mov     rbx, [ux_g_seal]                 ; w.lo
        mov     rbp, [ux_g_seal + 8]             ; w.hi
        xor     r15, r15                         ; stripe byte cursor
.g_abs:
        lea     rdi, [r12 + r15]                 ; data = T + 64*s
        mov     esi, 64
        mov     rdx, rbx
        mov     rcx, rbp
        mov     r8, r13                          ; v out = Z head (scratch,
                                                 ;   Z unused until chains)
        call    dash_hash256
        mov     rax, [r13]                       ; chain = (v.q0, v.q1)
        mov     rbx, rax
        mov     rax, [r13 + 8]
        mov     rbp, rax
        add     r15, 64
        cmp     r15, 1024
        jb      .g_abs

        ; D = (rbx, rbp)
        ; ---- forward chain ----
        mov     r8, rbx                          ; lo = D.lo
        mov     r9, rbp                          ; hi = D.hi
        xor     r14, r14                         ; j
.g_fwd:
        mov     rax, [r12 + r14 * 8]             ; T[j]
        xor     rax, r9                          ; z
        mov     r10, rax                         ; z kept
        mov     eax, eax                         ; lo32(z), zero-extended
        mov     r11, r10
        shr     r11, 32                          ; hi32(z)
        imul    rax, r11                         ; m = lo * hi (exact)
        mov     r11, rax                         ; r11 = m
        xor     rax, r10                         ; z ^ m
        mov     [r13 + r14 * 8], rax             ; Z[j]
        rol     r8, 19                           ; rotl64(lo, 19)
        xor     r10, r8                          ; z ^ rotl(lo)  -> new hi
        mov     r9, r10
        mov     r8, r11                          ; lo = m
        inc     r14
        cmp     r14, 128
        jb      .g_fwd

        ; ---- backward chain (in place) ----
        mov     r8, rbx                          ; lo = D.lo
        mov     r9, rbp                          ; hi = D.hi
        mov     r14, 127
.g_bwd:
        mov     r10, [r13 + r14 * 8]             ; Z[j]
        xor     r10, r9                          ; z
        mov     eax, r10d                        ; lo32(z)
        mov     r11, r10
        shr     r11, 32                          ; hi32(z)
        imul    rax, r11                         ; m
        mov     r11, rax                         ; m kept (mirror fwd)
        xor     rax, r10                         ; z ^ m
        mov     [r13 + r14 * 8], rax             ; Z[j]
        rol     r8, 17                           ; rotl64(lo, 17)
        xor     r10, r8                          ; new hi
        mov     r9, r10
        mov     r8, r11                          ; lo = m
        dec     r14
        jns     .g_bwd

        ; ---- seal ----
        mov     rax, rbx                         ; S = D.lo ^ D.hi
        xor     rax, rbp
        xor     r14, r14
.g_seal:
        mov     r10, rax
        mov     ecx, r14d
        and     ecx, 63
        rol     r10, cl                          ; rotl64(S, j mod 64)
        xor     [r13 + r14 * 8], r10
        inc     r14
        cmp     r14, 128
        jb      .g_seal

        add     rsp, 8
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbp
        pop     rbx
        ret

; ----------------------------------------------------------------------------
; ux_index_alpha — reference-window computation (spec §5; mirrors the Argon2
; reference, CC0).  Inlined into the fill body of uxpw_hash (needs loop
; registers); documented here with the formulas.
;
;   RAS (pass 0):  slice 0, same-lane (only case):        i - 1
;                  slice > 0, same lane:                  slice*seg + i - 1
;                  slice > 0, other lane:                 slice*seg + (i ? 0 : 0xFFFFFFFF)
;   RAS (pass>=1): same lane:                             lane - seg + i - 1
;                  other lane:                            lane - seg + (i ? 0 : 0xFFFFFFFF)
;   rel(RAS, j1):  rel = j1 ; rel = rel*rel >> 32 ;
;                  rel = RAS - 1 - u32((RAS * rel) >> 32)
;   start:         pass==0 ? 0 : (slice == 3 ? 0 : (slice+1)*seg)
;   ref_index:     (start + rel) mod lane_len
; ----------------------------------------------------------------------------

; ----------------------------------------------------------------------------
; uxpw_hash — the fill + tag, raw API (spec §10.).  RDI = ctx.
; ----------------------------------------------------------------------------
align 16
uxpw_hash:
        push    rbp
        mov     rbp, rsp
        push    rbx
        push    r12
        push    r13
        push    r14
        push    r15
        sub     rsp, 5120
        and     rsp, -64
        mov     [rsp + UX_ANCHOR], rbp           ; fill reuses rbp as seg_len

        mov     r12, rdi                         ; ctx

        ; ---------------- validation ----------------
        mov     rax, [r12 + 24]                  ; p
        test    rax, rax
        jz      .err_params
        cmp     rax, 64
        ja      .err_params
        mov     r13, [r12 + 16]                  ; t
        test    r13, r13
        jz      .err_params
        cmp     r13, 4096
        ja      .err_params
        mov     r14, [r12 + 40]                  ; pwdlen
        cmp     r14, UXPW_PWDLEN_MAX
        ja      .err_pwd
        mov     rax, [r12 + 56]                  ; saltlen
        cmp     rax, 8
        jb      .err_salt
        cmp     rax, UXPW_SALT_MAX
        ja      .err_salt
        mov     rax, [r12 + 64]                  ; taglen
        cmp     rax, 16
        jb      .err_tag
        cmp     rax, UXPW_TAGLEN_MAX
        ja      .err_tag
        mov     rax, [r12 + 0]                   ; mem
        test    rax, rax
        jz      .err_mem
        mov     rax, [r12 + 72]                  ; out
        test    rax, rax
        jz      .err_mem

        ; mprime = 4p * ceil(m / 4p); floor 8p; cap 2^22
        mov     r10, [r12 + 24]                  ; p
        shl     r10, 2                           ; d = 4p
        mov     rax, [r12 + 8]                   ; m
        add     rax, r10
        dec     rax
        xor     rdx, rdx
        div     r10
        imul    rax, r10                         ; mprime = d * ceil(m/d)
        lea     r11, [r10 * 2]                   ; 8p
        cmp     rax, r11
        jae     .mp_ok
        mov     rax, r11
.mp_ok:
        cmp     rax, UXPW_MPRIME_MAX
        ja      .err_params
        mov     [rsp + UX_MP], rax
        xor     rdx, rdx
        mov     rcx, r12
        mov     rcx, [rcx + 24]                  ; p (divisor)
        div     rcx                              ; lane = mprime / p
        mov     [rsp + UX_LAN], rax
        shr     rax, 2                           ; seg = lane / 4 (exact)
        mov     [rsp + UX_SEG], rax

        ; ---------------- H0 (§3) ----------------
        lea     rdx, [rsp + UX_HBUF]
        mov     rax, [ux_prose_h0]
        mov     [rdx], rax
        mov     qword [rdx + 8], 1               ; version
        mov     rax, [r12 + 24]
        mov     [rdx + 16], rax                  ; p
        mov     rax, [rsp + UX_MP]
        mov     [rdx + 24], rax                  ; m'
        mov     rax, [r12 + 16]
        mov     [rdx + 32], rax                  ; t
        mov     rax, [r12 + 64]
        mov     [rdx + 40], rax                  ; taglen
        mov     rax, [r12 + 40]
        mov     [rdx + 48], rax                  ; pwdlen
        ; copy pwd
        lea     rdi, [rdx + 56]
        mov     rsi, [r12 + 32]
        mov     rcx, [r12 + 40]
        rep     movsb
        ; saltlen, salt
        mov     rax, [r12 + 56]
        mov     [rdi], rax                       ; saltlen (rdi at hbuf+56+pwdlen)
        mov     rsi, [r12 + 48]                  ; salt content pointer
        add     rdi, 8
        mov     rcx, [r12 + 56]
        rep     movsb
        ; n = 64 + pwdlen + saltlen  (prose 8 || 5 LE64 || len8 || pwd || len8 || salt)
        mov     rax, [r12 + 40]
        add     rax, [r12 + 56]
        add     rax, 64
        mov     [rsp + UX_N], rax

        lea     rdi, [rsp + UX_HBUF]
        mov     rsi, [rsp + UX_N]
        mov     rdx, [ux_h0_seed]
        mov     rcx, [ux_h0_seed + 8]
        lea     r8, [rsp + UX_H0]
        call    dash_hash256

        ; ---------------- first blocks (§4) ----------------
        ; u = H0 stored to UX_T[0..31]; 48-byte step buffer = T[0..47]
        mov     rax, [rsp + UX_H0]
        mov     [rsp + UX_T], rax
        mov     rax, [rsp + UX_H0 + 8]
        mov     [rsp + UX_T + 8], rax
        mov     rax, [rsp + UX_H0 + 16]
        mov     [rsp + UX_T + 16], rax
        mov     rax, [rsp + UX_H0 + 24]
        mov     [rsp + UX_T + 24], rax

        mov     rbx, [rsp + UX_LAN]              ; lane_len (kept through tag)
        xor     r13, r13                         ; lane l
.fb_lane:
        mov     rax, r13
        imul    rax, rbx
        shl     rax, 10                          ; *1024
        add     rax, [r12 + 0]                   ; mem
        mov     r14, rax                         ; dst cursor
        ; u = H0 (reset each lane, per ref)
        mov     rax, [rsp + UX_H0]
        mov     [rsp + UX_T], rax
        mov     rax, [rsp + UX_H0 + 8]
        mov     [rsp + UX_T + 8], rax
        mov     rax, [rsp + UX_H0 + 16]
        mov     [rsp + UX_T + 16], rax
        mov     rax, [rsp + UX_H0 + 24]
        mov     [rsp + UX_T + 24], rax
        xor     r15, r15                         ; step i = 0..63
.fb_step:
        mov     rax, r13
        mov     [rsp + UX_T + 32], rax           ; lane field
        mov     rax, r15
        mov     [rsp + UX_T + 40], rax           ; step field
        lea     rdi, [rsp + UX_T]
        mov     esi, 48
        mov     rdx, [rsp + UX_T]                ; seed = u.q0
        mov     rcx, [rsp + UX_T + 8]            ; seed = u.q1
        lea     r8, [rsp + UX_Z]
        call    dash_hash256
        ; u = v (32 bytes from Z into T)
        mov     rax, [rsp + UX_Z]
        mov     [rsp + UX_T], rax
        mov     rax, [rsp + UX_Z + 8]
        mov     [rsp + UX_T + 8], rax
        mov     rax, [rsp + UX_Z + 16]
        mov     [rsp + UX_T + 16], rax
        mov     rax, [rsp + UX_Z + 24]
        mov     [rsp + UX_T + 24], rax
        ; store u into block 0/1 territory of this lane
        mov     rax, [rsp + UX_T]
        mov     [r14], rax
        mov     rax, [rsp + UX_T + 8]
        mov     [r14 + 8], rax
        mov     rax, [rsp + UX_T + 16]
        mov     [r14 + 16], rax
        mov     rax, [rsp + UX_T + 24]
        mov     [r14 + 24], rax
        add     r14, 32
        inc     r15
        cmp     r15, 64
        jb      .fb_step

        inc     r13
        cmp     r13, [r12 + 24]                  ; p
        jb      .fb_lane

        ; ---------------- fill (§5) ----------------
        mov     rbp, [rsp + UX_SEG]              ; seg_len (kept)
        xor     r13, r13                         ; pass
.fill_pass:
        xor     r14, r14                         ; slice
.fill_slice:
        xor     r15, r15                         ; lane
.fill_lane:
        xor     rax, rax
        mov     [rsp + UX_START], rax
        mov     [rsp + UX_INDEP], rax
        mov     [rsp + UX_NBLK], rax
        test    r13, r13
        jnz     .fl_hadep
        test    r14, r14
        jnz     .fl_hadep
        mov     qword [rsp + UX_START], 2        ; (0,0): blocks 0,1 done
.fl_hadep:
        test    r13, r13
        jnz     .fl_dep
        cmp     r14, 2                           ; i-d rule: pass0 slices 0..1
        jae     .fl_dep
        mov     qword [rsp + UX_INDEP], 1
        mov     rdi, r13
        mov     rsi, r14
        mov     rdx, r15
        xor     rcx, rcx                         ; n = 0
        lea     r8, [rsp + UX_ADDR]
        lea     r9, [rsp + UX_T]                 ; scratch
        call    ux_addr_gen
.fl_dep:
        ; cur = lane*lane_len + slice*seg + starting
        mov     rax, r15
        imul    rax, rbx
        mov     r9, r14
        imul    r9, rbp
        add     rax, r9
        add     rax, [rsp + UX_START]
        mov     [rsp + UX_CUR], rax
        ; prev = (cur % lane == 0) ? cur + lane - 1 : cur - 1
        mov     rax, [rsp + UX_CUR]
        xor     rdx, rdx
        div     rbx                              ; rdx = cur mod lane
        test    rdx, rdx
        jz      .fl_prev_tail
        mov     rax, [rsp + UX_CUR]
        dec     rax
        jmp     .fl_prev_set
.fl_prev_tail:
        mov     rax, [rsp + UX_CUR]
        add     rax, rbx
        dec     rax
.fl_prev_set:
        mov     [rsp + UX_PREV], rax

        mov     rax, [rsp + UX_START]
        mov     [rsp + UX_I], rax
.fill_i:
        ; per-step: prev wraps at lane boundary
        mov     rax, [rsp + UX_CUR]
        xor     rdx, rdx
        div     rbx
        cmp     rdx, 1
        jne     .fl_npc
        mov     rax, [rsp + UX_CUR]
        dec     rax
        mov     [rsp + UX_PREV], rax
.fl_npc:
        ; ---- pseudo-rand source (J1/J2) ----
        cmp     qword [rsp + UX_INDEP], 0
        jne     .fl_jind
        mov     rax, [rsp + UX_PREV]
        shl     rax, 10
        add     rax, [r12 + 0]
        mov     rax, [rax]                       ; prev block q0
        jmp     .fl_jhave
.fl_jind:
        mov     rax, [rsp + UX_I]
        test    rax, rax                         ; block 0 pregenerated at i=0
        jz      .fl_juse
        and     rax, 31
        jnz     .fl_juse                         ; pair inside current block
        inc     qword [rsp + UX_NBLK]
        mov     rdi, r13
        mov     rsi, r14
        mov     rdx, r15
        mov     rcx, [rsp + UX_NBLK]
        lea     r8, [rsp + UX_ADDR]
        lea     r9, [rsp + UX_T]
        call    ux_addr_gen
.fl_juse:
        mov     rax, [rsp + UX_I]
        and     rax, 31
        mov     rax, [rsp + UX_ADDR + rax * 8]
.fl_jhave:
        mov     [rsp + UX_W], rax
        ; ref_lane = (j2 = hi32(w)) % p
        mov     rax, rax
        shr     rax, 32
        xor     rdx, rdx
        mov     rcx, [r12 + 24]                  ; p
        div     rcx
        mov     r8, rdx                          ; ref_lane
        xor     r11, r11                         ; same flag
        cmp     r8, r15
        jne     .fl_same_ok
        mov     r11, 1
.fl_same_ok:
        test    r13, r13                         ; (0,0): own lane only
        jnz     .fl_window
        test    r14, r14
        jnz     .fl_window
        mov     r8, r15
        mov     r11, 1
.fl_window:
        ; ---- index_alpha (inline; formulas in the doc block above) ----
        mov     rax, [rsp + UX_I]                ; i
        test    r13, r13
        jnz     .ia_late
        test    r14, r14
        jnz     .ia_p0_s2
        dec     rax                              ; slice 0: i - 1
        mov     r10, rax
        jmp     .ia_have_ras
.ia_p0_s2:
        mov     r10, r14
        imul    r10, rbp                         ; slice*seg
        test    r11, r11
        jz      .ia_p0_other
        add     r10, rax
        dec     r10
        jmp     .ia_have_ras
.ia_p0_other:
        test    rax, rax
        jz      .ia_p0_o0
        jmp     .ia_have_ras                     ; + 0 (i != 0)
.ia_p0_o0:
        mov     eax, 0xFFFFFFFF
        add     r10, rax
        jmp     .ia_have_ras
.ia_late:
        mov     r10, rbx
        sub     r10, rbp                         ; lane - seg
        test    r11, r11
        jz      .ia_lateO
        add     r10, rax
        dec     r10
        jmp     .ia_have_ras
.ia_lateO:
        test    rax, rax
        jz      .ia_lateO0
        jmp     .ia_have_ras
.ia_lateO0:
        mov     eax, 0xFFFFFFFF
        add     r10, rax
.ia_have_ras:
        ; RAS in r10 ; rel = j1^2 >> 32 ; trim with RAS
        mov     rax, [rsp + UX_W]
        mov     eax, eax                         ; j1
        imul    rax, rax
        shr     rax, 32
        mov     r9, rax                          ; rel'
        mov     rax, r10
        imul    rax, r9
        shr     rax, 32
        mov     eax, eax                         ; u32 cast
        mov     rcx, r10
        dec     rcx
        sub     rcx, rax                         ; rel final
        ; start
        mov     rax, 0
        test    r13, r13
        jz      .ia_start_done
        cmp     r14, 3
        jne     .ia_start_calc
        xor     rax, rax
        jmp     .ia_start_done
.ia_start_calc:
        lea     rax, [r14 + 1]
        imul    rax, rbp
.ia_start_done:
        add     rax, rcx                         ; start + rel
        xor     rdx, rdx
        div     rbx                              ; rdx = ref_index (remainder)
        imul    r8, rbx
        add     r8, rdx                          ; ref_abs = ref_lane*lane + ri
        ; pointers
        mov     rax, r8
        shl     rax, 10
        add     rax, [r12 + 0]
        mov     [rsp + UX_RPTR], rax
        mov     rax, [rsp + UX_PREV]
        shl     rax, 10
        add     rax, [r12 + 0]
        mov     [rsp + UX_PPTR], rax
        mov     rax, [rsp + UX_CUR]
        shl     rax, 10
        add     rax, [r12 + 0]
        mov     [rsp + UX_CPTR], rax
        ; T = R ^ P
        mov     rdi, [rsp + UX_RPTR]
        mov     rsi, [rsp + UX_PPTR]
        lea     rdx, [rsp + UX_T]
        mov     rcx, 128
.fl_xorloop:
        mov     rax, [rdi]
        xor     rax, [rsi]
        mov     [rdx], rax
        add     rdi, 8
        add     rsi, 8
        add     rdx, 8
        dec     rcx
        jnz     .fl_xorloop
        ; G(T, Z)
        lea     rdi, [rsp + UX_T]
        lea     rsi, [rsp + UX_Z]
        call    ux_g
        ; C = Z ^ T (^ old C when pass >= 1)
        mov     rdi, [rsp + UX_CPTR]
        lea     rsi, [rsp + UX_Z]
        lea     rdx, [rsp + UX_T]
        mov     rcx, 128
.fl_merge:
        mov     rax, [rsi]
        xor     rax, [rdx]
        test    r13, r13
        jz      .fl_merge_noold
        xor     rax, [rdi]
.fl_merge_noold:
        mov     [rdi], rax
        add     rsi, 8
        add     rdx, 8
        add     rdi, 8
        dec     rcx
        jnz     .fl_merge
        ; advance
        inc     qword [rsp + UX_I]
        inc     qword [rsp + UX_CUR]
        inc     qword [rsp + UX_PREV]
        mov     rax, [rsp + UX_I]
        cmp     rax, rbp                         ; while i < seg_len
        jb      .fill_i
        ; lane / slice / pass / done
        inc     r15
        cmp     r15, [r12 + 24]
        jb      .fill_lane
        inc     r14
        cmp     r14, 4
        jb      .fill_slice
        inc     r13
        cmp     r13, [r12 + 16]
        jb      .fill_pass

        ; ---------------- tag (§8) ----------------
        lea     rdi, [rsp + UX_T]
        xor     eax, eax
        mov     ecx, 1024
        rep     stosb                            ; X = 0
        xor     r15, r15                         ; lane
.tag_lane:
        mov     rax, r15
        imul    rax, rbx
        add     rax, rbx
        dec     rax                              ; l*lane + lane - 1
        shl     rax, 10
        add     rax, [r12 + 0]
        mov     rsi, rax
        lea     rdi, [rsp + UX_T]
        mov     ecx, 128
.tag_xor:
        mov     rdx, [rsi]
        xor     [rdi], rdx
        add     rsi, 8
        add     rdi, 8
        dec     rcx
        jnz     .tag_xor
        inc     r15
        cmp     r15, [r12 + 24]
        jb      .tag_lane
        ; "uxpw\0tag" || taglen || X
        lea     rdx, [rsp + UX_HBUF]
        mov     rax, [ux_prose_tag]
        mov     [rdx], rax
        mov     rax, [r12 + 64]
        mov     [rdx + 8], rax
        lea     rdi, [rdx + 16]
        lea     rsi, [rsp + UX_T]
        mov     ecx, 1024
        rep     movsb
        lea     rdi, [rsp + UX_HBUF]
        mov     esi, 1040
        mov     rdx, [rsp + UX_H0]
        mov     rcx, [rsp + UX_H0 + 8]
        lea     r8, [rsp + UX_ADDR]
        call    dash_hash256                     ; chunk0 (32 B) -> ADDR
        mov     rdi, [r12 + 72]                  ; out
        lea     rsi, [rsp + UX_ADDR]
        mov     rax, [r12 + 64]
        cmp     rax, 32
        jbe     .tag_single
        mov     ecx, 32
        jmp     .tag_copy0
.tag_single:
        mov     ecx, eax
.tag_copy0:
        rep     movsb
        cmp     qword [r12 + 64], 32
        jbe     .tag_done
        ; chunk1: prev32 = chunk0; seeds (chunk0.q0, chunk0.q1 ^ 1)
        lea     rdi, [rsp + UX_HBUF]
        lea     rsi, [rsp + UX_ADDR]
        mov     rax, [rsi]
        mov     [rdi], rax
        mov     rax, [rsi + 8]
        mov     [rdi + 8], rax
        mov     rax, [rsi + 16]
        mov     [rdi + 16], rax
        mov     rax, [rsi + 24]
        mov     [rdi + 24], rax
        mov     rdx, [rsp + UX_ADDR]
        mov     rcx, [rsp + UX_ADDR + 8]
        xor     rcx, 1
        mov     esi, 32
        lea     r8, [rsp + UX_Z]
        call    dash_hash256
        lea     rsi, [rsp + UX_Z]
        mov     rdi, [r12 + 72]
        add     rdi, 32
        mov     rax, [r12 + 64]
        sub     rax, 32
        mov     ecx, eax
        rep     movsb
.tag_done:
        xor     rax, rax

.epi:
        mov     rbp, [rsp + UX_ANCHOR]
        lea     rsp, [rbp - 40]
        pop     r15
        pop     r14
        pop     r13
        pop     r12
        pop     rbx
        pop     rbp
        ret

.err_mem:
        mov     rax, -1
        jmp     .epi
.err_params:
        mov     rax, -2
        jmp     .epi
.err_salt:
        mov     rax, -3
        jmp     .epi
.err_pwd:
        mov     rax, -4
        jmp     .epi
.err_tag:
        mov     rax, -5
        jmp     .epi
