package com.example.calorie_tracker

import android.content.Context
import android.content.pm.ApplicationInfo
import android.util.Log
import com.google.android.gms.tasks.Task
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.common.MlKitException
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.common.model.RemoteModelManager
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.TranslateRemoteModel
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.Translator
import com.google.mlkit.nl.translate.TranslatorOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

internal object TranslationChannelErrors {
    const val MODEL_DOWNLOAD_FAILED = "MODEL_DOWNLOAD_FAILED"
    const val MODEL_NOT_READY = "MODEL_NOT_READY"
    const val TRANSLATOR_INIT_FAILED = "TRANSLATOR_INIT_FAILED"
    const val TRANSLATION_FAILED = "TRANSLATION_FAILED"
    const val NETWORK_UNAVAILABLE = "NETWORK_UNAVAILABLE"
    const val UNSUPPORTED_LANGUAGE = "UNSUPPORTED_LANGUAGE"
    const val INVALID_ARGUMENT = "INVALID_ARGUMENT"
    const val MODEL_DELETE_FAILED = "MODEL_DELETE_FAILED"
}

private class ModelDownloadStartException(cause: Throwable) : RuntimeException(cause)

internal class ChannelLifecycleGuard {
    var isRegistered: Boolean = false
        private set
    var isDisposed: Boolean = false
        private set

    fun register(action: () -> Unit) {
        if (isRegistered) return
        isDisposed = false
        isRegistered = true
        action()
    }

    fun dispose(action: () -> Unit) {
        if (isDisposed) return
        isDisposed = true
        isRegistered = false
        action()
    }
}

