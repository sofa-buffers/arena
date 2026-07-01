# The benchmark contract

Every benchmark target — in every language, for both `sofab` and `protobuf` —
does the **same logical work** and prints **one uniform, machine-readable line**
that the aggregating runner parses:

```
BENCH lang=<lang> impl=<sofab|protobuf> serialized_bytes=<n> iters=<n> cpu_time_s=<f> throughput_mbs=<f> sha256=<hex>
```

| field | meaning |
|---|---|
| `lang` | `c`, `cpp`, `python`, `go`, `rust`, `java`, `csharp`, `typescript` |
| `impl` | `sofab` or `protobuf` — the serialization library under test |
| `serialized_bytes` | wire size of one serialized message (bytes) |
| `iters` | how many encode+decode round-trips were timed |
| `cpu_time_s` | CPU time spent **only** in the encode+decode loop (seconds) |
| `throughput_mbs` | `serialized_bytes * iters / cpu_time_s / 1e6` (MB/s) |
| `sha256` | SHA-256 of the serialized message (hex) |

## Rules every target follows

1. **Identical message, identical state.** Every target encodes the exact same
   `FullScaleExample` message with the exact same field values — the canonical
   values in [`schema/STATE.md`](../schema/STATE.md) (machine form:
   [`schema/state.json`](../schema/state.json)).
2. **Warm-up + self-check first, outside the timed region.** Do one round-trip,
   capture `serialized_bytes` and `sha256`, and assert the decoded message
   re-encodes to the identical bytes. A target that fails its self-check must
   exit non-zero.
3. **Time only encode + decode.** Hoist the output buffer / decode target out of
   the loop where the language allows it; do not count object construction,
   JSON parsing, or I/O. Measure CPU time (process/thread CPU clock), not
   wall-clock, so a busy host doesn't skew the number.
4. **`BENCH_ITERS` overrides the iteration count** (env var), so a slow
   instrumented pass can use fewer iterations than the timed pass.

## Cross-language correctness gate

Because every SofaBuffers corelib speaks the **same wire format**, and protobuf
is deterministic for this message, the aggregator asserts that:

- all `impl=sofab` targets emit the **same `serialized_bytes` and `sha256`**, and
- all `impl=protobuf` targets emit the **same `serialized_bytes` and `sha256`**.

A divergent `sha256` means that language's message-fill drifted from the
canonical state — a bug, caught automatically.

Reference wires:
- SofaBuffers: **436 bytes**, `sha256=db362bf24959b41fd153b59958e2afdf59020c6c3501fb60e189526659a72ed4`
- Protobuf: **494 bytes**, `sha256=e8d391d98bc54c0ec24fff19ec96bb52114d9d34aed7d0f0023a0317bcfa5b3d`

**One documented exception.** The **C** target is the SofaBuffers *object API*
(corelib-c-cpp) — a runtime-descriptor codec for constrained/embedded use. It
drops the single empty string in `string_array` (a deliberate leanness
optimization), so its wire is **434 bytes**
(`sha256=e1733416c987b04faea747b7cdd8f2913934f45d4a77453f58c9e3ef12e29d9d`). This
is the *correct* output of that backend — the same 2-byte difference the original
C/C++ arena documented — not fill drift, so the gate expects 434 B specifically
for C. Every other SofaBuffers backend encodes empty array elements positionally
and lands on 436 B.
