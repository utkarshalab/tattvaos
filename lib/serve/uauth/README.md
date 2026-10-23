# serve/uauth — Authentication & Authorization

> Multi-provider authentication, token validation, and RBAC for Utkarsha OS serving layer.

## Responsibility

- **API Key validation** — Prefix lookup, hashed storage, scopes, rotation, expiration
- **JWT verification** — RS256/ES256/EdDSA, JWKS caching, claim validation, audience
- **mTLS verification** — Client certificate validation, SPIFFE/SPIRE integration
- **OIDC / OAuth2** — Authorization code flow, token introspection, userinfo
- **Token introspection** — RFC 7662 compliant, opaque token resolution
- **RBAC / ABAC** — Role/Policy engine, resource-action authorization
- **Session management** — Short-lived access tokens, refresh tokens, revocation

## Non-Responsibility

- **Firewall/IP policy** → `niti`
- **Audit logging** → `uaudit` (logs auth decisions)
- **Rate limiting** → `ugate` (uses identity from auth)
- **Domain logic** → domain adapters

## Architecture

```
Request
   │
   ▼
┌─────────────────────────────────────────────────────────────┐
│                    Auth Pipeline                            │
├─────────────────────────────────────────────────────────────┤
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │  Extractor  │──▶│  Verifier   │──▶│  Authorizer │         │
│  │  (credential│   │  (validate) │   │  (RBAC)     │         │
│  │   finder)   │   │             │   │             │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
│        │                │                │                   │
│        ▼                ▼                ▼                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │                 Identity Context                     │   │
│  │  sub, iss, aud, scopes, roles, claims, metadata      │   │
│  └─────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

## Credential Extractors (Priority Order)

| Priority | Type | Header / Location |
|----------|------|-------------------|
| 1 | mTLS | TLS client certificate |
| 2 | Bearer Token | `Authorization: Bearer <token>` |
| 3 | API Key | `X-API-Key: <key>` or `Authorization: ApiKey <key>` |
| 4 | Cookie | `__Host-ut_session=<token>` |
| 5 | Query Param | `?access_token=<token>` (least preferred) |

## Verifiers

### API Key
```rust
pub struct ApiKeyConfig {
    pub prefix: String,           // "tk_" for identification
    pub hash_algo: HashAlgo,      // Argon2id (recommended), SHA-256
    pub key_store: KeyStore,      // Memory, Redis, Database, File
    pub rotation: RotationPolicy, // Max age, overlap window
}
```
- **Prefix identification**: `tk_live_`, `tk_test_`, `tk_admin_` for instant routing
- **Hashed storage**: Never store plaintext; verify with constant-time comparison
- **Scopes**: `["inference:chat", "embeddings:create", "admin:metrics"]`

### JWT
```rust
pub struct JwtConfig {
    pub jwks_uri: String,                    // "https://auth.utkarshaos.com/.well-known/jwks.json"
    pub jwks_cache_ttl: Duration,            // default: 1h
    pub issuer: String,                      // "https://auth.utkarshaos.com"
    pub audiences: Vec<String>,              // ["utkarsha-api", "utkarsha-ai"]
    pub required_claims: Vec<String>,        // ["sub", "scope", "org_id"]
    pub clock_skew: Duration,                // default: 60s
}
```
- **Algorithms**: RS256, RS384, RS512, ES256, ES384, EdDSA
- **JWKS**: Auto-refresh with `cache-control` header respect
- **Claims**: Standard + custom (`org_id`, `tenant_id`, `roles`, `permissions`)

### mTLS
```rust
pub struct MtlsConfig {
    pub ca_store: CaStore,           // File, SPIRE, Vault
    pub verify_hostname: bool,
    pub require_spiffe: bool,        // Enforce SPIFFE ID format
    pub allowed_spiffe_patterns: Vec<String>, // "spiffe://utkarshaos.com/ns/prod/sa/*"
}
```
- **SPIFFE/SPIRE**: Native integration for workload identity
- **Certificate rotation**: Automatic via SPIRE or manual CA reload

### OIDC / Token Introspection
```rust
pub struct OidcConfig {
    pub issuer: String,
    pub client_id: String,
    pub client_secret: String,
    pub introspection_endpoint: String,
    pub userinfo_endpoint: String,
    pub token_cache_ttl: Duration,
}
```

## Authorization (RBAC / ABAC)

```rust
pub struct Policy {
    pub effect: Effect,              // Allow | Deny
    pub principals: Vec<Principal>,  // Role, User, Group, ServiceAccount
    pub actions: Vec<Action>,        // "inference:chat", "storage:read:*"
    pub resources: Vec<Resource>,    // "model:llama-3-70b", "bucket:data/*"
    pub conditions: Vec<Condition>,  // Time, IP, Resource tags, MFA
}

