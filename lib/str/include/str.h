/* ===========================================================================
 * str/include/str.h
 * C-compatible header for the Tattva OS str library.
 *
 * Part of Utkarsha Labs / Tattva OS
 *
 * This header exposes all public functions from the str library to C callers.
 * All functions use the System V AMD64 ABI (RDI, RSI, RDX, RCX, R8, R9).
 * Return convention: 0 = success, negative = error code.
 *
 * Link with: the assembled str library object files.
 *
 * Usage:
 *   #include "str.h"
 *
 *   StrSlice s = { .ptr = (uint8_t*)"hello", .len = 5 };
 *   uint64_t count;
 *   str_grapheme_count(&s, &count);
 * =========================================================================== */

#ifndef TATTVA_STR_H
#define TATTVA_STR_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ---- Error codes ---- */

#define STR_OK              0
#define STR_ERR_NULL       -1
#define STR_ERR_INVALID    -2
#define STR_ERR_BUF_TOO_SMALL -3
#define STR_ERR_ITER_END   -4
#define STR_ERR_PARSE      -5
#define STR_ERR_ALLOC      -6
#define STR_ERR_OVERFLOW   -7
#define STR_ERR_NOT_FOUND  -8

/* ---- Core types ---- */

typedef struct {
    uint8_t  *ptr;
    uint64_t  len;
} StrSlice;

typedef struct {
    uint8_t  *ptr;
    uint64_t  len;
    uint64_t  cap;
} StrBuf;

#define STRSLICE_SIZE  16
#define STRBUF_SIZE    24

/* ---- utf8/ ---- */

int64_t  str_utf8_charlen(uint8_t lead_byte);
int64_t  str_utf8_validate(const StrSlice *src);
uint64_t str_utf8_len(const StrSlice *src, uint64_t *out_count);
uint32_t str_utf8_decode_unchecked(const uint8_t *src, uint64_t *out_advance);
uint64_t str_utf8_encode_unchecked(uint32_t cp, uint8_t *dst);
int64_t  str_utf8_iter_init(const StrSlice *src, void *iter);
int64_t  str_utf8_iter_next(void *iter, uint32_t *out_cp);
int64_t  str_utf8_nth(const StrSlice *src, uint64_t n, uint32_t *out_cp);
int64_t  str_utf8_offset(const StrSlice *src, uint64_t cp_index, uint64_t *out_byte_offset);
int64_t  str_utf8_bom_detect(const StrSlice *src, uint64_t *out_bom_len);

/* ---- inspect/ ---- */

int64_t str_is_ascii(const StrSlice *src);
int64_t str_is_utf8(const StrSlice *src);
int64_t str_is_alpha(uint32_t cp);
int64_t str_is_numeric(uint32_t cp);
int64_t str_is_space(uint32_t cp);
int64_t str_is_upper(uint32_t cp);
int64_t str_is_lower(uint32_t cp);
int64_t str_is_alnum(uint32_t cp);
int64_t str_is_print(uint32_t cp);
int64_t str_is_blank(uint32_t cp);
int64_t str_char_class(uint32_t cp);
int64_t str_hex_digit_value(uint8_t ch);
int64_t str_is_null_or_empty(const StrSlice *src);

/* ---- core/ ---- */

