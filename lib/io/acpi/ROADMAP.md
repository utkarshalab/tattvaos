# acpi — Roadmap

**Part of:** Utkarsha OS, `lib/io/acpi` — ACPI tables, the AML interpreter,
platform events and power
**Status:** static tables (RSDP, XSDT, MADT, MCFG, FADT); AML interpreter
core written and host-tested in `aml/` (2026-11-06), not yet wired into the
kernel
**Covers:** ACPI 1.0b to 6.6

ACPI is how the firmware describes the machine to the OS. Fixed tables
describe CPUs, interrupt controllers and PCI. Everything else (touchpads,
lid, buttons, battery, thermal, fans, USB-C, device power, sleep) is
described in **AML bytecode** in the DSDT and SSDT tables, and the OS has
to run that bytecode to use it.

`lib/io/acpi` owns:
- every ACPI table;
- the AML interpreter and the device namespace;
- device discovery and resources for every bus driver;
- platform events (SCI, GPEs, fixed events, Notify) and the embedded
  controller;
- sleep, wake, shutdown and reset;
- battery, AC adapter, thermal zones, fans and buttons as raw platform data.

Policy (when to sleep, how hot is too hot, CPU frequency) belongs to
`kernel/power`; `lib/io/acpi` gives it the mechanism and the data.

Every part is built the same way as the rest of the OS:
- pure x86-64 assembly, statically linked;
- runs in ring 0 and is called directly, with no request layer in between;
- **firmware bytecode is treated as untrusted input**: it is checked,
  bounded and timed like data from a network.

Legend: ✅ done · ◐ exists but unproven · ☐ planned

Line counts are estimates of assembly source, not including tests, and
could be off by ±50%.

---

## 1. What enterprise grade means here

| Area | Requirement |
|---|---|
| Safety | No table, bytecode or firmware reply can crash or hang the OS. Every method has a time budget, a loop limit and a recursion limit |
| Compatibility | Runs the DSDT and SSDTs of every tested machine with no unknown opcodes and no failed methods |
| Correctness | Matches the specification for every opcode and implicit conversion, including the cases firmware relies on in practice |
| Sleep | Suspend and resume 1 000 times in a row on this machine with every device working afterwards |
| Events | Lid, buttons, battery, AC and thermal events reach their consumers within 10 ms |
| Isolation | AML can only touch the memory, I/O ports and PCI config ranges that the firmware's own tables declare; anything else is refused and logged |
| Observability | The namespace, every device, its resources, every GPE count and every method failure readable in `/sys/dev/acpi/`; table dump on demand |
| Lifecycle | Hot-added devices and tables loaded at run time (SSDTs loaded by `Load` and `LoadTable`) work without a reboot |

---

## 2. Target hardware

Read from the development machine's device list on 2026-11-06 (MSI laptop,
Ryzen 7 5700U).

| ACPI device | ID | Used by |
|---|---|---|
| Embedded controller | `PNP0C09` | Battery, lid, hotkeys, fans, thermal (Phase 4) |
| Battery | `PNP0C0A` | `/sys/power/battery` (Phase 5) |
| AC adapter | `ACPI0003` | `/sys/power/ac` (Phase 5) |
| Lid | `PNP0C0D` | `lib/input` (Phase 3) |
| Power button | `PNP0C0C` | `lib/input` (Phase 3) |
| Thermal zone | `THERMALZONE` | `kernel/power` (Phase 5) |
| WMI | `PNP0C14` | Vendor hotkeys and settings (Phase 6) |
| I²C controller, GPIO controller | `AMDI0010`, `AMDI0030` | `lib/io/i2c`, `lib/io/gpio` (Phase 2) |
| I²C-HID touchpad | `PNP0C50` | `lib/input` (Phase 2) |
| PS/2 keyboard and mouse | `MSI0007`, `MSNB0001` | `lib/input` |
| AMD power engine plug-in | `AMDI0005` | Low-power idle entry and exit (Phase 7) |
| Processor container | `ACPI0010` | `kernel/power` |
| TPM 2.0 | `MSFT0101` | `security/` |
| PCI Express root complex | `PNP0A08` | `lib/io/pci` (`_PRT`, `_OSC`) |
| HPET, RTC, legacy timer, PIC, DMA, speaker | `PNP0103`, `PNP0B00`, `PNP0100`, `PNP0000`, `PNP0200`, `PNP0800` | `lib/time`, `lib/io/intr` |

**Sleep states on this machine:** only **S0 low-power idle** (sometimes
called modern standby) and hibernate. **S3 is not available.** So suspend
on this machine means low-power idle with the AMD power engine plug-in, not
the classic S3 path. Both are planned; S0 idle comes first here.

