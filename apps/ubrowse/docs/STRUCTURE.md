# ubrowse and lib/web: Complete Folder and File Structure

The browser is spread over three kinds of home, as set out in `PLAN.md` section 5.1:

| Home | What it is | Part |
|---|---|---|
| `lib/web/` | the rendering engine and web platform; **rendering ends here** | Part 1 |
| `apps/ubrowse/` | the browser product: shell, chrome, containers, Tor switch, egress, profile, updates | Part 2 |
| `crypto/`, `unet/`, `lib/*` | shared libraries that gain browser-driven additions | Part 3 |

Later releases (`B45` to `B90`) are listed at directory level in **Part 4**. Their
file-level lists are written when each release is planned in detail, because listing
thousands of files years ahead would be fiction.

**Boundary rules**

1. `lib/web` never opens a socket, touches a file, reads the real clock or draws chrome.
   It receives providers from its embedder (network, storage, policy, clock, entropy,
   display target) through `lib/web/inc/web.inc`.
2. `lib/web` holds **mechanisms**; `apps/ubrowse` holds **policy**. Example: the API
   gate lives in `lib/web/src/gate/`; the table saying what Tor Safer allows lives in
   `apps/ubrowse/data/security/levels.conf`.
3. Nothing in `lib/web` includes anything from `apps/ubrowse`.
4. Work homed in `crypto/` or `unet/` follows that library's layout and conventions.
   Where a file already exists there, the phase audits and extends it.

Shared headers such as `abi.inc`, `macros.inc`, `errors.inc` and `test.inc` come from
`lib/canvas/inc/` through the include path. They are not copied.

## Part 1: `lib/web/` file-level structure (R1 and core R2)