int64_t str_new(StrSlice *out, const uint8_t *ptr, uint64_t len);
int64_t str_empty(StrSlice *out);
int64_t str_slice(const StrSlice *src, uint64_t start, uint64_t end, StrSlice *out);
int64_t str_cmp(const StrSlice *a, const StrSlice *b);
int64_t str_eq(const StrSlice *a, const StrSlice *b);
int64_t str_copy_bytes(uint8_t *dst, const uint8_t *src, uint64_t len);
int64_t str_concat(const StrSlice *a, const StrSlice *b, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_trim(const StrSlice *src, StrSlice *out);
int64_t str_split(const StrSlice *src, uint8_t delim, StrSlice *parts, uint64_t max_parts, uint64_t *out_count);
int64_t str_pad_left(const StrSlice *src, uint8_t pad_char, uint64_t target_len, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_repeat(const StrSlice *src, uint64_t count, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_reverse(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);

/* ---- search/ ---- */

int64_t str_find(const StrSlice *haystack, const StrSlice *needle, uint64_t *out_pos);
int64_t str_contains(const StrSlice *haystack, const StrSlice *needle);
int64_t str_starts_with(const StrSlice *str, const StrSlice *prefix);
int64_t str_ends_with(const StrSlice *str, const StrSlice *suffix);
int64_t str_count_occurrences(const StrSlice *haystack, const StrSlice *needle, uint64_t *out_count);

/* ---- convert/ ---- */

int64_t str_to_upper(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_to_lower(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_to_upper_tailored(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len, const char *locale);
int64_t str_to_lower_tailored(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len, const char *locale);
int64_t str_to_title_tailored(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len, const char *locale);
int64_t str_to_u64(const StrSlice *src, uint64_t *out);
int64_t str_to_i64(const StrSlice *src, int64_t *out);
int64_t str_u64_to_str(uint64_t val, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_to_hex(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_from_hex(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_base64_encode(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_base64_decode(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);

/* ---- format/ ---- */

int64_t str_itoa(int64_t val, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_ftoa(double val, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_fmt(const char *fmt_str, uint8_t *dst, uint64_t cap, uint64_t *out_len, ...);
int64_t str_sprintf(uint8_t *dst, uint64_t cap, uint64_t *out_len, const char *fmt, ...);

/* ---- hash/ ---- */

uint64_t str_fnv1a_64(const StrSlice *src);
uint32_t str_fnv1a_32(const StrSlice *src);
uint64_t str_djb2(const StrSlice *src);
uint64_t str_siphash_2_4(const StrSlice *src, const uint8_t key[16]);
void     str_murmur3_128(const StrSlice *src, uint32_t seed, uint64_t out[2]);
uint64_t str_xxhash_64(const StrSlice *src, uint64_t seed);

/* ---- diff/ ---- */

int64_t  str_hamming(const StrSlice *a, const StrSlice *b, uint64_t *out_distance);
int64_t  str_edit_distance(const StrSlice *a, const StrSlice *b, uint64_t *out_distance);
int64_t  str_lcs_length(const StrSlice *a, const StrSlice *b, uint64_t *out_len);
int64_t  str_jaro(const StrSlice *a, const StrSlice *b, uint64_t *out_score);
int64_t  str_jaro_winkler(const StrSlice *a, const StrSlice *b, uint64_t *out_score);
int64_t  str_diff_myers(const StrSlice *a, const StrSlice *b, int64_t *out_distance);
int64_t  str_soundex(const StrSlice *src, uint8_t *dst, uint64_t dst_cap, uint64_t *out_len);

/* ---- parse/ ---- */

int64_t str_parse_number(const StrSlice *src, uint64_t *out);
int64_t str_parse_duration(const StrSlice *src, uint64_t *out_ns);
int64_t str_parse_size(const StrSlice *src, uint64_t *out_bytes);
int64_t str_parse_version(const StrSlice *src, void *out_version);
int64_t str_parse_color(const StrSlice *src, uint32_t *out_rgba);
int64_t str_parse_uuid(const StrSlice *src, uint8_t out_uuid[16]);
int64_t str_parse_csv_line(const StrSlice *src, StrSlice *fields, uint64_t max_fields, uint64_t *out_count);

#define JSON_NULL   1
#define JSON_BOOL   2
#define JSON_NUMBER 3
#define JSON_STRING 4
#define JSON_ARRAY  5
#define JSON_OBJECT 6

int64_t str_json_parse(const StrSlice *json,
                       int64_t (*callback)(const StrSlice *key, const StrSlice *value, uint8_t type, void *ctx),
                       void *ctx);

/* ---- mem/ ---- */

int64_t str_arena_init(void *arena, uint8_t *buf, uint64_t buf_size);
void   *str_arena_alloc(void *arena, uint64_t size, uint64_t align);
int64_t str_arena_reset(void *arena);
uint64_t str_arena_used(const void *arena);
uint64_t str_arena_remaining(const void *arena);
void   *str_alloc(uint64_t size);
int64_t str_free(void *ptr, uint64_t size);
void   *str_realloc(void *old, uint64_t old_size, uint64_t new_size);
uint64_t str_align_up(uint64_t value, uint64_t align);
uint64_t str_align_down(uint64_t value, uint64_t align);

/* ---- buf/ ---- */

int64_t str_buf_init(StrBuf *buf);
int64_t str_buf_with_cap(StrBuf *buf, uint64_t cap);
int64_t str_buf_free(StrBuf *buf);
int64_t str_buf_push(StrBuf *buf, const uint8_t *data, uint64_t len);
int64_t str_buf_push_byte(StrBuf *buf, uint8_t byte);
int64_t str_buf_push_slice(StrBuf *buf, const StrSlice *slice);
int64_t str_buf_reserve(StrBuf *buf, uint64_t min_cap);
int64_t str_buf_clear(StrBuf *buf);
int64_t str_buf_as_slice(const StrBuf *buf, StrSlice *out);
int64_t str_buf_push_codepoint(StrBuf *buf, uint32_t cp);
int64_t str_buf_push_cstr(StrBuf *buf, const char *cstr);
int64_t str_buf_push_u64(StrBuf *buf, uint64_t value);
int64_t str_buf_push_newline(StrBuf *buf);

typedef struct {
    uint8_t  *ptr;
    uint64_t  len;
    uint64_t  cap;
} StrBuilder;

int64_t str_builder_init(StrBuilder *builder, uint8_t *buf, uint64_t cap);
int64_t str_builder_append(StrBuilder *builder, const StrSlice *slice);
int64_t str_builder_append_char(StrBuilder *builder, uint32_t cp);
int64_t str_builder_clear(StrBuilder *builder);
int64_t str_builder_build(const StrBuilder *builder, StrSlice *out);

/* ---- escape/ ---- */

int64_t str_html_escape(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_html_unescape(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_url_encode(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_url_decode(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_json_escape(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_json_unescape(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_xml_escape(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_shell_escape(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_regex_escape(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);

/* ---- sort/ ---- */

int64_t str_sort_u8(uint8_t *arr, uint64_t count);
int64_t str_sort_u64(uint64_t *arr, uint64_t count);
int64_t str_sort(void *arr, uint64_t count, uint64_t elem_size,
                 int64_t (*cmp)(const void *, const void *, void *), void *ctx);
int64_t str_sort_slices(StrSlice *arr, uint64_t count);
int64_t str_sort_slices_natural(StrSlice *arr, uint64_t count);
int64_t str_collate(const StrSlice *a, const StrSlice *b);
int64_t str_collate_tailored(const StrSlice *a, const StrSlice *b, const char *locale, uint64_t strength);

/* ---- interp/ ---- */

int64_t str_template_render(const StrSlice *tmpl,
                            int64_t (*lookup)(const StrSlice *, StrSlice *, void *),
                            void *ctx,
                            uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_env_expand(const StrSlice *src,
                       int64_t (*lookup)(const StrSlice *, StrSlice *, void *),
                       void *ctx,
                       uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_ansi_color(uint64_t code, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_ansi_reset(uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_ansi_strip(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
uint64_t str_ansi_visible_len(const StrSlice *src);

/* ---- pattern/ ---- */

int64_t str_glob_match(const StrSlice *pattern, const StrSlice *str);
int64_t str_glob_match_icase(const StrSlice *pattern, const StrSlice *str);
int64_t str_wildcard_match(const StrSlice *pattern, const StrSlice *str);
int64_t str_regex_test(const void *regex, const StrSlice *input);
int64_t str_regex_find_first(const void *regex, const StrSlice *input,
                             uint64_t *out_start, uint64_t *out_len);
uint64_t str_regex_count(const void *regex, const StrSlice *input);

/* ---- unicode/ ---- */

/* category, normalization, grapheme, word, sentence, linebreak, fold, block, name */
uint8_t  str_cp_category(uint32_t cp);
int64_t  str_cp_category_str(uint32_t cp, uint8_t *out2);
uint8_t  str_cp_category_group(uint32_t cp);
int64_t  str_cp_is_letter(uint32_t cp);
int64_t  str_cp_is_mark(uint32_t cp);
int64_t  str_cp_is_number_cat(uint32_t cp);
int64_t  str_cp_is_punct(uint32_t cp);
uint8_t  str_cp_ccc(uint32_t cp);
int64_t  str_normalize_nfd(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_normalize_nfc(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_normalize_nfkd(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_normalize_nfkc(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_is_nfc(const StrSlice *src);
int64_t  str_is_nfd(const StrSlice *src);
int64_t  str_is_nfkc(const StrSlice *src);
int64_t  str_is_nfkd(const StrSlice *src);
int64_t  str_grapheme_count(const StrSlice *src, uint64_t *out_count);
int64_t  str_grapheme_next(const StrSlice *src, uint64_t offset, uint64_t *out_next);
int64_t  str_grapheme_truncate(const StrSlice *src, uint64_t max_graphemes, uint64_t *out_byte_len);
int64_t  str_word_next(const StrSlice *src, uint64_t offset, uint64_t *out_next);
int64_t  str_word_count(const StrSlice *src, uint64_t *out_count);
int64_t  str_sentence_next(const StrSlice *src, uint64_t offset, uint64_t *out_next);
int64_t  str_sentence_count(const StrSlice *src, uint64_t *out_count);
uint8_t  str_linebreak_class(uint32_t cp);
int64_t  str_linebreak_next(const StrSlice *src, uint64_t offset,
                            uint64_t *out_pos, uint8_t *out_mandatory);
uint32_t str_cp_fold_simple(uint32_t cp);
int64_t  str_fold(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_fold_eq(const StrSlice *a, const StrSlice *b);
uint32_t str_cp_block(uint32_t cp);
const char *str_cp_block_name(uint32_t cp);
int64_t  str_cp_name(uint32_t cp, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_punycode_encode(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_punycode_decode(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_idna_to_ascii(const StrSlice *domain, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_idna_to_unicode(const StrSlice *domain, uint8_t *dst, uint64_t cap, uint64_t *out_len);
uint8_t  str_bidi_class(uint32_t cp);
uint8_t  str_bidi_paragraph_level(const StrSlice *src);
int64_t  str_bidi_resolve(const StrSlice *src, uint8_t base_level,
                          uint8_t *levels, uint64_t cap, uint64_t *out_count);
int64_t  str_bidi_reorder(const uint8_t *levels, uint64_t count, uint32_t *visual_order);
int64_t  str_bidi_is_rtl(const StrSlice *src);

/* decomposition type queries (decomposition.asm) */
uint8_t  str_cp_decomp_type(uint32_t cp);
int64_t  str_cp_has_decomp(uint32_t cp);
int64_t  str_cp_is_compat_decomp(uint32_t cp);
int64_t  str_cp_decomp_mapping(uint32_t cp, uint32_t *out_buf, uint64_t cap, uint64_t *out_count);
uint64_t str_cp_decomp_length(uint32_t cp);

/* composition exclusion (composition_exclusion.asm) */
int64_t  str_cp_is_composition_exclusion(uint32_t cp);
int64_t  str_cp_is_full_composition_exclusion(uint32_t cp);
int64_t  str_cp_is_singleton_decomp(uint32_t cp);
int64_t  str_cp_is_nonstarter_decomp(uint32_t cp);

/* security / confusable detection (security.asm) */
uint32_t str_cp_skeleton(uint32_t cp);
int64_t  str_cp_is_confusable_with(uint32_t cp1, uint32_t cp2);
int64_t  str_is_mixed_script_confusable(const StrSlice *src);
uint8_t  str_cp_identifier_status(uint32_t cp);
uint8_t  str_cp_identifier_type(uint32_t cp);
int64_t  str_cp_is_do_not_emit(uint32_t cp);
int64_t  str_is_highly_restrictive(const StrSlice *src);
int64_t  str_has_mixed_number_systems(const StrSlice *src);

/* named sequences (named_sequences.asm) */
uint64_t str_named_sequence_count(void);
int64_t  str_named_sequence_lookup(const StrSlice *name, uint32_t *out_cps,
                                    uint64_t cap, uint64_t *out_count);
int64_t  str_named_sequence_by_index(uint64_t index, uint32_t *out_cps,
                                      uint64_t cap, uint64_t *out_count);
int64_t  str_named_sequence_name(uint64_t index, StrSlice *out);

/* standardized variants (standardized_variants.asm) */
int64_t  str_cp_is_variation_selector(uint32_t cp);
int64_t  str_cp_variation_selector_num(uint32_t cp);
int64_t  str_cp_has_standardized_variant(uint32_t cp);
uint64_t str_cp_variant_count(uint32_t cp);
int64_t  str_is_text_presentation(uint32_t cp);
int64_t  str_is_emoji_presentation_vs(uint32_t cp);

/* emoji sequences (emoji_sequences.asm) */
int64_t  str_emoji_is_keycap_seq(const StrSlice *src, uint64_t offset, uint64_t *out_end);
int64_t  str_emoji_is_flag_seq(const StrSlice *src, uint64_t offset, uint64_t *out_end);
int64_t  str_emoji_is_modifier_seq(const StrSlice *src, uint64_t offset, uint64_t *out_end);
int64_t  str_emoji_is_tag_seq(const StrSlice *src, uint64_t offset, uint64_t *out_end);
int64_t  str_emoji_is_zwj_seq(const StrSlice *src, uint64_t offset, uint64_t *out_end);
uint8_t  str_emoji_presentation_style(uint32_t base_cp, uint32_t next_cp);
uint8_t  str_emoji_sequence_type(const StrSlice *src, uint64_t offset);
int64_t  str_emoji_has_modifier(uint32_t cp);
int64_t  str_emoji_resolve_modifiers(const StrSlice *src, uint64_t offset, uint64_t *out_advance, uint32_t *out_mod);
int64_t  str_emoji_is_multi_person(const StrSlice *src, uint64_t offset);

/* equivalent ideograph (equivalent_ideograph.asm) */
uint32_t str_cp_equivalent_unified(uint32_t cp);
int64_t  str_cp_is_compat_ideograph(uint32_t cp);
int64_t  str_cp_is_cjk_unified(uint32_t cp);

/* do-not-emit (do_not_emit.asm) */
uint8_t  str_cp_do_not_emit_reason(uint32_t cp);
int64_t  str_cp_is_deprecated(uint32_t cp);

/* property aliases (property_aliases.asm) */
int64_t  str_property_from_alias(const StrSlice *alias, uint8_t *out_prop_id);
int64_t  str_property_value_from_alias(uint8_t prop_id, const StrSlice *alias,
                                        uint8_t *out_value_id);
int64_t  str_property_short_name(uint8_t prop_id, StrSlice *out);
int64_t  str_property_long_name(uint8_t prop_id, StrSlice *out);

/* normalization corrections (normalization_corrections.asm) */
int64_t  str_cp_has_norm_correction(uint32_t cp);
uint32_t str_cp_norm_correction_old(uint32_t cp);
uint32_t str_cp_norm_correction_new(uint32_t cp);
uint16_t str_cp_norm_correction_ver(uint32_t cp);

/* nushu / tangut (nushu_tangut.asm) */
int64_t  str_cp_is_nushu(uint32_t cp);
int64_t  str_cp_is_tangut(uint32_t cp);
int64_t  str_cp_is_tangut_component(uint32_t cp);
int64_t  str_cp_nushu_radical(uint32_t cp, uint8_t *out_radical);
int64_t  str_cp_nushu_strokes(uint32_t cp, uint8_t *out_strokes);
int64_t  str_cp_tangut_radical(uint32_t cp, uint16_t *out_radical);
int64_t  str_cp_tangut_strokes(uint32_t cp, uint8_t *out_strokes);

/* ---- path/ ---- */

int64_t str_path_join(const StrSlice *left, const StrSlice *right,
                      uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_path_dirname(const StrSlice *path, StrSlice *out);
int64_t str_path_basename(const StrSlice *path, StrSlice *out);
int64_t str_path_extension(const StrSlice *path, StrSlice *out);
int64_t str_path_stem(const StrSlice *path, StrSlice *out);
int64_t str_path_normalize(const StrSlice *path, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_path_is_absolute(const StrSlice *path);
int64_t str_path_is_root(const StrSlice *path);
uint64_t str_path_depth(const StrSlice *path);

/* ---- intern/ ---- */

int64_t str_intern_pool_init(void *pool, void *arena);
int64_t str_intern(void *pool, const StrSlice *str, StrSlice *out);
int64_t str_intern_lookup(const void *pool, const StrSlice *str, StrSlice *out);
uint64_t str_intern_count(const void *pool);

/* ---- match/ ---- */

int64_t str_ac_build(const StrSlice *patterns, uint64_t count, void *arena, void *out);
int64_t str_ac_search(const void *ac, const StrSlice *text,
                      void (*on_match)(const void *match, void *ctx), void *ctx);
uint64_t str_ac_count(const void *ac, const StrSlice *text);

/* ---- standalone data structures ---- */

/* rope */
void    *str_rope_leaf(const StrSlice *chunk, void *arena);
void    *str_rope_concat(void *left, void *right, void *arena);
uint64_t str_rope_len(const void *rope);
int64_t  str_rope_index(const void *rope, uint64_t idx, uint8_t *out);
int64_t  str_rope_to_slice(const void *rope, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_rope_split(void *rope, uint64_t idx, void *arena, void **out_left, void **out_right);
int64_t  str_rope_insert(void *rope, uint64_t idx, const StrSlice *slice, void *arena);
int64_t  str_rope_delete(void *rope, uint64_t idx, uint64_t len, void *arena);
int64_t  str_simd_utf8_validate(const StrSlice *src);

/* trie */
int64_t str_trie_init(void *trie, void *arena);
int64_t str_trie_insert(void *trie, const StrSlice *key, uint64_t value);
int64_t str_trie_lookup(const void *trie, const StrSlice *key, uint64_t *out_value);
int64_t str_trie_starts_with(const void *trie, const StrSlice *prefix);
uint64_t str_trie_count(const void *trie);

/* script detection */
uint8_t     str_cp_script(uint32_t cp);
uint8_t     str_script_detect(const StrSlice *src);
const char *str_script_name(uint8_t script);
int64_t     str_is_mixed_script(const StrSlice *src);

/* devanagari */
int64_t  str_deva_is_consonant(uint32_t cp);
int64_t  str_deva_is_vowel(uint32_t cp);
int64_t  str_deva_is_matra(uint32_t cp);
int64_t  str_deva_is_virama(uint32_t cp);
int64_t  str_deva_akshar_count(const StrSlice *src, uint64_t *out_count);
int64_t  str_deva_to_digits(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t  str_deva_from_digits(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);

/* locale */
typedef struct {
    StrSlice lang;
    StrSlice script;
    StrSlice region;
    StrSlice variant;
} ParsedLocale;

int64_t str_locale_parse(const StrSlice *tag, ParsedLocale *out);
int64_t str_locale_canonicalize(const StrSlice *tag, uint8_t *dst, uint64_t dst_cap, uint64_t *out_len);
int64_t str_locale_match_fallback(const StrSlice *locale, const StrSlice *target_list, uint64_t target_count, uint64_t *out_index);

/* net */
typedef struct {
    StrSlice scheme;
    StrSlice user;
    StrSlice pass;
    StrSlice host;
    StrSlice port;
    StrSlice path;
    StrSlice query;
    StrSlice fragment;
} ParsedURL;

int64_t str_url_parse(const StrSlice *url, ParsedURL *out);
int64_t str_url_to_idn(const StrSlice *host, uint8_t *dst, uint64_t dst_cap, uint64_t *out_len);

/* ---- encoding/ ---- */

int64_t str_detect_encoding(const StrSlice *src, uint8_t *out_encoding);
int64_t str_detect_bom(const StrSlice *src, uint8_t *out_encoding, uint64_t *out_bom_len);
int64_t str_iso2022jp_to_utf8(const uint8_t *src, uint64_t len, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_gb18030_decode_one(const uint8_t *src, uint64_t len, uint32_t *out_cp, uint64_t *out_advance);

#Individual codec decode_one / to_utf8 functions follow the same pattern:
 *   int64_t str_<codec>_decode_one(const uint8_t *src, uint64_t len,
 *                                   uint32_t *out_cp, uint64_t *out_advance);
 *   int64_t str_<codec>_to_utf8(const uint8_t *src, uint64_t len,
 *                                uint8_t *dst, uint64_t cap, uint64_t *out_len);
 *
 * Codecs: ascii, latin1, latin2, cp1250, cp1251, cp1252, cp1256, koi8r,
 *         gb2312, gbk, gb18030, big5, shiftjis, euc_jp, euc_kr,
 *         iso2022, utf7, utf16le, utf16be, utf32le, utf32be
 */

/* ---- Newly implemented functions ---- */
int64_t str_replace(const StrSlice *src, const StrSlice *target, const StrSlice *repl, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_replace_all(const StrSlice *src, const StrSlice *target, const StrSlice *repl, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_replace_n(const StrSlice *src, const StrSlice *target, const StrSlice *repl, uint64_t n, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_join(const StrSlice *parts, uint64_t count, const StrSlice *delim, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_lines_next(const StrSlice *src, uint64_t *offset, StrSlice *out_line);
int64_t str_lines_count(const StrSlice *src, uint64_t *out_count);
int64_t str_nth_line(const StrSlice *src, uint64_t n, StrSlice *out_line);
int64_t str_squeeze_whitespace(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_squeeze_char(const StrSlice *src, uint8_t ch, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_insert_at(const StrSlice *src, uint64_t offset, const StrSlice *val, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_remove_range(const StrSlice *src, uint64_t offset, uint64_t len, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_remove_char(const StrSlice *src, uint8_t ch, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_remove_chars(const StrSlice *src, const StrSlice *chars, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_partition(const StrSlice *src, const StrSlice *sep, StrSlice *left, StrSlice *middle, StrSlice *right);
int64_t str_rpartition(const StrSlice *src, const StrSlice *sep, StrSlice *left, StrSlice *middle, StrSlice *right);
int64_t str_strip_prefix(const StrSlice *src, const StrSlice *prefix, StrSlice *out);
int64_t str_strip_suffix(const StrSlice *src, const StrSlice *suffix, StrSlice *out);
int64_t str_common_prefix_len(const StrSlice *a, const StrSlice *b, uint64_t *out_len);
int64_t str_common_suffix_len(const StrSlice *a, const StrSlice *b, uint64_t *out_len);
int64_t str_translate(const StrSlice *src, const StrSlice *from, const StrSlice *to, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_delete_chars(const StrSlice *src, const StrSlice *chars, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_expandtabs(const StrSlice *src, uint64_t tab_size, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_chomp(const StrSlice *src, StrSlice *out);
int64_t str_chop(const StrSlice *src, StrSlice *out);
int64_t str_count_lines(const StrSlice *src, uint64_t *out_count);
int64_t str_rfind(const StrSlice *src, const StrSlice *sub, uint64_t *out_offset);
int64_t str_rcontains(const StrSlice *src, const StrSlice *sub);
int64_t str_last_index_of(const StrSlice *src, uint8_t ch, uint64_t *out_offset);
int64_t str_find_any_of(const StrSlice *src, const StrSlice *chars, uint64_t *out_offset);
int64_t str_find_none_of(const StrSlice *src, const StrSlice *chars, uint64_t *out_offset);
int64_t str_bmh_replace_all(const StrSlice *src, const StrSlice *target, const StrSlice *repl, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_is_all_ascii(const StrSlice *src);
int64_t str_is_all_upper(const StrSlice *src);
int64_t str_is_all_lower(const StrSlice *src);
int64_t str_is_all_digits(const StrSlice *src);
int64_t str_is_all_space(const StrSlice *src);
int64_t str_is_identifier(const StrSlice *src);
int64_t str_is_printable_str(const StrSlice *src);
int64_t str_is_palindrome(const StrSlice *src);
int64_t str_to_title_case(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_capitalize(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_swap_case(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_rot13(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_caesar(const StrSlice *src, int64_t shift, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_slugify(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_to_snake_case(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_to_kebab_case(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_to_camel_case(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_to_pascal_case(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_indent(const StrSlice *src, uint64_t spaces, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_dedent(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_word_wrap(const StrSlice *src, uint64_t width, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_format_thousands(int64_t val, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_format_ordinal(uint64_t val, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_format_bytesize(uint64_t val, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_format_duration(uint64_t seconds, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_format_relative_time(int64_t seconds_diff, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_regex_replace(const StrSlice *src, const StrSlice *pattern, const StrSlice *replacement, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_uri_encode(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_uri_decode(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
uint64_t str_ngram_count(const StrSlice *src, uint64_t n);
int64_t str_ngram_extract(const StrSlice *src, uint64_t n, StrSlice *out_grams, uint64_t max_count, uint64_t *out_count);
int64_t str_jaccard_similarity(const StrSlice *a, const StrSlice *b, uint64_t n, double *out_sim);
int64_t str_metaphone(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);

int64_t str_strip_bom(const StrSlice *src, StrSlice *out);
int64_t str_center(const StrSlice *src, uint64_t width, uint8_t fill_char, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_zfill(const StrSlice *src, uint64_t width, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_truncate_ellipsis(const StrSlice *src, uint64_t max_graphemes, const StrSlice *ellipsis, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_display_truncate(const StrSlice *src, uint64_t max_columns, uint64_t *out_byte_len);
int64_t str_normalize_whitespace(const StrSlice *src, uint8_t *dst, uint64_t cap, uint64_t *out_len);
int64_t str_levenshtein_ratio(const StrSlice *a, const StrSlice *b, double *out_ratio);
int64_t str_dice_coefficient(const StrSlice *a, const StrSlice *b, double *out_coeff);
int64_t str_collation_key(const StrSlice *src, uint8_t *dst, uint64_t dst_cap, uint64_t *out_len);

#ifdef __cplusplus
}
#endif

#endif /* TATTVA_STR_H */