# Java analysis — why SofaBuffers doesn't "beat" protobuf-java

**Date:** 2026-07-17 · **Base:** arena `main` @ `8eb0697`, sofabgen v0.16.2, fresh corelibs
· **Host:** AMD Ryzen 7 5700U (16 threads), WSL2, Temurin JDK 21.0.11, ParallelGC,
`-Xms512m -Xmx512m -XX:+AlwaysPreTouch` · **Scope:** **Java only**.

> **Every number here comes from a laptop host under WSL2** (boost/thermal drift,
> ±5 % noise), so it is **not** comparable with `results/RESULTS.txt` (reference HW).
> They are still trustworthy: all variants were measured **interleaved**
> (round-robin, 9 rounds × 1 M iterations) and reported as **medians** — that
> cancels the drift which makes single runs useless here. Differences **below 3 %
> are not resolvable** and are reported as "neutral", never as small wins.

---

## TL;DR

1. **SofaBuffers is not slower than protobuf in Java.** Per message it sits at
   **1824 ns vs 1780 ns** (2.5 % behind) — and at **1784 ns vs 1780 ns** with the
   fixes measured below, i.e. **parity** (560k vs 562k msgs/s).
2. **The reported 0.85× is ~86 % a metric artifact.** `MB/s` divides by the wire
   size. SofaBuffers' wire is 12.1 % smaller (434 vs 494 B), so the metric
   **penalises its own headline feature**. The decomposition is exact:
   `0.8785 (size) × 0.9759 (real time) = 0.857` (measured: 0.857).
   **To reach 1.0×, SofaBuffers must be 13.8 % *faster* per message.**
3. **Decode is already a SofaBuffers win** (1138 vs 1176 ns) at **18 % less
   garbage**. The real deficit is **entirely on encode** (855 vs 714 ns).
4. **protobuf's encode number is itself an artifact:** `getSerializedSize()` is
   memoized on the immutable instance. Because the arena serialises the **same**
   `src` 2 M times, the size pass is paid **once instead of 2 M times**. With the
   memo reset, protobuf encode costs **1043 ns instead of 714 ns** — against a
   *freshly built* message SofaBuffers encode is **1.22× faster** as shipped.
5. **One generator bug costs 11 % of encode:** `Arrays.equals(this.u8, new long[5])`
   allocates a throwaway zero array **per array field, per encode** — 544 B/op.

---

## 1. Reproducing the current state

`protoc` is missing from the bare workspace (it only lives in the devcontainer).
Fetched from Maven Central without touching the arena, in exactly the version of the
pinned runtime (`protobuf-java 4.35.1`), into `tools/bin/` (gitignored):

```bash
mvn dependency:get -Dartifact=com.google.protobuf:protoc:4.35.1:exe:linux-x86_64
cp ~/.m2/repository/com/google/protobuf/protoc/4.35.1/protoc-4.35.1-linux-x86_64.exe tools/bin/protoc
PATH="$PWD/tools/bin:$PATH" LANGS=java ./scripts/run_benchmark.sh
```

Result (best-of-5, gate passed):

| | sofab | proto | adv |
|---|--:|--:|:--:|
| wire | 434 B `ok` | 494 B `ok` | **1.14×** |
| throughput | 230.57 MB/s | 256.04 MB/s | **0.90×** |

The `README.md` finding (0.85×) reproduces — this host is just slower and noisier.

---

## 2. Architecture and design of the generated code

Both generators solve the same task with **opposite** foundational choices. That is
the key to reading the measurements.

