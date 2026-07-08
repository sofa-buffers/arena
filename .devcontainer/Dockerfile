FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

# =============================================================================
# SofaBuffers Arena — multi-language dev environment.
#
# The Arena builds, for EVERY language, a SofaBuffers target and a Protocol
# Buffers target that encode+decode the same message, then compares them. So the
# image ships a full toolchain per language plus both serialization stacks:
#
#   build-essential cmake      C/C++ targets + binutils `size`
#   protobuf-compiler          protoc — protobuf codegen for C++, Java, C#, Go...
#   libprotobuf-dev            C++ protobuf runtime/headers (protoc-cpp target)
#   protobuf-c-compiler        protoc-c + libprotobuf-c — the C protobuf target
#   libprotobuf-c-dev
#   python3 + venv + pip       Python target + grpcio-tools protobuf compiler
#   default-jdk + maven        Java target (SofaBuffers corelib-java + protobuf-java)
#   (Go tarball)               Go target — official 1.25.x baked below
#                              (apt's golang-go is 1.22, too old for protobuf-go v1.36)
#   (rustup)                   Rust target (SofaBuffers corelib-rs + prost); adds
#                                thumbv7em/riscv32imac std libs for the no_std
#                                staticlibs of the rust bare-metal footprint targets
#   (dotnet 9)                 C# target (SofaBuffers corelib-cs + Google.Protobuf)
#   (nodejs)                   TypeScript target (corelib-ts + protobufjs) + Claude Code
#   (bun)                      typescript-bun target — the same TS codec run on
#                                Bun's JavaScriptCore engine (Node runs it on V8)
#   gcc-arm-none-eabi          bare-metal Cortex-M cross toolchain (c/cpp/rust-
#     + libnewlib + libstdc++    cortex-m footprint targets: --gc-sections
#                                link-delta builds; binaries are never executed)
#   gcc-riscv64-unknown-elf    bare-metal RISC-V cross toolchain (c-riscv +
#     + picolibc                 rust-riscv targets, rv32imac multilib; ships no
#                                bare-metal libstdc++ — hence xpack below)
#   (xpack riscv-none-elf-gcc) bare-metal RISC-V toolchain WITH libstdc++
#                                (cpp-riscv target; newlib, rv32imac default)
#   valgrind, time             optional CPU-independent / RSS measurement helpers
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl wget unzip git jq time pkg-config \
    build-essential cmake make \
    valgrind \
    protobuf-compiler libprotobuf-dev libprotoc-dev \
    protobuf-c-compiler libprotobuf-c-dev \
    gcc-arm-none-eabi libnewlib-arm-none-eabi libstdc++-arm-none-eabi-newlib \
    gcc-riscv64-unknown-elf picolibc-riscv64-unknown-elf \
    python3 python3-venv python3-pip python3-dev \
    default-jdk maven \
    && rm -rf /var/lib/apt/lists/*

# --- Rust (rustup, stable) ----------------------------------------------------
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:/usr/local/dotnet:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --profile minimal --default-toolchain stable \
    && rustup target add thumbv7em-none-eabihf riscv32imac-unknown-none-elf \
    && rustc --version

# --- .NET SDK 9 ---------------------------------------------------------------
ENV DOTNET_ROOT=/usr/local/dotnet \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1
RUN curl -sSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh \
    && chmod +x /tmp/dotnet-install.sh \
    && /tmp/dotnet-install.sh --channel 9.0 --install-dir /usr/local/dotnet \
    && rm /tmp/dotnet-install.sh \
    && dotnet --version

# --- Go (official toolchain) --------------------------------------------------
# apt's golang-go on Ubuntu 24.04 is 1.22; protoc-gen-go v1.36 and the Go target's
# generated go.mod need >= 1.23 (it pins `toolchain go1.25.11`). Bake the matching
# 1.25.x so the build needs no GOTOOLCHAIN auto-download (works offline /
# GOTOOLCHAIN=local). arch derived so the image builds on amd64 and arm64.
ENV PATH=/usr/local/go/bin:$PATH
RUN GO_VERSION=1.25.11 && ARCH="$(dpkg --print-architecture)" \
    && curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-${ARCH}.tar.gz" -o /tmp/go.tgz \
    && tar -C /usr/local -xzf /tmp/go.tgz \
    && rm /tmp/go.tgz \
    && go version

# --- xpack riscv-none-elf-gcc (bare-metal RISC-V C++ toolchain) ---------------
# Ubuntu's gcc-riscv64-unknown-elf ships picolibc but NO bare-metal libstdc++,
# so the cpp-riscv footprint target uses the xpack distribution (newlib +
# libstdc++; rv32imac/ilp32 is its default multilib). GCC 13.4 — same series as
# the apt cross compilers. Pinned; arch derived (x64/arm64).
ENV PATH=$PATH:/opt/xpack-riscv-none-elf-gcc-13.4.0-1/bin
RUN XPACK_V=13.4.0-1 && case "$(dpkg --print-architecture)" in \
        amd64) XA=x64;; arm64) XA=arm64;; *) XA=x64;; esac \
    && curl -fsSL "https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack/releases/download/v${XPACK_V}/xpack-riscv-none-elf-gcc-${XPACK_V}-linux-${XA}.tar.gz" \
        -o /tmp/xpack-riscv.tgz \
    && tar -C /opt -xzf /tmp/xpack-riscv.tgz \
    && rm /tmp/xpack-riscv.tgz \
    && riscv-none-elf-g++ --version | head -1

# --- protoc-gen-go (Go protobuf plugin) --------------------------------------
ENV GOPATH=/root/go PATH=/root/go/bin:$PATH
RUN go install google.golang.org/protobuf/cmd/protoc-gen-go@latest

# --- GitHub CLI ---------------------------------------------------------------
RUN mkdir -p -m 755 /etc/apt/keyrings \
    && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
    && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# --- Node.js LTS + Claude Code ------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/* \
    && npm install -g @anthropic-ai/claude-code

# --- Bun (JavaScriptCore runtime for the typescript-bun target) ---------------
# Same generated TypeScript codec as the `typescript` (Node/V8) target, run on
# Bun's JavaScriptCore engine so the arena can compare the two JS runtimes.
# Installed system-wide (BUN_INSTALL) so every user/shell finds it on PATH.
ENV BUN_INSTALL=/usr/local/bun PATH=/usr/local/bun/bin:$PATH
RUN curl -fsSL https://bun.sh/install | bash \
    && bun --version

WORKDIR /workspace

# One-time project bootstrap (sofabgen + python protobuf venv) is done at run
# time by scripts/bootstrap.sh, then ./scripts/run_benchmark.sh runs the Arena.
CMD ["/bin/bash"]
