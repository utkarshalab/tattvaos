# uxpw — tattvaos-native memory-hard password hashing (v1)

Status: design frozen 2026-10-30. Implementations: `uxpw.asm` (this tree, x86-64
asm over `lib/crypto/uhash/dash`) and the C reference used for differential
testing. Structure of the memory fill follows the Argon2 reference (CC0,
P-H-C phc-winner-argon2) so the indexing/windowing semantics are battle-tested;
every primitive is ours and verified (dash == official XXH3-128, 536/0).

Role (layering, enforced):
- **Passwords, logins, app secrets/action pins → uxpw.** Default profile:
  m = 65536 KiB (64 MiB), t = 3, p = 1, verify ≈ 0.4–0.6 s.
- Non-adversarial file/app integrity → dash (µs).
- Adversarial file integrity → blake3 / sha256.

Never used are記 interchangeable: uxpw records are `$uxpw$…` and must never be
labeled or parsed as `$argon2…`. They are NOT interoperable with anybody.

## 1. Parameters

| Param | Meaning | Range | Default profile LOGIN |
|---|---|---|---|
| m | memory, KiB | 8·p ≤ m ≤ 2^22 | 65536 |
| t | passes | 1 ≤ t ≤ 4096 | 3 |
| p | lanes | 1 ≤ p ≤ 64 | 1 |
| salt | raw bytes | 8..64 | 16 (urand) |
| pwd | raw bytes | 0..1024 | — |
| tag | output bytes | 16..64 | 32 |
| v | spec version | 1 | 1 |

