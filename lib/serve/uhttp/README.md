# serve/uhttp — HTTP Protocol Adapter

> HTTP/1.1, HTTP/2, HTTP/3 protocol handling for Utkarsha OS serving layer.

## Responsibility

- **HTTP/1.1** — Keep-alive, pipelining, chunked transfer, upgrade
- **HTTP/2** — Multiplexing, header compression (HPACK), server push, prioritization
- **HTTP/3 (QUIC)** — 0-RTT, connection migration, native multiplexing, QPACK
- **TLS termination** — SNI, ALPN (h2, h3), certificate management, OCSP stapling
- **Request/Response parsing** — Streaming, zero-copy where possible
- **WebSocket upgrade** — RFC 6455, permessage-deflate
- **Protocol detection** — ALPN, Upgrade header, Alt-Svc

## Non-Responsibility

- **Request routing** → `ugate` + `userve`
- **Authentication** → `uauth`
- **Firewall** → `niti`
- **Load balancing** → `ulb`
- **Audit logging** → `uaudit`
- **Streaming framing** → `ustream` (SSE, WebSocket frames)
- **Domain logic** → domain adapters

## Architecture

```
TCP/UDP Connection
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ uhttp Listener                                              │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │ TLS Acceptor│  │ ALPN/Upgrade│  │ Protocol    │         │
│  │ (rustls)    │──▶│ Dispatcher  │──▶│ Handler     │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│        │                │                │                   │
│        ▼                ▼                ▼                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Protocol Implementations                │   │
│  │  Http11 │ Http2 │ Http3 │ WebSocket │ Upgrade       │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## HTTP/1.1

```rust
pub struct Http11Config {
    pub max_request_size: usize,        // 32MB
    pub max_header_count: usize,        // 100
    pub max_header_size: usize,         // 8KB
    pub keep_alive_timeout: Duration,   // 75s
    pub keep_alive_max: usize,          // 100 requests
    pub pipeline_flush: bool,           // true
    pub h2c_upgrade: bool,              // Allow h2c via Upgrade
}
```

- **Pipelining**: Supported but responses in order
- **Chunked encoding**: Streaming request/response bodies
- **Expect: 100-continue**: Supported for large uploads

## HTTP/2

```rust
pub struct Http2Config {
    pub max_concurrent_streams: u32,    // 100
    pub initial_stream_window_size: u32, // 65535
    pub initial_connection_window_size: u32, // 65535
    pub max_frame_size: u32,            // 16384
    pub max_header_list_size: u32,      // 16KB
    pub enable_push: bool,              // false (server push)
    pub hpack_table_size: usize,        // 4096 (encoder/decoder)
}
```

- **Multiplexing**: Multiple streams per connection
- **HPACK**: Header compression with dynamic table
- **Flow control**: Stream + connection level windows
- **Priorities**: Stream dependency tree (RFC 7540)

## HTTP/3 (QUIC)

```rust
pub struct Http3Config {
    pub max_concurrent_streams: u32,    // 100 (bidirectional)
    pub max_uni_streams: u32,           // 100 (unidirectional)
    pub initial_stream_window_size: u64, // 1MB
    pub initial_connection_window_size: u64, // 10MB
    pub max_datagram_size: usize,       // 1350
    pub enable_datagrams: bool,         // false
    pub qpack_encoder_table_size: usize, // 4096
    pub qpack_decoder_table_size: usize, // 4096
    pub qpack_blocked_streams: u32,     // 100
    pub zero_rtt: bool,                 // true
    pub migration: bool,                // true (connection migration)
}
```

- **0-RTT**: Resume sessions with early data
- **Connection migration**: Survive IP change (CID-based)
- **QPACK**: Header compression (blocking-resistant)
- **Datagrams**: Unreliable delivery (WebRTC, gaming)

## TLS Configuration

```rust
pub struct TlsConfig {
    pub cert_file: PathBuf,
    pub key_file: PathBuf,
    pub ca_file: Option<PathBuf>,           // For mTLS
    pub alpn: Vec<String>,                  // ["h2", "http/1.1", "h3"]
    pub min_version: TlsVersion,            // TLS 1.2
    pub max_version: TlsVersion,            // TLS 1.3
    pub cipher_suites: Vec<CipherSuite>,    // TLS 1.3 only by default
    pub ocsp_stapling: bool,                // true
    pub session_resumption: bool,           // true (tickets)
    pub client_auth: ClientAuth,            // Require | VerifyIfGiven | No
}
```

- **Certificate management**: Hot reload, ACME integration (Let's Encrypt)
- **SNI**: Multiple certs per IP:port
- **mTLS**: Client cert verification with SPIFFE/SPIRE

## WebSocket

```rust
pub struct WsConfig {
    pub max_frame_size: usize,        // 16MB
    pub max_message_size: usize,      // 64MB
    pub ping_interval: Duration,      // 30s
    pub pong_timeout: Duration,       // 10s
    pub fragmentation: bool,          // true
    pub permessage_deflate: bool,     // true
    pub max_concurrent_messages: usize, // 100
}
```

- **Upgrade**: HTTP/1.1 `Upgrade: websocket`, HTTP/2 `CONNECT` + `:protocol=websocket`
- **Subprotocols**: Negotiation via `Sec-WebSocket-Protocol`
- **Extensions**: `permessage-deflate`, `x-webkit-deflate-frame`

## Request/Response Types

```rust
pub struct HttpRequest {
    pub method: Method,
    pub uri: Uri,
    pub version: Version,           // Http11 | Http2 | Http3
    pub headers: HeaderMap,
    pub body: RequestBody,          // Stream<Bytes> | Fixed(Bytes)
    pub trailers: Option<HeaderMap>, // HTTP/2, HTTP/3
    pub extensions: Extensions,     // Protocol-specific (stream_id, etc.)
}

