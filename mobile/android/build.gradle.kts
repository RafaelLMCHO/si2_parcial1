allprojects {
    repositories {
        google()
        mavenCentral()
    }

    // Fix: play-services-tapandpay is a private Google library not available in
    // public Maven repos. It's only needed for Stripe Issuing push-provisioning
    // (tap-to-pay NFC). We exclude it so the release build succeeds.
    configurations.configureEach {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.google.android.gms" &&
                requested.name == "play-services-tapandpay") {
                // Force a version that doesn't exist so Gradle skips it gracefully
                // via the exclude below
            }
        }
        exclude(group = "com.google.android.gms", module = "play-services-tapandpay")
    }
}

buildscript {
    repositories {
        google()
        mavenCentral()
    }
    dependencies {
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:2.4.0")
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

    pluginManager.withPlugin("org.jetbrains.kotlin.android") {
        extensions.configure<org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension>("kotlin") {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
