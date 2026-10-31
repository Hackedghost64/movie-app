# Flutter Engine and Plugins Keep Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# App Package and MainActivity
-keep class com.mbx.stream.mbx_app.** { *; }

# Keep all native JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Flutter Plugin Registrant
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# ExoPlayer / AndroidX Media3 (video_player)
-keep class androidx.media3.** { *; }
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn androidx.media3.**
-dontwarn com.google.android.exoplayer2.**

# Common Android Lifecycle and Annotations
-keep class androidx.lifecycle.DefaultLifecycleObserver
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-keepattributes InnerClasses,EnclosingMethod
-keepattributes Signature

# Suppress harmless warnings for optional dependencies
-dontwarn io.flutter.**
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
