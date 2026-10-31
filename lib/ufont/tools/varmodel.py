"""Variable fonts - the model sfnt/var.asm follows (OpenType font variations as HarfBuzz applies
them).

    normalize(font, {tag: value}) -> normalized coordinates (2.14 integers, axis order)
    ItemStore(data, offset).delta(outer, inner, coords) -> float32 (HarfBuzz's arithmetic)
    delta_map(data, offset, index) -> (outer, inner)
    hvar_advance(font, glyph, coords, advance) -> the advance with HVAR's delta
    gvar_deltas(font, glyph, coords, points, ends) -> per point (dx, dy), doubles (IUP for points
        a tuple does not name)
    feature_variation(table data, coords) -> {feature index: alternate Feature offset} of the first
        FeatureVariation record whose conditions hold

Normalization is HarfBuzz's to the bit: fvar's min / default / max as float32, the value clamped,
normalized in float32, rounded to 16.16, avar's segment maps in float32 (its exact-match and
out-of-range special cases), rounded to 2.14. Item variation deltas sum region scalars times
deltas in float32 as HarfBuzz does (so rounded advances and GPOS adjustments come out the same).
Glyph outlines vary in doubles (sfnt/var.asm does the same; HarfBuzz uses float32, so they agree
to a small tolerance). avar version 2, CFF2 and MVAR are not modelled.

Development-machine tooling only; not part of any OS image.
"""
import math
import struct


def f32(x):
    return struct.unpack('<f', struct.pack('<f', x))[0]


def roundf(x):
    """C roundf: half away from zero."""
    return int(math.floor(abs(x) + 0.5)) * (1 if x >= 0 else -1)


def u16(d, p):
    return struct.unpack_from('>H', d, p)[0]


def i16(d, p):
    return struct.unpack_from('>h', d, p)[0]


def u32(d, p):
    return struct.unpack_from('>I', d, p)[0]


def i32(d, p):
    return struct.unpack_from('>i', d, p)[0]


def fixed(d, p):
    return f32(f32(float(i32(d, p))) / 65536.0)


def f2dot14(d, p):
    return i16(d, p)


# ---------------------------------------------------------------- axes
def axes(fvar):
    """-> [(tag, min, default, max)] as float32, min / max ordered around the default."""
    off, count, size = u16(fvar, 4), u16(fvar, 8), u16(fvar, 10)
    out = []
    for i in range(count):
        p = off + i * size
        tag = fvar[p:p + 4].decode('latin-1')
        lo, de, hi = fixed(fvar, p + 4), fixed(fvar, p + 8), fixed(fvar, p + 12)
        out.append((tag, min(de, lo), de, max(de, hi)))
    return out


def map_float(maps, value):
    """avar's SegmentMaps.map_float (float32)."""
    n = len(maps)
    if n < 2:
        if not n:
            return value
        return f32(f32(value - maps[0][0]) + maps[0][1])
    start, end = 0, n
    if maps[0][0] == -1 and maps[0][1] == -1 and maps[1][0] == -1:
        start += 1
    if maps[end - 1][0] == 1 and maps[end - 1][1] == 1 and maps[end - 2][0] == 1:
        end -= 1
    i = start
    while i < end and value != maps[i][0]:
        i += 1
    if i < end:
        j = i
        while j + 1 < end and value == maps[j + 1][0]:
            j += 1
        if i == j:
            return maps[i][1]
        if i + 2 == j:
            return maps[i + 1][1]
        if value < 0:
            return maps[j][1]
        if value > 0:
            return maps[i][1]
        return maps[i][1] if abs(maps[i][1]) < abs(maps[j][1]) else maps[j][1]
    i = start
    while i < end and not value < maps[i][0]:
        i += 1
    if i == 0:
        return f32(f32(value - maps[0][0]) + maps[0][1])
    if i == end:
        return f32(f32(value - maps[end - 1][0]) + maps[end - 1][1])
    b, a = maps[i - 1], maps[i]
    denom = f32(a[0] - b[0])
    return f32(b[1] + f32(f32(f32(a[1] - b[1]) * f32(value - b[0])) / denom))


