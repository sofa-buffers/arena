# Canonical message state

Every benchmark target — every language, both `sofab` and `protobuf` — fills the
`FullScaleExample` message with **exactly** these values. The machine-readable
form is [`state.json`](state.json) (SofaBuffers jsonable shape); this file is the
human reference used when hand-filling (e.g. the protobuf targets).

If a target's serialized bytes don't match the reference SHA, its fill drifted.

- Reference **sofab** wire: **434 bytes**, `sha256 e1733416c987b04faea747b7cdd8f2913934f45d4a77453f58c9e3ef12e29d9d`
  (since sofabgen v0.11.0 every backend sparsely omits the one empty string in `string_array`,
  so all sofab targets — including the C object API — now share this single wire; before v0.11.0
  only C was 434 B and the rest were 436 B)
- Reference **protobuf** wire: **494 bytes**, `sha256 e8d391d98bc54c0ec24fff19ec96bb52114d9d34aed7d0f0023a0317bcfa5b3d`

## Top-level scalars (`FullScaleExample`)

| field | type | value |
|---|---|---|
| `u8`  | uint8  | `200` |
| `i8`  | int8   | `-100` |
| `u16` | uint16 | `50000` |
| `i16` | int16  | `-20000` |
| `u32` | uint32 | `3000000000` |
| `i32` | int32  | `-1000000000` |
| `u64` | uint64 | `10000000000000` |
| `i64` | int64  | `-5000000000000` |

## `nested` (`FullScaleSeqStruct`, field 10)

| field | type | value |
|---|---|---|
| `f32` | float  | `3.14` |
| `f64` | double | `3.14159265` |
| `str` | string | `"Hello, World!"` |
| `bytes_field` | bytes | `[0xDE, 0xAD, 0xBE, 0xEF]` |

## `arrays` (`FullScaleSeqStructOfArrays`, field 100) — every array has 5 elements

| field | type | values |
|---|---|---|
| `u8`  | uint32[] | `0, 64, 128, 191, 255` |
| `i8`  | int32[]  | `-128, -64, 0, 63, 127` |
| `u16` | uint32[] | `0, 16384, 32768, 49151, 65535` |
| `i16` | int32[]  | `-32768, -16384, 0, 16383, 32767` |
| `u32` | uint32[] | `0, 1073741824, 2147483648, 3221225471, 4294967295` |
| `i32` | int32[]  | `-2147483648, -1073741824, 0, 1073741823, 2147483647` |
| `u64` | uint64[] | `0, 4611686018427387904, 9223372036854775808, 13835058055282163711, 18446744073709551615` |
| `i64` | int64[]  | `-9223372036854775807, -4611686018427387904, 0, 4611686018427387903, 9223372036854775807` |

### `arrays.nested` (`FullScaleSeqStructOfFpArrays`, field 10)

| field | type | values |
|---|---|---|
| `fp32` | float[]  | `1, 2, 3, -FLT_MAX, FLT_MAX`  (`FLT_MAX = 3.4028234663852886e38`) |
| `fp64` | double[] | `1, 2, 3, -DBL_MAX, DBL_MAX`  (`DBL_MAX = 1.7976931348623157e308`) |

## `string_array` (`FullScaleSeqArrayOfStrings.strings`, field 200) — 5 strings

```
"Hello, Sofab!"
""
"1234567890"
"äöüÄÖÜß"
"This_is_a_very_long_test_string_with_!@#$%^&*()_+-=[]{}"
```
