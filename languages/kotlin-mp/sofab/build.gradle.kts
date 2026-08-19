// SofaBuffers impl of the kotlin-mp row. Everything except the runtime
// dependency is inherited from ../build.gradle.kts (shared with the protobuf
// impl); this file is deliberately only the dependency line.
kotlin {
    sourceSets.named("commonMain") {
        dependencies {
            // The version is passed by setup.sh, read off the corelib checkout it
            // just published to mavenLocal — so the harness can never build
            // against a stale release while the arena tracks the corelib tip.
            val v = providers.gradleProperty("sofab.version").orNull
                ?: error("run this build through languages/kotlin-mp/setup.sh (-Psofab.version)")
            implementation("org.sofabuffers:corelib-kotlin-mp:$v")
        }
    }
}
