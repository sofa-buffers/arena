// kotlin-mp target: the shared half of both impls' build.
//
// Both codecs are Kotlin Multiplatform: their message sources live in
// `commonMain` (stdlib-only Kotlin, no JVM API in sight) and the benchmark
// driver — SHA-256, the process CPU clock, printf — sits in `jvmMain`, which is the platform
// the arena measures. Everything below is applied to BOTH subprojects from this
// one block, so neither impl can be compiled with a flag the other did not get.
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinMultiplatformExtension

plugins {
    kotlin("multiplatform") version "2.4.10" apply false
}

subprojects {
    apply(plugin = "org.jetbrains.kotlin.multiplatform")

    extensions.configure<KotlinMultiplatformExtension> {
        // Gradle itself runs on this JDK (its Kotlin DSL compiler cannot parse a
        // JDK 25 version string), so the toolchain is already present and nothing
        // is auto-provisioned. The bench then RUNS on the image's default JVM,
        // like every other JVM target here.
        jvmToolchain(21)

        jvm {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_21)
            }
        }

        sourceSets.named("commonMain") {
            // Generated codec sources (sofabgen / the Wire compiler), written by
            // setup.sh into the same relative path for both impls.
            kotlin.srcDir("gen/src/main/kotlin")
        }
    }

    // bench.sh runs the harness through a bare `java` command — no Gradle daemon
    // anywhere near the timed loop, and stdout stays clean enough for the runner
    // (which parses it). That needs the runtime classpath as a plain string, so
    // the build writes it out, exactly as corelib-kotlin-mp does for its own
    // benchmarks.
    tasks.register("benchClasspath") {
        val cp = files(tasks.named("jvmJar"), configurations.named("jvmRuntimeClasspath"))
        val out = layout.buildDirectory.file("bench-classpath.txt")
        inputs.files(cp)
        outputs.file(out)
        doLast { out.get().asFile.writeText(cp.asPath) }
    }
}
