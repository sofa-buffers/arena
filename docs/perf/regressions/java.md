# Java throughput "regression" (2026-09): no code regression, run-to-run variance

Target `languages/java`, corelib-java `a00e05a`, sofabgen `0.0.0-20260918072500-d865b9213550`,
OpenJDK 25.0.4 (`default-jdk`). Measured 2026-09-18 on the 16-core WSL2 box, with the
`bench.sh` flags unchanged (`-XX:+UseParallelGC -Xms512m -Xmx512m -XX:+AlwaysPreTouch`),
2M iterations, unpinned like `bench.sh`, and 7 interleaved rounds. Every variant emitted
the 434 B reference wire (`e1733416…9d9d`) and passed both self-checks. protobuf
(`e8d391d9…`, 494 B) was not touched.

## Reproduced: OLD and NEW are the same

| variant | sofab best MB/s | msg/s | median MB/s |
|---|--:|--:|--:|
| OLD: arena `1971be6` generated code (with its own `Sbuf.java`) + corelib `54215f4` (the tip before `810cb4c`) | 291.0 | 670 k | 280.4 |
| NEW: HEAD generated code + corelib `a00e05a` | 295.3 | 680 k | 287.7 |
| protobuf-java (unchanged) | 259.9 | 526 k | 248.0 |

NEW is **not slower** than OLD. It is +1.5 % on best and +2.6 % on median, which is
inside this box's ±3–5 % spread between rounds. The sofab/protobuf ratio is 1.29× msg/s,
exactly what the README reports. The apparent −8 % on **both** sides comes from comparing
different measurement runs, not from anything in the code:
- The README's 312.8 / 276.7 does not even match `results/RESULTS.txt` at the same commit
  `1971be6`, which says 297.98 / 267.23.
- Today's single-run 289.2 / 254.6 falls inside the OLD and NEW spread measured above.

**What I checked on the harness and environment side:**
- **Harness.** `git diff 1971be6 HEAD` shows `Bench.java`, `setup.sh`, `bench.sh`,
  `versions.sh` and the protobuf project are identical. Only `sofab/gen/**` changed
  (`Sbuf.java` moved into the corelib, and `Main.java` grew). The timed region is identical.
- **JVM.** The Dockerfile had `default-jdk` on Ubuntu 26.04 then and still does now, so the
  runtime was JDK 25 at both points (its comment names 25.0.3; 25.0.4 is installed now).
  25.0.3 is no longer installable here, so that patch step could not be A/B'd. Corelib
  `a00e05a` "java-jdk to v25" only changes corelib CI.
- **JDK 21 as a control** (same jars, 4 interleaved rounds): sofab 280.7 vs 286.8 on 25, and
  protobuf 249.9 vs 258.7. JDK 25 is not the slower runtime.
- **The official `harness.jar`** (Maven-assembled) runs at the same speed as my scratch
  `javac` builds: 290.1 vs 291.8.
- **Measurement pitfall.** `taskset -c 2` (one core) is not usable for this target. C2 and
  the GC then share the core with the timed loop: protobuf falls to 167–199 MB/s and
  sofab to 242–255. `-c 2-5` is also slower and no less noisy than unpinned.

Because there is no regression, there was nothing to bisect. The corelib suspects
(`810cb4c`, `54215f4`, `5e30f9d`/`f30112a`, `e7b5454`/`5910ca0`, `5c744bb`) are covered by
the OLD→NEW comparison, which includes all of them and shows no loss.

## Hot path of NEW (async-profiler 4.1, `event=itimer`, 6M iterations)

The round trip splits into 57 % decode, 33 % encode and 10 % JIT/GC. No single hot spot
stands out. The top self-time entries are:
- `OStream.putVarint`: 9.6 %
- `IStream.decode`: 7.1 %
- `unsignedElements`: 4.8 %
- `ExampleVisitor.arrayBegin`: 4.8 %. This is the allocation of the ten result arrays.
- `fastFixlenScalar`: 4.2 %
- `Utf8.valid`: 4.1 %
- `String.<init>`: 4.1 %
- `gather7`: 4.1 %

I checked specifically for:
- duplicated work
- UTF-8 validated twice
- per-field allocation
- repeated cap checks
- dispatch

These are the findings:
1. **UTF-8 scanned twice on decode.** `Utf8.valid` walks the payload byte by byte, then
   `new String(…, UTF_8)` scans it again. Both scans are cheap for these 10–55 B strings.
2. **Generated visitor methods too large to inline** (`-XX:+LogCompilation`). C2 reports
   `ExampleVisitor::unsigned (402 B)` and `signed (412 B)` as *hot method too big*
   (FreqInlineSize is 325), so the 8 scalar fields cost one non-inlined call each. The bulk
   of those bytes is the `afill` array-element `switch`, which the bulk path never
   reaches for this message.
3. Encode: `Example::serialize` hits `NodeCountInliningCutoff`, so `putVarint`,
   `writeSequenceBeginLazy/End` and `writeString` are called rather than inlined. This was
   already the case in OLD.
4. fp32/fp64 arrays get no bulk destination (`armBulk` only fills `byte/short/int/long[]`),
   so each of those 10 elements is one visitor call. That costs under 1 % in the profile.

## Prototyped fixes, measured end-to-end (same 7 interleaved rounds as the table)

| # | change | where | best / median MB/s | verdict |
|---|---|---|--:|---|
| — | NEW, unmodified | — | 295.3 / 287.7 | — |
| 1 | `028e89d`: `Utf8.valid` skips ASCII runs 8 bytes at a time; an all-ASCII payload is materialized through ISO-8859-1 (a plain Latin-1 copy, no second scan). Rules and their order are unchanged. | corelib PR | 296.9 / 288.4 | **noise** (+0.5 %) |
| 2 | Generated `unsigned/signed/fp32/fp64`: move the `if (afill != 0) { … }` element switch into a private `<kind>Element(value)` helper. `unsigned` and `signed` then drop below 325 B and C2 inlines them into `IStream.decode` (confirmed in the compile log). Hand-edited scratch copy. | generator | 298.5 / 290.9 (1+2) | **noise** (+1 %) |

corelib-java `mvn test` passes 1571/0/0 on `028e89d`. That run covers the 131-vector shared
suite, the skip matrix, §6.2.1 header limits, §6.3 terminal refusal and strict UTF-8.

## Fix plan

- **Environment:** nothing to change. The README's old number and today's single run
  come from different runs. Re-baseline with a full `RUNS=5` run before calling any Java
  delta. On this box, a Java delta under about 4 % in a single run is noise.
- **Corelib PR (optional):** `028e89d` on branch `perf/arena-regression-2026-09`
  (local, not pushed). It is correct and cheaper per string, but the gain is not
  measurable on this message.
- **Generator (optional, sofabgen Java backend):** emit the armed-array element store as a
  separate private method, so that each scalar visitor callback stays below
  `FreqInlineSize`:
  ```java
  public void unsigned(int id, long value) {
      if (afill != 0) { unsignedElement(value); return; }
      …scalar routing only…
  }
  private void unsignedElement(long value) { afill--; switch (atgt) { … } }
  ```
  The inlining is verified in the compile log; the throughput gain is within noise here.
  Schemas with many scalar fields should benefit more.
- **Not pursued:** fp32/fp64 bulk destinations (a corelib and generator change for under
  1 % here) and the `NodeCountInliningCutoff` on encode (unchanged since OLD).
