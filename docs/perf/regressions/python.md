# Python throughput regression (2026-09): analysis and fix plan

Target `languages/python`, corelib-py `d034d93` with the native Cython accelerator,
sofabgen `0.0.0-20260918072500-d865b9213550`, CPython 3.14.4 (`tools/venv`).
Measured 2026-09-18 on the 16-core WSL2 box with `taskset -c 2`, the real `sofab/bench.py`
(200k iterations), interleaved A/B, best of 5–6. Every variant printed `codec=native`,
kept the reference wire (434 B, `e1733416…9d9d`) and passed its self-check.

## Reproduced

| variant | sofab MB/s | msg/s | vs protobuf (~185 MB/s) |
|---|--:|--:|--:|
| OLD: arena `1971be6` + corelib `219bf32` (current on 2026-08-19) | 22.2 | 51.2 k | 0.12× |
| NEW: HEAD + corelib `d034d93` | 17.1 | 39.4 k | 0.09× |

That is **−23 %** (the README had 21.8 → 17.1). The timed loop (`sofab/bench.py`), `bench.sh`,
`setup.sh`, the build flags and the interpreter are identical for both. Only generated code
and the corelib changed, and the regen only added to `harness.py`, which is not timed.
Encode and decode split per message (µs): encode 3.56 → 3.67 (+3 %, under 1 % end to end, which is noise),
**decode 13.4 → 19.1**. The generated `serialize`/`encode` bodies are byte-identical, so the
whole loss is on the decode side.

## Root cause: one C→Python hook call per field, several times over