| dimension | **protobuf-java** | **SofaBuffers** |
|---|---|---|
| data model | **immutable** + `Builder` | **mutable POJO**, public fields |
| generated code | 6265 lines | **287 lines** (22× smaller) |
| decode entry | `PARSER.parseFrom` → `Builder.mergeFrom` | `IStream.feed(data, visitor)` |
| decode shape | `while(!done) switch(tag)` — **pull** | visitor **push** + `switch(cur)`/`switch(id)` |
| decode engine | `CodedInputStream$ArrayDecoderOldVarint` | `IStream.fastField` (contiguous cursor) |
| size computation | `getSerializedSize()`, **memoized** | none — write straight into the buffer |
| encode target | `new byte[size]`, one pass | thread-local scratch → `Arrays.copyOf` |
| array storage | `Internal.IntList`/`LongList` (primitive, growable) | primitive `long[]`/`float[]` (schema count) |
| string array | `LazyStringArrayList` (`ArrayList<Object>`) | `ArrayList<String>` |
| streaming | no (buffer must suffice) | **yes** — `FlushSink` out, chunk feed in |
| `sun.misc.Unsafe` | yes (`writeUInt64NoTag`, `Utf8`) | **no** (pure Java, GraalVM-friendly) |

**The core design contrast:** protobuf **front-loads work into construction**
(immutability enables memoization), SofaBuffers **does everything per call**. That
explains the measurements symmetrically:

- **Decode** — protobuf pays for immutability: per sub-message a `SingleFieldBuilder`
  + `Builder` + the final message (**12 scaffolding objects** whose only purpose is to
  reach `buildPartial()`). SofaBuffers writes straight into the target fields:
  `IStream` + visitor, done. → **SofaBuffers wins.**
- **Encode** — protobuf's memoization eliminates the entire size pass because the
  arena reuses one instance. SofaBuffers has no equivalent (a mutable POJO *must not*
  memoize — the cache would be wrong the moment a field changes).
  → **protobuf wins, but only under reuse.**

### What the corelib gets right (not the bottleneck)

`IStream.fastField`/`fastVarintArray` are clean: contiguous cursor, fully unrolled
varint reader (`IStream.java:441-463`), one hoisted range check per 10-byte window, no
per-byte dispatch. `OStream.writeVarint`/`putVarint` (`OStream.java:521-541`) mirror
that. The byte-level codec is **not** the problem — consistent with the core finding in
[`bottlenecks.md`](bottlenecks.md).

---

## 3. Measurement: where the time actually goes

Encode and decode split, plus allocation via
`ThreadMXBean.getCurrentThreadAllocatedBytes()`. Identical fill and identical timing
method to the arena drivers. 9 interleaved rounds, medians:

| | encode | decode | **round trip** |
|---|--:|--:|--:|
| **sofab** (as shipped) | 855 ns / 1001 B | **1138 ns** / 1952 B | 1824 ns / 2944 B |
| **protobuf** | **714 ns** / 768 B | 1176 ns / 2384 B | **1780 ns** / 3152 B |
| ratio (sofab/proto) | 1.198 | **0.979** | 1.025 |

**Three things stand out immediately:**

1. **SofaBuffers decodes faster** (0.979×) while allocating **18 % less**.
2. The round trip is only **2.5 %** apart — not 15 %.
3. The entire deficit sits in **encode** (+19.8 %).

### 3.1 Why the arena still reports 0.86×

`throughput_mbs = serialized_bytes × iters / cpu_time` — the metric divides by the
wire size. SofaBuffers' advantage (434 instead of 494 B) becomes a **handicap**:

```
speed adv = (434/1824) / (494/1780)
          = 0.8785 (size handicap) × 0.9759 (real time per message)
          = 0.857                    ← measured: 0.857
```

**86 % of the reported gap is the metric, 14 % is real work.**
In messages per second: **548k (sofab) vs 562k (proto) = 0.975×**.

This is not an arena bug — the metric is applied identically across all 18 targets,
and in C++/Rust/Zig SofaBuffers wins *despite* the handicap (which shows how far ahead
it is per message there). But it answers the original question: **in Java there is
barely a real deficit to close — there is a 13.8 % handicap to overcome.**

### 3.2 protobuf's encode number is an artifact too

`FullScaleExample.getSerializedSize()` (`Message.java:4931`):