Effective memory: `m' = 4·p·floor(m / (4·p))` KiB (multiple of 4p, ≥ 8p because
of the m floor). Blocks: 1 KiB = 128 qwords. `lane_len = m'/p` blocks,
`seg_len = lane_len/4` blocks (4 slices per pass), `nblk = m'` total blocks.
Caller supplies the `m'` KiB buffer (8-byte min alignment; 64 recommended for
speed). Lanes are filled sequentially (threads may parallelize later without
changing results, same as Argon2's contract).

Endianness: all fixed-width encodings are little-endian. Any unterminated
lengths are u64.

## 2. Fixed constants & encodings

```
UX_H0_SEED   = (0x9E3779B97F4A7C15, 0x1BD1E0F51E0C5B6D)   ; dash256 seeds for H0
UX_ADDR_SEED = (0xA0761D6478BD642F, 0xE7037ED1A0B428DB)   ; address stream
UX_G_SEAL    = (0xBF58476D1CE4E5B9, 0x94D049BB133111EB)   ; G absorb chain
```
(Values are arbitrary but frozen; changing any of them changes every record.)

Domain prose: bytes of the ASCII strings used verbatim below (`"uxpw\0h0"`,
`"uxpwaddr"`, `"uxpw\0tag"`).

Primitive notation:
- `dash256(D, sa, sb) -> q0..q3` = 32 bytes: `dash128(D, seed=sa)` lo/hi then
  `dash128(D, seed=sb)` lo/hi. `dash128(D, seed)` = seeded XXH3-128 (official
  lib semantics; our dash is bit-proven for every length class).
- `mul32(x)` = uint64(lo32(x)) * uint64(hi32(x))  (exact 32×32→64).
- `rotl64(x, n)` = 64-bit rotate left.

## 3. H0

```
H0 = dash256(
        "uxpw\0h0"              ; 8 bytes
        || LE64(1)              ; version
        || LE64(p) || LE64(m') || LE64(t) || LE64(taglen)
        || LE64(pwdlen) || pwd
        || LE64(saltlen) || salt,
        UX_H0_SEED)
  -> q0..q3 (32 bytes)
```

## 4. Seed chain (H'-equivalent) and first blocks

```
chain(data, u) = dash256(data, u.q0, u.q1)   ; -> next 4 qwords

; first blocks of lane j: block0 = q[0..127], block1 = q[128..255]
u = H0
for i in 0..63:
    v = chain(  u (32 B) || LE64(lane) || LE64(i)  (48 B total), u )
    lblocks[j][4*i ..] = v          ; 64 chunks = 2 blocks of 128 qwords
    u = v
```

## 5. Memory fill (id-style: Argon2 twin with dash J-values)

Fill order: `for pass r in 0..t-1: for slice s in 0..3: for lane l in 0..p-1:
for i in 0..seg_len-1` (sequential lanes; deterministic regardless of core
count). Block-offset walk is uniform for every pass (mirrors the Argon2 reference
walk exactly): `cur = l·lane_len + s·seg_len + starting + (i - starting)`,
with `starting = 2` for `(r,s) = (0,0)` and `0` otherwise.
`prev` = block at `cur - 1`; when `cur % lane_len == 0` the prev block is
the lane's last block (`cur + lane_len - 1`), and whenever `cur % lane_len`
== 1 inside the loop, prev resets to `cur - 1`. Indices i = 0,1 of (0,0) are
the §4 blocks and are not filled by the loop.

Starting index: `(r==0 && s==0) -> i starts at 2` (blocks 0,1 already built by
§4).

Addressing source — **id rule** (mirrors Argon2id):
- data-independent while `r == 0 && s < 2`: `(J1, J2)` come from the address
  stream §6, pair `(i mod 32)` of the current addr block
  (`J1 = lo32(w), J2 = hi32(w)`; advance block chain every 32 pairs).
- otherwise data-dependent: `J1/J2` = lo32/hi32 of `prev_block.q0`.

Windowing (`index_alpha`, structure mirrors the Argon2 reference verbatim,
CC0 — omitted semantics are identical):

```
RAS(pass0, s, same_lane) = pass0 ? ( s·seg_len + i - 1                [same lane]
                                   | s·seg_len + (i ? 0 : -1) )       [other lane]
                          : ( lane_len - seg_len + i - 1
                                   | lane_len - seg_len + (i ? 0 : -1) )
ref_lane = J2 mod p        ; but forced to l when (r==0 && s==0)
rp = u64(J1); rp = rp*rp >> 32
rp = RAS - 1 - (RAS * rp >> 32)
start = (r == 0) ? 0 : (s == 3 ? 0 : (s+1)·seg_len)
ref_index = (start + rp) mod lane_len        ; absolute block in lane ref_lane
```

Compression for block at `cur` (prev = P, ref = R, old = existing `cur` block,
zeroed during pass 0):
```
T = R xor P                        ; 128 qwords
Z = G(T)                           ; §7
cur = Z xor T xor OLD              ; pass 0: OLD = 0. Pass ≥ 1: OLD = old cur.
```

## 6. Address stream (independent slices only)

```
w = UX_ADDR_SEED                      ; (lo, hi)
addr_block(n):                        ; n = 0,1,2,... chained blocks
    for i in 0..31:
        v = dash256(  "uzpwaddr" (8 B) || LE64(r) || LE64(s) || LE64(l)
                      || LE64(n) || LE64(i)   (48 B total),
                      w.lo, w.hi )
        addr.q[4*i .. 4*i+3] = v
        w = (v.q0, v.q1)
```
Each addr block yields 32 (J1,J2) pairs (q[k] -> J1 = lo32, J2 = hi32); blocks
are consumed in order 0,1,2,… with `n` incrementing. Unused trailing pairs are
discarded when a segment ends. The stream restarts per (r,s,l) segment.

## 7. G — chain-scatter block mixer

Input T (128 qwords) -> output Z (128 qwords). Strictly serial per step, every
output qword transitively depends on every input qword (forward chain covers
the prefix direction, backward chain the suffix direction, seal adds the
whole-block digest from the dash absorb).

```
; ---- absorb (whole-block digest via dash chain over stripes)
(cA, cB) = UX_G_SEAL
for s in 0..15:                              ; 64-byte stripes, contiguous
    v = dash256( T[8s .. 8s+7] (64 B), cA, cB )
    cA = v.q0
    cB = v.q1
D = (cA, cB)

; ---- forward chain
(lo, hi) = D
for j in 0..127:
    z = T[j] ^ hi
    m = mul32(z)
    Z[j] = z ^ m
    hi = z ^ rotl64(lo, 19)
    lo = m

; ---- backward chain (in place)
(lo, hi) = D
for j in 127..0:
    z = Z[j] ^ hi
    m = mul32(z)
    Z[j] = z ^ m
    hi = z ^ rotl64(lo, 17)
    lo = m

; ---- seal
S = D.lo ^ D.hi
for j in 0..127:
    Z[j] ^= rotl64(S, j mod 64)
```

Cost model at defaults: 196,608 G calls (m'=65536, t=3) × ~2.2 µs ≈ 0.45 s on
the dev reference machine — the sequential mul-chains are latency-bound, which
is the point: GPUs get the same serial wall per lane.

## 8. Tag

```
X = (last block of lane 0) ^ (last block of lane 1) ^ ...     ; 1 KiB
u = H0
v0 = dash256( "uxpw\0tag" (8 B) || LE64(taglen) || X (1024 B), u.q0, u.q1 )
tag = first taglen bytes of chain:
    out[0..3] = v0 ; v = v0
    while more needed: v = chain(v (32 B), v recycled seeds (v.q0, v.q1^count))
```
Concretely: chunk k (32 bytes each) for k ≥ 1:
`v_k = dash256( v_{k-1} (32 B), v_{k-1}.q0, v_{k-1}.q1 ^ LE64(k) )`.
taglen ≤ 64 → at most 2 calls.

## 9. Record format (PHC style, unpadded base64, standard alphabet)

```
$uxpw$v=<v>$m=<m_kib>,t=<t>,p=<p>$<salt>$<tag>
```
- `m` is the *requested* m (not m'); m' is recomputed on verify and must match
  the one recorded at creation — for fixed p it always recomputes to the same
  value, and the tag binds m' anyway.
- Strict order `m,t,p`; unpadded base64 (RFC 4648 §4, no padding).
- Parse failures / malformed records → verify error, never a "no match".

## 10. API (asm, next chunk)

```
uxpw_ctx_t (packed, 8-byte fields):
    u64 mem;        ; m' KiB buffer (caller-provided)
    u64 m, t, p;    ; requested params
    u64 pwd, pwdlen, salt, saltlen;
    u64 taglen, out;
uxpw_hash(RDI = ctx) -> RAX = UXPW_OK(0) | negative error
uxpw_record_create(RDI = ctx) -> writes record into u64(rec) field (or separate)
uxpw_verify(RDI = record ptr, RSI = len, RDX = pwd, RCX = pwdlen,
            R8 = mem, R9 = membytes) -> RAX = 0 match / -UXPW_AUTH / -err
```
Errors (negative): mem too small (-1), bad m/t/p (-2), salt range (-3),
pwd range (-4), tag range (-5), bad record (-6), no match (-7).

## 11. Test plan

- C reference (`tmp/verify/uxpw_ref.c`, built on official xxhash.h) generates
  KATs; asm must match block-for-block (KAT dump after fill, full tag).
- KAT sweep small-enough to run everywhere: m=32..256, t=1..4, p=1..4 both
  orderings of lanes, salt len 8/16/64, pwd lengths 0/1/7/64/1024.
- Property: single-bit flip in pwd/salt must change the tag (avalanche gate).
- Timing sanity: LOGIN profile once per host run (~0.5 s budget), never in the
  sweep loop.
- Record round-trip: create → parse → verify ✓; corrupted tag/salt → -7/-6.

## 12. Verification status (differential, not official-lib)

There is no external oracle for uxpw itself (not official Argon2). Correctness
is established differentially, asm vs the C reference here — which is in turn
grounded on the official dash primitives (verified separately):

- dash256 one-shot vs official-XXH3 reference: 285/0 cases
  (`tmp/dash_probe3.c`, all lengths 0..512, fixed + random seeds).
- `ux_g` (G mixer) asm vs C equations: 8/0 random blocks, stage traces
  (absorb D, post-fwd, post-bwd, post-seal) all bit-equal (`tmp/verify/probe4.c`,
  `pfcmp.sh`, `pbcmp.sh`).
- Lane prefill dump (blocks 0/1 and lane-1 blocks 16/17, full 128 qwords):
  bit-equal (`fbk_host.c`).
- Fill blocks m=32 t=1 p=1 and p=2: all 32 blocks bit-equal.
- End-to-end tag sweep: 15 combos (m 17..128, t 1..3, p 1..4, taglen 16..64,
  pwd 0/1024 B, salt 8/64 B) — bit-equal (`tmp/verify/sweep.sh`).
- KAT table (10 entries, `tmp/uxpw_kat.txt`, generated by
  `tmp/verify/gen_uxpw_kat.sh`): asm reproduces all 10 (`verify_uxpw_kat.sh`).
- Error codes: mutual rejection parity t/p ranges, salt/pwd limits, taglen
  limits — -2/-3/-4/-5 (`tmp/verify/errs.sh`).

Timing (WSL on the dev box, warm): asm ~0.39 s, ref ~0.28 s at
m=64 MiB, t=3, p=1. Default-profile cost is a pending decision (0.22–0.39 s
measured vs the 0.4–0.6 s target band).
