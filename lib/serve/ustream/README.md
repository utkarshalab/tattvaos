# serve/ustream — Streaming Response Layer

> Unified streaming abstraction: SSE, Chunked Transfer, WebSocket, gRPC streaming for Tattva OS.

## Responsibility

- **Frame encoding** — SSE (`text/event-stream`), HTTP Chunked, WebSocket frames, gRPC streaming
- **Backpressure** — Producer/consumer flow control, buffer limits, pause/resume
- **Client disconnect detection** — Early cancellation propagation
- **Stream lifecycle** — Open, data, error, close, reconnect hints
- **Multiplexing** — Multiple logical streams over single connection (HTTP/2, HTTP/3)

## Non-Responsibility

- **Protocol framing** → `uhttp`/`ugrpc`/`uws` (transport)
- **Request routing** → `ugate` + `userve`
- **Domain logic** → domain adapters (produce stream content)
- **Authentication** → `uauth`

## Stream Types

| Type | Protocol | Use Case |
|------|----------|----------|
| `SseStream` | HTTP/1.1, HTTP/2 | Token-by-token AI, server events, notifications |
| `ChunkedStream` | HTTP/1.1 | Large file download, progressive HTML, compatibility |
| `WebSocketStream` | WebSocket (ws/wss) | Bidirectional, real-time apps, browser terminals |
| `GrpcStream` | gRPC (h2) | Unary/Server/Client/Bidi streaming RPCs |
| `Http3Stream` | HTTP/3 (QUIC) | Low-latency, multiplexed, 0-RTT |

## Unified Stream Interface

```rust
pub enum StreamItem {
    Data(Bytes),           // Payload chunk
    Event(String, Bytes),  // SSE: event type + data
    Message(WebSocketMessage), // WS: text/binary/ping/pong/close
    GrpcMessage(Bytes),    // gRPC: length-prefixed message
    Trailers(HeaderMap),   // gRPC/HTTP: trailing headers
}

pub trait ResponseStream: Send {
    fn poll_next(&mut self, cx: &mut Context) -> Poll<Option<Result<StreamItem, StreamError>>>;
    fn size_hint(&self) -> (usize, Option<usize>);
    fn is_streaming(&self) -> bool;  // true = streaming, false = single response
}

pub struct StreamConfig {
    pub max_buffer_bytes: usize,        // default: 1MB
    pub high_water_mark: usize,         // pause producer
    pub low_water_mark: usize,          // resume producer
    pub client_timeout: Duration,       // default: 30s idle
    pub send_timeout: Duration,         // default: 5s per write
    pub enable_compression: bool,       // gzip/deflate for chunked
    pub sse_retry_ms: u64,              // default: 3000 (reconnect hint)
}
```

## Backpressure Model

```
Producer (Domain Adapter)          Consumer (Client)
         │                              │
         ▼                              │
┌─────────────────────┐                 │
│  Bounded Buffer     │◀────────────────┤
│  (max_buffer_bytes) │   WINDOW_UPDATE │
└─────────┬───────────┘                 │
          │                             │
    ┌─────┴─────┐                        │
    ▼           ▼                        │
 High Watermark  Low Watermark           │
 (pause)         (resume)                │
    │           │                        │
    └─────┬─────┘                        │
          │                              │
          ▼                              ▼
   Producer pauses              Client reads
```

- **Token bucket** per stream for rate smoothing
- **Credit-based** for HTTP/2, HTTP/3, gRPC (WINDOW_UPDATE)
- **Explicit pause/resume** for HTTP/1.1, WebSocket

## Client Disconnect Handling

```rust
pub enum DisconnectAction {
    CancelUpstream,      // Propagate cancellation to domain adapter (default)
    CompleteUpstream,    // Let domain finish, discard output
    BufferAndReconnect,  // Buffer for reconnect (requires stream ID)
}

pub struct DisconnectConfig {
    pub action: DisconnectAction,
    pub grace_period: Duration,    // Wait before action (default: 100ms)
    pub max_buffer_during_grace: usize, // default: 64KB
}
```

## SSE Specifics

```rust
pub struct SseEvent {
    pub id: Option<String>,           // Last-Event-ID for resume
    pub event: Option<String>,        // Event type (default: "message")
    pub data: Bytes,                  // Payload (multi-line supported)
    pub retry: Option<Duration>,      // Reconnect delay hint
}
```

- **Auto-reconnect**: Client sends `Last-Event-ID` on reconnect
- **Heartbeat**: Configurable `:keepalive` comments every N seconds
- **Compression**: Not standard; use HTTP/2 + chunked instead

## WebSocket Specifics

```rust
pub struct WsConfig {
    pub max_frame_size: usize,        // default: 16MB
    pub max_message_size: usize,      // default: 64MB
    pub ping_interval: Duration,      // default: 30s
    pub pong_timeout: Duration,       // default: 10s
    pub fragmentation: bool,          // Allow fragmented messages
    pub per_message_deflate: bool,    // RFC 7692 compression
}
```

- **Subprotocols**: Negotiate via `Sec-WebSocket-Protocol`
- **Extensions**: `permessage-deflate`, `x-webkit-deflate-frame`

## gRPC Streaming

```rust
// Unary: Request → Response
// Server Streaming: Request → Stream<Response>
// Client Streaming: Stream<Request> → Response
// Bidi Streaming: Stream<Request> → Stream<Response>

pub struct GrpcStreamConfig {
    pub max_concurrent_streams: u32,  // per connection
    pub max_message_size: usize,      // default: 4MB
    pub initial_window_size: u32,     // HTTP/2 flow control
}
```

## HTTP/3 (QUIC) Streams

- **Native multiplexing**: No head-of-line blocking
- **0-RTT**: Resume streams on reconnect
- **Unidirectional streams**: Server push, QPACK encoder/decoder
- **Datagram frames**: Unreliable, low-latency (WebRTC-style)

## Configuration

```toml
[streaming]
default_type = "sse"  # sse | chunked | websocket | grpc | auto
max_concurrent_streams = 10000
buffer_bytes = 1048576  # 1MB
high_water_mark = 8388608  # 8MB
low_water_mark = 1048576   # 1MB
client_idle_timeout = "30s"
send_timeout = "5s"

[streaming.sse]
retry_ms = 3000
heartbeat_interval = "15s"
heartbeat_comment = ":keepalive"

[streaming.websocket]
max_frame_size = "16MB"
max_message_size = "64MB"
ping_interval = "30s"
pong_timeout = "10s"
permessage_deflate = true

[streaming.grpc]
max_concurrent_streams = 100
max_message_size = "4MB"
initial_window_size = 65535

[streaming.http3]
max_uni_streams = 100
max_bidi_streams = 100
datagram_enabled = false

[streaming.disconnect]
action = "cancel_upstream"  # cancel_upstream | complete_upstream | buffer_and_reconnect
grace_period = "100ms"
max_buffer_during_grace = "64KB"
```

## Integration

- **Upstream**: `userve` (receives `ResponseStream` from domain adapter)
- **Downstream**: `uhttp` (HTTP/1.1, h2), `ugrpc` (gRPC), `uws` (WebSocket), `uhttp3` (HTTP/3)
- **Observability**: Emits `StreamEvent` (open, data, backpressure, close, error) for `uaudit`

## Status

🟡 **Design Phase** — Unified interface defined, per-protocol framing specified.