# vertex-agent — Build & Integration Guide

## Build System Integration

vertex-agent is an `app/` in Tattva OS, built with **utasm** and packaged as `.upk`.

### Prerequisites

All dependencies must exist in Tattva source tree:

| Module | Path | Status |
|--------|------|--------|
| `serve/userve` | `serve/userve/` | 🚧 HTTP/3+QUIC server |
| `net/unet` | `net/unet/` | ✅ Network stack |
| `storage/uxfs` | `storage/uxfs/` | ✅ Filesystem |
| `security/usrauth` | `security/usrauth/` | ✅ Capabilities |
| `kernel/sched` | `kernel/sched/` | ✅ Fiber scheduler |
| `kernel/mm` | `kernel/mm/` | ✅ Memory management |
| `lib/ulog` | `lib/ulog/` | ✅ Logging |
| `obs/umetric` | `obs/umetric/` | ✅ Metrics |
| `pkg/registry` | `pkg/registry/` | 🚧 OCI registry client |
| `crypto/usign` | `crypto/usign/` | ✅ Signatures |
| `lib/uparser` | `lib/uparser/` | ✅ Protobuf/BXP |

---

## Build Steps

### 1. Build with utasm

```bash
# From Tattva root
cd apps/vertex-agent

# Assemble main + all libs
utasm -arch amd64 -f elf64 --standalone \
  -I../../../ \
  main.asm \
  lib/sandbox/sandbox.asm \
  lib/container/container.asm \
  lib/image/image.asm \
  lib/network/network.asm \
  lib/volume/volume.asm \
  lib/exec/exec.asm \
  lib/metrics/metrics.asm \
  lib/oci/oci.asm \
  lib/cri/cri.asm \
  lib/common.asm \
  res/pause.asm \
  -o build/vertex-agent

# Link (utasm links automatically with --standalone)
# Output: build/vertex-agent (ELF64 executable)
```

### 2. Package as .upk

```bash
# Create package manifest
upm pack apps/vertex-agent/ \
  -o keep/upd/vertex-agent-0.1.0.upk \
  --sign sec/keys/vertex-agent.ed25519
```

### 3. Install on Node

```bash
# On target node (running Tattva OS)
upm install keep/upd/vertex-agent-0.1.0.upk

# Verifies signature, installs to app/vertex-agent/
# Registers with ish for supervision
```

---

## Integration with Tattva OS Build

### Add to PROJECTSTRUCTURE.md (apps/ section)

```markdown
## apps/ — First-Party Applications

```
apps/
├── ...
├── vertex-agent/              # CRI Runtime for Kubernetes
│   ├── main.asm               # Entry point
│   ├── manifest.json          # Capabilities, version
│   ├── ARCHITECTURE.md        # This document
│   ├── conf/
│   │   ├── config.toml        # Runtime config
│   │   └── default-profile.json
│   ├── lib/
│   │   ├── sandbox/           # Pod sandbox manager
│   │   ├── container/         # Container lifecycle
│   │   ├── image/             # Image pull/store/GC
│   │   ├── network/           # Pod networking (unet)
│   │   ├── volume/            # Volume mounting (uxfs)
│   │   ├── exec/              # Exec/Attach/PortForward
│   │   ├── metrics/           # CRI stats collector
│   │   ├── oci/               # OCI → upk translation
│   │   ├── cri/               # CRI protobuf codec
│   │   └── common/            # Shared utilities
│   └── res/
│       ├── pause.asm          # Pause fiber (PID 1)
│       └── default-profile.json
```
```

### Add to Build Order (PROJECTSTRUCTURE.md §12)

vertex-agent builds **after** all its dependencies:

```
...
20. serve/userve               # gRPC server
21. pkg/registry               # OCI client
22. apps/vertex-agent          # CRI runtime
```

### Add to Boot Image (for node distribution)

In `boot/stage2/fs/` or image builder script:

```bash
# Include vertex-agent in node image
cp apps/vertex-agent/build/vertex-agent boot/mod/vertex-agent
# Or as .upk in app/ layer
cp keep/upd/vertex-agent-*.upk app/vertex-agent.upk
```

---

## Runtime Dependencies

### Capabilities Required (in manifest.json)

