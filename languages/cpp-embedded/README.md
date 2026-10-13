# cpp-embedded target

Embedded C++ arena: **SofaBuffers** (the `corelib-c-cpp` C++ wrapper) vs
**EmbeddedProto**. This is the embedded analog of the maxspeed `languages/cpp/`
target — same generator (`--lang cpp`), but the sofab config selects
`corelib: c-cpp`, so the generated typed header drives the header-only C++ facade
(`sofab/sofab.hpp`) over the corelib-c-cpp C core (`object.c`/`ostream.c`/
`istream.c`). No dynamic allocation is required on the encode path.

## Impls

| impl | codec | source |
| --- | --- | --- |
| `sofab` | SofaBuffers C++ wrapper of corelib-c-cpp | generated `sofab/gen/example.hpp` + `vendor/corelib-c-cpp` |
| `embeddedproto` | EmbeddedProto (protoc plugin, fixed-size, no malloc) | generated `embeddedproto/gen/message.h` + `vendor/EmbeddedProto/src` |

## EmbeddedProto is GPLv3 — build-time only, never redistributed

EmbeddedProto (https://github.com/Embedded-AMS/EmbeddedProto) is licensed under
the **GNU GPL v3.0**. `setup.sh` fetches it into `vendor/EmbeddedProto`, which is
**gitignored** (`/vendor/` in `.gitignore`) and **must never be committed**. It is
used strictly as a **build-time dependency**: its protoc plugin generates
`message.h` and its runtime `.cpp` files are compiled into the local `embeddedproto`
bench for measurement only. No EmbeddedProto source or object is redistributed by
this repository.

## Codegen

* **sofab**: `sofabgen --config sofab/cfg.yaml --lang cpp --in schema/message.sofab.yaml --out sofab/gen`
  (`cfg.yaml` is `targets: { cpp: { namespace: fullscale, corelib: c-cpp } }`).
* **embeddedproto**: `protoc --plugin=protoc-gen-eams -I embeddedproto/proto -I vendor/EmbeddedProto/generator --eams_out=embeddedproto/gen embeddedproto/proto/message.proto`.
  EmbeddedProto needs a compile-time bound for every repeated/string/bytes field
  (it never allocates). These are supplied by its custom field options in a **local**
  annotated copy of the schema (`embeddedproto/proto/message.proto`; the shared
  `schema/message.proto` is untouched):
  * `string str` → `[(EmbeddedProto.options).maxLength = 32]`
  * `bytes bytes_field` → `[(EmbeddedProto.options).maxLength = 4]`
  * every `repeated` scalar → `[(EmbeddedProto.options).maxLength = 5]`
  * `repeated string strings` → `[(EmbeddedProto.options).maxLength = 5, (EmbeddedProto.options).nestedMaxLength = 64]`

  The annotated proto also declares the signed `i8`/`i16`/`i32` fields as `int64`
  (not `int32`). Canonical protobuf sign-extends a negative `int32` to a 10-byte
  varint, whereas EmbeddedProto encodes `int32` in 5 bytes; a negative `int64` and
  a negative `int32` of equal value serialize to identical protobuf bytes, so this
  keeps the wire **byte-identical** to the reference protobuf output while
  preserving values and field numbers. The cost lands on EmbeddedProto: those
  fields (scalars and arrays) are stored as 64-bit `int64_t` instead of 32-bit.

## Build flags

Both impls compile with identical flags, including `-std=c++20` (EmbeddedProto
requires C++17 or later and builds cleanly under C++20; sofab's wrapper needs C++20).

## Run

```bash
./setup.sh      # fetch EmbeddedProto, generate + compile both benches (idempotent)
./bench.sh      # 2 BENCH lines + 2 FOOTPRINT lines
```

## Wire sizes

* `embeddedproto`: **494 bytes** — byte-identical to the reference protobuf wire
  (sha256 `e8d391d98bc54c0ec24fff19ec96bb52114d9d34aed7d0f0023a0317bcfa5b3d`).
* `sofab`: **434 bytes** — byte-identical to the reference SofaBuffers wire
  (sha256 `e1733416c987b04faea747b7cdd8f2913934f45d4a77453f58c9e3ef12e29d9d`).

## Footprint

`footprint.sh` reports an object-sum footprint for both codecs (C++ source libs,
no libc), consistent with `languages/c-embedded/footprint.sh`: each codec's translation
units are compiled with `-Os -DNDEBUG -ffunction-sections -fdata-sections` and the
`.text`/`.rodata`/`.data`/`.bss` sections are summed with `size -A`. Because both
codecs are header/template based, a tiny driver TU instantiates the encode/decode
surface (the analog of the C target's generated `example.o`); `bench.cpp` and
`sha256` are excluded.
