# The benchmark contract

Every benchmark target — in every language, for both `sofab` and `protobuf` —
does the **same logical work** and prints **one uniform, machine-readable line**
that the aggregating runner parses:

```
BENCH lang=<lang> impl=<sofab|protobuf> serialized_bytes=<n> iters=<n> cpu_time_s=<f> throughput_mbs=<f> sha256=<hex>
```

| field | meaning |
|---|---|
| `lang` | `c`, `cpp`, `python`, `go`, `rust`, `zig`, `java`, `csharp`, `typescript` |
| `impl` | `sofab` or `protobuf` — the serialization library under test |
| `serialized_bytes` | wire size of one serialized message (bytes) |
| `iters` | how many encode+decode round-trips were timed |
| `cpu_time_s` | CPU time spent **only** in the encode+decode loop (seconds) |
| `throughput_mbs` | `serialized_bytes * iters / cpu_time_s / 1e6` (MB/s) |
| `sha256` | SHA-256 of the serialized message (hex) |

The runner also reports a **`msgs/s`** column (`iters / cpu_time_s`) next to MB/s.
It is **derived from the fields above**, not emitted — no target changes. MB/s scales
by `serialized_bytes`, so it credits SofaBuffers' smaller wire; `msgs/s` is the
size-neutral per-message codec speed. See #85.

## Rules every target follows

1. **Identical message, identical state.** Every target encodes the exact same
   `FullScaleExample` message with the exact same field values — the canonical
   values in [`schema/STATE.md`](../schema/STATE.md) (machine form:
   [`schema/state.json`](../schema/state.json)).
2. **Warm-up + self-check first, outside the timed region.** Do one round-trip,
   capture `serialized_bytes` and `sha256`, and assert the decoded message
   re-encodes to the identical bytes. A target that fails its self-check must
   exit non-zero.
3. **Time a chained encode+decode round trip.** Each timed iteration **decodes
   the reference wire and re-encodes the freshly decoded message**
   (`encode(decode(blob))`) — not a pre-built instance re-encoded every
   iteration. This models a proxy/transcode and, crucially, denies protobuf the
   once-per-instance serialized-size memo (`getSerializedSize` / `GetCachedSize`),
   so encode is measured on equal terms with SofaBuffers instead of as a
   pre-memoized re-serialization (issue #86). Hoist the output buffer out of the
   loop where the language allows it, and keep a per-iteration sink (a
   re-encoded-byte count checked against `serialized * iters`, or a
   `black_box` / `doNotOptimizeAway`) so the round trip can't be optimized away.
   Do not count object construction, JSON parsing, or I/O. Measure CPU time
   (process/thread CPU clock), not wall-clock, so a busy host doesn't skew the
   number.
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
- SofaBuffers: **434 bytes**, `sha256=e1733416c987b04faea747b7cdd8f2913934f45d4a77453f58c9e3ef12e29d9d`
- Protobuf: **494 bytes**, `sha256=e8d391d98bc54c0ec24fff19ec96bb52114d9d34aed7d0f0023a0317bcfa5b3d`

Since **sofabgen v0.11.0** every SofaBuffers backend sparsely omits a wrapper-array
element equal to its default (the single empty string in `string_array`), so all
`impl=sofab` targets — the C object API (corelib-c-cpp), its C++ wrapper, and every
other corelib — converge on the same **434-byte** wire. Before v0.11.0 only the C
object API omitted that element (434 B); every other backend encoded it positionally
and landed on 436 B. There is now no per-target exception — the gate checks all
sofab targets against the single 434 B reference.
