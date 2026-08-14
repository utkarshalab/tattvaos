# usrauth — Design and Maintenance Reference

The reference monitor for Tattva OS. This document is for someone changing,
extending or auditing `usrauth` later — it records not just what the code does
but **why it is shaped that way**, because most of the decisions here are only
obvious once you know what they are defending against.

`README.md` is the overview. This is the working reference.

---

## 1. The one invariant

> **Many independent ways to DENY. Exactly ONE way to GRANT.**
> Effective authority is the INTERSECTION of every layer, never the union.

Every layer can veto. No layer can override another's veto. There is no
"superuser" short-circuit, no `if (uid == 0) return ALLOW`, and adding one
would invalidate every other guarantee in this document.

If you are adding a feature and find yourself needing a bypass, the feature is
wrong. Model it as a *capability the subject holds* (L3) or a *relation that
grants it* (L4). Both are auditable; a bypass is not.

**When reviewing a change, the question to ask is: can this make some request
succeed that would previously have failed?** If yes, it must be adding a grant
through L3 or L4, and nowhere else.

---

## 2. Layer model

```text
  L0  IDENTITY      Who is this? Produces an assertion, not an authorisation.
  L1  TOKEN         A bearer credential, attenuable offline.
  L2  SUBJECT       The security context: groups, caps, integrity, MLS label.
  L3  CAPABILITY    Authority that is HELD, not looked up by name.
  L4  POLICY        Relations, attributes, time bounds, consent.
  L5  MANDATORY     Type enforcement, integrity, MLS.   <- CAN ONLY DENY
  L6  AUDIT         Hash-chained record of every decision.
```

The numbering is historical and does **not** match evaluation order. See §3.

### Why these particular layers

Each exists because the others cannot express its failure mode:

| Layer | Answers | Without it |
|---|---|---|
| L0 | Is this really that principal? | Anyone can claim any identity |
| L1 | Can authority be delegated without contacting the issuer? | Every delegation is a round trip, or a shared password |
| L2 | What context does this subject run in? | No stable place to hang integrity or labels |
| L3 | Does the subject actually *hold* this authority? | Confused-deputy: naming a resource is enough to reach it |
| L4 | Does policy grant it *right now*? | Authority is permanent once granted |
| L5 | Is this forbidden regardless of who asks? | An administrator can grant anything, including to malware |
| L6 | What actually happened? | No forensics, and no way to detect a compromised policy |

---

## 3. The decision function

`usrauth_check(subject_handle, object*, verb) -> 0 | negative`
in [usrauth.asm](usrauth.asm).

Evaluation order is **not** layer order. It is *cheapest denier first*:

```text
  1. usrauth_subject_get     invalid handle        -> DENY_INVALID
  2. usrauth_mandatory_check L5, and internally:
        usrauth_te_check       type rule missing   -> DENY_MANDATORY
        usrauth_mls_check      lattice violation   -> DENY_MLS
  3. usrauth_integrity_check L2, write-up attempt  -> DENY_INTEGRITY
  4. usrauth_cap_check       L3, authority not held-> DENY_CAPABILITY
  5. usrauth_policy_check    L4, no live relation  -> DENY_POLICY
  -> USRAUTH_ALLOW, then usrauth_audit_record
```

TE and MLS are both inside `usrauth_mandatory_check` ([mandatory/te.asm](mandatory/te.asm)):
TE runs first and short-circuits, so an object with no TE rule never reaches the
lattice check.

Two independent reasons for this order:

- **Cost.** TE and integrity are O(1) bitmask comparisons. The policy walk is a
  depth-capped graph traversal with a cache. Denying early avoids the expensive
  work entirely.
- **Information.** The layers that deny for *structural* reasons run before the
  ones that deny for *contextual* reasons, so a rejected request reveals as
  little as possible about the policy table.

**Order is load-bearing for the tests, not for correctness.** Because the result
is an intersection, any order produces the same allow/deny. But the *reported
deny code* depends on order, and the test suite asserts specific codes. If you
reorder, expect T2/T3/T4 to change which code they see — and think hard about
whether the new order still denies as early as possible.

