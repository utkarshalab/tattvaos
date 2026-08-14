# usrauth — Reference Monitor

> The single authority that decides whether a subject may perform a verb on an object.

`usrauth` is the Tattva OS reference monitor. Every access decision in the system
resolves through one function, and that function can only ever *narrow* authority.

> **Naming:** `usrauth` is deliberately distinct from [`serve/uauth/`](../../serve/),
> which terminates OAuth2/OIDC/JWT for remote clients. `uauth` proves *who a remote
> party is*; `usrauth` decides *what any subject may do*. `uauth` is a client of
> `usrauth`, never a parallel authority — see "One way to grant" below.

---

## The governing rule

Merging authentication mechanisms is good. Merging authorization **grant paths** is
how vulnerabilities are built. If two subsystems can each independently say "yes",
the result is union semantics, and union semantics grant exactly what one layer
meant to withhold.

That failure already exists in miniature in this codebase: a POSIX ACL where a
named user is granted `rw` but the mask permits only `r-x`. The correct answer is
**deny**. Union logic says allow.

> **Many independent ways to DENY. Exactly one way to GRANT.**
> Effective authority is the *intersection* of every layer, never the union.

---

## Layer stack

```
  L0  IDENTITY      passkey / Argon2id / TPM attestation / mTLS / code signature
        |           -> an assertion; long-term secrets never traverse the wire
  L1  TOKEN         ed25519-signed, offline-attenuable, PoP-bound, TTL + epoch
        |           -> encoded with storage/ubxp
  L2  SUBJECT       identity + groups + capabilities + integrity level + MLS label
        |              + entitlements. Immutable; changes only via checked transition
  L3  CAPABILITY    unforgeable handle + rights bits, attenuate-on-pass
        |           -> confused-deputy is structurally impossible, not merely checked
  L4  POLICY        relation tuples + ABAC conditions + TTL grants + consent
        |
  L5  MANDATORY     type enforcement + integrity + MLS      <- CAN ONLY DENY
        |
  L6  AUDIT         hash-chained decision log -> storage/uwal
```

### Decision function

Every term must hold. No layer can grant what another denies.

```
allow =  mandatory_allows        (L5, never overridable, not even by root)
       ∧ integrity_level_ok      (L2, no write-up)
       ∧ capability_present      (L3, authority is HELD, not looked up by name)
       ∧ caveats_satisfied       (L1, token attenuation)
       ∧ not_expired             (L1 + L4, against lib/time monotonic clock)
       ∧ policy_allows           (L4, relations + attributes)
```

### Evaluation order — cheapest denier first

Correctness is order-independent; latency is not.

| Step | Cost | Layer |
|---|---|---|
| 1 | O(1) bitmask | L5 mandatory |
| 2 | O(1) compare | L2 integrity |
| 3 | O(1) table index | L3 capability |
| 4 | O(caveats) | L1 expiry + caveats |
| 5 | O(depth), capped, cached | L4 policy graph |

---

## What each system contributed

| Source | Idea taken | Why it earns its place |
|---|---|---|
| **Windows** | Access token per subject; **integrity levels**; privileges distinct from permissions; SACL audit | Most complete subject model in production. MIC blocks write-up — Biba, shipping |
| **macOS** | **Entitlements signed into the binary**; TCC consent; SIP | Identity is what the code *is*, not a secret it holds — unescalatable at runtime |
| **Linux** | POSIX capabilities; seccomp-bpf; LSM hooks | Attenuation of ambient authority; pluggable enforcement points |
| **SELinux / RHEL** | **Type enforcement**; domain transition on exec; MLS/MCS | Policy the object owner cannot override |
| **seL4** | Capabilities as the *only* authority | Eliminates confused-deputy structurally |
| **Kerberos** | Short-lived tickets, mutual auth | Long-term secrets never sent |
| **Zanzibar** | Relation tuples | Answers "who can reach X" *and* "what can A reach" — ACLs answer only the first |
| **Biscuit / macaroons** | Offline attenuation | Delegate narrower authority with no issuer round-trip |
| **SPIFFE** | Attested workload identity | Identity from measurement, not a configured secret |
| **FIDO2 / WebAuthn** | Origin binding + hardware possession | Phishing resistance comes from binding, not entropy |
| **OpenBSD** | pledge / unveil | Voluntary, irreversible self-restriction |
| **BeyondCorp** | Per-request evaluation | Session establishment ≠ standing authority |

### Two things original to Tattva OS

**Time-bounded authority as a primitive.** Windows, Linux and macOS all treat grants
as permanent-until-revoked, which is why stale access accumulates for years. Here
expiry is **mandatory at grant time**, with permanence the explicit exception. This
generalises the `chmod_ttl` concept from a syscall into an attribute every L4 grant
carries.

