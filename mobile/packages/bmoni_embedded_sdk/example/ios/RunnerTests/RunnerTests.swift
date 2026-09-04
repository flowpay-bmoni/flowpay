import Flutter
import XCTest

// If your plugin has been explicitly set to "type: .dynamic" in the Package.swift,
// you will need to add your plugin as a dependency of RunnerTests within Xcode.

@testable import bmoni_embedded_sdk

/// Lightweight unit tests for the Swift portion of the plugin.
///
/// Tests that exercise the real BMONISigner SDK (wallet provisioning,
/// signing) live in `example/integration_test/plugin_integration_test.dart`
/// because they require a real device / simulator with the Secure Enclave
/// and the bundled xcframework.
class RunnerTests: XCTestCase {

  func testHandle_unknownMethod_returnsNotImplemented() {
    let plugin = BmoniEmbeddedSdkPlugin()

    let call = FlutterMethodCall(methodName: "doesNotExist", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertTrue(result is FlutterMethodNotImplemented)
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testHandle_signTransactionHash_missingArgument_returnsInvalidArgument() {
    let plugin = BmoniEmbeddedSdkPlugin()

    let call = FlutterMethodCall(methodName: "signTransactionHash", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      guard let error = result as? FlutterError else {
        XCTFail("Expected FlutterError, got \(String(describing: result))")
        resultExpectation.fulfill()
        return
      }
      XCTAssertEqual(error.code, "INVALID_ARGUMENT")
      XCTAssertEqual(error.message, "Missing required argument: hashHex")
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testHandle_signMessage_missingArgument_returnsInvalidArgument() {
    let plugin = BmoniEmbeddedSdkPlugin()

    let call = FlutterMethodCall(methodName: "signMessage", arguments: nil)

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      guard let error = result as? FlutterError else {
        XCTFail("Expected FlutterError, got \(String(describing: result))")
        resultExpectation.fulfill()
        return
      }
      XCTAssertEqual(error.code, "INVALID_ARGUMENT")
      XCTAssertEqual(error.message, "Missing required argument: message")
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }
}