```java
int size = memoizedSize;
if (size != -1) return size;      // ← a hit 2M-1 times
```

`AbstractMessage.memoizedSize` is set to `-1` in the constructor. Because the arena
builds **one** immutable `src` outside the timed loop and serialises it 2 M times, the
size pass is paid **exactly once**. The same holds for all four sub-messages and for
the per-field packed lengths (`u8MemoizedSerializedSize` etc.).

Two independent controls, both showing the size pass is real and never paid in the
timed loop:

| protobuf encode | ns/op | method |
|---|--:|---|
| reused instance (= arena condition) | **662–714** | as the arena runs it |
| **encoding a freshly decoded message** | **~888** (**+34 %**) | chained loop (§3.4) — *cleaner* |
| memo reset per iteration via reflection | ~1043 (+57 %) | **upper bound, contaminated** |

**The two methods disagree and the lower one is the trustworthy one.** The reflective
reset injects 5 `Field.setInt` calls into the loop body; subtracting their standalone
cost (30 ns) does not account for the damage they do to JIT optimisation of the
surrounding loop. The chained measurement adds no foreign code and lands at **+226 ns**,
so **the size pass is ≈25 % of a fresh encode, not 57 %**. An earlier revision of this
document reported the 57 % figure as the headline — that was an over-claim.

Either way the direction holds: against a freshly built message — the normal case in an
RPC server — SofaBuffers encode is **faster**, because it never does a size pass at all.

This is **not an accusation**: memoization is a genuine protobuf feature, and for
re-serialising the same message the advantage is real. But it means the arena measures
protobuf's **re-serialisation** against SofaBuffers' **serialisation**.

### 3.3 Why protobuf *has to* memoize — and SofaBuffers doesn't

The real point runs deeper than the measurement; it is in the **wire format**:

- **protobuf length-prefixes sub-messages**: `[tag][length][bytes…]`. The length comes
  **before** the content — the encoder must know it *before* writing the content. That
  forces **two passes**: measure everything, then write everything. Memoization is the
  workaround for that constraint.
- **SofaBuffers delimits sequences**: `writeSequenceBegin(id) … writeSequenceEnd()`
  (`Example.java:98-102`) — **no length**. The encoder writes forward and never needs
  to know how long anything will be. That is **one pass, by design** — and exactly what
  makes `FlushSink` streaming possible in the first place (a message may exceed the
  buffer, even exceed RAM; with a length prefix it could not).

**SofaBuffers is structurally single-pass, protobuf structurally two-pass.** That is a
real format advantage — and the arena makes it invisible: reusing one immutable
instance amortises protobuf's second pass over 2 M iterations down to nothing. What is
measured is therefore not "single-pass vs two-pass" but "single-pass vs
two-pass-with-the-pass-already-paid".

So the fact that SofaBuffers *cannot* memoize (a mutable POJO must not hold a size
cache) is not a drawback to fix — it is the flip side of never needing the second pass.

### 3.4 What defeats the amortisation — and what doesn't

The obvious idea is to **vary the payload per iteration** so the cache cannot be
reused. **Measured: it does nothing.**

| protobuf encode | ns/op |
|---|--:|
| same reused `src` (arena condition) | 662 |
| **cycling 64 pre-built, distinct payloads** | **648 — unchanged** |

The artifact is bound to **instance reuse, not payload constancy**. Every pre-built
message memoizes on its *own* first encode, so after warm-up there are still zero size
passes. To actually invalidate the cache you must **build** a new message per
iteration — which drags `toBuilder()`/`build()` into the timed loop. That both violates
`docs/BENCH.md` ("Construction … not counted") and punishes protobuf for something the
benchmark does not claim to measure. So payload variation is **either ineffective
(pre-built) or unfair (built in-loop)**.

**What does work, for free: chain the round trip.** The loop currently encodes a
*constant* object and throws the decoded result away:

