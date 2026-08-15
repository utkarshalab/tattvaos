# lib/str/dict — Default English Dictionary

The **`lib/str/dict`** module is Tattva OS's default English dictionary:
exact word lookup, prefix/autocomplete search, and edit-distance spellcheck
suggestions, backed by a ~348K-word table baked directly into the kernel
image. It exists so editors (`uedit`), the shell (`ush` tab completion), and
any other consumer can get correct, fast dictionary answers by including one
file — no init call, no allocation, nothing to wire up beyond the include.

---

## 1. Why this shape

Tattva OS has no filesystem lookup at boot and no libc dictionary to shell
out to (`/usr/share/dict/words` is a Linux/BSD convention, not something
this kernel has). The two options were: build the dictionary at runtime
(parse a wordlist, insert into a trie, pay that cost on every boot), or bake
a pre-sorted table into `.rodata` and binary-search it. This module does the
latter — it is read-only data the kernel never needs to construct, so there
is no init ordering to get right and no boot-time cost at all.

`lib/str/trie.asm` already provides a general-purpose dynamic trie for
*mutable* string sets (identifiers, DNS labels, tab-completion of things the
kernel didn't ship with). This module is not built on it: a trie over
348K English words costs roughly one node per unique prefix byte — several
million nodes even with prefix sharing, tens of megabytes of pointer-chasing
structure for data that never changes after boot. A flat sorted table with
two parallel index arrays holds the same words in ~4.9 MB with O(log N)
lookup and no pointers to chase.

---

## 2. Directory layout

```
lib/str/dict/
├── dict.asm            ← aggregator include — this is what consumers %include
├── dict.inc             ← DictMatch struct, DICT_* constants
├── lookup.asm           ← _dict_cmp_at, str_dict_word_count, str_dict_lookup,
│                           str_dict_get
├── prefix.asm            ← _dict_lower_bound, _dict_prefix_bounds,
│                           str_dict_prefix_range, str_dict_prefix_count
├── suggest.asm            ← _dict_edit_distance, str_dict_suggest
├── tables/
│   └── dict_table.asm      ← GENERATED — the word data itself (~4.9 MB)
└── tests/
    ├── dict_test.asm        ← semantic test suite (hosted Linux binary)
    └── run.sh                ← builds and runs it, decodes the pass/fail mask

lib/str/data/dict/            ← raw wordlist source, gitignored (see §6)
lib/str/tools/gen_dict_table.py  ← the generator, gitignored (see §6)
```

---

## 3. Table format

`dict/tables/dict_table.asm` defines four `.rodata` symbols, three parallel
arrays plus the blob they index into, all sorted ascending by the raw UTF-8
byte sequence of each word (which is the same total order as codepoint
order, so this is a correct, locale-independent sort with no collation
table needed):

```
dict_word_count   dd            N  (348454 as generated)
dict_blob_size    dd            total byte length of dict_blob
dict_offsets      dd[N]         dict_offsets[i] = byte offset of word i in dict_blob
dict_lengths      db[N]         dict_lengths[i] = byte length of word i (<= 255)
dict_blob         db[...]       concatenated word bytes, no separators
```

Word `i`'s bytes are `dict_blob[dict_offsets[i] .. dict_offsets[i] +
dict_lengths[i])`. Nothing is null-terminated; every function in this module
takes and returns `{ptr, len}` pairs (`StrSlice` for input, `DictMatch` for
output — see `dict.inc`).

---

## 4. Algorithms and complexity

| Operation | Function | Approach | Complexity |
|---|---|---|---|
| Exact membership | `str_dict_lookup` | binary search over the sorted table | O(log N) ≈ 19 compares |
| Indexed access | `str_dict_get` | direct array read | O(1) |
| Prefix range | `str_dict_prefix_range` / `_count` | two lower-bound searches: one for the prefix, one for its byte-successor | O(log N) |
| Spellcheck | `str_dict_suggest` | length-pruned linear scan + bounded Levenshtein DP | O(N) scan, O(len²) per surviving candidate |

**Prefix search.** Because the table is sorted by content, every word
sharing a prefix occupies one contiguous index range `[lo, hi)`. `lo` is
`lower_bound(prefix)`; `hi` is `lower_bound(successor(prefix))`, where
`successor` increments the prefix's last byte (carrying into earlier bytes
on `0xFF`, like incrementing a big-endian integer) to get the smallest
string that is *not* prefixed by it. Enumerate matches by calling
`str_dict_get` over `[lo, hi)`.

**Spellcheck.** `str_dict_suggest` computes plain Levenshtein distance
(insert/delete/substitute, unit cost — not Damerau-Levenshtein; transposition
support is a deliberate scope cut, not an oversight) between the query and
every candidate word, but two cheap checks reject almost all of the table
before the O(len²) DP ever runs: a length-difference prune
(`|len(word) - len(query)| > max_distance` can't possibly be within budget)
and a hard cap (`DICT_SUGGEST_MAX_LEN = 128`) that bounds the DP's stack row
buffers. Surviving candidates are kept in a running top-`max_results` list,
maintained by insertion sort as the scan proceeds, sorted ascending by
distance with ties broken by dictionary order (earlier scan position wins,
since the table is scanned index `0..N-1` in order).

Everything in this module runs on the stack or reads `.rodata` directly —
no arena, no heap allocation, anywhere.

---

## 5. API reference

All functions follow the `lib/str` calling convention (`arch/common/macros.inc`):
System V AMD64 integer args, `RAX = STR_OK (0)` on success and a negative
`STR_ERR_*` on failure unless noted otherwise. See each `.asm` file's header
comment for the full contract; summary:

| Function | Signature |
|---|---|
| `str_dict_word_count` | `uint64_t str_dict_word_count(void)` |
| `str_dict_lookup` | `int64_t str_dict_lookup(const StrSlice *word)` |
| `str_dict_get` | `int64_t str_dict_get(uint64_t index, DictMatch *out)` |
| `str_dict_prefix_range` | `int64_t str_dict_prefix_range(const StrSlice *prefix, uint64_t *out_lo, uint64_t *out_hi)` |
| `str_dict_prefix_count` | `int64_t str_dict_prefix_count(const StrSlice *prefix)` — count is the return value itself, not an out-param; a zero count is success, not `STR_ERR_NOT_FOUND` |
| `str_dict_suggest` | `int64_t str_dict_suggest(const StrSlice *word, uint32_t max_distance, DictMatch *out_matches, uint64_t max_results, uint64_t *out_count)` |

`DictMatch` (`dict.inc`, 24 bytes): `{ptr, len, distance}` — `ptr`/`len`
borrow directly into `dict_blob`; never free or mutate them. `distance` is
`0` for `str_dict_get` and `str_dict_lookup`-style exact results.

---

## 6. Regenerating the table

The raw wordlist and the generator script are intentionally not committed —
same policy as `lib/str/data/ucd` (Unicode Character Database) and
`lib/str/tools/gen_unicode_tables.py`, see `lib/str/.gitignore`. Only the
generated `.asm` table is tracked, since that is the only artifact the build
actually reads.

To regenerate:

```bash
# Fetch the source wordlist (SCOWL, via Debian's wamerican-huge package;
# apt-get download works without root):
apt-get download wamerican-huge
dpkg-deb -x wamerican-huge_*.deb /tmp/wah
cp /tmp/wah/usr/share/dict/american-english-huge lib/str/data/dict/american-english-huge.txt

python3 lib/str/tools/gen_dict_table.py \
    --in lib/str/data/dict/american-english-huge.txt \
    --out lib/str/dict/tables/dict_table.asm
```

Source wordlist license: `lib/str/data/dict/SOURCE-LICENSE.txt` (SCOWL,
Debian's `wamerican-huge`, permissive/BSD-style per-wordlist).

---

## 7. Testing

```bash
bash lib/str/dict/tests/run.sh
```

Builds `dict/tests/dict_test.asm` (which `%include`s `dict/dict.asm` — the
exact same include a real consumer would use) as a hosted Linux ELF binary
and runs it. Every non-error-path assertion in the suite was independently
cross-checked against the same wordlist using a separate Python
implementation of binary search and Levenshtein distance, not derived from
this assembly, so a bug shared between the generator and the lookup code
would not hide behind agreement between the two. The pass/fail mask is
written as four raw bytes on stdout rather than returned as an exit code —
see `security/usrauth/tests/harness.asm` for why an 8-bit exit status isn't
enough once a suite passes eight tests.

---

*Utkarsha Labs © 2026 — Building the last software stack.*
