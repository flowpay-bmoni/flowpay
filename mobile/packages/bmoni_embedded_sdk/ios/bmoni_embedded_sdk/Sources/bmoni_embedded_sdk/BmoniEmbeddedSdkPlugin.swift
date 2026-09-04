import BMONISigner
import Flutter
import Foundation
import os.log

/// Wallet/signing methods exposed by the plugin's `FlutterMethodChannel`.
///
/// The raw value of each case is the string the Dart side sends via
/// `MethodChannel.invokeMethod`. Adding a new case forces the `switch`
/// dispatch in `BmoniEmbeddedSdkPlugin.handle` to handle it.
enum ChannelMethods: String, CaseIterable {
  case initializeWallet = "initWallet"
  case signTransactionHash = "signTransactionHash"
  case signMessage = "signMessage"
  case deleteWallet = "deleteWallet"
}

/// Flutter plugin that bridges the Dart facade to the BMONISigner iOS
/// framework (Swift global functions: `initWallet`, `signTransactionHash`,
/// `signMessage`, `deleteWallet`).
///
/// All signer calls are dispatched on a background queue because they
/// touch the file system and Secure Enclave; results are forwarded to
/// Flutter on the main thread.
public class BmoniEmbeddedSdkPlugin: NSObject, FlutterPlugin {
  private static let channelName = "bmoni_embedded_sdk"
  private static let signerErrorCode = "BMONI_SIGNER_ERROR"
  private static let pluginErrorCode = "BMONI_PLUGIN_ERROR"
  private static let invalidArgumentCode = "INVALID_ARGUMENT"

  private static let logger = OSLog(
    subsystem: "me.bkey.bmoni_embedded_sdk",
    category: "plugin"
  )

  private let workQueue = DispatchQueue(
    label: "me.bkey.bmoni_embedded_sdk.signer",
    qos: .userInitiated
  )

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = BmoniEmbeddedSdkPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    guard let method = ChannelMethods(rawValue: call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }

    switch method {
    case .initializeWallet:
      runOnWorkQueue(result: result) {
        try initWallet()
      }

    case .signTransactionHash:
      guard
        let args = call.arguments as? [String: Any],
        let hashHex = args["hashHex"] as? String
      else {
        result(Self.missingArgument("hashHex"))
        return
      }
      runOnWorkQueue(result: result) {
        try signTransactionHash(hashHex)
      }

    case .signMessage:
      guard
        let args = call.arguments as? [String: Any],
        let message = args["message"] as? String
      else {
        result(Self.missingArgument("message"))
        return
      }
      runOnWorkQueue(result: result) {
        try signMessage(message)
      }

    case .deleteWallet:
      runOnWorkQueue(result: result) { () -> Any? in
        try deleteWallet()
        return nil
      }
    }
  }

  /// Runs [block] on the background work queue and forwards either the
  /// returned value or a typed [FlutterError] back to Flutter on the main
  /// queue.
  private func runOnWorkQueue(
    result: @escaping FlutterResult,
    block: @escaping () throws -> Any?
  ) {
    workQueue.async {
      let outcome: Outcome
      do {
        outcome = .success(try block())
      } catch let error as BMONISignerError {
        outcome = .signerFailure(error)
      } catch {
        // Surface the unexpected failure in the system log before
        // wrapping it: the consumer only sees the generic
        // `BMONI_PLUGIN_ERROR` code on the Dart side, so we want a
        // breadcrumb in Console.app / Xcode for production triage.
        os_log(
          "Unexpected error in BMONISigner bridge: %{public}@",
          log: Self.logger,
          type: .error,
          String(describing: error)
        )
        outcome = .unexpectedFailure(error)
      }

      DispatchQueue.main.async {
        switch outcome {
        case .success(let value):
          result(value)
        case .signerFailure(let error):
          result(Self.flutterError(from: error))
        case .unexpectedFailure(let error):
          result(
            FlutterError(
              code: Self.pluginErrorCode,
              message: error.localizedDescription,
              details: nil
            )
          )
        }
      }
    }
  }

  private static func missingArgument(_ name: String) -> FlutterError {
    FlutterError(
      code: invalidArgumentCode,
      message: "Missing required argument: \(name)",
      details: nil
    )
  }

  private static func flutterError(from error: BMONISignerError) -> FlutterError {
    let status: Int
    let message: String
    switch error {
    case .initError(let s, let m),
      .initWalletError(let s, let m),
      .signTransactionError(let s, let m):
      status = s
      message = m
    }

    return FlutterError(
      code: signerErrorCode,
      message: message,
      details: ["errorCode": status]
    )
  }

  private enum Outcome {
    case success(Any?)
    case signerFailure(BMONISignerError)
    case unexpectedFailure(Error)
  }
}
