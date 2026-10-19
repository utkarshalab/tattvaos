# identity — Architecture

## Layer Diagram
```
+---------------------+
|   Caller / Kernel   |
+---------------------+
          |
          v
+---------------------+
|   identity Public API   |
+---------------------+
          |
          v
+---------------------+
|   Core Engine       |
+---------------------+
          |
          v
+---------------------+
|   State / Storage   |
+---------------------+
```

## Design Principles
- Fail closed by default.
- All security-relevant decisions are audited.
- Constant-time where secrets are involved.
- Minimal attack surface — no unused exports.

## Thread Safety
This module is designed for single-threaded kernel execution.
Caller is responsible for synchronization.

## License
Apache-2.0