```
lib/web/
├── README.md                          # B0   scope, embedder boundary, build
├── Makefile                           # B0   targets: web, test, golden, fuzz, conformance, clean
│
├── inc/
│   ├── web.inc                        # B20  embedder API: engine, page, load, input, frame
│   ├── provider.inc                   # B15  network, storage, clock, entropy and policy provider tables
│   ├── origin.inc                     # B15  origin, site and partition key
│   ├── url.inc                        # B15
│   ├── request.inc                    # B18  request, response and policy structs
│   ├── bignum.inc                     # B1
│   ├── dom.inc                        # B20
│   ├── css.inc                        # B21
│   ├── style.inc                      # B21
│   ├── box.inc                        # B22
│   ├── text.inc                       # B25
│   ├── displaylist.inc                # B24  paint output handed to the embedder
│   ├── js_value.inc                   # B30
│   ├── js_object.inc                  # B30
│   ├── js_bytecode.inc                # B29
│   └── gate.inc                       # B34  API-gate table layout (values come from the embedder)
│
├── data/
│   └── psl.dat                        # B15  public suffix list (site and partition keys)
│
├── src/
│   ├── embed/                         # the only entry points an embedder calls
│   │   ├── engine.asm                 # B20  engine init and shutdown
│   │   ├── page.asm                   # B20  page create, load, navigate, destroy
│   │   ├── providers.asm              # B15  provider validation and dispatch
│   │   ├── input.asm                  # B27  input events from the embedder into the page
│   │   └── frame.asm                  # B24  produce a frame (display list) on request
│   │
│   ├── base/
│   │   ├── float.asm                  # B1   decimal parse and format
│   │   ├── sort.asm                   # B1   stable sort
│   │   ├── utf16.asm                  # B1
│   │   └── bignum.asm                 # B1   big-integer helpers (JS BigInt, number formatting)
│   │
│   ├── url/
│   │   ├── url.asm                    # B15  URL standard record and serialization
│   │   ├── url_parse.asm              # B15
│   │   ├── idna.asm                   # B15  uses lib/str
│   │   ├── psl.asm                    # B15  site key from the public suffix list
│   │   ├── origin.asm                 # B15
│   │   └── partition.asm              # B15  partition keys
│   │
│   ├── fetch/                         # the fetch algorithm; transport comes from the embedder
│   │   ├── fetch.asm                  # B15  main fetch, request modes and destinations
│   │   ├── loader.asm                 # B15  resource loader and priorities
│   │   ├── headers.asm                # B15
│   │   ├── redirect.asm               # B15
│   │   ├── content_decode.asm         # B15  gzip, deflate, brotli via lib/ucmp
│   │   ├── mime_sniff.asm             # B15
│   │   ├── cookie.asm                 # B15  cookie parsing and rules
│   │   ├── cookie_jar.asm             # B15  partitioned, backed by the storage provider
│   │   ├── cache.asm                  # B15  HTTP cache semantics, partitioned
│   │   ├── mixed_content.asm          # B18
│   │   ├── csp.asm                    # B18
│   │   ├── cors.asm                   # B18
│   │   ├── referrer.asm               # B18
│   │   ├── sandbox_flags.asm          # B18  iframe sandbox flags
│   │   ├── sri.asm                    # B18
│   │   └── policy_hooks.asm           # B18  calls the embedder's per-request policy (filters, local-net block)
│   │
│   ├── html/
│   │   ├── tok.asm                    # B20
│   │   ├── tok_states.asm             # B20
│   │   ├── entities.asm               # B20
│   │   ├── entities_data.asm          # B20
│   │   ├── tags.asm                   # B20
│   │   ├── tree.asm                   # B20
│   │   ├── insertion_modes.asm        # B20
│   │   ├── attrs.asm                  # B20
│   │   ├── dom.asm                    # B20
│   │   ├── dom_query.asm              # B20
│   │   └── serialize.asm              # B20
│   │
│   ├── css/
│   │   ├── tok.asm                    # B21
│   │   ├── parse.asm                  # B21
│   │   ├── properties.asm             # B21
│   │   ├── values.asm                 # B21
│   │   ├── units.asm                  # B21
│   │   ├── colors.asm                 # B21
│   │   ├── color_names.asm            # B21
│   │   ├── shorthand.asm              # B21
│   │   ├── selector_parse.asm         # B21
│   │   ├── select_match.asm           # B21
│   │   ├── specificity.asm            # B21
│   │   ├── cascade.asm                # B21
│   │   ├── ua.css                     # B21  default stylesheet source
│   │   ├── ua_sheet.asm               # B21
│   │   ├── inherit.asm                # B21
│   │   ├── computed.asm               # B21
│   │   ├── vars.asm                   # B21
│   │   └── media.asm                  # B21
│   │
│   ├── layout/
│   │   ├── boxgen.asm                 # B22
│   │   ├── box.asm                    # B22
│   │   ├── block.asm                  # B22
│   │   ├── margin.asm                 # B22
│   │   ├── overflow.asm               # B22
│   │   ├── inline.asm                 # B22
│   │   ├── linebox.asm                # B22
│   │   ├── float.asm                  # B22
│   │   ├── position.asm               # B22
│   │   ├── list.asm                   # B22
│   │   ├── table.asm                  # B22
│   │   ├── replaced.asm               # B22
│   │   ├── flex.asm                   # B23
│   │   ├── grid.asm                   # B23
│   │   └── grid_track.asm             # B23
│   │
│   ├── text/
│   │   ├── linebreak.asm              # B25
│   │   ├── bidi.asm                   # B25
│   │   ├── segmenter.asm              # B25  uses lib/str segmentation
│   │   ├── font_select.asm            # B25  from the font set the embedder allows
│   │   ├── font_fallback.asm          # B25
│   │   ├── shaper.asm                 # B25
│   │   ├── shape_latin.asm            # B25
│   │   ├── shape_indic.asm            # B25  Devanagari and other Indic scripts
│   │   ├── gsub.asm                   # B25
│   │   └── gpos.asm                   # B25
│   │
│   ├── paint/
│   │   ├── paint.asm                  # B24
│   │   ├── displaylist.asm            # B24  display list builder
│   │   ├── stacking.asm               # B24
│   │   ├── background.asm             # B24
│   │   ├── border.asm                 # B24
│   │   ├── text_paint.asm             # B24
│   │   ├── image_paint.asm            # B24
│   │   ├── scroll.asm                 # B24
│   │   ├── hittest.asm                # B24
│   │   ├── selection.asm              # B24
│   │   ├── hidpi.asm                  # B24
│   │   └── canvas_backend.asm         # B24  display list to a Canvas surface
│   │
│   ├── img/                           # glue and extra decoders (PNG, JPEG, GIF come from lib/canvas)
│   │   ├── decode_glue.asm            # B26
│   │   ├── webp.asm                   # B26
│   │   ├── webp_vp8.asm               # B26  lossy
│   │   ├── webp_vp8l.asm              # B26  lossless
│   │   └── anim.asm                   # B26  animation control
│   │
│   ├── forms/
│   │   ├── controls.asm               # B27
│   │   ├── form_submit.asm            # B27
│   │   ├── textedit.asm               # B27
│   │   ├── ime.asm                    # B27  Canvas text-input glue
│   │   ├── a11y_tree.asm              # B27  accessibility tree for Canvas
│   │   └── focus_nav.asm              # B27
│   │
│   ├── gate/                          # mechanisms only; the embedder supplies the table
│   │   ├── api_gate.asm               # B34  which APIs exist for this page
│   │   ├── canvas_guard.asm           # B34  canvas readback gating or noise
│   │   ├── timer_clamp.asm            # B34  clock resolution from the policy table
│   │   ├── navigator_const.asm        # B34  fixed navigator values from the policy table
│   │   └── screen_bucket.asm          # B34  reported screen and window size buckets
│   │
│   └── js/
│       ├── lex.asm                    # B28
│       ├── ast.asm                    # B28
│       ├── parse.asm                  # B28
│       ├── parse_expr.asm             # B28
│       ├── parse_stmt.asm             # B28
│       ├── parse_module.asm           # B28
│       ├── scope.asm                  # B28
│       ├── bytecode.asm               # B29
│       ├── compile.asm                # B29
│       ├── compile_async.asm          # B29
│       ├── vm.asm                     # B29
│       ├── ops.asm                    # B29
│       ├── exception.asm              # B29
│       ├── closure.asm                # B29
│       ├── value.asm                  # B30
│       ├── string.asm                 # B30
│       ├── atoms.asm                  # B30
│       ├── shape.asm                  # B30
│       ├── object.asm                 # B30
│       ├── array.asm                  # B30
│       ├── function.asm               # B30
│       ├── gc.asm                     # B30
│       ├── gc_mark.asm                # B30
│       ├── gc_sweep.asm               # B30
│       ├── eventloop.asm              # B32
│       ├── microtask.asm              # B32
│       ├── timers.asm                 # B32
│       ├── builtins/
│       │   ├── global.asm             # B31
│       │   ├── object.asm             # B31
│       │   ├── function.asm           # B31
│       │   ├── array.asm              # B31
│       │   ├── string.asm             # B31
│       │   ├── number.asm             # B31
│       │   ├── boolean.asm            # B31
│       │   ├── symbol.asm             # B31
│       │   ├── map_set.asm            # B31
│       │   ├── weak.asm               # B31
│       │   ├── promise.asm            # B31
│       │   ├── proxy_reflect.asm      # B31
│       │   ├── iterator.asm           # B31
│       │   ├── generator.asm          # B31
│       │   ├── regexp.asm             # B31
│       │   ├── regexp_compile.asm     # B31
│       │   ├── regexp_exec.asm        # B31
│       │   ├── date.asm               # B31  UTC only
│       │   ├── json.asm               # B31
│       │   ├── math.asm               # B31
│       │   ├── bigint.asm             # B31
│       │   ├── typed_array.asm        # B31
│       │   ├── arraybuffer.asm        # B31
│       │   ├── intl.asm               # B31  fixed locale
│       │   └── error.asm              # B31
│       └── dom/
│           ├── window.asm             # B33
│           ├── document.asm           # B33
│           ├── node.asm               # B33
│           ├── element.asm            # B33
│           ├── query.asm              # B33
│           ├── style_decl.asm         # B33
│           ├── classlist.asm          # B33
│           ├── event.asm              # B33
│           ├── fetch.asm              # B33
│           ├── xhr.asm                # B33
│           ├── storage.asm            # B33  partitioned storage API over the storage provider
│           ├── history.asm            # B33
│           ├── location.asm           # B33
│           ├── url.asm                # B33
│           ├── textcodec.asm          # B33
│           ├── crypto_random.asm      # B33  over the entropy provider
│           └── console.asm            # B33
│
├── tests/                             # run on Tattva, report over serial
│   ├── run_tests.sh                   # B2
│   ├── run_golden.sh                  # B2   display-list and frame goldens
│   ├── run_fuzz.sh                    # B41
│   ├── run_conformance.sh             # B42
│   ├── mock/
│   │   ├── mock_net.asm               # B2   scripted network provider
│   │   ├── mock_storage.asm           # B2
│   │   └── mock_policy.asm            # B2   policy tables for each mode and level
│   ├── unit/
│   │   ├── test_float.asm             # B1
│   │   ├── test_bignum.asm            # B1
│   │   ├── test_url.asm               # B15
│   │   ├── test_psl.asm               # B15
│   │   ├── test_fetch.asm             # B15
│   │   ├── test_cookie_jar.asm        # B15
│   │   ├── test_cache_partition.asm   # B15
│   │   ├── test_csp.asm               # B18
│   │   ├── test_cors.asm              # B18
│   │   ├── test_html_tok.asm          # B20
│   │   ├── test_html_tree.asm         # B20
│   │   ├── test_css_parse.asm         # B21
│   │   ├── test_selectors.asm         # B21
│   │   ├── test_cascade.asm           # B21
│   │   ├── test_block.asm             # B22
│   │   ├── test_inline.asm            # B22
│   │   ├── test_table.asm             # B22
│   │   ├── test_flex.asm              # B23
│   │   ├── test_grid.asm              # B23
│   │   ├── test_displaylist.asm       # B24
│   │   ├── test_bidi.asm              # B25
│   │   ├── test_shape_indic.asm       # B25
│   │   ├── test_webp.asm              # B26
│   │   ├── test_js_lex.asm            # B28
│   │   ├── test_js_parse.asm          # B28
│   │   ├── test_js_vm.asm             # B29
│   │   ├── test_js_gc.asm             # B30
│   │   ├── test_js_regexp.asm         # B31
│   │   ├── test_js_promise.asm        # B32
│   │   ├── test_js_dom.asm            # B33
│   │   ├── test_api_gate.asm          # B34
│   │   ├── test_timer_clamp.asm       # B34
│   │   └── test_no_egress.asm         # B15  engine makes no call outside its providers
│   ├── golden/
│   │   ├── pages/                     # hello, headings, lists, links, styled, box_model, inline_wrap,
│   │   │                              #   table, flex, grid, images, forms, devanagari, broken_markup
│   │   └── expected/                  # display-list dumps, checksums and reference frames
│   ├── fuzz/
│   │   ├── fuzz_html.asm              # B41
│   │   ├── fuzz_css.asm               # B41
│   │   ├── fuzz_js.asm                # B41
│   │   ├── fuzz_url.asm               # B41
│   │   ├── fuzz_mime.asm              # B41
│   │   ├── fuzz_webp.asm              # B41
│   │   └── corpus/                    # seed inputs per target
│   └── conformance/                   # B42  public test cases run as data
│       ├── html/
│       ├── css/
│       └── js/
│
├── tools/
│   ├── gen_entities.sh                # B20  HTML entity table to assembly data
│   ├── gen_properties.sh              # B21  CSS property table to assembly data
│   └── update_psl.sh                  # B15  refresh public suffix list
│
└── docs/
    ├── architecture.md                # B0   engine pipeline: fetch, parse, style, layout, paint, script
    ├── embedding.md                   # B20  embedder API, providers, display list contract
    ├── fetch.md                       # B15  fetch, cookies, cache, partitioning
    ├── engine-support.md              # B22  supported HTML, CSS and layout
    ├── js-support.md                  # B33
    ├── api-gate.md                    # B34  gate mechanism and policy table format
    ├── testing.md                     # B2
    ├── conformance.md                 # B42
    └── decisions/
        ├── 0001-rendering-ends-at-lib-web.md
        ├── 0002-no-sockets-in-the-engine.md
        ├── 0003-display-list-output.md
        ├── 0004-partition-keys.md
        └── 0005-mechanism-here-policy-in-embedder.md
```

