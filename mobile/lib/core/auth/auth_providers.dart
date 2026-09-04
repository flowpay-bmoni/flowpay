import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'account_capabilities.dart';
import 'app_lock_service.dart';
import 'secure_storage_service.dart';

/// Dependency Injection Providers
final secureStorageServiceProvider = Provider<SecureStorageService>((ref) {
  return SecureStorageService();
});

final appLockServiceProvider = Provider<AppLockService>((ref) {
  return AppLockService();
});

/// Current active Account Mode (Personal vs Business)
/// Drives root navigation and active shell
final currentAccountModeProvider = StateProvider<AccountMode>((ref) {
  return AccountMode.personal;
});

/// Holds the active UserProfile
class UserProfileNotifier extends StateNotifier<UserProfile?> {
  final SecureStorageService _storage;
  final Ref _ref;

  UserProfileNotifier(this._storage, this._ref) : super(null) {
    loadProfile();
  }

  Future<void> loadProfile() async {
    final profile = await _storage.getUserProfile();
    state = profile;
  }

  Future<void> saveProfile(UserProfile profile) async {
    await _storage.saveUserProfile(profile);
    state = profile;
    _ref.invalidate(accountCapabilitiesProvider);
  }

  Future<void> setKycVerified() async {
    if (state != null) {
      final updated = state!.copyWith(kycStatus: KycStatus.verified);
      await _storage.saveUserProfile(updated);
      await _storage.setKycCompleted(true);
      state = updated;
      _ref.invalidate(accountCapabilitiesProvider);
    }
  }

  Future<void> clearProfile() async {
    await _storage.resetSession();
    state = null;
    _ref.invalidate(accountCapabilitiesProvider);
  }
}

final currentUserProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile?>((ref) {
  final storage = ref.watch(secureStorageServiceProvider);
  return UserProfileNotifier(storage, ref);
});

/// Fetches AccountCapabilities with secure storage caching & TTL invalidation
final accountCapabilitiesProvider =
    FutureProvider<AccountCapabilities>((ref) async {
  final storage = ref.watch(secureStorageServiceProvider);

  // 1. Try reading from secure storage cache (with 15m TTL)
  final cached = await storage.getCachedCapabilities();
  if (cached != null) {
    return cached;
  }

  // 2. Check local user profile to derive strict capabilities based on signup
  final profile = await storage.getUserProfile();
  if (profile != null) {
    AccountCapabilities capabilities;
    if (profile.accountType == AccountType.personal) {
      capabilities = AccountCapabilities.personalOnly(
        bmoniUserId: profile.userId,
      );
    } else {
      capabilities = AccountCapabilities.businessOnly(
        bmoniUserId: profile.userId,
        companyName: profile.companyName ?? 'Business Account',
        companyRole: profile.companyRole ?? 'ADMIN',
      );
    }
    await storage.saveCapabilities(capabilities);
    return capabilities;
  }

  // 3. Fetch fresh capabilities from FlowPay backend
  try {
    final bmoniUserId =
        await storage.getBmoniUserId() ?? 'usr_flowpay_sandbox_master';
    final uri = Uri.parse(
        '${ApiConfig.baseUrl}/api/auth/capabilities?bmoniUserId=$bmoniUserId');

    final response = await http.get(uri).timeout(const Duration(seconds: 4));
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final capabilities = AccountCapabilities.fromJson(data);
      await storage.saveCapabilities(capabilities);
      return capabilities;
    }
  } catch (_) {
    // Network or server offline; use deterministic capabilities
  }

  // 4. Fallback: deterministic capabilities (both modes available in sandbox)
  final fallback = AccountCapabilities.demo();
  await storage.saveCapabilities(fallback);
  return fallback;
});

/// App-Lock UI & Lifecycle State
class AppLockState {
  final bool isLocked;
  final bool isAuthenticating;
  final AppLockAuthResult? lastResult;
  final bool isSupported;
  final bool showFallbackPin;
  final AccountMode activeMode;
  final String biometricLabel;
  final bool hasFaceId;
  final bool hasFingerprint;
  final bool isAuthExpired;

  const AppLockState({
    required this.isLocked,
    this.isAuthenticating = false,
    this.lastResult,
    this.isSupported = true,
    this.showFallbackPin = false,
    this.activeMode = AccountMode.personal,
    this.biometricLabel = 'Biometrics',
    this.hasFaceId = false,
    this.hasFingerprint = false,
    this.isAuthExpired = false,
  });

  AppLockState copyWith({
    bool? isLocked,
    bool? isAuthenticating,
    AppLockAuthResult? lastResult,
    bool? isSupported,
    bool? showFallbackPin,
    AccountMode? activeMode,
    String? biometricLabel,
    bool? hasFaceId,
    bool? hasFingerprint,
    bool? isAuthExpired,
  }) {
    return AppLockState(
      isLocked: isLocked ?? this.isLocked,
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
      lastResult: lastResult ?? this.lastResult,
      isSupported: isSupported ?? this.isSupported,
      showFallbackPin: showFallbackPin ?? this.showFallbackPin,
      activeMode: activeMode ?? this.activeMode,
      biometricLabel: biometricLabel ?? this.biometricLabel,
      hasFaceId: hasFaceId ?? this.hasFaceId,
      hasFingerprint: hasFingerprint ?? this.hasFingerprint,
      isAuthExpired: isAuthExpired ?? this.isAuthExpired,
    );
  }
}

class AppLockNotifier extends StateNotifier<AppLockState> {
  final AppLockService _appLockService;
  final SecureStorageService _storage;
  final Ref _ref;

