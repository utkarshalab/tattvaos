"""Reference implementations for the Security Manager tests, written from
FIPS-197, RFC 4493, SEC 1 and the Core specification's definitions, not
from the assembly: AES-128, AES-CMAC, the SMP functions and P-256. Values
are most significant octet first, as the specification writes them."""


def _xt(a):
    return ((a << 1) ^ 0x1B) & 0xFF if a & 0x80 else a << 1


def _sbox():
    box, p, q = [0] * 256, 1, 1
    while True:
        p = p ^ ((p << 1) & 0xFF) ^ (0x1B if p & 0x80 else 0)
        q ^= q << 1
        q ^= q << 2
        q ^= q << 4
        q &= 0xFF
        if q & 0x80:
            q ^= 0x09
        x = q ^ ((q << 1 | q >> 7) & 0xFF) ^ ((q << 2 | q >> 6) & 0xFF) ^ ((q << 3 | q >> 5) & 0xFF) \
            ^ ((q << 4 | q >> 4) & 0xFF)
        box[p] = x ^ 0x63
        if p == 1:
            break
    box[0] = 0x63
    return box


SBOX = _sbox()


def aes128(key, block):
    key, s = list(key), list(block)
    rk, rcon = [key[:]], 1
    for _ in range(10):
        w = rk[-1]
        t = [SBOX[w[13]] ^ rcon, SBOX[w[14]], SBOX[w[15]], SBOX[w[12]]]
        n = []
        for i in range(4):
            prev = t if i == 0 else n[4 * (i - 1):4 * i]
            n += [w[4 * i + j] ^ prev[j] for j in range(4)]
        rk.append(n)
        rcon = _xt(rcon)
    s = [s[i] ^ rk[0][i] for i in range(16)]
    for r in range(1, 11):
        s = [SBOX[x] for x in s]
        s = [s[(i + 4 * (i % 4)) % 16] for i in range(16)]           # ShiftRows (column-major)
        if r != 10:
            m = []
            for c in range(4):
                a = s[4 * c:4 * c + 4]
                m += [_xt(a[0]) ^ _xt(a[1]) ^ a[1] ^ a[2] ^ a[3], a[0] ^ _xt(a[1]) ^ _xt(a[2]) ^ a[2] ^ a[3],
                      a[0] ^ a[1] ^ _xt(a[2]) ^ _xt(a[3]) ^ a[3], _xt(a[0]) ^ a[0] ^ a[1] ^ a[2] ^ _xt(a[3])]
            s = m
        s = [s[i] ^ rk[r][i] for i in range(16)]
    return bytes(s)


def _shl(b):
    n = (int.from_bytes(b, "big") << 1)
    if n >> 128:
        n = (n & ((1 << 128) - 1)) ^ 0x87
    return n.to_bytes(16, "big")


def cmac(key, msg):
    l = aes128(key, bytes(16))
    k1 = _shl(l)
    k2 = _shl(k1)
    blocks = [msg[i:i + 16] for i in range(0, len(msg), 16)] or [b""]
    last = blocks[-1]
    if len(last) == 16 and msg:
        last = bytes(x ^ y for x, y in zip(last, k1))
    else:
        last = (last + b"\x80").ljust(16, b"\x00")
        last = bytes(x ^ y for x, y in zip(last, k2))
    x = bytes(16)
    for blk in blocks[:-1]:
        x = aes128(key, bytes(p ^ q for p, q in zip(x, blk)))
    return aes128(key, bytes(p ^ q for p, q in zip(x, last)))


def ah(k, r):
    return aes128(k, bytes(13) + r)[13:]


def c1(k, r, preq, pres, iat, rat, ia, ra):
    p1 = pres + preq + bytes([rat, iat])
    p2 = bytes(4) + ia + ra
    x = aes128(k, bytes(a ^ b for a, b in zip(r, p1)))
    return aes128(k, bytes(a ^ b for a, b in zip(x, p2)))


def s1(k, r1, r2):
    return aes128(k, r1[8:] + r2[8:])


def f4(u, v, x, z):
    return cmac(x, u + v + bytes([z]))


SALT = bytes.fromhex("6C888391AAF5A53860370BDB5A6083BE")


def f5(w, n1, n2, a1, a2):
    t = cmac(SALT, w)
    m = lambda c: cmac(t, bytes([c]) + b"btle" + n1 + n2 + a1 + a2 + b"\x01\x00")
    return m(0), m(1)


def f6(w, n1, n2, r, io, a1, a2):
    return cmac(w, n1 + n2 + r + io + a1 + a2)


def g2(u, v, x, y):
    return int.from_bytes(cmac(x, u + v + y), "big") & 0xFFFFFFFF


def h6(w, key_id):
    return cmac(w, key_id)


def h7(salt, w):
    return cmac(salt, w)


# ---- P-256 ------------------------------------------------------------------------------------------------
P = 2 ** 256 - 2 ** 224 + 2 ** 192 + 2 ** 96 - 1
N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
G = (0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296,
     0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5)


def on_curve(pt):
    x, y = pt
    return (y * y - (x * x * x - 3 * x + B)) % P == 0


def _add(p1, p2):
    if p1 is None:
        return p2
    if p2 is None:
        return p1
    (x1, y1), (x2, y2) = p1, p2
    if x1 == x2 and (y1 + y2) % P == 0:
        return None
    if p1 == p2:
        lam = (3 * x1 * x1 - 3) * pow(2 * y1, -1, P) % P
    else:
        lam = (y2 - y1) * pow(x2 - x1, -1, P) % P
    x3 = (lam * lam - x1 - x2) % P
    return x3, (lam * (x1 - x3) - y1) % P


def mul(k, pt=G):
    r = None
    while k:
        if k & 1:
            r = _add(r, pt)
        pt = _add(pt, pt)
        k >>= 1
    return r


def pub_bytes(pt):
    return pt[0].to_bytes(32, "big") + pt[1].to_bytes(32, "big")


def from_bytes(b):
    return int.from_bytes(b[:32], "big"), int.from_bytes(b[32:], "big")


# the specification's debug key pair (SMP, 2.3.5.6.1)
DEBUG_PRIV = 0x3f49f6d4a3c55f3874c9b3e3d2103f504aff607beb40b7995899b8a6cd3c1abd