def avar_maps(avar, naxes):
    if avar is None or len(avar) < 8:
        return None
    count = u16(avar, 6)
    p, out = 8, []
    for _ in range(min(count, naxes)):
        n = u16(avar, p)
        p += 2
        out.append([(f32(f2dot14(avar, p + 4 * k) / 16384.0), f32(f2dot14(avar, p + 4 * k + 2) / 16384.0))
                    for k in range(n)])
        p += 4 * n
    return out


def normalize(fvar, avar, settings):
    ax = axes(fvar)
    coords = [0] * len(ax)
    for tag, value in settings.items():
        for k, (t, lo, de, hi) in enumerate(ax):
            if t == tag:
                v = f32(min(max(f32(value), lo), hi))
                if v == de:
                    n = 0.0
                elif v < de:
                    n = f32(f32(v - de) / f32(de - lo))
                else:
                    n = f32(f32(v - de) / f32(hi - de))
                coords[k] = roundf(f32(n * 65536.0))
                break
    maps = avar_maps(avar, len(ax))
    if maps:
        for k, m in enumerate(maps):
            coords[k] = roundf(f32(map_float(m, f32(coords[k] / 65536.0)) * 65536.0))
    return [(c + 2) >> 2 for c in coords]


# ---------------------------------------------------------------- item variation stores
class ItemStore:
    def __init__(self, data, off):
        self.d, self.off = data, off
        reg = off + u32(data, off + 2)
        self.axis_count, self.region_count = u16(data, reg), u16(data, reg + 2)
        self.regions = reg + 4
        n = u16(data, off + 6)
        self.sets = [off + u32(data, off + 8 + 4 * k) for k in range(n)]

    def axis_factor(self, p, coord):
        start, peak, end = f2dot14(self.d, p), f2dot14(self.d, p + 2), f2dot14(self.d, p + 4)
        if peak == 0 or coord == peak:
            return 1.0
        if coord == 0:
            return 0.0
        if start > peak or peak > end:
            return 1.0
        if start < 0 and end > 0 and peak != 0:
            return 1.0
        if coord <= start or end <= coord:
            return 0.0
        if coord < peak:
            return f32(f32(float(coord - start)) / f32(float(peak - start)))
        return f32(f32(float(end - coord)) / f32(float(end - peak)))

    def region(self, r, coords):
        if r >= self.region_count:
            return 0.0
        v = 1.0
        for i in range(self.axis_count):
            c = coords[i] if i < len(coords) else 0
            f = self.axis_factor(self.regions + (r * self.axis_count + i) * 6, c)
            if f == 0.0:
                return 0.0
            v = f32(v * f)
        return v

    def delta(self, outer, inner, coords):
        if outer >= len(self.sets):
            return 0.0
        d, p = self.d, self.sets[outer]
        items, wc, rc = u16(d, p), u16(d, p + 2), u16(d, p + 4)
        if inner >= items or rc == 0:
            return 0.0
        long_words = bool(wc & 0x8000)
        wc &= 0x7FFF
        rix = [u16(d, p + 6 + 2 * k) for k in range(rc)]
        wsize, bsize = (4, 2) if long_words else (2, 1)
        row = wc * wsize + (rc - wc) * bsize
        q = p + 6 + 2 * rc + inner * row
        delta = 0.0
        for k in range(rc):
            if k < wc:
                v = i32(d, q) if long_words else i16(d, q)
                q += wsize
            else:
                v = i16(d, q) if long_words else struct.unpack_from('b', d, q)[0]
                q += bsize
            s = self.region(rix[k], coords)
            if s:
                delta = f32(delta + f32(s * f32(float(v))))
        return delta