## Part 2: `apps/ubrowse/` file-level structure (R1 and core R2)

Follows the app layout used across `apps/`: `manifest.json` and `conf/` at the root.
At runtime the app installs to `/app/ubrowse/`, keeps state in `/data/ubrowse/` and
per-user settings in `/user/<name>/app/ubrowse/`.

```
apps/ubrowse/
├── README.md                          # B0   overview, build, safety statement
├── manifest.json                      # B0   name, version, capabilities (net only through the egress gate)
├── CHANGELOG.md                       # B0
├── SECURITY.md                        # B0   vulnerability reporting, supported versions
├── CONTRIBUTING.md                    # B0   style, tests, review rules
├── Makefile                           # B0   targets: ubrowse, tools, test, leak, fingerprint, soak, bench, clean
│
├── conf/
│   └── default.conf                   # B35  default mode, Tor off, level, search provider, start page
│
├── inc/
│   ├── tv.inc                         # B0   Tattva service bindings
│   ├── egress.inc                     # B15  egress gate interface
│   ├── vault.inc                      # B19
│   ├── levels.inc                     # B34  mode and security level constants
│   ├── container.inc                  # B91  container record and flags
│   ├── blend.inc                      # B39
│   └── ui.inc                         # B36
│
├── data/
│   ├── containers/
│   │   └── defaults.conf              # B91  Personal, Work, Banking, Shopping: names, colours, icons
│   ├── tor/
│   │   ├── authorities.txt            # B9   directory authority list (read by unet/anon/tor)
│   │   ├── fallbacks.txt              # B9   fallback directory list
│   │   └── bridges_default.txt        # B13  built-in bridge lines
│   ├── tls/
│   │   ├── roots.bin                  # B17  root certificate store
│   │   └── hsts_preload.bin           # B17
│   ├── filters/
│   │   ├── default.filters            # B18  blocking rules
│   │   └── trackers.filters           # B18
│   ├── blend/
│   │   └── profile.conf               # B39  header order, TLS hello, HTTP/2 settings, window buckets
│   ├── security/
│   │   └── levels.conf                # B34  policy tables for Normal, Private, Tor Safest/Safer/Standard
│   ├── search/
│   │   └── providers.conf             # B37  search providers (including onion options)
│   └── update/
│       └── signers.pub                # B38  update signer public keys
│
├── src/
│   ├── main.asm                       # B35  browser entry point
│   │
│   ├── tattva/                        # thin binding to Tattva services
│   │   ├── tv_log.asm                 # B0
│   │   ├── tv_time.asm                # B0
│   │   ├── tv_entropy.asm             # B0
│   │   ├── tv_task.asm                # B0
│   │   └── tv_fs.asm                  # B0   durable writes for the vault
│   │
│   ├── net/                           # the browser side of the network
│   │   ├── egress.asm                 # B15  THE single egress gate; implements lib/web's network provider
│   │   ├── direct.asm                 # B15  direct mode over unet/http and unet/dns
│   │   ├── tor_switch.asm             # B36  Tor on/off per window and per container; lazy start of unet/anon/tor
│   │   ├── tor_route.asm              # B15  Tor traffic over unet/anon/tor, isolation key = partition key; fails closed
│   │   ├── tls_profile.asm            # B17  drives crypto/utls hooks
│   │   ├── client_hello.asm           # B17
│   │   ├── cert_validate.asm          # B17  root store and name checks over crypto/ux509
│   │   ├── roots.asm                  # B17
│   │   ├── hsts.asm                   # B17
│   │   ├── https_only.asm             # B17
│   │   ├── filters.asm                # B18  request filter engine (lib/web policy hook)
│   │   ├── filter_parse.asm           # B18
│   │   ├── local_net.asm              # B18  blocks loopback, private and link-local targets
│   │   ├── no_speculation.asm         # B18  no prefetch, preconnect or hints
│   │   └── permissions.asm            # B18
│   │
│   ├── storage/
│   │   ├── state.asm                  # B19  partitioned state manager; implements lib/web's storage provider
│   │   ├── partition_store.asm        # B19
│   │   ├── vault.asm                  # B19  encrypted persistent profile
│   │   ├── vault_crypto.asm           # B19
│   │   ├── vault_format.asm           # B19
│   │   ├── zeroize.asm                # B19  memory wiping
│   │   ├── session_wipe.asm           # B19
│   │   ├── persist_tor.asm            # B19  encrypted Tor state
│   │   ├── bookmarks.asm              # B35
│   │   └── passwords.asm              # B35  local password store
│   │
│   ├── containers/                    # native multi-account containers
│   │   ├── container.asm              # B91  create, edit, delete; name, colour, icon
│   │   ├── container_store.asm        # B91  persisted in the vault; in memory for Private windows
│   │   ├── assign.asm                 # B91  "always open this site in" rules and the switch prompt
│   │   ├── temporary.asm              # B91  throwaway container per tab, wiped on close
│   │   ├── open_in.asm                # B91  new tab, reopen and open link in a container
│   │   ├── clear.asm                  # B91  clear one container's data
│   │   ├── tor_routing.asm            # B91  per-container Tor routing flag, switch-and-clear
│   │   └── restore.asm                # B91  container-aware session restore
│   │
│   ├── policy/
│   │   ├── levels.asm                 # B34  loads levels.conf into lib/web policy tables
│   │   └── modes.asm                  # B34  Normal, Private and Tor windows; the Tor switch
│   │
│   ├── core/                          # browser core
│   │   ├── tab.asm                    # B35
│   │   ├── tab_task.asm               # B35  one task and one lib/web page per site partition
│   │   ├── site_partition.asm         # B35
│   │   ├── navigation.asm             # B35
│   │   ├── history.asm                # B35  session-only history
│   │   ├── session.asm                # B35
│   │   ├── permissions_ui.asm         # B35
│   │   ├── downloads.asm              # B35
│   │   ├── find.asm                   # B35
│   │   ├── reader.asm                 # B35  reader and text-only modes
│   │   ├── error_pages.asm            # B35
│   │   ├── settings.asm               # B35
│   │   ├── newidentity.asm            # B35
│   │   ├── panic.asm                  # B35  wipe everything and restart identity
│   │   └── canvas_glue.asm            # B35  window, compositing page frames under the chrome
│   │
│   ├── ui/
│   │   ├── chrome.asm                 # B36
│   │   ├── tabstrip.asm               # B36  container colours on tabs
│   │   ├── container_menu.asm         # B91  open-in, reopen-in, manage containers
│   │   ├── container_label.asm        # B91  container label in the URL bar
│   │   ├── tor_toggle.asm             # B36  Tor switch, New Tor window, "IP privacy only" notice
│   │   ├── urlbar.asm                 # B36
│   │   ├── indicators.asm             # B36  HTTPS, onion and security-level indicators
│   │   ├── privacy_panel.asm          # B36
│   │   ├── circuit_view.asm           # B36
│   │   ├── request_list.asm           # B36
│   │   ├── security_level_ui.asm      # B36
│   │   ├── settings_ui.asm            # B36
│   │   ├── dialogs.asm                # B36
│   │   ├── theme.asm                  # B36
│   │   ├── startpage.asm              # B37
│   │   ├── search.asm                 # B37
│   │   └── providers.asm              # B37
│   │
│   ├── blend/                         # blending with the target crowd
│   │   ├── profile.asm                # B39
│   │   ├── headers_profile.asm        # B39
│   │   ├── tls_hello_profile.asm      # B39
│   │   ├── h2_profile.asm             # B39
│   │   ├── window_buckets.asm         # B39  letterboxing sizes
│   │   └── quirks.asm                 # B39  engine quirk matching
│   │
│   ├── update/
│   │   ├── manifest.asm               # B38
│   │   ├── threshold_sig.asm          # B38  multi-signer verification
│   │   ├── fetch_update.asm           # B38  over Tor
│   │   ├── apply_update.asm           # B38
│   │   └── repro_check.asm            # B38
│   │
│   └── tools/                         # command-line tools
│       ├── tor_info.asm               # B11
│       ├── circuit_dump.asm           # B11
│       ├── consensus_dump.asm         # B9
│       └── fp_report.asm              # B39  prints the fingerprint the browser presents
│
├── tests/                             # run on Tattva, report over serial
│   ├── run_tests.sh                   # B2
│   ├── run_fingerprint.sh             # B39
│   ├── run_leak.sh                    # B40
│   ├── run_soak.sh                    # B41
│   ├── run_bench.sh                   # B43
│   ├── unit/
│   │   ├── test_egress.asm            # B15
│   │   ├── test_hsts.asm              # B17
│   │   ├── test_cert_validate.asm     # B17
│   │   ├── test_filters.asm           # B18
│   │   ├── test_local_net.asm         # B18
│   │   ├── test_vault.asm             # B19
│   │   ├── test_zeroize.asm           # B19
│   │   ├── test_levels.asm            # B34
│   │   ├── test_containers.asm        # B91  isolation of every store, cache, connection and circuit
│   │   ├── test_assign.asm            # B91
│   │   ├── test_temporary.asm         # B91  nothing survives a closed temporary container
│   │   ├── test_tor_switch.asm        # B36  lazy start, fails closed, never mixed
│   │   ├── test_threshold_sig.asm     # B38
│   │   ├── test_blend_headers.asm     # B39
│   │   └── test_blend_hello.asm       # B39
│   ├── fingerprint/
│   │   ├── fp_headers.asm             # B39
│   │   ├── fp_tls_hello.asm           # B39
│   │   ├── fp_navigator.asm           # B39
│   │   ├── fp_timers.asm              # B39
│   │   ├── fp_window.asm              # B39
│   │   ├── fp_canvas.asm              # B39
│   │   ├── fp_fonts.asm               # B39
│   │   ├── fp_js_quirks.asm           # B39
│   │   └── vectors/                   # target values for each vector
│   ├── leak/
│   │   ├── leak_tor_off.asm           # B40  with Tor off, nothing touches the Tor network
│   │   ├── leak_tor_mode.asm          # B40  only Tor link traffic leaves for Tor windows
│   │   ├── leak_tor_container.asm     # B40  a Tor-routed container sends nothing direct, even while switching
│   │   ├── leak_container.asm         # B40  no state or connection crosses containers
│   │   ├── leak_dns.asm               # B40
│   │   ├── leak_referrer.asm          # B40
│   │   ├── leak_localnet.asm          # B40
│   │   ├── leak_speculative.asm       # B40
│   │   ├── leak_timing.asm            # B40
│   │   ├── leak_direct_mode.asm       # B40  direct mode shares nothing with Tor mode
│   │   └── leak_new_identity.asm      # B40  nothing survives New Identity
│   ├── fuzz/
│   │   ├── fuzz_filters.asm           # B41
│   │   └── corpus/
│   ├── soak/
│   │   ├── soak_circuit_churn.asm     # B41
│   │   ├── soak_tab_churn.asm         # B41
│   │   ├── soak_container_churn.asm   # B41  temporary containers created and wiped in a loop
│   │   ├── soak_tor_toggle.asm        # B41  Tor switched on and off repeatedly under load
│   │   └── soak_zeroization.asm       # B41
│   └── bench/
│       ├── bench_bootstrap.asm        # B43  Tor bootstrap time
│       ├── bench_pageload.asm         # B43
│       ├── bench_js.asm               # B43
│       ├── bench_memory.asm           # B43
│       └── results/                   # recorded results per hardware
│
├── res/
│   ├── fonts/
│   │   ├── default.ttf                # B25  default proportional font (choose an open-licence font)
│   │   ├── mono.ttf                   # B25
│   │   └── devanagari.ttf             # B25  Devanagari coverage (choose an open-licence font)
│   ├── startpage/
│   │   ├── start.html                 # B37
│   │   ├── about.html                 # B37
│   │   ├── error.html                 # B35
│   │   └── onion-error.html           # B35
│   ├── icons/                         # B36  UI icons
│   └── strings/
│       ├── en.txt                     # B36  UI strings
│       └── ne.txt                     # B36
│
├── tools/                             # build-host developer scripts
│   ├── count_lines.sh                 # B0   line counter across all homes, updates the phase table
│   ├── new_module.sh                  # B0   scaffold .asm, test and doc stub in the right home
│   ├── gen_data.sh                    # B9   pack data/ files into assembly data blobs
│   ├── update_authorities.sh          # B9   refresh authority and fallback lists
│   ├── update_roots.sh                # B17  refresh root store
│   ├── update_hsts.sh                 # B17  refresh HSTS preload
│   ├── update_filters.sh              # B18  refresh block lists
│   ├── repro_build.sh                 # B38  reproducible build and comparison
│   └── leak_report.sh                 # B40  summarize leak harness output
│
└── docs/
    ├── PLAN.md                        # B0   master plan and phase table
    ├── STRUCTURE.md                   # B0   this file
    ├── architecture.md                # B0   processes, homes, embedder boundary
    ├── tattva-contract.md             # B0   sockets, TLS hooks, clocks, filesystem, tasks
    ├── threat-model.md                # B0   who we defend against and what is out of scope
    ├── privacy-model.md               # B0   privacy rules from the plan, made testable
    ├── isolation-model.md             # B15  partition keys, tab tasks, software isolation limits
    ├── containers.md                  # B91  container model, what is separated and shared
    ├── tor-switch.md                  # B36  Tor windows vs container routing, guarantees of each
    ├── fingerprint-model.md           # B39
    ├── blend-profile.md               # B39
    ├── security-levels.md             # B34  policy tables per mode and level
    ├── tls-profile.md                 # B17
    ├── storage-vault.md               # B19
    ├── ui-guide.md                    # B36
    ├── update-and-repro.md            # B38
    ├── leak-testing.md                # B40
    ├── performance.md                 # B43
    ├── audit-package.md               # B44
    └── decisions/                     # one short record per design decision
        ├── 0001-no-libc.md
        ├── 0002-tor-in-process.md
        ├── 0003-single-egress-gate.md
        ├── 0004-engine-in-lib-web.md
        ├── 0005-amnesic-by-default.md
        ├── 0006-blend-target.md
        ├── 0007-no-jit.md
        ├── 0008-no-extensions.md
        ├── 0009-tls-hooks-or-own-tls.md
        ├── 0010-software-isolation.md
        ├── 0011-safer-as-default.md
        ├── 0012-reuse-tattva-crypto.md
        ├── 0019-containers-native.md
        ├── 0020-tor-off-by-default.md
        └── 0021-container-tor-routing-is-not-anonymity.md
```

