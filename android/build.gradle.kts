group = "com.koji_1009.app.qr_scanner_view"
version = "0.2.2"

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

plugins {
    id("com.android.library")
}

android {
    namespace = "com.koji_1009.app.qr_scanner_view"

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
    val cameraxVersion = "1.6.1"
    implementation("androidx.camera:camera-core:$cameraxVersion")
    implementation("androidx.camera:camera-camera2:$cameraxVersion")
    implementation("androidx.camera:camera-lifecycle:$cameraxVersion")
    implementation("androidx.camera:camera-view:$cameraxVersion")
    implementation("androidx.camera:camera-mlkit-vision:$cameraxVersion")
    implementation("androidx.lifecycle:lifecycle-runtime:2.10.0")
    implementation("androidx.lifecycle:lifecycle-process:2.10.0")

    // Both artifacts expose the same com.google.mlkit.vision.barcode API; only
    // where the model lives differs. Unbundled (default) resolves it through
    // Google Play services; bundled ships it inside the app, so devices
    // without Play services can scan and the first scan never waits for a
    // model download, at the cost of APK size.
    val useBundled = (project.findProperty("com.koji_1009.app.qr_scanner_view.useBundled") ?: "false")
        .toString()
        .toBoolean()
    if (useBundled) {
        implementation("com.google.mlkit:barcode-scanning:17.3.0")
    } else {
        implementation("com.google.android.gms:play-services-mlkit-barcode-scanning:18.3.1")
    }

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.mockito:mockito-core:5.14.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
}