def delta_map(d, off, index):
    """A DeltaSetIndexMap -> (outer, inner)."""
    fmt, ef = d[off], d[off + 1]
    if fmt == 0:
        count, p = u16(d, off + 2), off + 4
    else:
        count, p = u32(d, off + 2), off + 6
    if count == 0:
        return 0, index
    if index >= count:
        index = count - 1
    width = ((ef >> 4) & 3) + 1
    inner_bits = (ef & 0xF) + 1
    v = int.from_bytes(d[p + index * width:p + index * width + width], 'big')
    return v >> inner_bits, v & ((1 << inner_bits) - 1)


def hvar_delta(hvar, glyph, coords):
    store = ItemStore(hvar, u32(hvar, 4))
    mapoff = u32(hvar, 8)
    if mapoff:
        outer, inner = delta_map(hvar, mapoff, glyph)
    else:
        outer, inner = 0, glyph
    return store.delta(outer, inner, coords)


# ---------------------------------------------------------------- gvar
def _points(d, p):
    """Packed point numbers -> (list (empty: all points), p after)."""
    n = d[p]
    p += 1
    if n & 0x80:
        n = ((n & 0x7F) << 8) | d[p]
        p += 1
    out, last = [], 0
    while len(out) < n:
        c = d[p]
        p += 1
        words = c & 0x80
        run = (c & 0x7F) + 1
        for _ in range(run):
            if words:
                last += u16(d, p)
                p += 2
            else:
                last += d[p]
                p += 1
            out.append(last)
    return out, p


def _deltas(d, p, n):
    out = []
    while len(out) < n:
        c = d[p]
        p += 1
        run = (c & 0x3F) + 1
        kind = c & 0xC0
        for _ in range(run):
            if kind == 0x80:
                out.append(0)
            elif kind == 0x40:
                out.append(i16(d, p))
                p += 2
            elif kind == 0xC0:
                out.append(i32(d, p))
                p += 4
            else:
                out.append(struct.unpack_from('b', d, p)[0])
                p += 1
    return out[:n], p


def tuple_scalar(coords, peak, start, end):
    s = 1.0
    for i, pk in enumerate(peak):
        if not pk:
            continue
        v = coords[i] if i < len(coords) else 0
        if not v:
            return 0.0
        if v == pk:
            continue
        if start is not None:
            st, en = start[i], end[i]
            if st > pk or pk > en or (st < 0 and en > 0 and pk):
                continue
            if v < st or v > en:
                return 0.0
            if v < pk:
                if pk != st:
                    s *= (v - st) / (pk - st)
            elif pk != en:
                s *= (en - v) / (en - pk)
        elif v < min(0, pk) or v > max(0, pk):
            return 0.0
        else:
            s *= v / pk
    return s