## Part 3: additions to shared libraries (R1 and core R2)

These files are driven by the browser but belong to their library. Each library's own
tests, docs and conventions apply. **Audit first:** files marked *exists* are already
in the tree and get reviewed and extended, not rewritten.

### `crypto/`

```
crypto/
├── ucrypt/
│   ├── symmetric/aes_ctr.asm          # B3
│   ├── ct.asm                         # B5   constant-time helpers
│   └── elligator2.asm                 # B13  for obfs4
├── uhash/
│   ├── sha1.asm                       # B3   needed by Tor link and relay digests
│   ├── sha3/                          # B3   exists; add SHAKE
│   └── blake2/                        # B5   exists
├── ukdf/
│   ├── hkdf/                          # B3   exists
│   └── argon2/                        # B5   exists
├── usign/
│   ├── ed25519/ed25519_blind.asm      # B4   key blinding for onion services
│   ├── ed25519/                       # B4   exists
│   ├── ecdsa/                         # B4   exists; confirm P-256
│   ├── rsa/                           # B4   exists; confirm verify paths
│   └── bignum_ct.asm                  # B4   constant-time bignum
├── utls/                              # B6, B17  TLS 1.3 client with certificate and ClientHello hooks
│   ├── tls13_client.asm               #      (decision D1: build here if absent)
│   ├── tls13_keysched.asm
│   ├── tls13_records.asm
│   └── hooks.asm                      #      certificate-verify and ClientHello callbacks
└── ux509/                             # B17  exists; chain, name checks, ASN.1
```