---

## 3. Key decisions

| # | Decision | Why |
|---|---|---|
| 1 | **Own AML interpreter, written from the specification** | Pure assembly, no outside code; the interpreter is part of the trusted base |
| 2 | Interpret, do not compile | Bytecode is small, runs rarely and must stay checkable; speed is not a concern |
| 3 | AML runs in a sandbox: allowed memory, I/O and PCI ranges come from the firmware's own declarations and the memory map | A buggy or hostile DSDT cannot write over the kernel |
| 4 | One fiber runs AML; other fibers queue requests | AML has global state (mutexes, the global lock, operation regions); one runner keeps it simple and ordered |
| 5 | Mechanism here, policy in `kernel/power` | Same split as canvas decision 0009 |
| 6 | `_OSI` and `_REV` answers come from one table, chosen so firmware takes its current, best-tested paths; admin-overridable | Firmware changes behaviour on these answers; one place to fix a machine |
| 7 | Platform Runtime Mechanism (PRM) handlers are **never run** | They are native firmware code; only signed native code runs in Utkarsha OS (decision A1) |
| 8 | S0 low-power idle before S3 | This machine has no S3 |

---

## 4. Specification coverage

### 4.1 Tables

| Table | What it gives | Consumer | Phase |
|---|---|---|---|
| RSDP, RSDT, XSDT | Table list | here | ✅ ◐ (exists) |
| FADT | Power management blocks, flags, reset register, DSDT pointer | here | ◐ |
| MADT | CPUs, local APICs, IO-APICs, interrupt overrides | `lib/io/intr` | ◐ |
| MCFG | PCIe configuration space | `lib/io/pci` | ◐ |
| FACS | Global lock, waking vector, hardware signature | here | 1 |
| DSDT, SSDT | AML bytecode | here | 1 |
| HPET | High precision timer | `lib/time` | 1 |
| SRAT, SLIT, HMAT | NUMA memory and distances, memory performance | `lib/hw/unuma` | 8 |
| PPTT | Cache and core topology | `lib/hw/uhwloc` | 8 |
| IVRS (AMD), DMAR (Intel) | IOMMU units and device scopes | `lib/io/dma` | 2 |
| BGRT | Boot logo | canvas | 8 |
| TPM2 | TPM interface | `security/` | 8 |
| SPCR, DBG2 | Serial and debug ports | `lib/io/char` | 8 |
| FPDT | Boot performance records | `lib/obs` | 8 |
| WSMT | Firmware SMM protections | `security/` | 8 |
| BERT, HEST, ERST, EINJ (APEI) | Hardware error reporting, error records, error injection | `lib/obs`, RAS | 8 |
| CEDT | CXL host bridges and windows | `lib/hw/ucxl` | 8 |
| PCCT | Platform communication channels (used by CPPC and others) | here | 7 |
| LPIT | Low-power idle states | `kernel/power` | 7 |
| ECDT | Embedded controller before the namespace is ready | here | 4 |
| SBST | Smart battery warning levels | here | 5 |
| PRMT | Platform Runtime Mechanism handlers | here (decision A1) | 8 |
| MPST, PMTT, NFIT, SDEV, others | Memory power, persistent memory, secure devices | as needed | 8 |
| OEM tables | Vendor data | passed through to `/sys` | 8 |

### 4.2 AML language

- ☐ All name and namespace modifier terms: `Scope`, `Device`, `Method`,
  `Name`, `Alias`, `Processor`, `PowerResource`, `ThermalZone`, `External`
- ☐ All data types: integers (32 and 64 bit, by DSDT revision), strings,
  buffers, packages and variable packages, field units, buffer fields,
  object references, `DDBHandle`, events, mutexes, operation regions
- ☐ Control flow: `If`, `Else`, `While`, `Break`, `Continue`, `Return`,
  `Noop`; method calls with 7 arguments and 8 locals; serialized methods and
  sync levels
- ☐ Every expression opcode: arithmetic, logical, bit, shift, `Concatenate`,
  `Mid`, `Match`, `Index`, `RefOf`, `DerefOf`, `CondRefOf`, `SizeOf`,
  `ObjectType`, `ToBuffer`, `ToInteger`, `ToString`, `ToHexString`,
  `ToDecimalString`, `ToBCD`, `FromBCD`, `CopyObject`, `Store` with all
  implicit conversions, `Timer`, `Fatal`, `Debug`
- ☐ Synchronisation: `Acquire`, `Release`, `Event`, `Signal`, `Wait`,
  `Reset`, `Sleep`, `Stall`, the global lock
