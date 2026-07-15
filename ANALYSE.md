# ANALYSE — sofabgen v0.16.2 in der Arena

**Datum:** 2026-07-15 · **Branch:** `chore/sofabgen-0.16.2` · **Basis:** main @ `92e4708`
· **Ziel-Generator:** sofabgen **v0.16.2** (aktuelles Release) ·
**Corelibs:** alle frisch von `origin main` geklont (Stand 2026-07-15).

> **ZIEL (Vorgabe):** Die Arena soll mit dem *aktuellen* Generator + den *aktuellen*
> Corelibs laufen. Probleme dürfen **nicht** mit Workarounds in der Arena gefixt
> werden — nur die Tests/Treiber dürfen an den generierten Code angepasst werden.

---

## TL;DR

- **Alle 18 Targets laufen** mit sofabgen v0.16.2 + frischen Corelibs — Gate
  `sofab 434B` / `protobuf 494B` `ok`, alle byte-identisch, alle Status `OK`.
- Der zuvor gefundene **Zig-Blocker ist upstream gelöst** (nicht in der Arena):
  `corelib-zig` main stellte `decode()→Status` um; das released sofabgen v0.16.1
  hatte die Zig-Emission noch nicht angepasst → als **generator#120** gemeldet,
  gefixt in **sofabgen v0.16.2** (#121). Der Generator bindet den `Status` jetzt
  und mappt truncated Input auf `error.IncompleteMessage`.
- **Der Zig-Teil der Arena brauchte keine Handanpassung:** der Treiber
  `languages/zig/sofab/bench.zig` nutzt `pub fn main() !void` (inferred error set),
  sodass `try Example.decode(...)` die neue `error.IncompleteMessage` automatisch
  weiterreicht. Es änderte sich **nur** der regenerierte Code.
- **Kein Arena-Workaround** wurde eingebaut. Der einzige historische (Go-`bytes`)
  ist upstream-getrieben aus main entfernt (`92e4708`).
- **Footprint:** `corelib-c-cpp #77` senkt den C/C++-Codec **unter die
  Ausgangs-Baseline** (altes P1 damit aufgelöst).

**Einschätzung: OK — saubere Architektur, ein einziger Anpassungsvektor, keine
Workarounds. Das Ziel „läuft mit aktuellem Generator + aktuellen Corelibs" ist mit
v0.16.2 wieder vollständig (18/18) erfüllt.**

---

## Verlauf (warum v0.16.2)

| Schritt | Ergebnis |
|---|---|
| v0.16.1 + frische Corelibs | 17/18 ok; **`zig` bricht** — `corelib-zig` main (`0f861e4`) hat `decode()→Status`, released Generator ignorierte den Rückgabewert |
| Root-Cause dokumentiert + upstream gemeldet | **generator#120** (self-contained Bug-Report) |
| Upstream-Fix released | **sofabgen v0.16.2** / PR #121: `decode()` bindet `feed(chunk)→Status`, truncated → `IncompleteMessage` |
| v0.16.2 + frische Corelibs | **18/18 ok** — dieser Stand |

Das ist das vom Ziel geforderte Muster: **Problem upstream lösen, nicht in der Arena
umgehen.**

---

## Was v0.16.x seit main (v0.16.0) ändert

| Issue/PR | Backend | Änderung | Wire? |
|---|---|---|---|
| #113 / #114 (v0.16.1) | Go | Leeren Blob via `len()` statt `bytes.Equal`; `bytes`-Import entfällt | nein |
| #103 / #118 (v0.16.1) | C/C++ | Fixed-Profil reserviert `char[maxlen+1]` (NUL) | nein |
| #104 / #118 (v0.16.1) | C/C++ | Unbounded Field = harter Generate-Time-Fehler (feuert nicht: Message voll gebunden) | n/a |
| #112 / #118 (v0.16.1) | C++ | count-loses natives Scalar-Array → `std::vector` statt `std::array<T,0>` | nein |
| **#120 / #121 (v0.16.2)** | **Zig** | **`decode()` bindet `feed(chunk)→Status`; truncated → `error.IncompleteMessage`** | **nein** |

---

## Tabelle der nötigen Änderungen

| Datei | Art | Grund | Handgeschrieben? | Workaround? |
|---|---|---|---|---|
| `scripts/bootstrap.sh` | Pin `v0.16.0`→`v0.16.2` + Kommentar | Bump | ja (1 Zeile + Doku) | **nein** |
| `languages/zig/sofab/gen/src/message.zig` | **regeneriert** | #120: `DecodeError` + `Status`-Bindung + `IncompleteMessage` | nein | **nein** |
| `languages/c-embedded/sofab/gen/example.h` | **regeneriert** | #103 `char[32]→[33]`, `[64]→[65]` | nein | **nein** |
| `languages/cpp/sofab/gen/example.hpp` | **regeneriert** | #103 + #112 | nein | **nein** |
| `languages/cpp-embedded/sofab/gen/example.hpp` | **regeneriert** | #103 + #112 | nein | **nein** |
| `languages/go/sofab/message/types.go` | **regeneriert** | #113 `len()`, `bytes`-Import entfällt | nein | **nein** |

**Nicht geändert (0 Handanpassungen):** alle `bench.*`-Treiber (inkl.
`zig/sofab/bench.zig`), `footprint.sh`, `setup.sh`, `sofab/cfg.yaml`, Schema,
`state.json`, hardcodierte C/C++-Fills, nanopb-`message.options`.

> **Warum der Zig-Treiber nicht angepasst werden musste:** die generierte `decode()`
> wechselte den Fehlertyp von `sofab.Error!Example` auf
> `DecodeError!Example` (`= sofab.Error || error{IncompleteMessage}`). Da der
> Treiber ein *inferred* error set (`!void`) verwendet, absorbiert `try` die neue
> Fehlervariante ohne Codeänderung. Die unter „passe den Zig-Teil an" antizipierte
> Anpassung war de facto **null** — nur der Generator-Output ändert sich.

---

## Footprint (deterministisch, bare-metal link delta)

`corelib-c-cpp #77` verkleinert den C/C++-Codec unter die Ausgangs-Baseline
(Zig ist maxspeed, kein Footprint-Target):

| Target | Baseline (committet) | **jetzt (v0.16.2 + frische Corelibs)** | Δ vs Baseline |
|---|---|---|---|
| `c-cortex-m` sofab | 3616 | **3552** | −64 |
| `c-riscv` sofab | 3720 | **3688** | −32 |
| `cpp-cortex-m` sofab | 6696 | **6440** | −256 |
| `cpp-riscv` sofab | 6210 | **5896** | −314 |
| `rust-cortex-m` sofab | 6068 | 6096 | +28 |
| `rust-riscv` sofab | 6912 | 6936 | +24 |

Nur ein minimaler Rust-Zuwachs (+24…28 B) bleibt — legitime Kosten der
§7/LimitExceeded-Härtung in `corelib-rs`. Kein Fairness-Problem (gleiche Flags pro
Row; das Gate misst Wire, nicht Footprint).

**Throughput / README-Benchmark-Zahlen: bewusst NICHT angefasst** — sie werden auf
einer dedizierten Referenzmaschine erhoben. `results/RESULTS.txt` und die
README-Tabellen bleiben in diesem PR unverändert (Host-Rauschen dieses Containers
wäre irreführend).

---

## Architektur-Bewertung über alle Corelibs

**Sauber? → Ja.**

1. **Ein Anpassungsvektor, keine Meinungs-Divergenz.** Der Umstieg erzeugt
   *ausschließlich* Generator-Output-Diffs; jede Sprache konsumiert denselben
   Generator + dieselbe Corelib-Familie über eine einheitliche `setup.sh`/`bench.sh`.
   Keine widersprüchlichen per-Target-Fixes.

2. **Keine Codec-Workarounds.** Die einzigen „patch"-Stellen in den `setup.sh` sind
   deterministische Build-Glue (Cargo.toml/build.zig neu schreiben für die eigene
   `bench`-Binary + vendored Corelib-Pfad; Generator-Feature-Set verbatim). Die
   historischen Perf-`*.patch` sind seit sofabgen ≥ v0.6.0 upstream gefaltet; die im
   Repo auffindbaren `*.patch` liegen nur in `.devcontainer/.claude-config/jobs/…`
   (Job-Scratch), nicht im Arena-Quellbaum.

3. **Selbstheilung statt Workaround-Wucherung.** Zwei Belege in diesem Zyklus: der
   Go-`bytes`-Workaround wurde entfernt, *nachdem* #113 ihn überflüssig machte; und
   der Zig-Desync wurde upstream (generator#120→v0.16.2) statt in der Arena gelöst.

4. **Konsistente §7-Umsetzung über alle Backends.** Das dreiwertige Decode-Modell
   (COMPLETE/INCOMPLETE/INVALID) ist nun in allen Corelibs *und* deren
   Generator-Emissionen angekommen — Rust `try_decode`, C#/Java `TryDecode`/`tryDecode`,
   und mit v0.16.2 auch Zig (`DecodeError` + `IncompleteMessage`). Der
   sprachübergreifende Invariant — identischer Wire, identischer Fill, identische
   Flags pro Row — bleibt in allen 18 Targets gewahrt (Gate-Beweis).

*Grenze der Aussage:* Bewertung stützt sich auf den verhaltensbasierten Arena-Vertrag
(Wire-Gleichheit, Build/Link, Self-Check, Footprint/MB/s), nicht auf ein zeilenweises
Quell-Audit jeder Corelib.

---

## Werden die spezifizierten Testbedingungen noch eingehalten?

| Bedingung (`docs/BENCH.md` / `CLAUDE.md`) | Status |
|---|---|
| Referenz-Wire 434B/494B, byte-identisch pro Impl | ✅ alle 18 Targets `ok` |
| Vollständige Abdeckung aller Ziel-Sprachen | ✅ 18/18 (zig wieder dabei) |
| Vier Wire-Sync-Punkte unberührt (kein Wire-Change) | ✅ |
| Identische Optimierung pro Row (Flags/Profile/Tuning) | ✅ unverändert |
| Warm-up + Self-Check vor Messung, non-zero bei Mismatch | ✅ unverändert, alle bestehen |
| Runner ohne Impl-Registry | ✅ |
| Best-of-5-Throughput / deterministischer Footprint | ✅ Methodik unverändert |
| Kein per-Target-Codec-Patch / keine ISA-Pinnung | ✅ |

**Alle Testbedingungen eingehalten.**

---

## Problembericht

| # | Schwere | Problem | Ursache | Status |
|---|---|---|---|---|
| P0 | (war Blocker) | `zig` baute nicht: generierte `decode()` ignorierte `Status` | Generator↔Corelib-Desync (v0.16.1 vs corelib-zig main) | **GELÖST** upstream via generator#120 → **v0.16.2** (#121); nicht in der Arena umgangen |
| P1 | (war niedrig) | C-Footprint-Zuwachs | #103-NUL + Härtung | **GELÖST** durch `corelib-c-cpp #77` — Footprint unter Baseline |
| P2 | keine (Policy) | Throughput host-abhängig | langsamer Container | RESULTS.txt/README bewusst nicht angefasst; Zahlen auf Referenz-HW |
| P3 | keine (inert) | neue `max_dyn_*` cfg-Keys ungenutzt | Message voll gebunden | bewusst kein Opt-in |

**Keine offenen Blocker. Keine Workarounds nötig oder eingebaut.**

---

## Reproduktion

```bash
./scripts/bootstrap.sh                 # v0.16.2 + frische Corelib-Clones von main
RUNS=1 ./scripts/run_benchmark.sh
# → 18/18 Targets OK, Gate 434B/494B; zig baut und passt.
```