**Attestation-rooted local identity.** In a unikernel there is no user database to
compromise. Subject identity derives from measured boot state via TPM PCR unsealing
([`storage/uxfs/crypto/vault.asm`](../../storage/uxfs/crypto/vault.asm)), so no
shared secret exists anywhere to be stolen.

---

## No scheduler dependency

`usrauth` **owns its own subject and capability tables** and hands out opaque handles.
It does not hook a scheduler, and does not require one to exist.

```
usrauth_subject_create(...)  -> subject_handle
usrauth_check(subject_handle, object_id, object_class, verb) -> 0 | -EACCES
```

When `sched/` is eventually written, a task struct stores the handle and nothing
else changes. When a syscall boundary appears, it calls `usrauth_check` at entry.
Until then, any caller can invoke it directly.

This is what makes the whole module buildable now rather than blocked behind kernel
infrastructure that does not exist.

---

## Directory layout

```text
security/usrauth/
├── usrauth.asm              Dispatcher + usrauth_check() decision function
├── usrauth.inc              Subject, token, label, decision structs
├── identity/               L0
│   ├── password.asm        Argon2id verification via crypto/upass
│   ├── webauthn.asm        FIDO2 assertion verify (Ed25519 + ES256)
│   ├── attest.asm          TPM PCR -> workload identity
│   └── svid.asm            Workload identity document
├── token/                  L1
│   ├── token.asm           Issue / verify / attenuate
│   ├── caveat.asm          Time, scope, proof-of-possession caveats
│   └── revoke.asm          Revocation epoch + set
├── subject/                L2
│   ├── table.asm           Subject handle table (owned here, no sched dep)
│   └── transition.asm      Domain transition rules
├── capability/             L3
│   ├── cap.asm             Handle table, rights bits, attenuate-on-pass
│   └── restrict.asm        Irreversible self-restriction
├── policy/                 L4
│   ├── relation.asm        Relation tuples + depth-capped graph walk
│   ├── attribute.asm       ABAC conditions
│   ├── ttl.asm             Time-bounded grants
│   └── consent.asm         Consent gate
├── mandatory/              L5
│   ├── te.asm              Type enforcement
│   ├── integrity.asm       Integrity levels (Biba)
│   └── mls.asm             MLS categories (Bell-LaPadula)
├── audit/                  L6
│   └── decision_log.asm    Hash-chained records -> storage/uwal
└── tests/
    ├── usrauth_test.asm    24 semantic tests, one bit of the mask each
    ├── harness.asm         Clock + entropy doubles, result reporting
    └── run.sh              bash security/usrauth/tests/run.sh
```

---

## Dependencies

### Available

| Need | Provider |
|---|---|
| AES-GCM (token wrap) | `crypto/ucrypt/symmetric/aes_gcm.asm` |
| Argon2id, HKDF, PBKDF2 | `crypto/ukdf/` |
| BLAKE3, SHA-256/512, SHA-3 | `crypto/uhash/` |
| HMAC-SHA256 | `crypto/uhash/` |
| Signature **verification** | `crypto/usign/` — Ed25519, ECDSA P-256, RSA-PSS |
| Post-quantum | `crypto/upqc/` — Kyber, Dilithium |
| X.509 / TLS for mTLS | `crypto/ux509/`, `crypto/utls/` |
| **Monotonic trusted time** | `lib/time/mono.asm` — `mono_clock_gettime`, `mono_get_nanos` |
| CSPRNG | `lib/urand/` |
| Constant-time compare | `ucrypt_ct_memcmp` |
| Token serialization | `storage/ubxp/` |
| Audit log substrate | `storage/uwal/` |
| DAC input for L4 | `storage/uxfs/security/acl.asm`, `xattr.asm` |
| Device attestation | `storage/uxfs/crypto/vault.asm` |

Trusted monotonic time matters more than it appears: without it, every TTL and token
expiry is decorative, because an attacker controlling the clock never expires.

### Dependency status