```json
{
  "capabilities": [
    "net:bind:port=10010",
    "net:raw:unet_socket",
    "net:namespace:create",
    "fs:mount:overlayfs",
    "fs:read:data/vertex-agent/images",
    "fs:write:data/vertex-agent/images",
    "fs:read:data/vertex-agent/containers",
    "fs:write:data/vertex-agent/containers",
    "fs:read:data/vertex-agent/pods",
    "fs:write:data/vertex-agent/pods",
    "sched:fiber_create",
    "sched:fiber_kill",
    "cap:delegate",
    "cap:restrict",
    "ulog:sink:create",
    "umetric:export"
  ]
}
```

### Filesystem Layout (at runtime)

```
/data/vertex-agent/
├── images/
│   ├── index.bxp              # Image manifest index
│   ├── layers/
│   │   ├── sha256-abc/        # uxfs snapshot (read-only)
│   │   └── sha256-def/
│   └── overlays/
│       └── container-xyz/     # RW upper layer
├── containers/
│   └── <container-id>/
│       ├── meta.bxp           # Container metadata
│       ├── config.bxp         # OCI config
│       └── stdout.log         # ulog sink
├── pods/
│   └── <sandbox-id>/
│       ├── meta.bxp           # Sandbox metadata
│       └── netns.bxp          # Network namespace state
```

### Network Integration

vertex-agent uses **unet** directly (no CNI plugins):

- Pod IP allocation: `unet_ipam_allocate()` from node CIDR
- Network namespace: `unet_namespace_create()` per pod
- veth pairs: `unet_veth_create()` to node bridge
- NetworkPolicy: `niti` firewall rules per pod labels
- Service IPs: `niti` DNAT rules (no kube-proxy)

### Storage Integration

All volumes via **uxfs**:

- `emptyDir` → `tmpfs` mount in `tmp/app/vertex-agent/volumes/`
- `hostPath` → bind mount from `vol/ext/` or `vol/att/`
- `configMap`/`secret` → read-only bind from `conf/` or `sec/vault/`
- `PVC` → bind mount from `data/<app>/` (provisioned by vertex-controllers)
- `CSI` → gRPC to CSI driver socket

---

## Testing

### CRI Conformance

```bash
# Run upstream critest against vertex-agent
critest --runtime-endpoint unix:///run/vertex-agent/cri.sock \
  --ginkgo.focus="Runtime"
```

### K8s E2E

```bash
# With Tattva node image
kubetest --provider=skeleton \
  --kubectl-path=/usr/bin/kubectl \
  --kubeconfig=/etc/kubernetes/kubelet.conf \
  --test=false --build=false \
  --check-version-skew=false
```

### Unit Tests

```bash
# Run vertex-agent internal tests
utasm -arch amd64 -f elf64 \
  tests/vertex_agent_test.asm \
  -o build/vertex_agent_test
./build/vertex_agent_test
```

---

## Development Workflow

### 1. Modify Source

Edit `.asm` files in `apps/vertex-agent/lib/`

### 2. Rebuild

```bash
cd apps/vertex-agent
./build.sh  # Wrapper script
```

### 3. Test in QEMU

```bash
# Build Tattva OS with vertex-agent
make -C ../../.. node-image

# Boot in QEMU
qemu-system-x86_64 -kernel build/node/kernel.img \
  -initrd build/node/initrd.img \
  -append "vertex_agent.enabled=1"
```

### 4. Debug

```bash
# Attach udbg
udbg attach vertex-agent

# Or check logs
cat /keep/log/app/vertex-agent/stdout.log
```

---

## Troubleshooting

| Issue | Cause | Fix |
|-------|-------|-----|
| `net:bind` capability denied | Missing in manifest | Add to manifest.json |
| Image pull fails | Registry auth missing | Configure `conf/config.toml` |
| Pod sandbox not ready | unet namespace create failed | Check `unet` kernel module |
| Container OOM | Memory limit too low | Increase `memory_limit_bytes` |
| gRPC connection refused | serve/userve not ready | Build serve/userve first |

---

## Future: Native Build

Once utasm is self-hosting (Gen1+), build entirely within Tattva:

```bash
# On Tattva node
utasm apps/vertex-agent/main.asm -o /tmp/vertex-agent
upm pack apps/vertex-agent/ -o /tmp/vertex-agent.upk
upm install /tmp/vertex-agent.upk
```

No cross-compilation needed.