- ☐ Fields: `Field`, `IndexField`, `BankField`, access types, access
  attributes, lock rules, update rules, `Offset`, `AccessAs`, `Connection`
- ☐ Operation region spaces: system memory, system I/O, PCI config,
  embedded controller, SMBus, CMOS, PCI BAR target, IPMI, general purpose
  I/O, generic serial bus (I²C, SPI, UART), platform communication channel,
  platform runtime mechanism, functional fixed hardware
- ☐ `Load`, `LoadTable`, `Unload` (run-time tables)
- ☐ `Notify` delivery to registered handlers
- ☐ `_OSI`, `_REV`, `_OS` answers (decision 6)
- ☐ Implementation quirks that real firmware depends on (for example
  forward references, out-of-order `External`, too-long packages); each one
  listed and tested

### 4.3 Namespace and device objects

- ☐ Initialisation order: `_STA`, `_INI`, `_REG` for every operation region
- ☐ Identification: `_HID`, `_CID`, `_UID`, `_ADR`, `_CLS`, `_SUB`, `_HRV`,
  `_STR`, `_DDN`
- ☐ Resources: `_CRS`, `_PRS`, `_SRS`, `_DIS` with every resource
  descriptor: memory (24-bit, 32-bit, fixed, address space 16/32/64,
  extended), I/O and fixed I/O, IRQ and extended IRQ, DMA and fixed DMA,
  GPIO interrupt and GPIO I/O, I²C, SPI, UART and CSI-2 serial bus
  connections, pin function and pin configuration, clock input
- ☐ `_DSD` device properties (with known UUIDs) and `_DSM` methods
- ☐ `_PRT` PCI interrupt routing, link devices
- ☐ `_OSC` for PCIe (native hot plug, AER, PME, LTR, DPC), USB4, CXL and
  processors
- ☐ `_DEP` dependencies, `_EJD`/`_EJx` eject, `_LCK`, `_BBN`, `_SEG`, `_CCA`
- ☐ Device driver matching: each bus driver registers the IDs it handles

### 4.4 Events

- ☐ SCI interrupt, fixed events (power button, sleep button, RTC alarm,
  global lock release), PM timer
- ☐ General purpose events: `_Lxx` and `_Exx` methods, GPE blocks 0 and 1
  and GPE block devices, enable and wake masks, storm detection
- ☐ GPIO-signalled events: `_AEI` and `_EVT` (through `lib/io/gpio`)
- ☐ `Notify` handlers per device for bus checks, device checks, ejects,
  status changes and device-specific codes
- ☐ Embedded controller: query events (`_Qxx`), burst mode, ECDT early
  access, timeouts and recovery

### 4.5 Power and sleep

- ☐ Device power: `_PS0` to `_PS3`, `_PR0` to `_PR3`, `_PSC`, power
  resources with reference counts, `_PSW`, `_DSW`, `_PRW` wake sources,
  `_S0W` and deepest-state rules
- ☐ **S0 low-power idle**: LPIT, the low-power `_DSM` on the AMD power
  engine plug-in (`AMDI0005`) and its Intel equivalent, display-off and
  sleep-entry notifications, residency counters, wake by GPIO and GPE
- ☐ S3: `_PTS`, `_TTS`, `_WAK`, `\_Sx` packages, PM1 control writes,
  FACS waking vector, resume path in the kernel
- ☐ S4 hibernate: image written and read by `lib/storage` (later, needs
  storage)
- ☐ S5 shutdown, reset through the FADT reset register, then fallbacks
- ☐ Processor objects: `_PSS`, `_PCT`, `_PPC` (P-states), `_CST`, `_LPI`
  (C-states), `_CPC` (CPPC), `_TSS`/`_PTC` (throttling), handed to
  `kernel/power`

### 4.6 Platform devices

- ☐ Battery: `_BIF`, `_BIX`, `_BST`, `_BTP`, `_BTM`, `_BMC`, charge limits;
  smart battery over SMBus
- ☐ AC adapter: `_PSR`, power source and power meter devices
- ☐ Thermal zones: `_TMP`, `_PSV`, `_CRT`, `_HOT`, `_ACx`, `_ALx`, `_TC1`,
  `_TC2`, `_TSP`, `_TZP`; trip point events; data to `kernel/power`
- ☐ Fans: `_FIF`, `_FPS`, `_FSL`, `_FST`
- ☐ Lid `_LID`, buttons, sleep button
- ☐ Ambient light `_ALI`, backlight `_BCL`, `_BCM`, `_BQC` (handed to
  canvas)