def gvar_deltas(gvar, glyph, coords, points, ends):
    """points: [(x, y)] including the four phantoms; ends: indices ending contours (a composite's
    components each end one). -> [(dx, dy)] doubles."""
    n = len(points)
    total = [[0.0, 0.0] for _ in range(n)]
    axis_count, shared_count = u16(gvar, 4), u16(gvar, 6)
    shared_off, glyph_count, flags = u32(gvar, 8), u16(gvar, 12), u16(gvar, 14)
    data_off = u32(gvar, 16)
    if glyph >= glyph_count:
        return total
    if flags & 1:
        a, b = u32(gvar, 20 + 4 * glyph), u32(gvar, 24 + 4 * glyph)
    else:
        a, b = 2 * u16(gvar, 20 + 2 * glyph), 2 * u16(gvar, 22 + 2 * glyph)
    if b <= a:
        return total
    g = data_off + a
    count = u16(gvar, g)
    shared_points = bool(count & 0x8000)
    count &= 0x0FFF
    ser = g + u16(gvar, g + 2)
    p = g + 4
    shared = []
    if shared_points:
        shared, ser = _points(gvar, ser)
    end_set = set(ends)
    for _ in range(count):
        size, tidx = u16(gvar, p), u16(gvar, p + 2)
        p += 4
        if tidx & 0x8000:
            peak = [f2dot14(gvar, p + 2 * k) for k in range(axis_count)]
            p += 2 * axis_count
        else:
            k = tidx & 0x0FFF
            peak = [f2dot14(gvar, shared_off + 2 * (k * axis_count + j)) for j in range(axis_count)]
        start = end = None
        if tidx & 0x4000:
            start = [f2dot14(gvar, p + 2 * k) for k in range(axis_count)]
            end = [f2dot14(gvar, p + 2 * axis_count + 2 * k) for k in range(axis_count)]
            p += 4 * axis_count
        q, ser = ser, ser + size
        scalar = tuple_scalar(coords, peak, start, end)
        if scalar == 0.0:
            continue
        if tidx & 0x2000:
            idx, q = _points(gvar, q)
        else:
            idx = shared
        allp = not idx
        m = n if allp else len(idx)
        xs, q = _deltas(gvar, q, m)
        ys, q = _deltas(gvar, q, m)
        d = [[0.0, 0.0] for _ in range(n)]
        named = [allp] * n
        for k in range(m):
            pt = k if allp else idx[k]
            if pt >= n:
                continue
            d[pt][0] += xs[k] * scalar
            d[pt][1] += ys[k] * scalar
            named[pt] = True
        if not allp:
            _iup(points, d, named, ends)
        for k in range(n):
            total[k][0] += d[k][0]
            total[k][1] += d[k][1]
    return total


def _iup(points, d, named, ends):
    """Deltas for the points a tuple does not name, from the named ones around them (per contour)."""
    start = 0
    for end in ends:
        idx = list(range(start, end + 1))
        start = end + 1
        refs = [i for i in idx if named[i]]
        if not refs or len(refs) == len(idx):
            continue
        for i in idx:
            if named[i]:
                continue
            # the nearest named points before and after, around the contour
            k = idx.index(i)
            prev = next_ = None
            for s in range(1, len(idx)):
                j = idx[(k - s) % len(idx)]
                if named[j]:
                    prev = j
                    break
            for s in range(1, len(idx)):
                j = idx[(k + s) % len(idx)]
                if named[j]:
                    next_ = j
                    break
            for c in (0, 1):
                t, pv, nv = points[i][c], points[prev][c], points[next_][c]
                pd, nd = d[prev][c], d[next_][c]
                if pv == nv:
                    v = pd if pd == nd else 0.0
                elif t <= min(pv, nv):
                    v = pd if pv < nv else nd
                elif t >= max(pv, nv):
                    v = pd if pv > nv else nd
                else:
                    v = pd + (t - pv) / (nv - pv) * (nd - pd)
                d[i][c] = v


# ---------------------------------------------------------------- feature variations
def feature_variation(table, coords):
    """GSUB / GPOS 1.1: {feature index: alternate Feature table offset (from the table's start)}
    for the first record whose condition set holds, else {}."""
    if len(table) < 14 or u16(table, 2) < 1:
        return {}
    off = u32(table, 10)
    if not off:
        return {}
    n = u32(table, off + 4)
    for k in range(n):
        rec = off + 8 + 8 * k
        cs, sub = u32(table, rec), u32(table, rec + 4)
        ok = True
        if cs:
            cs += off
            for c in range(u16(table, cs)):
                cp = cs + u32(table, cs + 2 + 4 * c)
                if u16(table, cp) != 1:
                    ok = False
                    break
                axis, lo, hi = u16(table, cp + 2), f2dot14(table, cp + 4), f2dot14(table, cp + 6)
                v = coords[axis] if axis < len(coords) else 0
                if not lo <= v <= hi:
                    ok = False
                    break
        if ok:
            out = {}
            if sub:
                sub += off
                for s in range(u16(table, sub + 4)):
                    sp = sub + 6 + 6 * s
                    out[u16(table, sp)] = sub + u32(table, sp + 2)
            return out
    return {}
