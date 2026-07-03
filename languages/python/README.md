# SofaBuffers — Python target: why it's the slowest

The Python SofaBuffers target is the slowest in the arena (~0.11× of
protobuf-python), **and it's *not* a fallback bug.** The Python sofab target runs
the **compiled Cython accelerator**, not the pure-Python engine — verified at
runtime (`sofab.IMPL == "native"`, and the generated `message.Encoder`/`Decoder`
resolve to `sofab._speedups`). Native is doing real work: forcing the pure-Python
fallback with `SOFAB_PUREPYTHON=1` drops throughput ~**7×** (≈3 MB/s), so the
accelerator is the only reason Python is as fast as it is.

It still trails protobuf because protobuf-python is a thin shell over Google's C
**`upb`** engine — nearly all its encode/decode runs in C — whereas SofaBuffers
keeps the **per-field driver in Python**. A callgrind profile of the timed
encode+decode loop (instruction attribution, `scripts`-independent) shows where the
cost actually lands:

| origin | share of instructions |
|---|--:|
| CPython interpreter running the generated `message.py` driver + dataclasses | **~83%** |
| native `sofab._speedups` codec (the real serialization work) | **~14%** |
| libc / other | ~3% |

Inside that 83%: the bytecode eval loop (per-field `_marshal`/`_unmarshal`
`while/if-elif` dispatch), object churn (a fresh dataclass per nested message, a
boxed `Field` object returned per field by `Decoder.next()`, boxed `int`s for every
scalar), and attribute get/set on those objects — alloc/free/GC alone is ~16% of the
interpreter cost. The native codec is **not** the bottleneck; the Python↔C boundary
crossed once per field, plus the pure-Python object model, is. Even an infinitely
fast codec would only remove ~14%.

## Implication for optimization

The lever is *not* the harness or the corelib's byte-level codec (both already lean)
— it's collapsing the per-field boundary. A whole-message native path (walk the
schema in C and populate the object in one `_speedups` call, instead of returning a
`Field` per field to a Python loop) is what would close the gap. Reproduce with
`valgrind --tool=callgrind` over an encode+decode loop of
`languages/python/sofab/gen/message.py`, or compare `SOFAB_PUREPYTHON=1` vs unset to
see the native contribution directly.
