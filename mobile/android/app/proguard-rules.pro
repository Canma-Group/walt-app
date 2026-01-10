# Flutter specific rules
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Suppress missing class warnings for slf4j
-dontwarn org.slf4j.**
-dontwarn org.slf4j.impl.StaticLoggerBinder

# Web3 related
-keep class org.web3j.** { *; }
-dontwarn org.web3j.**

# Bouncy Castle (crypto)
-keep class org.bouncycastle.** { *; }
-dontwarn org.bouncycastle.**

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**

# NFC Manager
-keep class io.flutter.plugins.nfc_manager.** { *; }

# Google Play Core (deferred components)
-dontwarn com.google.android.play.core.**
-dontwarn com.google.android.play.core.splitcompat.**
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**

# Suppress all missing class errors
-ignorewarnings
