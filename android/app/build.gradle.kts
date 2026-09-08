import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
    id("com.google.devtools.ksp")
}

val localProperties = Properties()
val localFile = rootProject.file("local.properties")
if (localFile.exists()) {
    localFile.inputStream().use { localProperties.load(it) }
}
val notesApiUrl = localProperties.getProperty(
    "notesApiUrl",
    "https://notes-api.paperorg.com",
)
val playCloudProjectNumber = localProperties.getProperty("playCloudProjectNumber", "357171624667")

// Play App Signing expects the upload cert registered for this app
// (SHA1 D9:54:D4:…), which is ~/Documents/keys/paperorg-upload alias key0 —
// not the later unused paperorg-notes-upload.p12.
val uploadKeystore = file(
    localProperties.getProperty(
        "uploadKeystore",
        "${System.getProperty("user.home")}/Documents/keys/paperorg-upload",
    ),
)
val uploadKeystoreAlias = localProperties.getProperty("uploadKeystoreAlias", "key0")
val uploadKeystorePassword: String? = System.getenv("PAPERORG_UPLOAD_STORE_PASSWORD")
// The password is only present when Gradle is launched through secret_run.py, so
// every other build has to keep working without it rather than failing to configure.
val canSignRelease = uploadKeystore.exists() && !uploadKeystorePassword.isNullOrBlank()

android {
    namespace = "com.paperorg.notes"
    compileSdk = 36

    defaultConfig {
        applicationId = "com.paperorg.notes"
        minSdk = 26
        targetSdk = 36
        versionCode = 5
        versionName = "1.0.4"
        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        buildConfigField("String", "NOTES_API_URL", "\"$notesApiUrl\"")
        buildConfigField("long", "PLAY_CLOUD_PROJECT_NUMBER", "${playCloudProjectNumber}L")
    }

    signingConfigs {
        if (canSignRelease) {
            create("upload") {
                storeFile = uploadKeystore
                storePassword = uploadKeystorePassword
                keyAlias = uploadKeystoreAlias
                keyPassword = uploadKeystorePassword
            }
        }
    }

    buildTypes {
        release {
            if (canSignRelease) {
                signingConfig = signingConfigs.getByName("upload")
            }
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    testOptions {
        unitTests.isReturnDefaultValues = true
    }
}

dependencies {
    val composeBom = platform("androidx.compose:compose-bom:2024.12.01")
    implementation(composeBom)
    androidTestImplementation(composeBom)

    implementation("androidx.core:core-ktx:1.15.0")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    implementation("androidx.navigation:navigation-compose:2.8.5")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("com.google.android.material:material:1.12.0")

    implementation("androidx.room:room-runtime:2.6.1")
    implementation("androidx.room:room-ktx:2.6.1")
    ksp("androidx.room:room-compiler:2.6.1")

    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    implementation("com.google.android.play:integrity:1.4.0")
    implementation("com.android.billingclient:billing:9.1.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    testImplementation("org.json:json:20240303")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