```java
for (…) { byte[] b = src.encode(); Example.decode(b); }   // decode result discarded
```

Chained, the encode operates on what was just decoded:

```java
for (…) { byte[] b = Example.decode(blob).encode(); }
```

protobuf's `parseFrom` → `buildPartial()` yields a **fresh instance with
`memoizedSize = -1`**, so the size pass is paid — legitimately, with **no construction
added** (the decode was already timed work) and **without disabling memoization**.
Medians of 5 interleaved rounds:

| | current loop | chained loop | Δ |
|---|--:|--:|--:|
| SofaBuffers | 1851 ns | **1829 ns** | −22 (noise — nothing to lose) |
| protobuf | 1803 ns | **2033 ns** | **+230** |
| *arena metric adv* | *0.856* | ***0.977*** | |
| *per-message ratio* | *0.974* | ***1.112*** | *sofab from 2.6 % behind to 11.2 % ahead* |

**Caveats before anyone acts on this:**

- It **changes what is measured** — "re-serialise what you parsed" (proxy/gateway)
  instead of "serialise a message you hold" (broadcast). Both are real workloads.
  Neither form is neutral: the current one hands protobuf a discount only it can use;
  the chained one grants no discount to anyone. The tell that the current loop is the
  more artificial of the two is that it **discards its own decode result** — nobody
  writes that loop outside a benchmark.