pub struct HttpResponse {
    pub status: StatusCode,
    pub version: Version,
    pub headers: HeaderMap,
    pub body: ResponseBody,         // Stream<Bytes> | Fixed(Bytes)
    pub trailers: Option<HeaderMap>,
}
```

## Streaming Integration

```
uhttp (protocol)                    ustream (framing)
     │                                    │
     ▼                                    │
┌─────────────────┐                       │
│ Parse headers   │                       │
│ Determine body  │                       │
│   type          │                       │
└────────┬────────┘                       │
         │                                │
    ┌────┴────┐                            │
    ▼         ▼                            ▼
 Streaming   Non-streaming          SseStream | ChunkedStream | WsStream
    │         │                            │
    └────┬────┘                            │
         ▼                                  ▼
    ustream.encode() ─────────────────▶ Write to wire
```

## Configuration

```toml
[uhttp]
# Bind addresses
bind = [
  { addr = "0.0.0.0:80", proto = "http", redirect_https = true },
  { addr = "0.0.0.0:443", proto = "https", alpn = ["h2", "http/1.1"] },
  { addr = "0.0.0.0:443", proto = "http3", alpn = ["h3"] },
]

# TLS
tls = {
  cert_file = "/etc/utkarsha/certs/server.crt"
  key_file = "/etc/utkarsha/certs/server.key"
  ocsp_stapling = true
  session_resumption = true
}

# HTTP/1.1
http11 = {
  keep_alive_timeout = "75s"
  keep_alive_max = 100
  max_request_size = "32MB"
}

# HTTP/2
http2 = {
  max_concurrent_streams = 100
  initial_window_size = 65535
  enable_push = false
}

# HTTP/3
http3 = {
  max_concurrent_streams = 100
  max_uni_streams = 100
  zero_rtt = true
  migration = true
}

# WebSocket
websocket = {
  max_frame_size = "16MB"
  max_message_size = "64MB"
  ping_interval = "30s"
  permessage_deflate = true
}

# Limits (global)
limits = {
  max_header_count = 100
  max_header_size = "8KB"
  request_timeout = "30s"
  body_timeout = "60s"
}
```

## Integration

- **Upstream**: `niti` (firewall), `uauth` (auth), `uaudit` (audit) — middleware before uhttp
- **Downstream**: `userve` (core engine) — uhttp calls `Server::handle_connection`
- **External**: rustls (TLS), quinn (QUIC), h2 (HTTP/2)

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `uhttp_connections_total` | Counter | `protocol` (http11/h2/h3), `tls` |
| `uhttp_connections_active` | Gauge | `protocol` |
| `uhttp_requests_total` | Counter | `protocol`, `method`, `status` |
| `uhttp_request_duration_seconds` | Histogram | `protocol`, `method` |
| `uhttp_request_size_bytes` | Histogram | `protocol` |
| `uhttp_response_size_bytes` | Histogram | `protocol` |
| `uhttp_tls_handshake_duration_seconds` | Histogram | `resumed` (true/false) |
| `uhttp_http2_streams_active` | Gauge | |
| `uhttp_http3_streams_active` | Gauge | `type` (bidi/uni) |

## Status

🔴 **Planned** — Architecture defined, protocol implementations pending (rustls, quinn, h2).