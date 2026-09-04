package com.bmoni.embedded.sdk

import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlin.test.Test
import org.mockito.ArgumentMatchers.eq
import org.mockito.Mockito

/*
 * Unit tests for the Kotlin portion of the plugin's implementation.
 *
 * These tests cover the synchronous code paths that do not invoke the
 * BMONISigner static methods (which require an Android Context and the
 * native crypto library). The full signing flow is exercised end-to-end
 * via the example app's integration tests.
 *
 * Run with `./gradlew testDebugUnitTest` from the example app's
 * `android/` directory, or directly from Android Studio / IntelliJ.
 */

internal class BmoniEmbeddedSdkPluginTest {
    @Test
    fun onMethodCall_unknownMethod_isNotImplemented() {
        val plugin = BmoniEmbeddedSdkPlugin()

        val call = MethodCall("doesNotExist", null)
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult).notImplemented()
    }

    @Test
    fun onMethodCall_signTransactionHash_missingArgument_returnsInvalidArgument() {
        val plugin = BmoniEmbeddedSdkPlugin()

        val call = MethodCall("signTransactionHash", emptyMap<String, Any?>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult)
                .error(
                        eq("INVALID_ARGUMENT"),
                        eq("Missing required argument: hashHex"),
                        eq(null),
                )
    }

    @Test
    fun onMethodCall_signMessage_missingArgument_returnsInvalidArgument() {
        val plugin = BmoniEmbeddedSdkPlugin()

        val call = MethodCall("signMessage", emptyMap<String, Any?>())
        val mockResult: MethodChannel.Result = Mockito.mock(MethodChannel.Result::class.java)
        plugin.onMethodCall(call, mockResult)

        Mockito.verify(mockResult)
                .error(
                        eq("INVALID_ARGUMENT"),
                        eq("Missing required argument: message"),
                        eq(null),
                )
    }
}
