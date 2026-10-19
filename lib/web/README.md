# lib/web — Web Rendering Engine

> The web platform as a library: URL, fetch, HTML, DOM, CSS, layout, text, paint,
> JavaScript and Web APIs. Rendering ends here; browsers and other apps embed it.

Status: **planned, nothing written yet.** First consumer: [`apps/ubrowse`](../../apps/ubrowse/).
Plan and file list: [`apps/ubrowse/docs/PLAN.md`](../../apps/ubrowse/docs/PLAN.md)
(section 5.1) and [`apps/ubrowse/docs/STRUCTURE.md`](../../apps/ubrowse/docs/STRUCTURE.md)
(Part 1).

## Responsibility

- **Parse** — WHATWG URL, HTML tokenizer and tree builder, CSS, JavaScript
- **Fetch** — the fetch algorithm, cookies, HTTP cache, CORS, CSP, SRI, referrer policy, all partitioned
- **Style and layout** — cascade, block, inline, floats, tables, flex, grid
- **Text** — line breaking, bidi, shaping (Latin, Devanagari and other scripts)
- **Paint** — a display list, plus a backend that draws it into a Canvas surface
- **Script** — JS engine, DOM bindings, Web APIs
- **API gate** — the mechanism that turns APIs off or clamps them, driven by an embedder-supplied table

## Non-Responsibility

- **Sockets, TLS, Tor** → the embedder's network provider (`unet/http`, `unet/anon/tor`, `crypto/utls`)
- **Files and persistence** → the embedder's storage provider
- **Modes, security levels, blocking lists** → the embedder (for the browser, `apps/ubrowse`)
- **Window, tabs, URL bar, chrome** → the embedder
- **Serving web apps** → `lib/serve/uweb`

## Embedder boundary

The engine never opens a socket, touches a file, reads the real clock or draws chrome.
Each page gets providers from its embedder: network transport, storage, policy table,
clock, entropy and a display target. Nothing here includes anything from `apps/`.

## Uses

`lib/str` (Unicode, segmentation), `lib/ucmp` (gzip, deflate, brotli),
`lib/canvas` (surfaces, fonts, PNG/JPEG/GIF), `lib/regex`, `lib/umath`.