### Deny codes

| Code | Value | Meaning |
|---|---|---|
| `USRAUTH_ALLOW` | 0 | Permitted |
| `USRAUTH_DENY_MANDATORY` | -1 | L5 type enforcement |
| `USRAUTH_DENY_INTEGRITY` | -2 | L2 no write-up |
| `USRAUTH_DENY_MLS` | -3 | L5 lattice |
| `USRAUTH_DENY_CAPABILITY` | -4 | L3 authority not held |
| `USRAUTH_DENY_CAVEAT` | -5 | L1 token caveat unsatisfied |
| `USRAUTH_DENY_EXPIRED` | -6 | L1/L4 grant lapsed, or password lockout |
| `USRAUTH_DENY_POLICY` | -7 | L4 no relation grants it |
| `USRAUTH_DENY_REVOKED` | -8 | L1 token revoked |
| `USRAUTH_DENY_INVALID` | -9 | Malformed request |
| `USRAUTH_DENY_FORGED` | -10 | L1 token tag did not authenticate |

`DENY_FORGED` is deliberately distinct from `DENY_CAVEAT`. A failed caveat is
the system working; a failed tag is someone attempting forgery. An audit trail
that cannot tell them apart cannot tell an administrator what just happened.

---

## 4. Directory map

```text
security/usrauth/
├── usrauth.asm              Dispatcher + usrauth_check()
├── usrauth.inc              Structs, constants, the TTL macro
├── identity/               L0
│   ├── password.asm         Enrolment, throttling, rehash-on-verify
│   ├── webauthn.asm         FIDO2 assertions (EdDSA + ES256)
│   ├── attest.asm           TPM PCR -> workload identity
│   └── svid.asm             Workload identity documents
├── token/                  L1
│   ├── token.asm            Issue / verify / attenuate / tag
│   ├── caveat.asm           Caveat evaluation
│   └── revoke.asm           Epoch bump + bounded revocation set
├── subject/                L2
│   ├── table.asm            Handle table (owned here, no sched dependency)
│   └── transition.asm       Domain transition rules
├── capability/             L3
│   ├── cap.asm              Rights bits, attenuate-on-pass, delegation
│   └── restrict.asm         Irreversible self-restriction
├── policy/                 L4
│   ├── relation.asm         Relation tuples + depth-capped walk + cache
│   ├── attribute.asm        ABAC conditions
│   ├── ttl.asm              Time-bounded grants, renewal, sweep
│   └── consent.asm          Consent gate
├── mandatory/              L5
│   ├── te.asm               Type enforcement
│   ├── integrity.asm        Biba integrity levels
│   └── mls.asm              Bell-LaPadula lattice
├── audit/                  L6
│   └── decision_log.asm     Hash-chained records
└── tests/
    ├── usrauth_test.asm     24 semantic tests
    ├── harness.asm          Clock double + result reporting
    └── run.sh
```

---

## 5. Layer notes

### L0 — Identity

Identity produces an **assertion**, never an authorisation. `usrauth_password_authenticate`
returning 0 means "this is who they say"; it does not grant anything. The
grant comes from L3/L4 attached to the resulting subject.

**password.asm**
- Hashing lives in `crypto/upass`. This file is the identity-layer wrapper.
- **Throttling is per subject, never global.** A global failure counter lets one
  attacker lock out every user by failing repeatedly against one account.
- The failure path does **not** distinguish "no such credential" from "wrong
  password". Reporting the difference turns a password guess into a free user
  enumeration oracle.
- **Rehash-on-verify**: on a successful authentication, if `upass_needs_rehash`
  says the record is below policy, it is recomputed. This is the only moment
  the plaintext is legitimately available. Without it, raising policy protects
  only new accounts.

**webauthn.asm**
- Phishing resistance is **not** from the signature. It is from binding: the
  authenticator signs an RP ID hash it computed itself. Three checks carry the
  security and run *before* any curve arithmetic: RP ID match, User Present
  flag, and a strictly increasing signature counter.
