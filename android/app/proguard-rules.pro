# kotlinx.serialization: keep generated serializers of @Serializable classes.
-keepattributes *Annotation*, InnerClasses, Signature, EnclosingMethod
-dontnote kotlinx.serialization.**
-keepclassmembers class kotlinx.serialization.json.** { *** Companion; }
-keepclasseswithmembers class kotlinx.serialization.json.** { kotlinx.serialization.KSerializer serializer(...); }
-keep,includedescriptorclasses class de.letzgo.stashy.**$$serializer { *; }
-keepclassmembers class de.letzgo.stashy.** { *** Companion; }
-keepclasseswithmembers class de.letzgo.stashy.** { kotlinx.serialization.KSerializer serializer(...); }

-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Vosk (AI Subtitles) talks to libvosk through JNA, which needs its classes and the callback /
# structure types unobfuscated.
-keep class com.sun.jna.** { *; }
-keep class * implements com.sun.jna.** { *; }
-keep class org.vosk.** { *; }
-dontwarn java.awt.**