Random numbers come from `lib/urand` (exists); B5 adds only what its audit finds missing.

### `unet/anon/tor/` (the Tor client)

`unet/anon/tor_cell.asm` and `unet/anon/obfs4.asm` already exist; B6 and B13 start by
folding them into this layout.

```
unet/anon/tor/
├── link.asm                           # B6   TLS link to a relay
├── link_certs.asm                     # B6   link certificate checks
├── versions.asm                       # B6   version negotiation
├── cell.asm                           # B6   cell codec (from tor_cell.asm)
├── circuit.asm                        # B7   circuit state machine
├── ntor.asm                           # B7   ntor handshake
├── extend.asm                         # B7   EXTEND2
├── relay_crypto.asm                   # B7   layered relay encryption and digests
├── destroy.asm                        # B7
├── stream.asm                         # B8
├── flow.asm                           # B8   window accounting
├── sendme.asm                         # B8   authenticated SENDME
├── resolve.asm                        # B8   DNS by exit
├── padding_conn.asm                   # B8   connection padding
├── dir_authorities.asm                # B9
├── dir_bootstrap.asm                  # B9
├── dir_fetch.asm                      # B9
├── consensus.asm                      # B9
├── consensus_verify.asm               # B9   authority signature checks
├── microdesc.asm                      # B9
├── dir_cache.asm                      # B9
├── time_check.asm                     # B9   time sanity from the consensus
├── guards.asm                         # B10
├── guard_state.asm                    # B10  persistent guard state
├── path.asm                           # B10  path selection
├── weights.asm                        # B10  bandwidth weighting
├── family.asm                         # B10  family and subnet rules
├── exit_policy.asm                    # B10
├── build_timeout.asm                  # B10
├── circuit_pool.asm                   # B10
├── isolation.asm                      # B10  per-key circuit isolation
├── tor.asm                            # B11  public tor_* API
├── tor.inc                            # B6   structs and public API
├── bootstrap.asm                      # B11
├── identity.asm                       # B11  New Identity
├── tor_status.asm                     # B11
├── onion_addr.asm                     # B12  .onion parsing and checksum
├── hs_blind.asm                       # B12  time-period key blinding
├── hs_ring.asm                        # B12  directory ring selection
├── hs_desc.asm                        # B12  descriptor parse
├── hs_decrypt.asm                     # B12  two-layer decryption
├── hs_intro.asm                       # B12  introduction points
├── hs_rend.asm                        # B12  rendezvous
├── hs_ntor.asm                        # B12
├── hs_auth.asm                        # B12  client authorization
├── hs_client.asm                      # B12  onion connection driver
├── bridges.asm                        # B13
├── bridge_line.asm                    # B13
├── pt_iface.asm                       # B13  pluggable transport interface (obfs4 from unet/anon)
├── pt_meek.asm                        # B14
├── pt_webtunnel.asm                   # B14
├── padding_circ.asm                   # B14  circuit padding
├── padding_machines.asm               # B14
├── congestion.asm                     # B14
├── conflux.asm                        # B14
├── vanguards.asm                      # B14
├── hs_pow.asm                         # B14  onion service proof-of-work client
├── testnet/                           # local Tor test network
│   ├── test_authority.asm             # B14
│   ├── test_relay.asm                 # B14
│   ├── test_exit.asm                  # B14
│   └── test_net.asm                   # B14
└── tests/                             # cell, link_certs, ntor, relay_crypto, circuit, stream_flow,
                                       #   sendme, consensus, consensus_verify, microdesc, guards, path,
                                       #   exit_policy, isolation, onion_addr, hs_blind, hs_desc, hs_ntor,
                                       #   obfs4, padding, congestion; fuzz: cells, consensus, hs_desc
```

