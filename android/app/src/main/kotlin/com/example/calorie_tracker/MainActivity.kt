package com.example.calorie_tracker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var translationChannel: OnDeviceTranslationChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        if (translationChannel != null) return
        translationChannel = OnDeviceTranslationChannel(
            context = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
        translationChannel?.register()
    }

    override fun onDestroy() {
        translationChannel?.dispose()
        translationChannel = null
        super.onDestroy()
    }
}