| Dependency | State | Verified against |
|---|---|---|
| `crypto/upass/` | **built** — Argon2id, pepper, device wrap | 11 tests incl. legacy migration |
| `crypto/ukdf/argon2/` | **built** — RFC 9106 Argon2id | RFC 9106 §5.3 tag, exact |
| `crypto/uhash/blake2/blake2b.asm` | **built** | `b2sum`, incl. block boundaries |
| `crypto/usign/ed25519/` | **built** — sign, verify, keygen | RFC 8032 tests 1–3, both ways |
| `crypto/usign/ecdsa/` | **built** — sign, verify, keygen, DER | RFC 6979 vectors + 12 negative cases |
| `crypto/uhash/sha512/` | **built** | FIPS vectors |
| `crypto/ucrypt/mac/hmac.asm` | **built** | RFC 4231 |
| `crypto/ukdf/pbkdf2/` | **built** | RFC 6070 |
| `lib/urand/` | **built** — ChaCha20 + CTR_DRBG | RFC 8439, FIPS-197 |

`ed25519_sign` is deliberately absent, not pending. The field and group arithmetic
in `crypto/usign/ed25519/` branches on its inputs, which is free for verification
(every input is public) and disqualifying for signing (the secret scalar would
steer the branches and leak through timing). Signing needs a constant-time scalar
multiplication first; a signer built on the current code would be worse than no
signer at all.

L1 tokens are unaffected: they are authenticated with HMAC-SHA256, because issuer
and verifier are the same authority inside one kernel. Asymmetric signing is only
required for cross-node federation.

### Deferred, not blocking

`sched/` and a syscall boundary. L2 and L3 work standalone via handles; these only
change *who calls* `usrauth_check`, not what it computes.

---

## Companion: crypto/upass

Password hashing is **composition, not a merged primitive**. Argon2id is memory-hard
(the only property that defeats GPU/ASIC cracking); BLAKE3 deliberately is not.
Splicing them would discard Argon2id's analysis without gaining anything.

```
Stage 1   mk     = Argon2id(password, salt, secret=pepper, ad=uid, m, t, p)
Stage 2   dk     = HMAC-SHA256(pepper, "UPASS-KDF-v1" || uid || mk)
Stage 3   stored = dk XOR HMAC-SHA256(device_key, "UPASS-WRAP-v1" || salt)
```

Defaults: m = 16 MiB, t = 3, p = 1. Lanes are pinned to 1 because extra lanes
only pay off when they actually run in parallel — on a single thread they
shorten the dependency chain and make the hash *cheaper* to attack.

| Attacker holds | Stopped by |
|---|---|
| Credential database | Stage 1 — Argon2id memory cost per guess |
| Database + disk image | Stage 2 — pepper is not in the database |
| Database + pepper | Stage 3 — device key never leaves the TPM |
| Powered-off machine | Stage 3 — TPM will not unseal against changed PCRs |

**The pepper goes inside Stage 1, not only after it.** Argon2 has a secret
parameter K for exactly this. Applied only afterwards, an attacker holding the
database but not the pepper pays the memory-hard cost once per password guess
and then tries candidate peppers cheaply against the result. Fed to Argon2,
every (password, pepper) pair costs a full evaluation. Stage 2 keeps the pepper
too, so a weakness in either construction leaves the other standing.

Stage 3 is a **reversible wrap, not a hash**, so hardware migration is a re-wrap
rather than a password reset. This requires an escrow key — without one, a dead
board means unrecoverable credentials. The keystream is derived per record from
the salt; a fixed keystream would cancel out when two stored values are XORed.

Algorithm and cost are stored per record, so **rehash-on-verify** upgrades
records on the next successful login — the one moment the plaintext is
legitimately in hand. PBKDF2 records written before Argon2id existed still
verify and are rewritten at current policy; a migration requiring every user to
reset their password is one nobody deploys.

---

## Documentation

[DESIGN.md](DESIGN.md) is the maintenance reference: layer semantics, the
decision function, data model, extension rules, and the reasoning behind the
choices. Read it before changing anything here.

---

## Testing

```sh
bash security/usrauth/tests/run.sh
```

24 semantic tests. The point is not that the code runs — it is that each layer
denies what it is supposed to deny *even when every other layer would have
allowed it*. Most tests set up an access that all-but-one layer permits and
assert the exact deny code the remaining layer must produce. Asserting the
specific code matters: a bug making every request fail would pass a suite that
only checked for denial.

Results come back as a bitmask written to stdout, not as an exit status, because
an exit status is truncated to 8 bits and would silently lose every test past
the eighth.

---

## Known risks

- **Six layers on a hot path.** L5/L3 must stay O(1) bitmask checks. Only L4 may walk
  a graph, and it needs a decision cache keyed by `(subject, object, verb)` with an
  epoch for invalidation.
- **Relation walks can be unbounded.** Depth must be capped — same reasoning as the
  nesting cap in UBXP.
- **Policy becomes a compiled artifact.** Requires a policy compiler and a signed
  update path, or L5 is unmaintainable.
- **Device binding is a availability hazard** without escrow. See upass Stage 3.
