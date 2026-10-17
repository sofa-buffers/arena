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
	"syscall"

	"example.com/gen/message"
)

// cpuSeconds returns this process's CPU time (user+sys), not wall-clock
// (docs/BENCH.md rule 3) — the same helper as the protobuf side.
func cpuSeconds() float64 {
	var ru syscall.Rusage
	syscall.Getrusage(syscall.RUSAGE_SELF, &ru)
	return float64(ru.Utime.Nano()+ru.Stime.Nano()) / 1e9
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

	src := message.Example__New()
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

	// Warm-up self-check through the SAME entry point the timed loop uses, so it
	// validates the path that gets measured.
	dec := &message.Example{}
	if err := message.Example__TryDecode(blob, dec); err != nil {
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
	// it (issue #86) into a caller-owned MaxSize buffer hoisted out of the loop,
	// through the generated EncodeInto (the message's own encoder options, no
	// restated internals).
	//
	// The destination is hoisted too, through Example__TryDecode(data, out): it
	// Resets `out` itself and keeps the storage its slices and strings already
	// hold (the generated _spare members). Example__Decode would hand that back
	// per iteration and time the allocator instead of the codec. The protobuf
	// driver hoists its destination the same way for the same reason —
	// proto.Unmarshal already resets what it is handed (docs/BENCH.md rule 6).
	out := make([]byte, message.Example__MaxSize)
	var last []byte
	t0 := cpuSeconds()
	for i := 0; i < iters; i++ {
		message.Example__TryDecode(blob, dec)
		n, _ := dec.EncodeInto(out)
		last = out[:n]
	}
	cpu := cpuSeconds() - t0

	// Loop-path check: the last re-encode must be the reference wire.
	if !bytes.Equal(last, blob) {
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