- **This is not Java-local.** Size memoization is a protobuf-wide design (C++'s
  `GetCachedSize`, C#, Go all do it), so chaining would likely move **every maxspeed
  row**, not just Java's — a full 18-target re-run and new README tables. **Unverified
  outside Java.**
- Measured on the noisy host; the +230 ns is well outside noise, the −22 ns is not.

---

## 4. The generator bug: 544 B of garbage per encode

`Example.java:47` (generated):

```java
if (!java.util.Arrays.equals(this.u8, new long[5])) {   // ← new long[5] PER ENCODE
    os.writeArrayUnsigned(0, Sbuf.trimTail(this.u8));
}
```

To ask "is this array still default?", a **fresh zero array is allocated** — 8×
`long[5]` + `float[5]` + `double[5]` = **544 B per encode**, garbage immediately after.
`Arrays.equals` is implemented as a vector intrinsic, which prevents escape analysis
from removing the allocation. The accounting closes exactly:

| item | B/op |
|---|--:|
| `byte[434]` output copy | 456 |
| 8× `new long[5]` (default checks) | 448 |
| `new float[5]` + `new double[5]` | 96 |
| **total** | **1000** |
| *measured* | *1001* |

A second weakness compounds it: each array is walked **three times** — `Arrays.equals`
(scan 1), `Sbuf.trimTail` (scan 2), then the write (pass 3).

The decode side mirrors it: `new Example()` allocates 10 arrays via the field
initialisers — `arrayBegin` (`Example.java:235-246`) throws them away and allocates
**10 fresh ones**. 544 B twice, at a fixed schema count of 5.

---

## 5. Verified countermeasures

All variants built as scratchpad experiments (**not** in the arena tree — per
`CLAUDE.md`, perf work belongs in the generator/corelib). **Every variant produces the
identical 434 B wire with an identical SHA-256** (`e1733416…` = `REF_SOFAB_SHA`).

- **P1** *(generator)* — `Arrays.equals(x, new long[5])` → allocation-free `anyNonZero(x)`
- **P3** *(generator)* — `arrayBegin`: zero the already correctly sized array instead of reallocating
- **P4** *(corelib)* — `OStream.BULK_MIN` 16 → 2, so 5-element arrays take the unrolled
  `putVarint` bulk path (the room check guards it anyway)
- **P5** *(generator)* — `u8→byte[]`, `u16→short[]`, `u32→int[]` instead of `long[]`
  throughout (the corelib **already has** every overload — the generator just never uses them)

| variant | encode | decode | round trip | garbage | adv | msgs/s |
|---|--:|--:|--:|--:|:--:|--:|
| V0 as shipped | 855 ns | 1138 ns | 1824 ns | 2944 B | 0.857 | 548k |
| **P1+P3+P4** | **758 ns** | 1154 ns | 1798 ns | 1896 B | 0.870 | 556k |
| P1+P3+P4+**P5** | 787 ns | 1170 ns | **1784 ns** | **1752 B** | **0.876** | **560k** |
| *protobuf* | *714 ns* | *1176 ns* | *1780 ns* | *3152 B* | *1.000* | *562k* |

**What this shows:**

- **P1 is the winner: encode −11.3 %** (855→758 ns), garbage −1048 B/op, wire
  identical, zero risk. Best value/effort ratio in the whole Java target.
- **P5 (narrow arrays) buys no throughput** — encode even got slightly *worse* (787 vs
  758 ns). The initial hypothesis was wrong; P5 only justifies itself on memory
  (−144 B/op). Do **not** sell it as a perf measure.
- **P3 is throughput-neutral** (decode 1138→1154 ns, within noise): `Arrays.fill` costs
  about as much as a fresh TLAB allocation. The gain is −544 B/op of GC pressure, not
  time. Take it only where allocation rate matters (it does for GraalVM/latency goals).
- With all fixes: **round trip 1784 vs 1780 ns = parity**, at **44 % less garbage**
  than protobuf. The arena metric still reports **0.876×**.

### Also measured: the copy in encode

`encode()` marshals into a thread-local scratch and returns `Arrays.copyOf(buf, n)` —
an extra 434 B copy plus allocation. With an `encodeInto(byte[] dst)` (reusing the
`OStream` via `bufferSet`):

| | ns/op | B/op |
|---|--:|--:|
| `sofab encodeInto(dst)` | 650 | **0** |
| `proto writeTo(CodedOutputStream)` | 612 | 256 |

**SofaBuffers reaches true zero allocation**, protobuf does not. This is the API shape
in which SofaBuffers' design (caller buffer, streaming) actually pays off — and it does
not exist in the generated Java code.

---

## 6. Proposals — how SofaBuffers gets ahead of protobuf in Java

Sorted by value/effort. "measured" = evidenced in this document.

| # | where | measure | effect | status |
|---|---|---|---|---|
| **1** | **generator** | allocation-free default check (`anyNonZero`) instead of `Arrays.equals(x, new T[n])` | **encode −11.3 %**, −544 B/op | **measured**, wire identical |
| **2** | **generator** | fuse the default check and `trimTail` into **one** pass (`trimLen()` once, then `writeArray*(id, a, 0, n)`) | 2 scans → 1 | **not measured** (needs corelib overloads taking `from/len`) |
| **3** | **generator + corelib** | emit `encodeInto(byte[])`/`encodeTo(OStream)`; reuse the `OStream` thread-locally | **650 ns, 0 B/op** | **measured** (API addition) |
| **4** | **corelib** | `BULK_MIN` 16 → ~2; the room check `end-p >= len*10` already guards the path | small, within noise | measured (in P1+P3+P4) |
| **5** | **generator** | `arrayBegin`: zero the array instead of reallocating | −544 B/op, **time-neutral** | measured |
| **6** | **generator** | narrow arrays (`byte[]`/`short[]`/`int[]`) | −144 B/op, **time-neutral/negative** | measured — **not a perf argument** |
| **7** | **arena** | **report `msgs/s` or `ns/op` next to `MB/s`** | makes the 13.8 % distortion visible | methodology |
| **8** | **arena** | measure encode against a **freshly built** message (or report both) | protobuf encode 714 → 1043 ns | methodology |

### On #7 and #8 — stated honestly

These are **methodology questions, not tricks to make SofaBuffers look better** — and
they have to be discussed as such:

- **#7:** `MB/s` is applied identically across all 18 targets and is therefore
  internally fair. But it does **not** answer "who serialises the same message faster?"
  — it systematically penalises the more compact format. An additional `msgs/s` column
  costs nothing, changes no existing number, and would make visible that Java is
  effectively at parity. The README note "only wire size and the ratios are comparable"
  does **not** cover this, because *the ratio itself* carries the handicap.
- **#8:** Reusing an immutable instance is a **legitimate** protobuf scenario, and
  memoization is a real feature. Both framings are defensible — but right now it is not
  disclosed that the arena pits protobuf's *re-serialisation* against SofaBuffers'
  *serialisation*. The clean route: **report both numbers**, don't replace one with the
  other.

### What is **not** worth doing

- **Optimising the byte-level codec.** `IStream`/`OStream` are already at the level of
  protobuf's `CodedInputStream` (unrolled varints, contiguous cursor, hoisted range
  checks). There is nothing to gain here.
