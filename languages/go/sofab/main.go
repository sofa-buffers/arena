// SofaBuffers Go benchmark target.
//
// Encodes + decodes the canonical FullScaleExample message (schema/state.json)
// through the generated message.Example type, backed by the real corelib-go
// runtime. Prints one uniform BENCH line (see docs/BENCH.md).
//
// This file lives inside the generated module (module example.com/gen) as its
// own package so it can import the generated `message` package directly. It is
// NOT overwritten by re-running the generator.
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

	"example.com/gen/message"
)

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

	src := message.NewExample()
	if err := json.Unmarshal(data, src); err != nil {
		fmt.Fprintln(os.Stderr, "FAIL: sofab from-json:", err)
		return 1
	}

	// Warm-up round-trip + self-check (outside the timed region).
	blob, err := src.Encode()
	if err != nil {
		fmt.Fprintln(os.Stderr, "FAIL: sofab encode:", err)
		return 1
	}
	serialized := len(blob)
	sum := sha256.Sum256(blob)
	sha := hex.EncodeToString(sum[:])

	dec, err := message.DecodeExample(blob)
	if err != nil {
		fmt.Fprintln(os.Stderr, "FAIL: sofab decode:", err)
		return 1
	}
	reblob, err := dec.Encode()
	if err != nil || !bytes.Equal(reblob, blob) {
		fmt.Fprintln(os.Stderr, "FAIL: sofab round-trip self-check")
		return 1
	}

	iters := 1000000
	if v := os.Getenv("BENCH_ITERS"); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 {
			iters = n
		}
	}

	// Timed region: chained round trip — decode the reference wire, then re-encode
	// the freshly decoded message (issue #86). This is the proxy/transcode shape,
	// and it denies protobuf its once-per-instance serialized-size memo so encode
	// is measured on equal terms. sink keeps the re-encode from being optimized out
	// and doubles as a loop-path check (every re-encode is `serialized` bytes).
	sink := 0
	t0 := time.Now()
	for i := 0; i < iters; i++ {
		dec, _ := message.DecodeExample(blob)
		b, _ := dec.Encode()
		sink += len(b)
	}
	cpu := time.Since(t0).Seconds()

	if sink != serialized*iters {
		fmt.Fprintln(os.Stderr, "FAIL: sofab loop-path self-check")
		return 1
	}

	mbs := 0.0
	if cpu > 0 {
		mbs = float64(serialized) * float64(iters) / cpu / 1e6
	}
	fmt.Printf("BENCH lang=go impl=sofab serialized_bytes=%d iters=%d "+
		"cpu_time_s=%.6f throughput_mbs=%.2f sha256=%s\n",
		serialized, iters, cpu, mbs, sha)
	return 0
}
