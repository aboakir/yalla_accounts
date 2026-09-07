// YALLA FACEBOOK AUTH JVM TARGET
// flutter_facebook_auth 7.1.2 compiles its Java sources for JVM 1.8.
// Keep only that plugin's Kotlin bytecode on the same target.
// The app module remains Java/Kotlin 11 as configured in android/app/build.gradle.kts.
subprojects {
    if (name == "flutter_facebook_auth") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions.jvmTarget.set(
                org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8
            )
        }
    }
}
allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
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
