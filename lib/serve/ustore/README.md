# serve/ustore — Object Storage Serving Adapter

> Domain adapter for S3-compatible object storage API: buckets, objects, multipart, presigned URLs, lifecycle.

## Responsibility

- **S3 API compatibility** — Core operations: bucket, object, multipart, ACL, policy
- **Presigned URLs** — Temporary credentials for direct client upload/download
- **Multipart upload** — Initiate, upload parts, complete, abort
- **Range requests** — Byte-range serving, resumable downloads
- **Lifecycle/Versioning** — Expiration, transitions, version management
- **Event notifications** — ObjectCreated, ObjectRemoved → `uevent`/`ukafka`

## Non-Responsibility

- **Authentication** → `uauth` (validates credentials, provides identity)
- **Firewall** → `niti`
- **Load balancing** → `ulb` (selects storage node)
- **Audit logging** → `uaudit`
- **Protocol framing** → `uhttp`
- **Data persistence** → `storage/` (the actual storage engine)

## Architecture

```
Request (ugate → userve)
         │
         ▼
┌─────────────────────────────────────────────────────────────┐
│ ustore Adapter                                               │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐       │
│  │ S3 Request   │  │ AuthZ        │  │ Storage      │       │
│  │ Parser       │──▶│ (bucket/obj  │──▶│ Router       │       │
│  │ (XML/JSON)   │   │  policies)   │   │ (shard →     │       │
│  └──────────────┘   └──────────────┘   │  node)       │       │
│         │                │             └──────────────┘       │
│         ▼                ▼                  │                  │
│  ┌─────────────────────────────────────────┴──────────────┐   │
│  │              Storage Backend Client                     │   │
│  │  (gRPC to storage/ engine)                              │   │
│  └─────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Supported S3 Operations

| Category | Operations |
|----------|------------|
| **Service** | `ListBuckets` |
| **Bucket** | `CreateBucket`, `DeleteBucket`, `HeadBucket`, `ListObjects`, `ListObjectsV2`, `GetBucketLocation`, `GetBucketVersioning`, `PutBucketVersioning`, `GetBucketLifecycle`, `PutBucketLifecycle`, `DeleteBucketLifecycle`, `GetBucketPolicy`, `PutBucketPolicy`, `DeleteBucketPolicy`, `GetBucketAcl`, `PutBucketAcl` |
| **Object** | `PutObject`, `GetObject`, `HeadObject`, `DeleteObject`, `DeleteObjects`, `CopyObject`, `GetObjectAcl`, `PutObjectAcl`, `GetObjectLegalHold`, `PutObjectLegalHold`, `GetObjectRetention`, `PutObjectRetention`, `GetObjectTagging`, `PutObjectTagging`, `DeleteObjectTagging`, `RestoreObject` |
| **Multipart** | `CreateMultipartUpload`, `UploadPart`, `UploadPartCopy`, `CompleteMultipartUpload`, `AbortMultipartUpload`, `ListMultipartUploads`, `ListParts` |
| **Presigned** | `PresignGetObject`, `PresignPutObject`, `PresignPostPolicy` |

## Request Flow (PutObject)

```
PUT /bucket/key
         │
         ▼
┌─────────────────────────────────────┐
│ Parse: bucket, key, headers         │
│   Content-Length, Content-Type      │
│   x-amz-storage-class, x-amz-acl    │
│   x-amz-meta-*, x-amz-tagging       │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│ AuthZ: Check bucket policy, ACL     │
│   Identity from uauth               │
│   Allow: s3:PutObject               │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│ Storage Router:                     │
│   shard = hash(bucket + key) % N    │
│   Select primary + replicas         │
└────────────────┬────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────┐
│ storage/engine: Write object        │
│   - Erasure coding / replication    │
│   - Metadata index update           │
│   - ETag = MD5 (or custom)          │
└────────────────┬────────────────────┘
                 │
                 ▼
         200 OK + ETag header
```

## Presigned URLs

```rust
pub struct PresignConfig {
    pub max_expiry: Duration,             // default: 7 days
    pub allowed_methods: Vec<Method>,     // GET, PUT, POST
    pub allowed_headers: Vec<String>,     // For POST policy
    pub enforce_content_length: bool,     // Require Content-Length
}
```

- **Signature V4**: AWS-compatible signing
- **POST Policy**: Form-based upload with conditions (bucket, key, content-length-range, etc.)

## Range Requests & Resumable

```
GET /bucket/key
Range: bytes=0-1023
         │
         ▼
  206 Partial Content
  Content-Range: bytes 0-1023/1048576
  Accept-Ranges: bytes
```

- **Multipart resume**: Client tracks uploaded parts via `ListParts`
- **Parallel downloads**: Multiple range requests for throughput

## Configuration

```toml
[ustore]
# S3 compatibility
api_version = "2006-03-01"
virtual_hosted_style = true
path_style = true

# Limits
max_bucket_name = 63
max_object_key = 1024
max_object_size = "5TB"
max_multipart_parts = 10000
max_part_size = "5GB"
min_part_size = "5MB"  # except last part

# Presigned URLs
presign = {
  max_expiry = "7d"
  default_expiry = "1h"
  enforce_content_length = true
}

# Multipart
multipart = {
  cleanup_aborted_after = "1d"
  cleanup_completed_after = "7d"
}

# Versioning
versioning = {
  enabled_by_default = false
  max_versions = 1000
}

# Lifecycle
lifecycle = {
  max_rules_per_bucket = 1000
  transition_check_interval = "1d"
  expiration_check_interval = "1d"
}

# Storage backend
storage = {
  endpoint = "unix:///run/utkarsha/storage.sock"
  read_replicas = 2
  write_quorum = 2
  consistency = "strong"  # strong | eventual
}

# Notifications
notifications = {
  enabled = true
  endpoint = "ukafka://utkarsha.storage.events"
  events = ["ObjectCreated:*", "ObjectRemoved:*", "ObjectRestore:*"]
}
```

## Integration

- **Upstream**: `ugate` (routes `/api/store/*` here), `ulb` (selects storage gateway node)
- **Downstream**: `storage/` engine (gRPC: `ObjectService`, `BucketService`, `MultipartService`)
- **External**: `uevent`/`ukafka` (notifications), CDN (CloudFront, Cloudflare via origin shield)

## Metrics

| Metric | Type | Labels |
|--------|------|--------|
| `ustore_requests_total` | Counter | `operation`, `bucket`, `status` |
| `ustore_bytes_transferred` | Counter | `direction` (in/out), `bucket` |
| `ustore_latency_seconds` | Histogram | `operation` |
| `ustore_multipart_active` | Gauge | `bucket` |
| `ustore_presigned_issued_total` | Counter | `method` |

## Status

🔴 **Planned** — S3 API surface defined, storage engine integration pending.