### `unet/http/`, `unet/dns/`, `lib/ucmp/`

| File | Phase | State |
|---|---|---|
| `unet/http/http1.asm` (+ chunked) | B15 | exists; audit, add chunked and limits |
| `unet/http/http2.asm` with HPACK, streams, flow, settings | B16 | exists; audit, add settings control for the blend profile |
| `unet/http/http3.asm`, `qpack.asm`, QUIC, `webtransport.asm` | B58 | exists in part; audit, add QUIC |
| `unet/http/websocket.asm`, `sse.asm` | B45 | exists; audit |
| `unet/dns/` (DoH, DoT) | B15 | exists; direct mode only, never in Tor mode |
| `lib/ucmp/` brotli with static dictionary, gzip, deflate | B15 | add brotli if absent |

## Part 4: later releases, directory level (B45 to B90)

Every directory also gets `tests/unit/`, `tests/fuzz/` and `docs/` entries when it is
expanded.

### `lib/web/` (engine and platform)

```
lib/web/src/
├── webidl/                            # B45  WebIDL to bindings (runtime glue; generator in tools/)
├── streams/                           # B45  fetch streaming, streams API, WebSocket and SSE APIs over the network provider
├── workers/                           # B46  dedicated and shared workers, structured clone, message channels
├── idb/                               # B47  IndexedDB (b-tree, transactions, indexes, cursors) over the storage provider
├── cachestorage/                      # B47  Cache API
├── opfs/                              # B47  origin private file system
├── webcomp/                           # B48  custom elements, shadow DOM, templates, slots
├── css_modern/                        # B49  container queries, :has(), nesting, @layer, @scope, subgrid,
│                                      #      logical properties, color spaces, math functions
├── anim/                              # B50  transitions, animations, Web Animations, scroll-driven, view transitions
├── svg/                               # B51  full SVG engine
├── mathml/                            # B51  MathML layout
├── fonts/                             # B52  WOFF, WOFF2, variable fonts, color fonts, Arabic, Hebrew, Thai,
│                                      #      Khmer shaping, vertical text
├── intl/                              # B53  Intl.* on top of lib/str (collation, plural rules, formatters)
├── editing/                           # B54  contenteditable, ranges, selections, execCommand, clipboard, drag and drop
├── secplatform/                       # B55  Trusted Types, COOP/COEP/CORP, permissions policy, Fetch Metadata
├── print/                             # B56  paged media, print to PDF
├── forms_full/                        # B57  all input types, validation, pickers, autofill hooks
├── webtransport/                      # B58  WebTransport API over the network provider
├── a11y/                              # B59  full ARIA, accessibility tree, caret browsing
├── pwa/                               # B60  manifest parsing, offline shell
├── jit/                               # B63, B64
│   ├── baseline/                      #      template JIT, code cache, W^X manager, deopt hooks
│   └── optimizing/                    #      type feedback, IR, inlining, escape analysis, regalloc, codegen, deopt
├── gc2/                               # B65  generational, incremental and concurrent GC, compaction, off-thread work
├── layout_perf/                       # B66  incremental layout, parallel style, SIMD text measurement, layers
├── gpu_raster/                        # B67  tile rasterizer and compositor over Canvas GPU (C24)
├── snapshot/                          # B68  engine snapshots, lazy init
├── media/                             # B70, B71
│   ├── containers/                    #      MP4, WebM, Ogg
│   ├── audio_codecs/                  #      Opus, Vorbis, FLAC, MP3, AAC
│   ├── video_codecs/                  #      VP8, VP9, AV1, H.264
│   ├── output/                        #      A/V sync, rendering path
│   └── element/                       #      HTMLMediaElement, MSE, WebVTT, picture-in-picture, media session
├── webaudio/                          # B72  audio graph, worklets
├── wasm/                              # B73  validator, interpreter, baseline and optimizing compilers, threads
├── canvas2d/                          # B74  full Canvas 2D, OffscreenCanvas, image bitmaps, ImageDecoder
├── img_ext/                           # B74  AVIF, JPEG XL
├── webgl/                             # B75  WebGL 1 and 2, shader translator for the chosen GPU family
├── webgpu/                            # B76  WebGPU, WGSL compiler
├── sw/                                # B77  service workers, push, background sync, notifications
├── webrtc/                            # B78  peer connections, data channels, codecs (ICE transport from unet)
├── devices/                           # B79  WebAuthn, gamepad, USB, Bluetooth, Serial, HID, geolocation,
│                                      #      sensors, camera, microphone, screen capture (permission via embedder)
└── inspect/                           # B82  inspector backend: DOM, CSS, console, debugger, network, profilers

lib/web/tools/
├── webidlgen.asm                      # B45  WebIDL binding generator
└── specgen/                           # B45  CSS property, HTML parser and Unicode table generators

lib/web/tests/
├── wpt/                               # B42  Web Platform Tests subsets (data) and runner glue
├── test262/                           # B42  JavaScript conformance data and runner
└── perf/                              # B43  JS, layout and paint suites
```

