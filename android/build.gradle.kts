group = "com.pusher.channels_flutter"
version = "1.0-SNAPSHOT"

buildscript {
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// NOTE: Flutter's "Built-in Kotlin" support (Flutter 3.47+) will eventually let
// AGP compile Kotlin sources without a plugin explicitly applying KGP. Once this
// project's minimum supported Flutter is bumped past that line, this can become:
//   if (com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt() < 9) {
//       apply(plugin = "org.jetbrains.kotlin.android")
//   }
// See https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-plugin-authors
plugins {
    id("com.android.library")
    id("kotlin-android")
}

android {
    namespace = "com.pusher.channels_flutter"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
    }

    defaultConfig {
        minSdk = 24
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    api("com.pusher:pusher-java-client:2.+")
    api("com.google.code.gson:gson:2.+")
}