- ☐ Time and alarm device (`ACPI000E`) for wake timers
- ☐ WMI (`PNP0C14`): `_WDG` GUID blocks, method, data and event blocks,
  for vendor hotkeys and settings (consumed by `lib/input/plat/vendor`)
- ☐ Memory and CPU hot plug (servers)
- ☐ USB-C connector manager (UCSI) mailbox for `lib/usb/typec`

---

## 5. Architecture

```
 kernel/power   lib/input   lib/usb   lib/io/pci   lib/io/i2c,gpio,spi   lib/obs
      │             │          │          │                │                │
 ┌────┴─────────────┴──────────┴──────────┴────────────────┴────────────────┴──┐
 │ api/      device lookup by ID · resources · notify handlers · power calls   │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ dev/      enumeration · driver matching · power resources · battery,       │
 │           thermal, fan, lid, buttons, WMI, UCSI · sleep (S0 idle, S3, S5)   │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ evt/      SCI · fixed events · GPEs · GPIO events · embedded controller     │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ aml/      parser · interpreter · namespace · objects · conversions ·       │
 │           mutexes, events, global lock · operation regions · sandbox        │
 ├─────────────────────────────────────────────────────────────────────────────┤
 │ tbl/      RSDP · XSDT · FADT · FACS · MADT · MCFG · HPET · IVRS/DMAR ·     │
 │           SRAT/SLIT/HMAT · PPTT · APEI · LPIT · PCCT · others               │
 └─────────────────────────────────────────────────────────────────────────────┘
```

### 5.1 Folder layout

The existing files stay where they are and move under `tbl/` when the
folder grows.

```
lib/io/acpi/
├── ROADMAP.md
├── acpi.asm  fadt.asm  madt.asm  mcfg.asm   (existing)
├── tbl/          facs hpet ivrs dmar srat slit hmat pptt apei lpit pcct
│                 ecdt sbst prmt bgrt tpm2 spcr dbg2 fpdt wsmt cedt
├── aml/          parse.asm exec.asm ns.asm obj.asm conv.asm field.asm
│                 region/ (mem io pci ec smbus cmos gpio gsbus pcc)
│                 sync.asm load.asm notify.asm osi.asm sandbox.asm
├── evt/          sci.asm fixed.asm gpe.asm ec.asm gpio_evt.asm
├── dev/          enum.asm match.asm res.asm (resource descriptors)
│                 power.asm sleep/ (s0idle s3 s4 s5 reset) battery.asm
│                 ac.asm thermal.asm fan.asm button.asm lid.asm wmi.asm
│                 ucsi.asm backlight.asm tad.asm hotplug.asm
├── tools/        table dump, namespace view, method trace
└── tests/        AML corpus, dumped tables, conformance cases
```

### 5.2 Where data lives

| Data | Path |
|---|---|
| Namespace, devices, resources, GPE counts | `/sys/dev/acpi/` |
| Battery, AC, thermal, fans | `/sys/power/` |
| Table dumps | `/keep/dump/acpi/` (on demand) |
| Per-machine overrides (`_OSI` answers, GPE masks, replacement SSDTs) | `/conf/acpi/` (admin) |
| AML errors and sandbox refusals | `/keep/log/sys/acpi` |

### 5.3 API shape

- `acpi_find(hid_or_cid, index) → device`, `acpi_walk(callback)`
- `acpi_resources(device) → list` (memory, I/O, IRQ, GPIO, I²C, SPI and so on)
- `acpi_eval(device, "_XXX", args) → object`, with a time budget
- `acpi_dsm(device, uuid, revision, function, args)`
- `acpi_notify_register(device, handler)`
- `acpi_power(device, state)`, `acpi_wake_enable(device)`
- `acpi_sleep(state)`, `acpi_reset()`, `acpi_poweroff()`
- `acpi_region_register(space, handler)` so `lib/io/i2c`, `lib/io/gpio` and
  others serve AML operation regions

---

## 6. Phases

### Phase 0 — Test base

- ☐ Table dumper (runs on bare metal, writes to `/keep/dump/acpi/`)
- ◐ AML test tables built by an encoder (`aml/tests/aml_gen.py`), 118
  checks in `aml/tests/test_aml.py`; tables from this machine still to come
- ◐ Mutation fuzzing: 3 000 mutated tables per run, plus every truncation
  of a table; a longer fuzzer still to come

Estimate: ~1 500 lines.

### Phase 1 — Interpreter core

- ☐ FACS, DSDT and SSDT loading with checksums (the interpreter takes a
  table pointer today)
- ◐ Parser and namespace build: every named-object operator, search rules,
  parent prefixes, aliases, External placeholders replaced by later
  tables, method-local names removed when the method returns
