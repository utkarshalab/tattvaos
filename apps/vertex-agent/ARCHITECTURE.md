# vertex-agent — CRI Runtime on Utkarsha OS

> The CRI (Container Runtime Interface) shim translating kubelet gRPC calls → Utkarsha OS primitives (fibers, capabilities, unet, uxfs).

---

## 1. Position in Stack

```
kubelet (on node) ──CRI gRPC (port 10010)──► vertex-agent (app/vertex-agent/)
                                                    │
                                                    ├── Pod sandbox  ──► pause fiber + shared netns/ipcns
                                                    ├── Container    ──► fiber + attenuated caps + mount ns
                                                    ├── Image pull   ──► OCI → upk → uxfs overlay layers
                                                    ├── Exec/Attach  ──► fiber ptys via ulog sinks
                                                    ├── Port-forward ──► unet socket proxy
                                                    └── Metrics      ──► umetric → kubelet /stats
```

**vertex-agent is NOT Kubernetes.** It is the CRI runtime — the narrow translation layer.

---

## 2. Utkarsha Primitives Mapping

| CRI Concept | Utkarsha Implementation |
|-------------|----------------------|
| **Pod Sandbox** | Fiber group: pause fiber (PID 1 of pod) holds shared `netns` + `ipcns`; child fibers = containers |
| **Container** | Fiber with attenuated `usrauth` capabilities, private VFS mount namespace (overlayfs) |
| **Image** | OCI manifest → `.upk` package → `uxfs` overlayfs layers (read-only base + RW upper) |
| **Volume Mount** | `uxfs` bind mount / overlay lower dir into container's mount namespace |
| **Network Namespace** | `unet` socket namespace (per-pod IP, port space, routing table) |
| **PID Namespace** | Fiber tree: pause fiber = PID 1, containers = children (visible via `sys/tasks/`) |
| **IPC Namespace** | Shared memory region + message queue scoped to pause fiber |
| **Resource Limits** | `sched` affinity + `mm` arena quota + `ulib/ring` for CPU accounting |
| **Seccomp/AppArmor** | `usrauth` capability attenuation (no syscall filter needed — no syscalls) |
| **Logs** | `ulog` structured sinks → `keep/log/app/vertex-agent/containers/<id>/` |
| **Metrics** | `umetric` counters/gauges → kubelet `/stats/summary` endpoint |

---

## 3. Architecture

### 3.1 Process Model

```
vertex-agent (single fiber, supervised by ush)
├── gRPC server fiber          # Listens on [::]:10010, spawns handler fibers
├── Image manager fiber        # Pull, unpack, layer GC
├── Sandbox manager fiber      # Pod lifecycle, netns/ipcns creation
├── Container manager fiber    # Container lifecycle, fiber spawn
├── Exec/Attach handler fiber  # PTY allocation, stream multiplexing
├── Metrics collector fiber    # Periodic umetric scrape → CRI stats
└── GC fiber                   # Dead container cleanup, image layer GC
```

All fibers cooperative (`fiber_yield` on I/O). No preemption = no locks in hot paths.

### 3.2 Capability Model

**vertex-agent manifest declares:**
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

**Container fiber receives attenuated caps:**
```json
{
  "capabilities": [
    "fs:read:data/<app>/...",      # Only its own data
    "fs:write:data/<app>/...",
    "net:connect:allowed_cidrs",   # From NetworkPolicy
    "net:bind:allowed_ports",      # From containerPort
    "sched:cpu_quota:ms=100000",   # CPU limit
    "mm:arena_quota:bytes=536870912"  # Memory limit
  ]
}
```

---

## 4. CRI API Implementation

### 4.1 RuntimeService

| CRI Method | Implementation |
|------------|----------------|
| `RunPodSandbox` | 1. Allocate pod IP from `unet` IPAM<br>2. Create pause fiber (entry = `sched_idle_task`)<br>3. Create `netns` + `ipcns` attached to pause fiber<br>4. Setup `uxfs` mount namespace (shared base)<br>5. Write sandbox metadata to `data/vertex-agent/pods/<id>/` |
| `StopPodSandbox` | 1. Signal pause fiber → `fiber_kill` cascades to children<br>2. Teardown `netns`/`ipcns`<br>3. Unmount VFS namespace<br>4. Mark sandbox `SANDBOX_NOTREADY` |
| `RemovePodSandbox` | After stop: delete metadata, release IP |
| `PodSandboxStatus` | Read from `sys/tasks/` + `unet` counters + `uxfs` mount info |
| `ListPodSandbox` | Scan `data/vertex-agent/pods/` |
| `CreateContainer` | 1. Resolve image → overlayfs mount<br>2. Create container fiber (entry = user cmd)<br>3. Attenuate capabilities from pod + container spec<br>4. Setup mounts (volumes, devices, secrets)<br>5. Write container metadata |
| `StartContainer` | `fiber_resume` container fiber |
| `StopContainer` | `fiber_kill` with timeout → `SIGKILL` equivalent |
| `RemoveContainer` | Cleanup metadata, release resources |
| `ContainerStatus` | Fiber state + `umetric` counters |
| `ListContainers` | Scan `data/vertex-agent/containers/` |
| `ExecSync` / `Exec` | Allocate PTY pair, inject into container fiber stdin/stdout |
| `Attach` | Connect to existing PTY streams |
| `PortForward` | `unet` socket proxy: localhost:port → podIP:targetPort |
| `ContainerStats` | `umetric` snapshot: CPU (ticks), Mem (arena), Net (unet), FS (uxfs) |
| `ListContainerStats` | Batch collect |
| `UpdateContainerResources` | Update `sched` affinity + `mm` quota |
| `ReopenContainerLog` | Rotate `ulog` sink |
| `RuntimeConfig` | No-op (static config via manifest) |
| `Status` | vertex-agent health + `unet`/`uxfs` status |

