"""The Security Manager's functions (sm/crypto.asm) against published
vectors (FIPS-197, RFC 4493, the Core specification's samples) and the
reference implementations in smp_ref.py, over many random inputs.

usage: python3 test_crypto.py path/to/ubt.so
"""
import ctypes as C
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smp_ref as R  # noqa: E402

lib = C.CDLL(sys.argv[1])
passed = failed = 0
h = bytes.fromhex
rng = random.Random(1)


def check(label, got, want):
    global passed, failed
    if got == want:
        passed += 1
    else:
        failed += 1
        print(f"FAIL {label}: got {got!r}, want {want!r}")


def fn(name, res, *args):
    f = getattr(lib, name)
    f.restype, f.argtypes = res, list(args)
    return f


B = C.c_char_p
aes = fn("ubt_aes128", None, B, B, C.c_void_p)
cmac_ = fn("ubt_cmac", None, B, B, C.c_uint32, C.c_void_p)
ah_ = fn("ubt_ah", None, B, B, C.c_void_p)
c1_ = fn("ubt_c1", None, B, B, B, B, B, C.c_void_p)
s1_ = fn("ubt_s1", None, B, B, B, C.c_void_p)
f4_ = fn("ubt_f4", None, B, B, B, C.c_uint32, C.c_void_p)
f5_ = fn("ubt_f5", None, B, B, B, B, B, C.c_void_p)
f6_ = fn("ubt_f6", None, B, B, B, B, B, B, C.c_void_p)
g2_ = fn("ubt_g2", C.c_uint32, B, B, B, B)
h6_ = fn("ubt_h6", None, B, C.c_uint32, C.c_void_p)
h7_ = fn("ubt_h7", None, B, B, C.c_void_p)
pub_ = fn("ubt_p256_public", C.c_int32, B, C.c_void_p)
dh_ = fn("ubt_p256_dh", C.c_int32, B, B, C.c_void_p)


def out(n, call, *args):
    buf = C.create_string_buffer(n)
    call(*args, buf)
    return buf.raw


def rnd(n):
    return bytes(rng.getrandbits(8) for _ in range(n))


# ---- published vectors -------------------------------------------------------------------------------
check("AES-128, FIPS-197 C.1", out(16, aes, h("000102030405060708090a0b0c0d0e0f"), h("00112233445566778899aabbccddeeff")),
      h("69c4e0d86a7b0430d8cdb78070b4c55a"))
K = h("2b7e151628aed2a6abf7158809cf4f3c")
M = h("6bc1bee22e409f96e93d7e117393172aae2d8a571e03ac9c9eb76fac45af8e5130c81c46a35ce411e5fbc1191a0a52ef"
      "f69f2445df4f9b17ad2b417be66c3710")
for n, tag in ((0, "bb1d6929e95937287fa37d129b756746"), (16, "070a16b46b4d4144f79bdd9dd04a287c"),
               (40, "dfa66747de9ae63030ca32611497c827"), (64, "51f0bebf7e3b9d92fc49741779363cfe")):
    check(f"AES-CMAC, RFC 4493, {n} bytes", out(16, cmac_, K, M[:n], n), h(tag))
check("ah, the specification's sample", out(3, ah_, h("ec0234a357c8ad05341010a60a397d9b"), h("708194")), h("0dfbaa"))
check("c1, the specification's sample",
      out(16, c1_, bytes(16), h("5783D52156AD6F0E6388274EC6702EE0"), h("07071000000101"), h("05000800000302"),
          bytes([1, 0]) + h("A1A2A3A4A5A6") + h("B1B2B3B4B5B6")), h("1e1e3fef878988ead2a74dc5bef13b86"))
check("s1, the specification's sample",
      out(16, s1_, bytes(16), h("000F0E0D0C0B0A091122334455667788"), h("010203040506070899AABBCCDDEEFF00")),
      h("9a1fe1f0e8b0f49b5b4216ae796da062"))