internal class OnDeviceTranslationChannel(
    context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        const val CHANNEL_NAME = "calorie_tracker/on_device_translation"
        private const val LOG_TAG = "CalorieTranslation"
    }

    // Retain only the application context. ML Kit itself is not touched here.
    private val applicationContext = context.applicationContext ?: context
    private val isDebuggable =
        applicationContext.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val lifecycle = ChannelLifecycleGuard()
    private val downloadLock = Any()
    private var translator: Translator? = null
    private var modelManager: RemoteModelManager? = null
    private var activeDownload: Task<Void>? = null
    private var modelsReady: Boolean = false

    fun register() {
        lifecycle.register {
            channel.setMethodCallHandler(this)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        debugLog("method=${call.method}")
        if (lifecycle.isDisposed) {
            result.error(
                TranslationChannelErrors.MODEL_NOT_READY,
                "MODEL_NOT_READY: channel disposed",
                null,
            )
            return
        }
        when (call.method) {
            "isTranslationSupported" -> checkAvailability(result)
            "ensureModelsDownloaded" -> ensureModels(result)
            "translateFoodName" -> translateFoodName(call, result)
            "deleteTranslationModels" -> deleteModels(result)
            else -> result.notImplemented()
        }
    }

    private fun checkAvailability(result: MethodChannel.Result) {
        // A missing model is supported-but-not-ready. Readiness is established
        // by downloadModelIfNeeded rather than blocking on model enumeration.
        result.success(mapOf("supported" to true, "modelsReady" to modelsReady))
    }

    private fun ensureModels(result: MethodChannel.Result) {
        val task = runCatching { downloadTask() }.getOrElse { exception ->
            reportDownloadStartFailure(result, exception)
            return
        }
        task.addOnSuccessListener {
            modelsReady = true
            debugLog("model_download=succeeded")
            result.success(null)
        }.addOnFailureListener { exception ->
            modelsReady = false
            debugLogException("model_download=failed", exception)
            nativeError(result, downloadErrorCode(exception), exception)
        }
    }

    private fun translateFoodName(call: MethodCall, result: MethodChannel.Result) {
        val foodName = call.argument<String>("foodName")?.trim().orEmpty()
        if (foodName.isEmpty() || foodName.length > 150) {
            result.error(
                TranslationChannelErrors.INVALID_ARGUMENT,
                "A valid food name is required.",
                null,
            )
            return
        }
        val task = runCatching { downloadTask() }.getOrElse { exception ->
            reportDownloadStartFailure(result, exception)
            return
        }
        task.addOnSuccessListener {
            modelsReady = true
            debugLog("model_download=succeeded; translate=started")
            val activeTranslator = translator
            if (activeTranslator == null) {
                result.error(
                    TranslationChannelErrors.MODEL_NOT_READY,
                    "MODEL_NOT_READY: Translator",
                    null,
                )
                return@addOnSuccessListener
            }
            activeTranslator.translate(foodName)
                .addOnSuccessListener { translated ->
                    debugLog("translate=succeeded")
                    result.success(translated)
                }
                .addOnFailureListener { exception ->
                    debugLogException("translate=failed", exception)
                    nativeError(
                        result,
                        TranslationChannelErrors.TRANSLATION_FAILED,
                        exception,
                    )
                }
        }.addOnFailureListener { exception ->
            modelsReady = false
            debugLogException("model_download=failed", exception)
            nativeError(result, downloadErrorCode(exception), exception)
        }
    }

    private fun deleteModels(result: MethodChannel.Result) {
        closeTranslator()
        val languages = languagePair()
        val manager = runCatching { getModelManager() }.getOrElse {
            result.error(
                TranslationChannelErrors.MODEL_DELETE_FAILED,
                "Translation model management is unavailable.",
                null,
            )
            return
        }
        val sourceModel = TranslateRemoteModel.Builder(languages.first).build()
        val targetModel = TranslateRemoteModel.Builder(languages.second).build()
        Tasks.whenAll(
            manager.deleteDownloadedModel(sourceModel),
            manager.deleteDownloadedModel(targetModel),
        ).addOnSuccessListener {
            debugLog("model_delete=succeeded")
            result.success(null)
        }.addOnFailureListener { exception ->
            debugLogException("model_delete=failed", exception)
            result.error(
                TranslationChannelErrors.MODEL_DELETE_FAILED,
                "Translation models could not be deleted.",
                null,
            )
        }
    }

    private fun downloadTask(): Task<Void> = synchronized(downloadLock) {
        val existing = activeDownload
        if (existing != null && !existing.isComplete) return@synchronized existing

        val languages = languagePair()
        debugLog("translator_init=started")
        val activeTranslator = getTranslator(languages)
        // No requireWifi(): first-use downloads may use Wi-Fi or mobile data.
        val conditions = DownloadConditions.Builder().build()
        debugLog("model_download=started; conditions=wifi_or_mobile")
        val created = try {
            activeTranslator.downloadModelIfNeeded(conditions)
        } catch (exception: Throwable) {
            throw ModelDownloadStartException(exception)
        }
        activeDownload = created
        created.addOnCompleteListener {
            synchronized(downloadLock) {
                if (activeDownload === created) activeDownload = null
            }
        }
        created
    }

    private fun getTranslator(languages: Pair<String, String>): Translator {
        translator?.let { return it }
        val options = TranslatorOptions.Builder()
            .setSourceLanguage(languages.first)
            .setTargetLanguage(languages.second)
            .build()
        debugLog("translator_init=options_built")
        return Translation.getClient(options).also { translator = it }
            .also { debugLog("translator_init=succeeded") }
    }

    private fun getModelManager(): RemoteModelManager {
        modelManager?.let { return it }
        // Referencing applicationContext here documents and enforces that this
        // lazy initialization happens after Activity attachment, never in the
        // channel constructor.
        applicationContext.packageName
        return RemoteModelManager.getInstance().also { modelManager = it }
    }

    private fun languagePair(): Pair<String, String> =
        TranslateLanguage.PERSIAN to TranslateLanguage.ENGLISH

    private fun downloadErrorCode(exception: Throwable): String =
        if (exception is MlKitException &&
            exception.errorCode == MlKitException.NETWORK_ISSUE
        ) {
            TranslationChannelErrors.NETWORK_UNAVAILABLE
        } else {
            TranslationChannelErrors.MODEL_DOWNLOAD_FAILED
        }

    private fun reportDownloadStartFailure(
        result: MethodChannel.Result,
        exception: Throwable,
    ) {
        val isDownloadFailure = exception is ModelDownloadStartException
        val cause = if (isDownloadFailure) exception.cause ?: exception else exception
        val code = if (isDownloadFailure) {
            downloadErrorCode(cause)
        } else {
            TranslationChannelErrors.TRANSLATOR_INIT_FAILED
        }
        debugLogException(
            if (isDownloadFailure) "model_download=start_failed" else "translator_init=failed",
            cause,
        )
        nativeError(result, code, cause)
    }

    private fun nativeError(
        result: MethodChannel.Result,
        code: String,
        exception: Throwable,
    ) {
        val exceptionClass = exception.javaClass.simpleName.ifBlank { "Exception" }
        val mlKitCode = (exception as? MlKitException)?.errorCode
        result.error(
            code,
            "$code: $exceptionClass",
            if (mlKitCode == null) null else mapOf("mlKitErrorCode" to mlKitCode),
        )
    }

    private fun debugLog(message: String) {
        if (isDebuggable) Log.d(LOG_TAG, message)
    }

    private fun debugLogException(message: String, exception: Throwable) {
        if (!isDebuggable) return
        val mlKitCode = (exception as? MlKitException)?.errorCode
        Log.d(
            LOG_TAG,
            "$message; code=${mlKitCode ?: "none"}; exception=${exception.javaClass.simpleName}",
        )
    }

    private fun closeTranslator() {
        translator?.close()
        translator = null
    }

    fun dispose() {
        lifecycle.dispose {
            channel.setMethodCallHandler(null)
            synchronized(downloadLock) {
                activeDownload = null
            }
            closeTranslator()
            modelManager = null
            modelsReady = false
        }
    }
}