- The signed message is `authData || clientDataHash`. **Both halves.** The
  challenge lives in the client data; a signature covering only `authData` is
  not bound to the challenge and one captured assertion replays forever.
- `authData` is bounded by `USRAUTH_WA_MAX_AUTHDATA`; oversized input is
  refused, never truncated. Truncating would verify a signature over an
  attacker-chosen prefix.
- ES256 signatures are DER; EdDSA are raw 64 bytes. The DER decoder is strict
  (§8).

### L1 — Tokens

- Authenticated with **HMAC-SHA256, not a public-key signature**. Inside one
  kernel the issuer and verifier are the same authority, so asymmetric signing
  would add cost and a great deal of field arithmetic while protecting against
  nothing in this threat model. Asymmetric signing becomes necessary only for
  cross-node federation.
- **Attenuation is offline.** A holder narrows a token by appending a caveat and
  re-tagging. Caveats can only be *added*, and every caveat is a restriction, so
  the result is provably no broader than what was handed over.
- **Caveats are conjunctive.** All must hold. Evaluated disjunctively, a token
  would grow *broader* with every added restriction.
- **An unrecognised caveat kind must DENY.** This is the opposite of UBXP's
  unknown-field tolerance, and the asymmetry is deliberate: skipping a data
  field you do not understand loses information; skipping a *restriction* you do
  not understand grants access the issuer explicitly withheld.

Verification order in `usrauth_token_verify` — **do not reorder**:

```text
  1. tag           authenticity first; every other field is attacker-controlled
  2. epoch         bulk revocation
  3. revocation    individual revocation
  4. caveats       the token's own restrictions
```

Checking the epoch or caveats of an unauthenticated token is the classic
parse-before-verify mistake.

**Revocation** has two granularities:
- **Epoch bump** (`usrauth_revoke_subject`) — O(1), invalidates every token for
  a subject at once. The right answer for logout, credential change, compromise.
- **Revocation set** (`usrauth_revoke_token`) — for one delegated token while
  siblings survive. Bounded and deliberately small; entries are pruned once the
  token they name would have expired anyway.

  The set reuses dead slots by *scanning*, because pruning only marks entries
  inactive and cannot compact the ones above them. Without that scan the
  high-water mark only rises and the bound is reached by accumulation.

### L2 — Subject

The subject table is owned here, with **no scheduler dependency**. That is what
lets L2/L3 work standalone: a subject is a handle, not a running task.

`token_epoch` on the subject is what makes O(1) bulk revocation possible.

### L3 — Capability

Authority is **held**, not looked up by name. This is what makes the
confused-deputy problem structurally impossible rather than merely checked: a
subject cannot act on a resource it cannot name *and* hold.

- **Delegation attenuates.** `usrauth_cap_delegate` intersects the requested
  rights with the delegator's own. Requesting more than you hold succeeds, with
  the excess silently dropped — it does not fail, and it does not confer.
- **`usrauth_subject_restrict` is irreversible.** There is no API to widen a
  restricted subject. Sandboxes that can be exited are not sandboxes.

### L4 — Policy

- Relation tuples with a **depth-capped** graph walk (`USRAUTH_RELATION_MAX_DEPTH`
  = 8). The cap is what stops a cyclic relation graph from spinning.
- **Time-bounded by default.** Every grant carries an expiry; permanence is
  possible but must be stated explicitly as `expires_ns = 0`.
- Expiry is checked on the **read path**, in the walk. `usrauth_ttl_sweep` is
  therefore housekeeping, not security — correctness must never depend on it
  having run, because a sweep that is late or never called would otherwise
  become a silent grant of expired authority.
- **Renewal cannot resurrect.** A lapsed grant is gone; extending it is a fresh
  grant that must be authorised as such. Otherwise anyone holding a stale
  reference could push the deadline forward forever and the grant would never
  end. Renewal is also capped (`USRAUTH_TTL_MAX_EXTENSION`, 24h) so no sequence
  of renewals manufactures permanence.
