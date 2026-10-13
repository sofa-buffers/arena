# SofaBuffers — Python target: why it's the slowest

The Python SofaBuffers target is the slowest in the arena relative to
protobuf-python, **and it's *not* a fallback bug.** corelib-py ships two engines
behind one API — the **compiled accelerator** (`sofab._speedups`, built by Cython)
and the pure-Python fallback — and the arena runs **both**, one row each:

| row | engine | `codec` |
|---|---|---|
| `python/native` | `sofab._speedups`, the compiled accelerator | `native` |
| `python/pure` | the pure-Python fallback, forced with `SOFAB_PUREPYTHON=1` | `python` |

`import sofab` resolves the engine once per process, so `bench.sh` runs the same
`sofab/bench.py` twice — same message, same `BENCH_ITERS`, same interpreter, only
the environment differs. Nothing is assumed about which engine loaded:
`bench.py` fails the run unless `sofab.IMPL` matches the row's `BENCH_IMPL` label,
so a missing extension can never masquerade as the accelerator. Both rows share
the target's single protobuf measurement and are held to the same 434 B sofab
reference wire by the gate — the engines are byte-for-byte identical, only their
speed differs.

That pair is what prices the accelerator — it is the only reason Python is as
fast as it is. The headline Python row is `python/native`; the current numbers
for both rows live in the main [README](../../README.md) and
[`results/RESULTS.txt`](../../results/RESULTS.txt).

It still trails protobuf because protobuf-python is a thin shell over Google's C
**`upb`** engine — parse and serialize each run as one C call — whereas the
generated SofaBuffers `message.py` still does part of every round trip in Python:

- **Encode** — `Example.serialize(e)` is generated Python that walks the
  dataclass and makes one `Encoder.write_*` call per field (per sequence
  begin/end, per string-array element), each a Python→engine call.
- **Decode** — `Example.decode` builds the dataclass (`cls()`, nested messages
  via `default_factory`), a generated `_Example__Visitor` and a `sofab.Decoder`,
  then feeds the whole buffer once. Every field the schema's **destination
  table** (`_Example__Bind`, a `sofab.Binding` built once at import) names —
  all scalars, `nested`'s floats/string/bytes, every fixed `arrays` member — is
  written by the decoder straight into the visitor's slot buffer, with no
  visitor callback. Only `string_array` (a wrapper sequence of strings) reaches
  the visitor's hooks (`on_sequence_begin`, `on_field`, `on_schema_bound`,
  `on_string` per element). After COMPLETE, one generated `scatter()` pass
  copies the slots onto the dataclass (`list(...)` per array).

So what remains in Python is object construction (dataclasses, visitor,
decoder), the per-field encode calls, the `string_array` hooks and the
`scatter()` pass; the byte-level codec runs in the engine.

### Profile (older codegen — needs a re-profile)

The callgrind attribution below was measured against an **earlier** generated
`message.py`, which decoded through a Python `while`/`if-elif` loop over
`Decoder.next()` (one boxed `Field` per field) instead of the destination table
and `scatter()` above. It is kept for history only; the shares no longer
describe the current code and have not been re-measured:

| origin (older codegen) | share of instructions |
|---|--:|
| CPython interpreter running the generated `message.py` driver + dataclasses | ~83% |
| native `sofab._speedups` codec | ~14% |
| libc / other | ~3% |

Re-profile with `valgrind --tool=callgrind` over an encode+decode loop of
`languages/python/sofab/gen/message.py`; the native engine's contribution can
also be read straight off the `python/native` vs `python/pure` rows of a
benchmark run.
