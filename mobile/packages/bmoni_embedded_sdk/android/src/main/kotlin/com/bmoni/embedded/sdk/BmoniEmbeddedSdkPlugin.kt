package com.bmoni.embedded.sdk

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import me.bkey.ip.bmonisigner.BMONISigner
import me.bkey.ip.bmonisigner.BMONISignerException

/**
 * Wallet/signing methods exposed by the plugin's [MethodChannel].
 *
 * The [methodName] of each entry is the string the Dart side sends via
 * `MethodChannel.invokeMethod`. Adding a new entry forces the `when`
 * dispatch in [BmoniEmbeddedSdkPlugin.onMethodCall] to handle it.
 */
enum class ChannelMethods(val methodName: String) {
    INITIALIZE_WALLET("initWallet"),
    SIGN_TRANSACTION_HASH("signTransactionHash"),
    SIGN_MESSAGE("signMessage"),
    DELETE_WALLET("deleteWallet"),
    ;

    companion object {
        private val byMethodName: Map<String, ChannelMethods> =
            entries.associateBy(ChannelMethods::methodName)

        fun fromMethodName(methodName: String): ChannelMethods? = byMethodName[methodName]
    }
}

/**
 * Flutter plugin that bridges the Dart facade to the native BMONISigner Android SDK
 * (`me.bkey.ip.bmonisigner.BMONISigner`).
 *
 * All signer calls are dispatched on a background executor because they touch the file system and
 * perform OpenSSL-backed crypto. Results are delivered back to Flutter on the main thread.
 */
class BmoniEmbeddedSdkPlugin :
    FlutterPlugin,
    MethodCallHandler {
    private companion object {
        const val CHANNEL_NAME = "bmoni_embedded_sdk"
        const val INVALID_ARGUMENT_CODE = "INVALID_ARGUMENT"
        const val SIGNER_ERROR_CODE = "BMONI_SIGNER_ERROR"
        const val PLUGIN_ERROR_CODE = "BMONI_PLUGIN_ERROR"
    }

    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    private val executor: ExecutorService =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "bmoni-embedded-sdk").apply { isDaemon = true }
        }
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(
        call: MethodCall,
        result: Result,
    ) {
        val method = ChannelMethods.fromMethodName(call.method)
        if (method == null) {
            result.notImplemented()
            return
        }

        when (method) {
            ChannelMethods.INITIALIZE_WALLET -> runOnExecutor(result) {
                BMONISigner.initWallet(applicationContext)
            }

            ChannelMethods.SIGN_TRANSACTION_HASH -> {
                val hashHex = call.argument<String>("hashHex")
                if (hashHex == null) {
                    result.missingArgument("hashHex")
                    return
                }
                runOnExecutor(result) {
                    BMONISigner.signTransactionHash(applicationContext, hashHex)
                }
            }

            ChannelMethods.SIGN_MESSAGE -> {
                val message = call.argument<String>("message")
                if (message == null) {
                    result.missingArgument("message")
                    return
                }
                runOnExecutor(result) {
                    BMONISigner.signMessage(applicationContext, message)
                }
            }

            ChannelMethods.DELETE_WALLET -> runOnExecutor(result) {
                BMONISigner.deleteWallet(applicationContext)
                null
            }
        }
    }

    /**
     * Executes [block] on the background [executor] and forwards either the returned value or a
     * typed error back to Flutter on the main thread.
     */
    private fun runOnExecutor(
        result: Result,
        block: () -> Any?,
    ) {
        executor.execute {
            val outcome: Outcome =
                try {
                    Outcome.Success(block())
                } catch (e: BMONISignerException) {
                    Outcome.SignerFailure(e)
                } catch (e: Exception) {
                    // Deliberately narrower than Throwable so JVM `Error`s
                    // (OutOfMemoryError, StackOverflowError, …) propagate
                    // and crash loudly instead of being swallowed and
                    // forwarded to Flutter as a recoverable error.
                    Outcome.UnexpectedFailure(e)
                }

            mainHandler.post {
                when (outcome) {
                    is Outcome.Success -> result.success(outcome.value)
                    is Outcome.SignerFailure -> {
                        val details = mapOf("errorCode" to outcome.exception.errorCode)
                        result.error(
                            SIGNER_ERROR_CODE,
                            outcome.exception.message ?: "BMONISigner error",
                            details,
                        )
                    }
                    is Outcome.UnexpectedFailure -> result.error(
                        PLUGIN_ERROR_CODE,
                        outcome.error.message ?: outcome.error.javaClass.name,
                        null,
                    )
                }
            }
        }
    }

    private fun Result.missingArgument(name: String) {
        error(INVALID_ARGUMENT_CODE, "Missing required argument: $name", null)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        executor.shutdown()
    }
}

/** Result wrapper for background work executed by [BmoniEmbeddedSdkPlugin]. */
private sealed class Outcome {
    data class Success(val value: Any?) : Outcome()
    data class SignerFailure(val exception: BMONISignerException) : Outcome()
    data class UnexpectedFailure(val error: Throwable) : Outcome()
}
