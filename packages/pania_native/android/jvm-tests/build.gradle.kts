// Runs the unit tests of the trail-recorder plugin's pure logic (GPS stats, off-track guard) on a plain
// JVM, so CI does not need the Android SDK or a generated Android project: `gradle test` in this folder.
// The classes that touch Android (service, notification, widget) are left out; the Context they need
// for persistence is a stub (src/main/kotlin/android).
plugins { kotlin("jvm") version "2.0.21" }

repositories { mavenCentral() }

dependencies {
    implementation("org.json:json:20240303")
    testImplementation("junit:junit:4.13.2")
}

val plugin = "../src"

sourceSets {
    main {
        kotlin.srcDir("$plugin/main/kotlin")
        kotlin.exclude("**/LiveNotification.kt", "**/LiveWidgetProvider.kt", "**/RecorderService.kt", "**/PaniaNativePlugin.kt", "**/SecretStore.kt", "**/AppInstaller.kt", "**/PointBuffer.kt")
    }
    test { kotlin.srcDir("$plugin/test/kotlin") }
}

tasks.test {
    testLogging {
        events("passed", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