- The **decision cache** is keyed by `(subject, object, verb)` and invalidated by
  a policy epoch. Anything that changes what the table says must call
  `usrauth_policy_bump_epoch` — `relation_add`, `relation_remove`, `ttl_renew`
  and `ttl_sweep` all do.

  **This is the most common way to introduce a bug here.** A new mutation path
  that forgets the bump leaves memoised verdicts alive after the policy that
  produced them is gone.

The expiry predicate is a single macro, `USRAUTH_JMP_IF_LAPSED`, in
`usrauth.inc`. It is a macro rather than a call because the walk evaluates it
once per relation per request. A deadline of 0 means permanent and **must be
tested first**: comparing a real clock against 0 makes every permanent grant
look infinitely expired.

### L5 — Mandatory

**Can only deny.** Nothing here ever contributes a grant, including for root.

- **te.asm** — SELinux-style type enforcement. Absent rule means deny.
- **integrity.asm** — Biba: no write-up. A medium-integrity subject cannot write
  a high-integrity object.
- **mls.asm** — Bell-LaPadula: no read-up, no write-down, over a level plus a
  category bitmap (`USRAUTH_MAX_CATEGORIES` = 64, one bit each).

MLS is off by default (`usrauth_mls_enable`). When enabled it denies *before*
policy is consulted, which matters when writing tests: an MLS-denied request
never reaches L4, so a test intending to exercise L4 must either keep MLS off
or call `usrauth_policy_check` directly.

### L6 — Audit

Records are **hash-chained**: each record's hash covers the previous hash. An
attacker who edits one record invalidates every record after it, so tampering
is detectable without an external log service.

`usrauth_audit_verify_chain` walks the chain. The test suite both checks the
chain is intact *and* corrupts a record to confirm the check fails — a verifier
that returned "intact" unconditionally would pass the first test alone.

---

## 6. Data model

Key structures, all in [usrauth.inc](usrauth.inc):

| Struct | Holds |
|---|---|
| `usrauth_subject_t` | uid, gid, groups, type_id, integrity, MLS label, flags, caps, `token_epoch` |
| `usrauth_object_t` | object_id, class, type_id, owner uid/gid, integrity, MLS label, POSIX mode |
| `usrauth_cap_t` | object_id, class, rights bitmask, `expires_ns`, flags |
| `usrauth_relation_t` | object_id, relation verbs, subject or `via_object`, `expires_ns` |
| `usrauth_token_t` | magic, version, subject, caveat count, `issued_ns`, epoch, caveats, 32-byte tag |
| `usrauth_audit_t` | subject, object, verb, verdict, timestamp, chained hash |

**Verbs** are a bitmask (`USRAUTH_VERB_MASK` = 0x00FF): READ, WRITE, EXEC,
APPEND, CREATE, DELETE, ADMIN, DELEGATE.

**Static limits** — all tables are fixed-size arrays, because there is no
allocator at this level and an authorisation check that can fail on allocation
fails *open* under memory pressure:

| Limit | Value |
|---|---|
| `USRAUTH_MAX_SUBJECTS` | 256 |
| `USRAUTH_MAX_CAPS_PER_SUBJECT` | 64 |
| `USRAUTH_MAX_GROUPS` | 16 |
| `USRAUTH_MAX_RELATIONS` | 1024 |
| `USRAUTH_MAX_TE_RULES` | 512 |
| `USRAUTH_MAX_CATEGORIES` | 64 |
| `USRAUTH_TOKEN_MAX_CAVEATS` | 8 |
| `USRAUTH_RELATION_MAX_DEPTH` | 8 |

Raising any of these costs BSS only. Check the containing table's index type
before raising past 2^32.

---

## 7. Dependencies

