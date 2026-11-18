package app.thinkcaps.android

import android.app.Activity
import android.content.Intent
import android.database.sqlite.SQLiteConstraintException
import com.google.android.gms.tasks.Task
import com.google.mlkit.common.model.DownloadConditions
import com.google.mlkit.nl.translate.TranslateLanguage
import com.google.mlkit.nl.translate.Translation
import com.google.mlkit.nl.translate.TranslatorOptions
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val database by lazy { WordDatabase(applicationContext) }
    private val translator by lazy {
        Translation.getClient(
            TranslatorOptions.Builder()
                .setSourceLanguage(TranslateLanguage.ENGLISH)
                .setTargetLanguage(TranslateLanguage.RUSSIAN)
                .build()
        )
    }
    private val recognizer by lazy { TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS) }
    private val shares = mutableListOf<String>()
    private var channel: MethodChannel? = null
    private var scanResult: MethodChannel.Result? = null
    private var modelDownload: Task<Void>? = null
    private var translatorUsed = false
    private var recognizerUsed = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.thinkcaps/bridge")
        captureShare(intent)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "drainShares" -> {
                    result.success(shares.toList())
                    shares.clear()
                }
                "scanScreenshot" -> openScreenshot(result)
                "translate" -> translate(call.arguments as String, result)
                "loadEntries" -> disk(result) { database.entries() }
                "saveEntry" -> disk(result) { database.save(call.arguments as Map<*, *>); null }
                "removeEntry" -> disk(result) { database.remove(call.arguments as Number); null }
                "grade" -> disk(result) { database.grade(call.arguments as Map<*, *>); null }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        captureShare(intent)
    }

    private fun captureShare(intent: Intent) {
        if (intent.action != Intent.ACTION_SEND || intent.type?.startsWith("text/") != true) return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()?.trim()
            ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.text?.toString()?.trim()
        if (text.isNullOrEmpty()) return
        shares.add(text.take(100_000))
        intent.removeExtra(Intent.EXTRA_TEXT)
        intent.clipData = null
        channel?.invokeMethod("shareAvailable", null)
    }

    private fun translate(word: String, result: MethodChannel.Result) {
        translatorUsed = true
        val download = modelDownload?.takeUnless { it.isComplete && !it.isSuccessful }
            ?: translator.downloadModelIfNeeded(DownloadConditions.Builder().build()).also {
                modelDownload = it
            }
        download.continueWithTask { task ->
            task.getResult(Exception::class.java)
            translator.translate(word)
        }.addOnSuccessListener { result.success(it) }
            .addOnFailureListener { result.error("TRANSLATION", it.localizedMessage, null) }
    }

    @Suppress("DEPRECATION")
    private fun openScreenshot(result: MethodChannel.Result) {
        if (scanResult != null) {
            result.error("BUSY", null, null)
            return
        }
        scanResult = result
        try {
            startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT)
                    .addCategory(Intent.CATEGORY_OPENABLE)
                    .setType("image/*"),
                SCREENSHOT_REQUEST
            )
        } catch (error: Exception) {
            scanResult = null
            result.error("PICKER", error.localizedMessage, null)
        }
    }

    @Deprecated("FlutterActivity uses the platform activity result callback")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != SCREENSHOT_REQUEST) return
        val result = scanResult ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            scanResult = null
            result.success(null)
            return
        }
        recognizerUsed = true
        executor.execute {
            try {
                val image = InputImage.fromFilePath(applicationContext, uri)
                recognizer.process(image)
                    .addOnSuccessListener { text ->
                        scanResult = null
                        result.success(text.textBlocks.joinToString("\n\n") { it.text })
                    }
                    .addOnFailureListener { failure ->
                        scanResult = null
                        result.error("OCR", failure.localizedMessage, null)
                    }
            } catch (error: Exception) {
                runOnUiThread {
                    scanResult = null
                    result.error("IMAGE", error.localizedMessage, null)
                }
            }
        }
    }

    private fun disk(result: MethodChannel.Result, operation: () -> Any?) {
        executor.execute {
            try {
                val value = operation()
                runOnUiThread { result.success(value) }
            } catch (error: SQLiteConstraintException) {
                runOnUiThread { result.error("DUPLICATE", null, null) }
            } catch (error: Exception) {
                runOnUiThread { result.error("STORAGE", error.localizedMessage, null) }
            }
        }
    }

    override fun onDestroy() {
        channel?.setMethodCallHandler(null)
        if (translatorUsed) translator.close()
        if (recognizerUsed) recognizer.close()
        executor.execute { database.close() }
        executor.shutdown()
        super.onDestroy()
    }

    private companion object {
        const val SCREENSHOT_REQUEST = 121
    }
}
