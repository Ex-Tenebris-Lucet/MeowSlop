# Flutter wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Video player
-keep class com.google.android.exoplayer2.** { *; }
-keep class * implements com.google.android.exoplayer2.** { *; }

# Supabase
-keep class io.supabase.** { *; }
-keep class com.google.gson.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep the BuildConfig
-keep class com.extenebrislucet.reelai.BuildConfig { *; }

# Keep setters in Views so that animations can still work.
-keepclassmembers public class * extends android.view.View {
    void set*(***);
    *** get*();
} 