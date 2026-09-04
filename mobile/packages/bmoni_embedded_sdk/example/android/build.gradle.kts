allprojects {
    repositories {
        google()
        mavenCentral()
        // BMONISigner is hosted on Bkey's private GitHub Packages Maven
        // repo. Any app that depends on bmoni_embedded_sdk needs this
        // entry so Gradle can resolve `me.bkey.ip:bmonisigner:1.0.0`.
        //
        // Credentials must be supplied via either:
        //   * `bkey.gpr.user` / `bkey.gpr.key` Gradle properties
        //     (set in ~/.gradle/gradle.properties), or
        //   * `USERNAME` / `TOKEN` environment variables.
        maven {
            url = uri("https://maven.pkg.github.com/bkey-inc/package-distribution")
            credentials {
                username = providers.gradleProperty("bkey.gpr.user").orNull
                    ?: System.getenv("USERNAME")
                password = providers.gradleProperty("bkey.gpr.key").orNull
                    ?: System.getenv("TOKEN")
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