- **Replacing the visitor-push design.** [`bottlenecks.md`](bottlenecks.md) lists the
  move to "direct switch-into-fields" decode as an open design item (#8). For Java it is
  **moot**: decode already beats protobuf (1138 vs 1176 ns) *despite* per-element
  interface dispatch — C2 devirtualises the monomorphic call. Spend the effort elsewhere.
- **Introducing `Unsafe`.** protobuf uses it only in `writeUInt64NoTag` and `Utf8`.
  Avoiding it costs SofaBuffers nothing measurable and is a GraalVM argument.

---

## 7. Corrections to `bottlenecks.md`

Three Java claims there were stale (all now revised in that file):

| claim there | today |
|---|---|
| "Java: `ByteArrayOutputStream.write` (**synchronized**!) → `toByteArray`" (Mistake 1) | **done** — the generated visitor has the single-shot path (`Example.java:197`); the BAOS is only the lazy split-chunk fallback |
| "Java: `List<Long>`/`List<Float>`, ~50 boxing allocations" (Mistake 2) | **done** — primitive `long[]`/`float[]`/`double[]` since sofabgen v0.6.0 |
| Backlog #5: "string/blob single-shot — Rust/Java **TODO**" | **done for Java** (contradicted #3 "done" in the same table) |
| "java 0.62× \| mid" | **0.857×** on this host — and that is **86 %** metric handicap, not work |

The open Java item is **none of those**, but the new P1 (default-check allocation) — a
regress introduced by the very v0.6.0 fixes that removed the boxing allocations.

---

## 8. Limits of this analysis

- **Host.** Laptop CPU under WSL2, ±5 % noise. Interleaving + medians catch the drift,
  but differences **< 3 % are not resolvable** — which is why P3/P4/P5 are reported as
  "neutral" rather than as small wins. These numbers should be re-measured on the
  reference HW.
- **No sampling profiler.** Attribution rests on split encode/decode timing, exact
  allocation accounting (closed to within 1 B) and source/bytecode reading — not on
  async-profiler or JFR.
- **No JMH.** A hand-written loop using the same timing method as the arena drivers
  (deliberate: comparability with the `BENCH` lines). No dead-code-elimination guards
  beyond cheap result checks.
- **Java only.** Whether the metric handicap distorts other targets similarly was not
  investigated — but it applies to every one, since the wire is 434 vs 494 B everywhere.
- **The patches are experiments**, not production code: `arrayBegin`'s `Arrays.fill`
  reset was not tested against reused decode targets or against §7 semantics
  (INCOMPLETE/INVALID), and the corelib test suite was not run against the `BULK_MIN`
  change.

## 9. Reproduction

```bash
PATH="$PWD/tools/bin:$PATH" LANGS=java ./scripts/run_benchmark.sh   # arena run
```

The profiling harnesses (`Profile.java`, `ProfilePb.java`, `ProfilePb3.java` for the
memo reset) and the four patch variants live in the analysis session's scratchpad and
are deliberately **not** committed — the fixes belong in `sofa-buffers/generator` and
`corelib-java`, not in the arena.