- ◐ Interpreter: data objects, LocalX/ArgX, method calls with arguments
  and results, If/Else/While/Break/Continue/Return, Store with type
  conversion, references (RefOf, DerefOf, Index, CondRefOf), arithmetic,
  logic, comparisons, Concatenate, ToInteger, ToBuffer, ToString, Mid,
  CopyObject, ObjectType, SizeOf, buffer fields, region fields (plain,
  index, bank; access widths; update rules), Notify, Sleep/Stall hooks,
  32-bit integers for revision 1 tables, \_OSI, \_REV, \_OS
- ☐ Still missing: Match, ToHexString, ToDecimalString, ToBCD, FromBCD,
  ConcatenateResTemplate, Load, LoadTable, region fields wider than 64
  bits, connection fields (GPIO, serial bus), continuing a table load
  past an error
- ◐ Limits: call depth, While iterations, machine stack budget, heap; all
  fail cleanly
- ☐ Memory, I/O and PCI config region handlers with the sandbox (the
  interpreter calls one hook, `aml_region_fn`)
- ☐ `_STA`, `_INI`, `_REG` initialisation

Demo: this machine's whole namespace loads and every `_STA` and `_INI`
runs with no errors.
Estimate: ~12 000 lines.

### Phase 2 — Device discovery

- ☐ Resource descriptors, device matching, `_DSD`, `_DSM`
- ☐ `_PRT` routing for `lib/io/pci`, `_OSC`
- ☐ IVRS and DMAR for `lib/io/dma`
- ☐ Region handlers hooked up for `lib/io/gpio` (GPIO) and `lib/io/i2c`
  (generic serial bus)

Demo: the touchpad's I²C address, interrupt pin and HID descriptor address
come from ACPI, not hard-coded.
Estimate: ~5 000 lines.

### Phase 3 — Events and buttons

- ☐ SCI, fixed events, GPEs, GPIO events, `Notify`
- ☐ Power button, sleep button and lid for `lib/input`

Estimate: ~3 000 lines.

### Phase 4 — Embedded controller

- ☐ EC driver, ECDT, query events, burst mode, recovery

Estimate: ~1 500 lines.

### Phase 5 — Battery, AC, thermal, fans

- ☐ Everything in 4.6 except WMI and UCSI
- ☐ Data to `/sys/power/` and `kernel/power`

Estimate: ~3 000 lines.

### Phase 6 — WMI, UCSI, backlight, wake timers

- ☐ WMI for vendor hotkeys (MSI first)
- ☐ UCSI mailbox for `lib/usb/typec`
- ☐ Backlight and ambient light for canvas
- ☐ Time and alarm device

Estimate: ~3 000 lines.

### Phase 7 — Device power and sleep

- ☐ Device power states and power resources, wake sources
- ☐ **S0 low-power idle on this machine** (AMD), then Intel
- ☐ S3 for machines that have it; S5 and reset
- ☐ Processor objects handed to `kernel/power`; PCCT for CPPC

Demo: lid closed → low-power idle → lid opened → keyboard, touchpad, USB,
Bluetooth and display all working.
Estimate: ~5 000 lines.

### Phase 8 — Remaining tables and features

- ☐ Every table in 4.1 still marked 8
- ☐ Run-time `Load` and `LoadTable`, hot plug
- ☐ PRM handling per decision A1

Estimate: ~5 000 lines.

### Phase 9 — Hardening

- ☐ 24-hour fuzzing with no findings for the parser and interpreter
- ☐ Tables from as many machines as can be collected, all loading cleanly
- ☐ 1 000 sleep and resume cycles on this machine
- ☐ Method time budgets and storm detection proven by fault injection

---

## 7. Rough size

| Part | Lines (±50%) |
|---|---|
| Tables | 4 000 |
| AML parser, interpreter, namespace, regions, sandbox | 14 000 |
| Device discovery and resources | 4 000 |
| Events and embedded controller | 4 000 |
| Battery, thermal, fans, buttons, WMI, UCSI, backlight | 5 000 |
| Device power and sleep | 5 000 |
| Tools and tests support | 2 000 |
| **Total** | **~38 000** |

Phases 0 to 3 (enough for the touchpad, lid and buttons) are about 21 500
lines, roughly 4 to 6 sessions.

---

## 8. Decisions

| # | Question | Options |
|---|---|---|
| A1 | PRM handlers (native code from the firmware) | **Decided 2026-11-06:** never run; the call is refused and logged |
| A2 | Hibernate (S4) | **Decided 2026-11-06:** later, with storage |
