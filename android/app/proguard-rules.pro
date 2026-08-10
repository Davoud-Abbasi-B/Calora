# ML Kit discovers these registrars through Android manifest metadata. Keep
# their component factories intact when Flutter's release shrinker runs.
-keep class com.google.mlkit.common.internal.CommonComponentRegistrar { *; }
-keep class com.google.mlkit.nl.translate.NaturalLanguageTranslateRegistrar { *; }