| Symbol | Provided by | Notes |
|---|---|---|
| `mono_get_nanos` | `lib/time/mono.asm` | Every TTL depends on it |
| `urand_get_bytes` | `lib/urand/urand.asm` | Token key, password salts |
| `sha256_hash` | `crypto/uhash/sha256` | Audit chain, RP ID hashing |
| `hmac_sha256` | `crypto/ucrypt/mac/hmac.asm` | Token tags |
| `ucrypt_ct_memcmp` | `crypto/ucrypt/guards/ct_guard.asm` | Constant-time compares |
| `upass_hash` / `_verify` / `_needs_rehash` | `crypto/upass` | Password records |
| `ed25519_verify` | `crypto/usign/ed25519` | WebAuthn EdDSA |
| `ecdsa_p256_verify_der` | `crypto/usign/ecdsa` | WebAuthn ES256 |

**Trusted monotonic time matters more than it looks.** Without it every TTL and
token expiry is decorative, because an attacker who controls the clock never
expires.

**Every dependency must preserve the SysV callee-saved registers** — RBX, RBP,
R12–R15. `usrauth` holds live pointers in these across calls: fifteen call sites
keep one in RBX across `mono_get_nanos` alone, and several write through it
immediately afterwards. A callee that clobbers one does not fail loudly; it
turns an authorisation check into a store through a garbage pointer.

`tsc_elapsed_nanos` violated this — it loaded the TSC frequency into RBX
without saving it, so every caller of `mono_get_nanos` got RBX replaced with
3000000000. The whole dependency set is now checked by a probe that calls each
function with sentinels in those registers. **Add any new dependency to that
probe.** The test suites cannot catch this class of bug on their own, because
the harness substitutes the clock.

Include order in `kernel/entry.asm` matters only for `%include` resolution —
the whole kernel is one translation unit, so symbol references resolve across
files regardless of order. `usrauth.asm` must come after crypto and `lib/time`.

---

## 8. Cryptographic decisions worth knowing

These live outside `usrauth` but its guarantees rest on them.

**Passwords — `crypto/upass`.** Three stages: Argon2id (memory-hard), an
HMAC-SHA256 pepper stage, and a reversible device-key wrap. The pepper is fed
to Argon2's *secret* parameter, not only mixed afterwards — applied only
afterwards, an attacker with the database but not the pepper pays the
memory-hard cost once per password and then tries peppers cheaply. Records
carry their own algorithm and cost, so PBKDF2 records from before Argon2id
existed still verify and are upgraded on next login.

**Ed25519.** Verification uses variable-time scalar multiplication (every input
is public). Signing uses `ge25519_scalarmult_ct`, which performs a doubling and
an addition at *every* bit and selects with a mask. Sharing the fast routine
would leak the private key through timing while still producing valid
signatures. Signing is deterministic — the nonce is `SHA-512(prefix || M)`,
never drawn from the RNG, which removes the repeated-nonce key-recovery failure
rather than managing it.

**ECDSA P-256.** Sign, verify and keygen. Signatures are DER and the decoder is
**strict**: long-form lengths, non-minimal integer padding and trailing bytes
are all rejected. Every alternative encoding accepted would be a second valid
byte string for the same signature, and anything keyed on signature bytes — a
replay cache, an audit record — would be bypassable.

Nonces are deterministic (RFC 6979), derived from the key and the message by an
HMAC-DRBG rather than drawn from the RNG. ECDSA gives up the private key
outright if a nonce repeats — two signatures under one k yield
`k = (e1-e2)/(s1-s2)` and then `d` directly — and leaks it to lattice attacks
if nonces are merely *biased*. Determinism removes the failure mode instead of
managing it, and keeps signing safe on a machine whose entropy pool has failed.

Signing uses `p256_scalarmult_ct`, built on `p256_add_ct`. The variable-time
addition branches to handle the cases the Jacobian formula cannot (`P == Q`,
`P == -Q`, an identity operand); the constant-time one computes every candidate
and selects with a mask. Those branches are exactly what a signing path must
not have, because the scalar steering them is the private key.

**Randomness — `lib/urand`.** ChaCha20 (default) or AES-CTR_DRBG, seeded from
RDSEED/RDRAND plus timing jitter, combined by XOR into Fortuna pools so an
attacker must defeat *every* source rather than the weakest. Both generators
perform key erasure. `urand_get_bytes` returns 0 and writes nothing on failure —
**callers must check**, because a salt buffer left untouched holds whatever was
there before.

