import com.android.build.gradle.internal.crash.afterEvaluate
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinVersion
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

allprojects {
    repositories {
        google()
        mavenCentral()
    }
    subprojects {
        afterEvaluate {
            if (plugins.hasPlugin("com.android.application") ||
                            plugins.hasPlugin("com.android.library")
            ) {
                extensions.findByType(com.android.build.gradle.BaseExtension::class.java)?.let {
                        androidExt ->
                    androidExt.compileSdkVersion = "android-35"
                    androidExt.ndkVersion = "28.2.13676358"
                    androidExt.compileOptions.sourceCompatibility = JavaVersion.VERSION_17
                    androidExt.compileOptions.targetCompatibility = JavaVersion.VERSION_17

                    if (androidExt.namespace == null) {
                        androidExt.namespace = project.group.toString()
                    }

                    if (androidExt.buildFeatures.buildConfig == null) {
                        androidExt.buildFeatures.buildConfig = true
                    }

                    project
                            .fileTree(project.projectDir) { include("**/AndroidManifest.xml") }
                            .forEach { manifestFile ->
                                var manifestContent = manifestFile.readText()
                                if (manifestContent.contains("package=")) {
                                    println("Removing package attribute from ${manifestFile}")
                                    manifestContent =
                                            manifestContent.replace(Regex("package=\"[^\"]*\""), "")
                                    manifestFile.writeText(manifestContent)
                                }
                            }
                }
            }
        }
    }
}

allprojects {
    tasks.withType<JavaCompile> {
        sourceCompatibility = JavaVersion.VERSION_17.toString()
        targetCompatibility = JavaVersion.VERSION_17.toString()
        options.compilerArgs.plusAssign("-Xlint:unchecked")
        options.compilerArgs.plusAssign("-Xlint:deprecation")
    }
    tasks.withType<KotlinCompile>().configureEach {
        compilerOptions {
            apiVersion.set(KotlinVersion.KOTLIN_1_8)
            languageVersion.set(KotlinVersion.KOTLIN_1_8)
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()

rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}

subprojects { project.evaluationDependsOn(":app") }

tasks.register<Delete>("clean") { delete(rootProject.layout.buildDirectory) }
