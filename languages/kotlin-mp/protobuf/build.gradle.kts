// Protobuf baseline of the kotlin-mp row: Square Wire, the protobuf
// implementation that generates Kotlin Multiplatform sources directly (no Java
// classes, no protobuf-java under the hood) and whose runtime is itself a KMP
// library. Everything except this dependency is inherited from
// ../build.gradle.kts, shared with the sofab impl.
//
// This version line is the SINGLE source of truth for Wire in this row:
// setup.sh reads it back out to fetch the matching wire-compiler CLI, so the
// generator and the runtime can never drift apart (and Renovate can bump both
// by editing one line).
kotlin {
    sourceSets.named("commonMain") {
        dependencies {
            implementation("com.squareup.wire:wire-runtime:5.3.3")
        }
    }
}