### 4.2 ImageService

| CRI Method | Implementation |
|------------|----------------|
| `ListImages` | Scan `data/vertex-agent/images/` (`.upk` index) |
| `ImageStatus` | Check local + remote (registry) |
| `PullImage` | 1. `pkg/registry` client → OCI manifest<br>2. Download layers (blobs) via `net/uhttp`<br>3. Verify signatures (`crypto/usign`)<br>4. Convert OCI → `.upk` (layer per layer)<br>5. Store in `uxfs` overlayfs: base layer = read-only, upper = RW |
| `RemoveImage` | Unmount if unused, delete layers (refcounted) |
| `ImageFsInfo` | `uxfs` stats for `data/vertex-agent/images/` |

---

## 5. Image Store: OCI → `.upk` → `uxfs`

```
OCI Image (registry)
├── manifest (application/vnd.oci.image.manifest.v1+json)
├── config (application/vnd.oci.image.config.v1+json)
└── layers (application/vnd.oci.image.layer.v1.tar+gzip)

▼ vertex-agent PullImage

.upk Package (local store)
├── manifest.upk (BXP-encoded: name, version, layers[], config, signatures)
├── layer-<digest>.upk (each layer = squashed uxfs snapshot)
└── sig/ (Ed25519 signatures over manifest)

▼ Unpack (lazy, on first container create)

uxfs Overlayfs Mount
├── lower/ (read-only layer snapshots, shared)
│   ├── layer-sha256-abc/
│   ├── layer-sha256-def/
│   └── ...
└── upper/ (per-container RW, copy-on-write)
    └── container-<id>/
```

**Deduplication:** Identical layer digests → single `uxfs` snapshot (clone). Refcount in `data/vertex-agent/images/layers/index.bxp`.

**GC:** `vertex-agent` GC fiber scans `containers/` + `pods/` for live layer refs; unreferenced layers → `keep/trash/` → async delete.

---

## 6. Networking: Pod Sandbox = `unet` Namespace

```
Pod Sandbox (pause fiber)
├── netns: unique IP (from node CIDR), own routing table
├── lo: 127.0.0.1/8 (shared by all containers in pod)
├── eth0: veth pair → node bridge (CNI: none needed, unet native)
├── iptables/niti rules: NetworkPolicy → DNAT/DROP
└── DNS: /etc/resolv.conf → cluster DNS (from kubelet)

Container in pod:
├── Shares pause fiber's netns (same IP, same ports)
├── Cannot bind same port as sibling (SO_REUSEPORT not set)
└── Sees only pod's network interfaces
```

**CNI compatibility:** `vertex-agent` implements CNI spec as *library calls* (not exec plugins). `unet` handles IPAM, veth, routing, firewall natively.

---

## 7. Storage: Volumes = `uxfs` Bind Mounts

| Volume Type | Implementation |
|-------------|----------------|
| `emptyDir` | `uxfs` tmpfs mount at `tmp/app/vertex-agent/volumes/<pod>/<vol>/` |
| `hostPath` | `uxfs` bind mount from `vol/ext/` or `vol/att/` |
| `configMap` / `secret` | `uxfs` read-only overlay from `conf/` or `sec/vault/` |
| `PVC` | `uxfs` bind mount from `data/<app>/` (provisioned by `vertex-controllers`) |
| `CSI` | `vertex-agent` calls CSI gRPC → `unet`/`uxfs` driver in node |

**Mount namespace:** Each container = private `uxfs` mount namespace (overlayfs). `pivot_root` not needed — `uxfs` namespace isolation.

---

## 8. Security: `usrauth` All the Way Down

```
Pod creation:
1. vertex-agent creates pod subject: usrauth_subject_create(uid=podUID, type="k8s_pod_t", integrity=MEDIUM)
2. Attach capabilities: net:namespace, fs:mount, sched:fiber_create
3. MLS label: level=namespace, categories=NetworkPolicy peers

Container creation:
1. vertex-agent delegates attenuated caps from pod subject → container subject
2. usrauth_cap_delegate(pod_cap, requested_cap) → container_cap (intersection)
3. Container fiber runs with container subject handle in FCB
4. All access checks → usrauth_check(container_subject, object, verb)
```