U = h("20b003d2f297be2c5e2c83a7e9f9a5b9eff49111acf4fddbcc0301480e359de6")
V = h("55188b3d32f6bb9a900afcfbeed4e72a59cb9ac2f19d7cfb6b4fdd49f47fc5fd")
X = h("d5cb8454d177733effffb2ec712baeab")
check("f4, the specification's sample", out(16, f4_, U, V, X, 0), h("f2c916f107a9bd1cf1eda1bea974872d"))
check("g2, the specification's sample", g2_(U, V, X, h("a6e8e7cc25a75f6e216583f7ff3dc4cf")), 0x2f9ed5ba)

# ---- against the reference, random inputs ------------------------------------------------------------
bad = []
for i in range(200):
    k, m = rnd(16), rnd(rng.randrange(0, 97))
    if out(16, cmac_, k, m, len(m)) != R.cmac(k, m):
        bad.append(("cmac", len(m)))
    if out(16, aes, k, m[:16].ljust(16, b"\0")) != R.aes128(k, m[:16].ljust(16, b"\0")):
        bad.append(("aes", i))
check("AES and AES-CMAC of 0-96 bytes, 200 times", bad, [])
bad = []
for i in range(50):
    w, n1, n2, a1, a2 = rnd(32), rnd(16), rnd(16), rnd(7), rnd(7)
    if out(32, f5_, w, n1, n2, a1, a2) != b"".join(R.f5(w, n1, n2, a1, a2)):
        bad.append("f5")
    w, r, io = rnd(16), rnd(16), rnd(3)
    if out(16, f6_, w, n1, n2, r, io, a1 + a2) != R.f6(w, n1, n2, r, io, a1, a2):
        bad.append("f6")
    u, v, x, y = rnd(32), rnd(32), rnd(16), rnd(16)
    z = rng.randrange(256)
    if out(16, f4_, u, v, x, z) != R.f4(u, v, x, z):
        bad.append("f4")
    if g2_(u, v, x, y) != R.g2(u, v, x, y):
        bad.append("g2")
    if out(16, h6_, w, 0x6C656272) != R.h6(w, b"lebr"):
        bad.append("h6")
    if out(16, h7_, x, w) != R.h7(x, w):
        bad.append("h7")
    if out(3, ah_, w, r[:3]) != R.ah(w, r[:3]):
        bad.append("ah")
    p1, p2 = rnd(7), rnd(7)
    addrs = rnd(14)
    if out(16, c1_, w, r, p1, p2, addrs) != R.c1(w, r, p1, p2, addrs[0], addrs[1], addrs[2:8], addrs[8:]):
        bad.append("c1")
    if out(16, s1_, w, r, x) != R.s1(w, r, x):
        bad.append("s1")
check("f4, f5, f6, g2, h6, h7, ah, c1, s1, 50 times each", bad, [])

# ---- P-256 ---------------------------------------------------------------------------------------------
dbg = R.DEBUG_PRIV.to_bytes(32, "big")
pub = C.create_string_buffer(64)
check("the debug key's public key", (pub_(dbg, pub), pub.raw), (0, R.pub_bytes(R.mul(R.DEBUG_PRIV))))
check("its x is the f4 sample's U", pub.raw[:32], U)
bad = []
for _ in range(6):
    a, b = rng.randrange(1, R.N), rng.randrange(1, R.N)
    ab, bb = a.to_bytes(32, "big"), b.to_bytes(32, "big")
    pa, pb = C.create_string_buffer(64), C.create_string_buffer(64)
    pub_(ab, pa)
    pub_(bb, pb)
    s1b, s2b = C.create_string_buffer(32), C.create_string_buffer(32)
    r1, r2 = dh_(ab, pb.raw, s1b), dh_(bb, pa.raw, s2b)
    want = R.mul(a, R.mul(b))[0].to_bytes(32, "big")
    if (r1, r2, s1b.raw, s2b.raw, pa.raw) != (0, 0, want, want, R.pub_bytes(R.mul(a))):
        bad.append(hex(a))
check("Diffie-Hellman both ways agrees with the reference, 6 key pairs", bad, [])
off = bytearray(R.pub_bytes(R.mul(5)))
off[63] ^= 1
check("a point not on the curve: refused", dh_(dbg, bytes(off), C.create_string_buffer(32)), -1)
check("a private key of 0: refused", pub_(bytes(32), C.create_string_buffer(64)), -1)

print(f"test_crypto: {passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
