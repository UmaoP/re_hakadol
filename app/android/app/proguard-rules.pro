# Google Mobile Ads SDK (AdMob)
-keep class com.google.android.gms.ads.** { *; }
-keep class com.google.android.gms.internal.ads.** { *; }

# For Google Mobile Ads SDK templates
-keep class com.google.android.gms.ads.nativead.NativeAdView { *; }
-keep class com.google.android.gms.ads.nativead.MediaView { *; }

# Flutter AdMob Plugin Wrapper
-keep class io.flutter.plugins.googlemobileads.** { *; }

# Supabase and standard Flutter Serialization
-keep class io.flutter.plugins.** { *; }
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod
