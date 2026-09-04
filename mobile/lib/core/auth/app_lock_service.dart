import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';
import 'secure_storage_service.dart';

/// Status result from an App Lock authentication attempt
enum AppLockStatus {
  success,
  userCanceled,
  lockedOut,
  permanentlyLockedOut,
  notEnrolled,
  passcodeNotSet,
  notSupported,
  failed,
}

class AppLockAuthResult {
  final bool success;
  final AppLockStatus status;
  final String? errorMessage;

  const AppLockAuthResult({
    required this.success,
    required this.status,
    this.errorMessage,
  });

  factory AppLockAuthResult.success() => const AppLockAuthResult(
        success: true,
        status: AppLockStatus.success,
      );

  factory AppLockAuthResult.failure(AppLockStatus status, [String? message]) =>
      AppLockAuthResult(
        success: false,
        status: status,
        errorMessage: message,
      );
}

/// App-Level Lock & Biometrics Service.
///
/// CRITICAL ARCHITECTURAL BOUNDARY:
/// This service gates opening the app and resuming from the background.
/// It uses `local_auth` and NEVER accesses or passes key material into
/// `bmoni_embedded_sdk`. BMONI's own on-device signing PIN is an entirely
/// separate cryptographic secret serving a separate purpose.
class AppLockService {
  final LocalAuthentication _auth;

  AppLockService({LocalAuthentication? auth})
      : _auth = auth ?? LocalAuthentication();

  /// Check if this device supports biometric or device-level passcode authentication
  Future<bool> canAuthenticate() async {
    if (SecureStorageService.isTestEnv) return false;
    try {
      final canCheckBiometrics = await _auth.canCheckBiometrics;
      final isDeviceSupported = await _auth.isDeviceSupported();
      return canCheckBiometrics || isDeviceSupported;
    } catch (_) {
      return false;
    }
  }

  /// Check available biometric types (Face ID, Fingerprint, etc.)
  Future<List<BiometricType>> getAvailableBiometrics() async {
    if (SecureStorageService.isTestEnv) return [];
    try {
      return await _auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  /// Check if Face ID / facial recognition is enrolled
  Future<bool> hasFaceId() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.face);
  }

  /// Check if Fingerprint / Touch ID is enrolled
  Future<bool> hasFingerprint() async {
    final biometrics = await getAvailableBiometrics();
    return biometrics.contains(BiometricType.fingerprint) ||
        biometrics.contains(BiometricType.strong);
  }

  /// Human-readable label representing available hardware on this device
  Future<String> getBiometricLabel() async {
    final biometrics = await getAvailableBiometrics();
    final hasFace = biometrics.contains(BiometricType.face);
    final hasFinger = biometrics.contains(BiometricType.fingerprint) ||
        biometrics.contains(BiometricType.strong);

    if (hasFace && hasFinger) return 'Face ID & Fingerprint';
    if (hasFace) return 'Face ID';
    if (hasFinger) return 'Fingerprint';
    return 'Biometrics';
  }

  /// Authenticate user via Biometrics (Face ID / Fingerprint) or Device Passcode.
  ///
  /// Note: `biometricOnly: false` is intentionally set to preserve device passcode
  /// fallback per security guidelines.
  Future<AppLockAuthResult> authenticate({
    String localizedReason = 'Unlock FlowPay with Biometrics or Passcode',
  }) async {
    try {
      final canAuth = await canAuthenticate();
      if (!canAuth) {
        // No biometric hardware and no device lockscreen set up.
        // Route gracefully to fallback rather than hard-blocking the user.
        return AppLockAuthResult.failure(
          AppLockStatus.notSupported,
          'No biometric hardware or device passcode configured on this device.',
        );
      }

      final didAuthenticate = await _auth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: false, // Mandatory: keep device passcode fallback
          stickyAuth: true,
          useErrorDialogs: true,
          sensitiveTransaction: true,
        ),
        authMessages: const <AuthMessages>[
          AndroidAuthMessages(
            signInTitle: 'Unlock FlowPay',
            biometricHint: 'Verify fingerprint or glance to unlock',
            cancelButton: 'Cancel',
          ),
          IOSAuthMessages(
            localizedFallbackTitle: 'Enter Passcode',
            cancelButton: 'Cancel',
          ),
        ],
      );

      if (didAuthenticate) {
        return AppLockAuthResult.success();
      } else {
        return AppLockAuthResult.failure(
          AppLockStatus.userCanceled,
          'Authentication was cancelled by user.',
        );
      }
    } on PlatformException catch (e) {
      // Map local_auth error codes to domain status
      switch (e.code) {
        case auth_error.lockedOut:
          return AppLockAuthResult.failure(
            AppLockStatus.lockedOut,
            'Too many failed attempts. The device has temporarily locked biometrics.',
          );
        case auth_error.permanentlyLockedOut:
          return AppLockAuthResult.failure(
            AppLockStatus.permanentlyLockedOut,
            'Biometrics permanently locked. Please unlock using your device passcode in settings.',
          );
        case auth_error.notEnrolled:
          return AppLockAuthResult.failure(
            AppLockStatus.notEnrolled,
            'No biometrics are enrolled on this device.',
          );
        case auth_error.passcodeNotSet:
          return AppLockAuthResult.failure(
            AppLockStatus.passcodeNotSet,
            'No device passcode is configured.',
          );
        case auth_error.notAvailable:
          return AppLockAuthResult.failure(
            AppLockStatus.notSupported,
            'Biometric authentication is currently unavailable.',
          );
        default:
          return AppLockAuthResult.failure(
            AppLockStatus.failed,
            e.message ?? 'Authentication failed.',
          );
      }
    } catch (e) {
      return AppLockAuthResult.failure(
        AppLockStatus.failed,
        e.toString(),
      );
    }
  }

  /// Cancel any active authentication session
  Future<void> stopAuthentication() async {
    try {
      await _auth.stopAuthentication();
    } catch (_) {}
  }
}
