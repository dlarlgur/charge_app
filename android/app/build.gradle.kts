import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("com.google.gms.google-services")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(keyPropertiesFile.inputStream())
}

android {
    namespace = "com.dksw.charge"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.dksw.charge"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        // 네이버 지도: gradle.properties에 NAVER_MAP_CLIENT_ID 없으면 아래 기본값 사용 (Dart Secrets와 동일하게)
        manifestPlaceholders["naverMapClientId"] = project.findProperty("NAVER_MAP_CLIENT_ID") ?: "x57z7zsj7i"
    }

    signingConfigs {
        create("release") {
            keyAlias = keyProperties["keyAlias"] as String
            keyPassword = keyProperties["keyPassword"] as String
            storeFile = file(keyProperties["storeFile"] as String)
            storePassword = keyProperties["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

flutter {
    source = "../.."
}

// workmanager_android는 work-runtime 2.10.2로 빌드됨. 더 낮은 버전으로 force 하면
// FlutterEngine(백그라운드 FCM 아이솔레이트)에서 GeneratedPluginRegistrant 실패(NoSuchFieldError: WorkManager.Companion) 난다.
configurations.all {
    resolutionStrategy {
        force("androidx.work:work-runtime:2.10.2")
        force("androidx.work:work-runtime-ktx:2.10.2")
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    // Kakao AdFit
    implementation("com.kakao.adfit:ads-base:3.21.17")
}