**No seccomp, no AppArmor, no SELinux needed** — `usrauth` is the single reference monitor.

---

## 9. Observability

| Signal | Source | Export |
|--------|--------|--------|
| **Container CPU** | `sched` ticks per fiber | `umetric` counter `container_cpu_seconds_total` |
| **Container Memory** | `mm` arena usage per fiber | `umetric` gauge `container_memory_usage_bytes` |
| **Container Network** | `unet` per-netns counters | `umetric` counter `container_network_*` |
| **Container FS** | `uxfs` per-mount I/O | `umetric` counter `container_fs_*` |
| **Pod Sandbox** | Aggregated from containers | Same metrics with `pod` label |
| **Node** | `sys/mem`, `sys/cpu`, `unet` global | `kubelet` `/stats/summary` |

**Log format:** `ulog` structured JSON → `keep/log/app/vertex-agent/containers/<container-id>/stdout.log` (rotated, compressed via `ucmp/zstd`).

---

## 10. Upgrade / HA

- **In-place binary swap:** New `vertex-agent` staged in `keep/upd/`, verified, `ush` sends `SIGUSR1` → old fiber drains connections, new fiber starts, old exits
- **State persistence:** All metadata in `data/vertex-agent/` (survives restart)
- **Image layers:** `uxfs` snapshots survive reboot
- **Pod sandbox recovery:** On `vertex-agent` restart, scan `data/vertex-agent/pods/`, recreate pause fibers, reattach container fibers (if `restartPolicy=Always`)

---

## 11. Directory Structure

```
app/vertex-agent/
├── main                 # Entry: gRPC server + fiber supervisors
├── manifest             # Capabilities, version, signature
├── conf/
│   ├── config.toml      # Listen addr, image GC policy, registry mirrors
│   └── seccomp.json     # Not used (kept for compat)
├── lib/
│   ├── cri/             # CRI protobuf (generated from .proto)
│   ├── oci/             # OCI → upk translation
│   ├── sandbox/         # Pod sandbox lifecycle
│   ├── container/       # Container lifecycle
│   ├── image/           # Image pull, unpack, store
│   ├── network/         # unet namespace management
│   ├── volume/          # uxfs mount namespace ops
│   ├── exec/            # PTY, stream handling
│   └── metrics/         # umetric → CRI stats mapping
└── res/
    ├── pause.asm        # Pause fiber entry (minimal)
    └── default-profile.json  # Default capability profile
```

---

## 12. Build & Deploy

```
# Build (utasm)
utasm -arch amd64 -f elf64 --standalone app/vertex-agent/main.s -o build/vertex-agent

# Package (.upk)
upm pack app/vertex-agent/ -o keep/upd/vertex-agent-<ver>.upk

# Install (on node)
upm install keep/upd/vertex-agent-<ver>.upk

# Runs as app/vertex-agent/main under ush supervision
```

---

## 13. Testing

| Test | Method |
|------|--------|
| **CRI conformance** | `critest` (upstream) against running vertex-agent |
| **K8s e2e** | `kubetest` with Utkarsha node image |
| **Security** | `usrauth` test suite + capability attenuation fuzzing |
| **Performance** | `umark` benchmarks: pod startup latency, image pull throughput, exec latency |
| **Chaos** | `ufuzz` on gRPC parser, OCI parser, overlayfs mount paths |

---

## 14. Future Extensions

- **Wasm/WASI containers** — `ai/uinfer` style sandboxed modules
- **MicroVM (Firecracker-style)** — `kernel/ebpf` + `hw/ucxl` for hardware isolation
- **GPU sharing** — `ugpu` MIG/time-slice via capability delegation
- **Confidential containers** — `kernel/security/tee.asm` + `usrauth` MLS

---

## 15. Dependencies (Must Exist in Utkarsha)

| Module | Status | Notes |
|--------|--------|-------|
| `serve/userve` | 🚧 | gRPC server (HTTP/2 or QUIC) |
| `net/unet` | ✅ | Namespaces, IPAM, socket API |
| `storage/uxfs` | ✅ | Overlayfs, snapshots, bind mounts |
| `security/usrauth` | ✅ | Capabilities, delegation, MLS |
| `kernel/sched` | ✅ | Fibers, affinity, quotas |
| `kernel/mm` | ✅ | Arenas, quotas |
| `lib/ulog` | ✅ | Structured logging |
| `obs/umetric` | ✅ | Metrics export |
| `pkg/registry` | 🚧 | OCI registry client |
| `crypto/usign` | ✅ | Signature verification |
| `lib/uparser` | ✅ | Protobuf/BXP parsing |

---

**Next:** Create skeleton `app/vertex-agent/` with manifest + main.asm entry point.