pub enum Principal {
    Role(String),           // "admin", "developer", "ai-service"
    User(String),           // "user:123"
    Group(String),          // "group:ml-team"
    ServiceAccount(String), // "sa:inference-worker"
}

pub struct Condition {
    pub attribute: String,      // "request.time", "resource.tag.env", "principal.mfa"
    pub operator: Operator,     // Equals, In, NotIn, Matches, Before, After
    pub value: Value,
}
```

## Identity Context (Output)

```rust
pub struct Identity {
    pub sub: String,                    // Subject (user ID, service account)
    pub iss: String,                    // Issuer
    pub auth_method: AuthMethod,        // ApiKey | Jwt | Mtls | Oidc | Session
    pub scopes: Vec<String>,            // ["inference:chat", "embeddings:create"]
    pub roles: Vec<String>,             // ["developer", "ml-engineer"]
    pub claims: ClaimMap,               // All JWT claims / token introspection data
    pub metadata: MetadataMap,          // org_id, tenant_id, tier, rate_limit_tier
    pub expires_at: Option<DateTime>,   // Token expiration
    pub authenticated_at: DateTime,     // When this request was authenticated
}
```

## Configuration

```toml
[auth]
# Extractor priority (first match wins)
extractors = ["mtls", "bearer", "api_key", "cookie", "query"]

[auth.api_key]
prefix = "tk_"
hash = "argon2id"
store = "redis"  # memory | redis | database | file
rotation = { max_age = "90d", overlap = "7d" }

[auth.jwt]
jwks_uri = "https://auth.utkarshaos.com/.well-known/jwks.json"
issuer = "https://auth.utkarshaos.com"
audiences = ["utkarsha-api", "utkarsha-ai"]
required_claims = ["sub", "scope", "org_id"]
cache_ttl = "1h"

[auth.mtls]
ca_store = "spire"  # file | spire | vault
require_spiffe = true
allowed_patterns = ["spiffe://utkarshaos.com/ns/prod/sa/*"]

[auth.oidc]
enabled = true
issuer = "https://auth.utkarshaos.com"
introspection_endpoint = "https://auth.utkarshaos.com/oauth2/introspect"
cache_ttl = "5m"

[auth.authorization]
policy_engine = "casbin"  # casbin | opa | builtin
policies = [
  { effect = "allow", principals = ["role:admin"], actions = ["*"], resources = ["*"] },
  { effect = "allow", principals = ["role:developer"], actions = ["inference:*", "embeddings:*"], resources = ["*"] },
  { effect = "allow", principals = ["role:ai-service"], actions = ["inference:chat"], resources = ["model:*"], conditions = [{ attribute = "resource.tag.tier", operator = "in", value = ["standard", "premium"] }] },
  { effect = "deny", principals = ["*"], actions = ["admin:*"], resources = ["*"] },
]

[auth.session]
access_token_ttl = "15m"
refresh_token_ttl = "7d"
refresh_rotation = true
revocation_check = true
```

## Integration

- **Upstream**: `niti` (firewall passes request), `uhttp`/`ugrpc`/`uws` (protocol)
- **Downstream**: `ugate` (identity for rate limiting), `uaudit` (auth decisions), `userve` (identity context)
- **External**: JWKS endpoint, SPIRE, Vault, OIDC provider, Redis (token cache/revocation)

## Error Responses

| Code | Condition | Headers |
|------|-----------|---------|
| `401` | Missing/invalid credentials | `WWW-Authenticate: Bearer realm="utkarsha", error="invalid_token"` |
| `403` | Valid identity, insufficient permissions | `X-Auth-Decision: deny` |
| `419` | Session expired | `WWW-Authenticate: Bearer realm="utkarsha", error="token_expired"` |
| `503` | Auth service unavailable (JWKS, introspection) | `Retry-After` |

## Status

🟡 **Design Phase** — Multi-provider pipeline designed, RBAC model defined.