### `apps/ubrowse/` (product)

```
apps/ubrowse/src/
├── proc/                              # B61  process model
│   ├── process, spawn, lifecycle, supervisor
│   ├── ipc (handles-only channels, shared memory, message codec)
│   └── sandbox (policy, capabilities, resource limits)
├── harden/                            # B62  CET setup, browser use of the lib/mem hardened allocator
├── memory/                            # B68  tab discarding, memory pressure
├── netperf/                           # B69  pooling, prioritization, preload scanner policy, cache tuning
├── pwa/                               # B60, B77  install and app windows
├── pdf/                               # B80  PDF viewer (candidate to become its own library later)
├── ext/                               # B81  extension host, API bindings, permissions, content scripts, signing
├── devtools/                          # B82  devtools front end and remote debugging protocol
├── profiles/                          # B84  tab groups, vertical tabs, split view, sleeping tabs,
│                                      #      encrypted session restore (containers are R1, B91)
├── sync/                              # B85  E2E-encrypted sync client and self-hostable server
├── passwords/                         # B86  password manager, passkeys, autofill, private breach check
├── enterprise/                        # B87  managed policy, audit logs, remote management, certificates, kiosk
├── update_scale/                      # B88  delta updates, staged rollout, rollback, supply-chain verification
└── l10n/                              # B89  UI languages, RTL UI, themes, import from other browsers

apps/ubrowse/tests/
├── corpus/                            # B42, B83  archived top-site pages and scripted flows
├── compat/                            # B83  quirks database, corpus harness, triage tooling
├── perf/                              # B43  page-load, startup and memory suites
├── security/                          # B61  sandbox escape tests, IPC fuzzing, JIT validation tests
└── scoreboard/                        # B43  generated dashboards per release

apps/ubrowse/tools/
├── corpus_capture.sh                  # B83  archive pages for the corpus
└── scoreboard.sh                      # B43  collect results from all homes and update the scoreboard

apps/ubrowse/docs/
├── scoreboard.md                      # B43  targets and measured results per release
├── process-model.md                   # B61
├── sandbox-policy.md                  # B61
├── jit-design.md                      # B63  (engine side lives in lib/web/docs)
├── gpu-pipeline.md                    # B67
├── media-pipeline.md                  # B70
├── extensions.md                      # B81
├── devtools.md                        # B82
├── compat-program.md                  # B83
├── sync-protocol.md                   # B85
├── enterprise-guide.md                # B87
└── decisions/
    ├── 0013-hardware-isolation-prerequisite.md
    ├── 0014-three-modes-one-engine.md
    ├── 0015-jit-policy-per-mode.md
    ├── 0016-codec-licensing.md
    ├── 0017-drm-scope.md
    └── 0018-generators-and-oracles.md
```

### Shared libraries

| Home | Phases | Adds |
|---|---|---|
| `unet/http/` | B58, B69 | QUIC, connection pooling and prioritization primitives |
| `unet/` | B78 | ICE, STUN, TURN transport for WebRTC (relay-only in Private, off in Tor) |
| `lib/mem/` | B62 | hardened allocator with guard pages and red-zone debug mode |
| `lib/canvas/` | B67, B75, B76 | GPU surfaces and planes the engine rasterizes into (Canvas C24, C25) |