  AppLockNotifier({
    required AppLockService appLockService,
    required SecureStorageService storage,
    required Ref ref,
  })  : _appLockService = appLockService,
        _storage = storage,
        _ref = ref,
        super(const AppLockState(isLocked: true)) {
    _initialize();
  }

  Future<void> _initialize() async {
    final canAuth = await _appLockService.canAuthenticate();
    final hasFace = await _appLockService.hasFaceId();
    final hasFinger = await _appLockService.hasFingerprint();
    final bioLabel = await _appLockService.getBiometricLabel();
    final isLockEnabled = await _storage.isAppLockEnabled();
    final storedMode = await _storage.getAccountMode();
    final isExpired = await _storage.isAuthExpired();

    if (storedMode != null) {
      _ref.read(currentAccountModeProvider.notifier).state = storedMode;
    }

    if (!isLockEnabled && !isExpired) {
      // User disabled app lock in settings and session active
      state = state.copyWith(
        isLocked: false,
        isSupported: canAuth,
        activeMode: storedMode ?? AccountMode.personal,
        biometricLabel: bioLabel,
        hasFaceId: hasFace,
        hasFingerprint: hasFinger,
        isAuthExpired: false,
      );
      return;
    }

    state = state.copyWith(
      isLocked: true,
      isSupported: canAuth,
      showFallbackPin:
          !canAuth, // If no biometrics on device, show fallback PIN immediately
      activeMode: storedMode ?? AccountMode.personal,
      biometricLabel: bioLabel,
      hasFaceId: hasFace,
      hasFingerprint: hasFinger,
      isAuthExpired: isExpired,
    );

    // Auto-prompt on launch if supported and currently locked
    if (canAuth && state.isLocked) {
      await authenticate();
    }
  }

  /// Check session expiration on app resume
  Future<void> checkSessionExpiration() async {
    final expired = await _storage.isAuthExpired();
    if (expired) {
      state = state.copyWith(isLocked: true, isAuthExpired: true);
    }
  }

  /// Set explicit auth expired state (e.g. on 401 Unauthorized API response)
  void setAuthExpired(bool expired) {
    state = state.copyWith(
        isLocked: expired ? true : state.isLocked, isAuthExpired: expired);
  }

  /// Trigger biometric/passcode prompt
  Future<bool> authenticate() async {
    state = state.copyWith(isAuthenticating: true);

    final result = await _appLockService.authenticate(
      localizedReason: 'Unlock FlowPay with Biometrics or Passcode',
    );

    if (result.success) {
      await _storage.updateAuthTimestamp();
      state = state.copyWith(
        isLocked: false,
        isAuthenticating: false,
        isAuthExpired: false,
        lastResult: result,
      );
      return true;
    } else {
      // If user canceled or failed, give option for in-app fallback PIN
      final shouldShowPin = result.status == AppLockStatus.notSupported ||
          result.status == AppLockStatus.notEnrolled ||
          result.status == AppLockStatus.passcodeNotSet ||
          result.status == AppLockStatus.userCanceled;

      state = state.copyWith(
        isLocked: true,
        isAuthenticating: false,
        lastResult: result,
        showFallbackPin: shouldShowPin,
      );
      return false;
    }
  }

  /// Fallback In-App PIN Entry (6 digits)
  Future<bool> verifyFallbackPin(String pin) async {
    final isValid = await _storage.verifyFallbackPin(pin);
    if (isValid) {
      await _storage.updateAuthTimestamp();
      state = state.copyWith(
        isLocked: false,
        isAuthExpired: false,
        showFallbackPin: false,
        lastResult: AppLockAuthResult.success(),
      );
      return true;
    }
    return false;
  }

  /// Show or hide manual fallback PIN
  void setShowFallbackPin(bool show) {
    state = state.copyWith(showFallbackPin: show);
  }

  /// Lock app on background pause
  void lockApp() {
    state = state.copyWith(isLocked: true);
  }

  /// Change active Account Mode and persist to secure storage
  Future<void> setAccountMode(AccountMode mode) async {
    _ref.read(currentAccountModeProvider.notifier).state = mode;
    state = state.copyWith(activeMode: mode);
    await _storage.saveAccountMode(mode);
  }

  /// Reset to signup flow (for testing or switching accounts)
  Future<void> resetToSignup() async {
    await _storage.resetSession();
    _ref.read(currentUserProfileProvider.notifier).clearProfile();
    state = state.copyWith(isLocked: true);
  }

  /// Direct login as a specific persona (e.g. personal, business, or demo master)
  Future<void> loginAsPersona(UserProfile profile, {String? pin}) async {
    await _storage.saveUserProfile(profile);
    await _storage.setKycCompleted(true);
    if (pin != null) {
      await _storage.setFallbackPin(pin);
    }
    final mode = profile.accountType == AccountType.personal
        ? AccountMode.personal
        : AccountMode.business;
    await setAccountMode(mode);
    await _ref.read(currentUserProfileProvider.notifier).saveProfile(profile);
    await _ref.read(currentUserProfileProvider.notifier).setKycVerified();
    state = state.copyWith(isLocked: false, activeMode: mode);
  }
}

final appLockStateProvider =
    StateNotifierProvider<AppLockNotifier, AppLockState>((ref) {
  final appLockService = ref.watch(appLockServiceProvider);
  final storage = ref.watch(secureStorageServiceProvider);
  return AppLockNotifier(
    appLockService: appLockService,
    storage: storage,
    ref: ref,
  );
});
