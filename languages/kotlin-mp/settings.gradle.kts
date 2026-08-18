// One Gradle build holding BOTH impls of the kotlin-mp row as subprojects, so
// the compiler/toolchain settings they share live in exactly one place
// (../build.gradle.kts) instead of in two files that could drift apart — the
// arena's "identical optimization per row" rule, made structural.
rootProject.name = "kotlin-mp-arena"

pluginManagement {
    repositories {
        gradlePluginPortal()
        mavenCentral()
    }
}

dependencyResolutionManagement {
    // Declared centrally (and only here) so both impls resolve their runtime
    // from the identical repository list.
    repositories {
        // mavenLocal first: setup.sh publishes the corelib-kotlin-mp build under
        // test there, and it must win over any released artifact of the same
        // version (the arena tracks the corelib tip, not a release).
        mavenLocal()
        mavenCentral()
    }
}

include(":sofab", ":protobuf")