---

## 9. Testing

```sh
bash security/usrauth/tests/run.sh
```

24 semantic tests. The point is not that the code runs. It is that **each layer
denies what it should even when every other layer would have allowed it** — most
tests set up an access that all-but-one layer permits, then assert the exact
deny code the remaining layer must produce.

Asserting the *specific* code is what makes them worth anything: a bug that made
every request fail would pass a suite that only checked for denial.

Two harness decisions, both learned the hard way:

- **Results are written to stdout, not returned as an exit status.** An exit
  status is truncated to 8 bits, so a bitmask suite silently loses every test
  past the eighth.
- **Only the clock is substituted.** Entropy comes from the real `lib/urand`,
  because stubbing it is precisely what hid a CSPRNG that faulted on its first
  store and then returned identical bytes on every call. A test double for a
  security primitive tests the double.

The clock advances 1ns per read rather than being frozen: a frozen clock gives
every token in a run the same `issued_ns`, and individual revocation is keyed on
exactly that field — so a test claiming to revoke one token would revoke all of
them and still pass.

### When adding a test

1. Set up an access that every layer *except* the one under test would permit.
2. Assert the exact deny code.
3. Add the mirror case where possible — if you test that something is rejected,
   also test that the legitimate version is still accepted. Otherwise a
   deny-everything bug passes.

---

## 10. Extending it

**Adding a verb.** Add the bit in `usrauth.inc`, widen `USRAUTH_VERB_MASK`, and
check every mask-and-compare site. The mask is used to reject unknown bits;
forgetting to widen it makes the new verb silently unrequestable.

**Adding an object class.** Add the constant. TE rules are keyed by
`(source type, target type, class, verbs)`, so a new class starts with no rules
and therefore denies everything — which is the correct default.

**Adding a caveat kind.** Add the constant and a case in
`usrauth_token_check_caveats`. The default branch **must** deny. Verify the
default is still reached; an unrecognised caveat that falls through to allow is
the worst bug this file can have.

**Adding a policy mutation.** It must call `usrauth_policy_bump_epoch`, or the
decision cache will serve verdicts computed under the old table. The existing
call sites are the pattern to follow: `relation_add`, `relation_remove`,
`attr_add`, `consent_grant`, `consent_revoke`, `ttl_renew`, `ttl_sweep`.

**Adding an L0 method.** It must produce a subject handle and nothing else. If
you find it granting authority directly, it belongs in L3/L4.

**Adding a deny code.** Append to the list; do not renumber. Audit records store
the numeric verdict, so renumbering rewrites history.

---

## 11. Known limits and deferred work

| Item | State |
|---|---|
| `usrauth_check_current` | Not built. The current API takes the subject handle as an ARGUMENT, which with no ring boundary is confused-deputy-prone — any caller can pass any handle. It must read the handle from the running fiber instead. See §12. |
| Locking / SMP safety | Not built, and correct only while nothing preempts. See §12. |
| Policy as a compiled artifact | Rules are added programmatically. A policy compiler and a signed update path are needed before L5 is maintainable at scale. |
| Device binding without escrow | An availability hazard: a dead board means unrecoverable credentials. See upass Stage 3. |
| Table sizes | Static. Fine for a unikernel; revisit if subject counts grow past a few hundred. |

### Risks to keep in mind

- **Six layers on a hot path.** L5/L3 must stay O(1) bitmask checks. Only L4 may
  walk a graph, and it needs its cache to stay correct — see the epoch note.
- **Relation walks must stay bounded.** The depth cap is the only thing stopping
  a cyclic graph.
- **The decision cache is a correctness surface, not just a performance one.**
  A stale entry is a grant that policy no longer supports.

---

## 12. Operating in a unikernel with no user ring