The corelib removed its pull API in `f70ad02` (#117, 2026-08-23). The generator (regen `322feac`)
moved from a Python loop over `d.next()`, which makes cheap Python→C calls, to a flat `Visitor`
that the Cython `feed` loop calls back into. The old code cannot run past `f70ad02` and the new
code cannot run before `4a815fa`, so the bisect has two windows, and both are flat:

- old gen on corelib `219bf32` / `1f05885` / `215e804`: 22.5 / 22.2 / 22.2 MB/s
- new gen on corelib `4a815fa` / `64574e4` / `792f583` / `d034d93`: 17.4 / 16.8 / 16.9 / 17.2 MB/s
  (±2–3 %, noise)

The step is therefore the handler shape, not any single corelib commit. cProfile on one NEW
decode shows **113 Python function calls**: `on_field` ×26, `on_schema_bound` ×16,
`on_array_begin` ×8, the value hooks ×26 and the sequence begin/end hooks ×8.
Four of these calls fall on every integer array. `feed`'s own time is mostly the
C→Python dispatch. Callgrind: **243 k Ir per round trip, 84 % in the CPython
interpreter** (eval loop 40 %, `PyObject_VectorcallMethod` 3 %, `RichCompare` on IntEnums 1.5 %),
and `_speedups` accounts for 34 k Ir.

Ablation on the real bench (NEW corelib, hand-edited generated `_ExampleVisitor`):

| change | MB/s | Δ |
|---|--:|--:|
| NEW as generated | 17.1 | — |
| `on_field` body → a per-scope `{id: (wt, st)}` table with identity tests (same verdicts) | 18.4 | +7 % |
| `on_field` → `return True` (only the Field build and the call remain) | 20.8 | +21 % |
| no `on_field` at all (not spec-safe, attribution only) | 23.8 | +39 % |

So `on_field` alone explains more than the regression. Two things drive it: the `Field` built
for it (the one hook that needs an object), and a body of chained `if c == _L_…` tests with
`WireType.X` enum attribute lookups. The corelib already says generated code should not
override it (`_bind_visitor` comment, #133). The rest is the other roughly 58 hook calls, which a
visitor cannot avoid.

Corelib-side cost found in passing: `_visit_value`/`_visit_varints` read each value through
`self._unsigned()`, `self._string()`, `self._read_signed_array(lo, hi)` and similar. These are still `def`
methods left over from the pull API, so each value paid a Python method dispatch inside the C loop.

## Fixes (measured end-to-end against unmodified NEW)

corelib-py branch `perf/arena-regression-2026-09` (local, not pushed). Every commit passes the full
suite with native and with `SOFAB_PUREPYTHON=1`: 3963 passed, 131/131 shared vectors, skip matrix,
header_limits §6.2.1/§6.3, strict UTF-8.

| # | change | kind | MB/s |
|---|---|---|--:|
| 1 | `93c3b9d` value readers `def` → `cdef` (same bodies and verdicts) | corelib PR | 17.1 → 17.6–17.8 (+3–4 %) |
| 2 | `e5c41b4` `Binding.unsigned/signed(value_min=, value_max=)`: a scalar row's declared width, INVALID at the value | corelib PR (enabler) | perf-neutral |
| 3 | `235104e` `Binding.indexed(cap)`: in a wrapper-array table, an index ≥ cap under the element tag is INVALID at its header | corelib PR (enabler) | perf-neutral |
| 4 | generated decode over **one destination map** (below) | **generator** | **17.1 → 42.0 (+146 %)** |

Fix 4 measured 40.4–42.2 MB/s over 6 rounds: **2.46× NEW, 1.9× OLD**, about 0.23× protobuf
(decode 19.1 → 5.95 µs, 108 k Ir per round trip). Without fixes 2/3 the same map runs at
41.6–42.4 on the unmodified corelib, so they only close the semantic gaps and cost nothing.

Tried and dropped: caching the `on_field`/`on_schema_bound` functions per bind (**−5 %**). Proving that
no instance attribute shadows a hook means touching `visitor.__dict__`. On 3.14 that materialises
the instance dict and slows every `self._c`/`self._o` load in the hooks.

## Fix plan

- **Generator (sofabgen Python backend): the main fix.** Emit the schema as a module-level `Binding`
  tree plus one `Struct.unpack_from` readback, instead of the flat visitor. Scalar row
  `unsigned(id, at, value_max=…)` / `signed(…, value_min, value_max)`, array row
  `*_array(id, at, cap=count, count_at, elem_min/elem_max)`, `string/bytes(id, at, maxlen)`,
  `sequence(id, child)`, and for a repeated string/blob a child table of rows `0..count-1` with
  `.indexed(count)`. `decode()` becomes `Decoder(binding=…, words=bytearray(N*8), objects=[None]*M,
  <caps>, reassembly=MAX_FIELD_SPAN).feed(data)`, one `unpack_from(words)`, and positional
  dataclass construction: lists sliced by their `count_at` slots, strings from `objects`,
  `string_array` trimmed to its last present index. Scratch prototype:
  `/tmp/claude-0/regress/python/v9/gen/message.py` (`_EX_B`, `_example_decode`).
  The streaming `decoder()` gets the same table and reads back at COMPLETE.
  *Semantics:* in a 60 000-case differential fuzz against NEW, all outcomes and values were
  identical except 66 cases. In each of those, a root-scope scalar id arrives under an aggregate
  tag (for example u32 id 4 as an array). NEW's root `on_field` arm has no tag check for such a
  header, so it materialises the field and fails it on the receiver cap (SofaLimitError or
  SofaArgumentError). §7.3 says the header must be skipped, which the table does. That is a
  latent generator bug the change fixes. One difference is open: a second occurrence of
  `string_array` replaced the list in NEW and overwrites index slots in the table. The generator
  must decide whether to keep "replace", for example by giving each occurrence a fresh `objects` range.
  If the table route is deferred, the cheap interim step is the table-driven `on_field` body (+7 %).
- **Corelib PR (corelib-py):** fixes 1–3 as they stand, with tests for fixes 2 and 3 in both engines
  (`tests/test_elem_bound.py`, `tests/test_indexed.py`). No check was removed. Fix 3 moves the index-cap
  rule from a per-field Python hook into a miss-only C test.
- **Environment:** nothing. Same interpreter, flags and harness for OLD and NEW, and the protobuf
  row was untouched (182–187 MB/s).
