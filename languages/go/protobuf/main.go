// Protobuf Go benchmark target.
//
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through protobuf-go's generated types. Same message, same state, same timed
// region as the SofaBuffers target. Prints one uniform BENCH line.
package main

import (
	"bytes"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"strconv"
	"time"

	"google.golang.org/protobuf/proto"

	pb "example.com/pbbench/gen"
)

type state struct {
	U8     uint32 `json:"u8"`
	I8     int32  `json:"i8"`
	U16    uint32 `json:"u16"`
	I16    int32  `json:"i16"`
	U32    uint32 `json:"u32"`
	I32    int32  `json:"i32"`
	U64    uint64 `json:"u64"`
	I64    int64  `json:"i64"`
	Nested struct {
		F32        float32 `json:"f32"`
		F64        float64 `json:"f64"`
		Str        string  `json:"str"`
		BytesField []byte  `json:"bytes_field"`
	} `json:"nested"`
	Arrays struct {
		U8     []uint32 `json:"u8"`
		I8     []int32  `json:"i8"`
		U16    []uint32 `json:"u16"`
		I16    []int32  `json:"i16"`
		U32    []uint32 `json:"u32"`
		I32    []int32  `json:"i32"`
		U64    []uint64 `json:"u64"`
		I64    []int64  `json:"i64"`
		Nested struct {
			Fp32 []float32 `json:"fp32"`
			Fp64 []float64 `json:"fp64"`
		} `json:"nested"`
	} `json:"arrays"`
	StringArray []string `json:"string_array"`
}

func build(s *state) *pb.FullScaleExample {
	return &pb.FullScaleExample{
		U8:  s.U8,
		I8:  s.I8,
		U16: s.U16,
		I16: s.I16,
		U32: s.U32,
		I32: s.I32,
		U64: s.U64,
		I64: s.I64,
		Nested: &pb.FullScaleSeqStruct{
			F32:        s.Nested.F32,
			F64:        s.Nested.F64,
			Str:        s.Nested.Str,
			BytesField: s.Nested.BytesField,
		},
		Arrays: &pb.FullScaleSeqStructOfArrays{
			U8:  s.Arrays.U8,
			I8:  s.Arrays.I8,
			U16: s.Arrays.U16,
			I16: s.Arrays.I16,
			U32: s.Arrays.U32,
			I32: s.Arrays.I32,
			U64: s.Arrays.U64,
			I64: s.Arrays.I64,
			Nested: &pb.FullScaleSeqStructOfFpArrays{
				Fp32: s.Arrays.Nested.Fp32,
				Fp64: s.Arrays.Nested.Fp64,
			},
		},
		StringArray: &pb.FullScaleSeqArrayOfStrings{
			Strings: s.StringArray,
		},
	}
}

func main() {
	os.Exit(run())
}

func run() int {
	statePath := os.Getenv("STATE_JSON")
	if statePath == "" {
		statePath = "/workspace/schema/state.json"
	}
	data, err := os.ReadFile(statePath)
	if err != nil {
		fmt.Fprintln(os.Stderr, "FAIL: read state:", err)
		return 1
	}
	var s state
	if err := json.Unmarshal(data, &s); err != nil {
		fmt.Fprintln(os.Stderr, "FAIL: protobuf state parse:", err)
		return 1
	}
	src := build(&s)

	mo := proto.MarshalOptions{Deterministic: true}

	// Warm-up round-trip + self-check (outside the timed region).
	blob, err := mo.Marshal(src)
	if err != nil {
		fmt.Fprintln(os.Stderr, "FAIL: protobuf marshal:", err)
		return 1
	}
	serialized := len(blob)
	sum := sha256.Sum256(blob)
	sha := hex.EncodeToString(sum[:])

	chk := &pb.FullScaleExample{}
	if err := proto.Unmarshal(blob, chk); err != nil {
		fmt.Fprintln(os.Stderr, "FAIL: protobuf unmarshal:", err)
		return 1
	}
	reblob, err := mo.Marshal(chk)
	if err != nil || !bytes.Equal(reblob, blob) {
		fmt.Fprintln(os.Stderr, "FAIL: protobuf round-trip self-check")
		return 1
	}

	iters := 1000000
	if v := os.Getenv("BENCH_ITERS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			iters = n
		}
	}

	// Timed region: encode + decode only. A fresh decode target per iteration
	// mirrors the sofab side (new object per decode) and avoids proto.Unmarshal's
	// merge-into-existing semantics appending to repeated fields.
	t0 := time.Now()
	for i := 0; i < iters; i++ {
		b, _ := mo.Marshal(src)
		dec := &pb.FullScaleExample{}
		proto.Unmarshal(b, dec)
	}
	cpu := time.Since(t0).Seconds()

	mbs := 0.0
	if cpu > 0 {
		mbs = float64(serialized) * float64(iters) / cpu / 1e6
	}
	fmt.Printf("BENCH lang=go impl=protobuf serialized_bytes=%d iters=%d "+
		"cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s\n",
		serialized, iters, cpu, mbs, sha)
	return 0
}