Tattva OS is a unikernel: one address space, ring 0 only, cooperative fibers, no
`syscall` instruction anywhere. That is not a limitation to work around — it is
the architecture — but it changes what this monitor is and is not.

### What is being defended

There is no untrusted *code*: every byte of the image is compiled together. So
usrauth is **not** a barrier between a trusted kernel and untrusted user
programs. It defends three other things:

- **Untrusted data.** The image is trusted; its inputs are not. `unet/http`,
  `unet/dns`, `uxfs`, `ubxp`, X.509 — every parser is attack surface, and a
  memory-safety bug in one yields a write primitive *already in ring 0*. usrauth
  bounds the blast radius after that happens.
- **Multi-tenancy over data.** The subject model carries uid, gid, groups and MLS
  labels. Policy is between principals and data flows, not between address spaces.
- **Audit.** The hash-chained log is meaningful regardless of rings.

A consequence worth internalising: **the cryptographic layers carry more weight
here than the memory-protection ones**, because there is no ring boundary
underneath them. L1 tokens are unforgeable because of an HMAC tag, not because of
page tables, and that property is unaffected by the absence of a user ring.

### What replaces the syscall boundary

A reference monitor needs three properties. A syscall supplied all three for
free; here each must be built.

| Property | Replacement |
|---|---|
| Unforgeable caller identity | The subject handle lives in the fiber control block and is written **only by the scheduler**. Never passed as an argument. |
| Tamper-proof state | MPK domains (`kernel/sched/fiber_pkey.asm`): application fibers hold the auth domain write-disabled. |
| Complete mediation | A build-time call-graph assertion. There is no untrusted binary to load, so this is *stronger* than a runtime check — it cannot be branched around. |

**MPK caveat, by design not oversight:** `WRPKRU` is unprivileged, so code in the
same address space can grant itself write access. MPK is a boundary against bugs,
not against arbitrary code. The accepted fix (ERIM, Hodor) is binary-level:
enforce W^X and scan all mapped code for unintended `WRPKRU`/`XRSTOR` byte
sequences, including ones appearing unaligned inside other instructions. A single
translation unit makes that tractable — one image, scanned once at build time.

### The non-preemption invariant

> **A usrauth operation must be non-preemptible and must never yield.**

`security/usrauth/` contains **no synchronisation primitives at all** — no `lock`,
no `cmpxchg`, no fences. Today that is correct: fibers are cooperative, and no
usrauth path yields (there is no I/O in it; `upass_hash` is pure computation).
Every operation is therefore atomic by construction.

That correctness evaporates the moment either of these lands:

- **Preemption.** A timer landing between "read subject count" and "write slot"
  in `usrauth_subject_create` corrupts the table with no error anywhere. This is
  why `sched/preempt.asm` must not be written.
- **SMP.** With multiple cores it breaks regardless of yielding.

Concrete races, for whoever brings SMP up:

| Site | Race |
|---|---|
| `usrauth_subject_create` | read count → write slot → increment; two cores take the same slot |
| `usrauth_revoke_token` | scans for a dead slot, then writes it |
| `usrauth_policy_cache_store` | torn verdict, or one stored under a stale epoch |
| `usrauth_audit_record` | **worst** — the chain is hash-linked; two records on the same prev-hash silently break verification |
| `argon2_memory` | explicitly non-reentrant; concurrent hashes corrupt each other's arena |
| `master_urand_state` | shared DRBG state; concurrent draws can repeat keystream |

### The intended SMP answer

Make the monitor **single-threaded**, reached through the MPMC queue that
`kernel/sched/smp_mpmc.asm` already exists to provide:

```text
  application fiber ──► MPMC queue ──► monitor (one core) ──► verdict
```

Serialisation then *is* the synchronisation: the tables stay lock-free because
exactly one consumer touches them, and the queue restores the single-entry-point
property the syscall used to give. The scheduler stamps the producing fiber's
subject handle into each queue entry, which is also how `usrauth_check_current`
becomes natural rather than bolted on.

The alternative — fine-grained locking across a dozen tables in assembly — is
more code, more failure modes, and gives up the single entry point.
