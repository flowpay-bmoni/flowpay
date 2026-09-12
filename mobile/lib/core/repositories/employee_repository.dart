import '../money/currency.dart';
import '../money/money.dart';

/// The 6 lifecycle stages of an employee on FlowPay & BMONI rails:
/// 1. CREATED - User registered on BMONI rails (POST /v1/users), has bmoniUserId
/// 2. WALLET_PENDING - Awaiting on-device smart wallet provisioning & owner challenge
/// 3. KYC_PENDING - Awaiting KYC documents submission (or kyc.action_required)
/// 4. ONBOARDING - KYC under verification by provider
/// 5. READY - KYC verified, VBA provisioned, smart wallet active, ready for payroll
/// 6. FAILED - Onboarding or KYC failed; see failedStage
class EmployeeLifecycleStages {
  static const String invited = 'INVITED';
  static const String created = 'CREATED';
  static const String walletPending = 'WALLET_PENDING';
  static const String kycPending = 'KYC_PENDING';
  static const String onboarding = 'ONBOARDING';
  static const String ready = 'READY';
  static const String failed = 'FAILED';
}

class EmployeeModel {
  final String id;
  final String? bmoniUserId;
  final String firstName;
  final String lastName;
  final String email;
  final String? phoneNumber;
  final String country; // "NG", "MX", "CA"
  final String countryName; // "Nigeria", "Mexico", "Canada"
  final Currency targetCurrency;
  final String
      status; // CREATED, WALLET_PENDING, KYC_PENDING, ONBOARDING, READY, FAILED
  final String? failedStage;
  final String
      onboardingStatus; // CREATED, WALLET_PENDING, KYC_PENDING, ONBOARDING, READY, FAILED
  final String walletStatus; // ACTIVE, PROVISIONED, PENDING, NONE
  final String cardStatus; // ACTIVE, ISSUED, FROZEN, PENDING
  final Money? payrollAmount;
  final Money? usdPayrollAmount;
  final String? walletAddress;
  final String? cardId;
  final String? cardLast4;
  final String? failureReason;

  const EmployeeModel({
    required this.id,
    this.bmoniUserId,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phoneNumber,
    required this.country,
    this.countryName = '',
    required this.targetCurrency,
    required this.status,
    this.failedStage,
    this.onboardingStatus = 'READY',
    this.walletStatus = 'ACTIVE',
    this.cardStatus = 'ACTIVE',
    this.payrollAmount,
    this.usdPayrollAmount,
    this.walletAddress,
    this.cardId,
    this.cardLast4,
    this.failureReason,
  });

  String get fullName => '$firstName $lastName';
  double get salaryAmount => payrollAmount?.majorUnits ?? 0;

  bool get isReady => status.toUpperCase() == EmployeeLifecycleStages.ready;
  bool get isFailed => status.toUpperCase() == EmployeeLifecycleStages.failed;

  /// Collapses the detailed lifecycle stage into the simple 3-state label
  /// product/design actually wants surfaced in list rows: Pending, Onboarded,
  /// or Failed. Use `status`/`onboardingStatus` directly when you need the
  /// full-fidelity stage (e.g. for the multi-stage onboarding screen).
  String get simpleStatusLabel {
    final s = status.toUpperCase();
    if (s == EmployeeLifecycleStages.ready ||
        s == 'ACTIVE' ||
        s == 'LINKED') {
      return 'Onboarded';
    }
    if (s == EmployeeLifecycleStages.failed) {
      return 'Failed';
    }
    // INVITED, CREATED, WALLET_PENDING, KYC_PENDING, ONBOARDING all read as
    // "Pending" to a business owner glancing at the team list.
    return 'Pending';
  }

  /// Short, human-friendly wallet identifier for list/detail display.
  /// Falls back to the wallet id if the on-chain address isn't set yet.
  String? get displayWalletId {
    final addr = walletAddress;
    if (addr != null && addr.isNotEmpty) {
      if (addr.length > 12) {
        return '${addr.substring(0, 6)}…${addr.substring(addr.length - 4)}';
      }
      return addr;
    }
    return null;
  }

  String get resolvedCountryName {
    if (countryName.isNotEmpty) return countryName;
    switch (country.toUpperCase()) {
      case 'NG':
        return 'Nigeria';
      case 'MX':
        return 'Mexico';
      case 'CA':
        return 'Canada';
      default:
        return country;
    }
  }

  String get flagEmoji {
    switch (country.toUpperCase()) {
      case 'NG':
        return '🇳🇬';
      case 'MX':
        return '🇲🇽';
      case 'CA':
        return '🇨🇦';
      default:
        return '🌐';
    }
  }

  factory EmployeeModel.fromJson(Map<String, dynamic> json) {
    final countryCode = (json['country'] ?? 'NG').toString().toUpperCase();
    final targetCurr = Currency.fromCode(
        json['target_currency'] ?? json['targetCurrency'] ?? 'USD');

    // Parse payroll amount
    Money? payroll;
    final rawPayroll = json['payroll_amount_minor'] ??
        json['payrollAmountMinor'] ??
        json['payroll_amount'] ??
        json['payrollAmount'];
    if (rawPayroll != null && rawPayroll is num) {
      payroll = Money.fromMinor(rawPayroll.toInt(), targetCurr);
    } else if (rawPayroll != null) {
      final parsed = int.tryParse(rawPayroll.toString());
      if (parsed != null) {
        payroll = Money.fromMinor(parsed, targetCurr);
      }
    }

    Money? usdPayroll;
    final rawUsdPayroll = json['usd_payroll_amount_minor'] ??
        json['usdPayrollAmountMinor'] ??
        json['usd_payroll_amount'] ??
        json['usdPayrollAmount'];
    if (rawUsdPayroll != null && rawUsdPayroll is num) {
      usdPayroll = Money.fromMinor(rawUsdPayroll.toInt(), Currency.usd);
    } else if (rawUsdPayroll != null) {
      final parsed = int.tryParse(rawUsdPayroll.toString());
      if (parsed != null) {
        usdPayroll = Money.fromMinor(parsed, Currency.usd);
      }
    }

    final rawStatus = (json['status'] ?? 'CREATED').toString().toUpperCase();

    final walletAddr = json['wallet_address'] ?? json['walletAddress'];
    final cardIdVal = json['card_id'] ?? json['cardId'];

    // Derive wallet/card status TRUTHFULLY. The backend does not send
    // wallet_status/card_status columns, so we must infer them from real data
    // instead of fabricating 'ACTIVE'. Showing a fake ACTIVE wallet/card on a
    // FAILED or not-yet-onboarded employee hides real state in a fintech app.
    final explicitWalletStatus = json['wallet_status'] ?? json['walletStatus'];
    final derivedWalletStatus = explicitWalletStatus ??
        ((walletAddr != null && walletAddr.toString().isNotEmpty)
            ? 'ACTIVE'
            : 'NONE');

    final explicitCardStatus = json['card_status'] ?? json['cardStatus'];
    final derivedCardStatus = explicitCardStatus ??
        ((cardIdVal != null && cardIdVal.toString().isNotEmpty)
            ? 'ACTIVE'
            : 'NONE');

    return EmployeeModel(
      id: json['id'] ?? '',
      bmoniUserId: json['bmoni_user_id'] ?? json['bmoniUserId'],
      firstName: json['first_name'] ?? json['firstName'] ?? '',
      lastName: json['last_name'] ?? json['lastName'] ?? '',
      email: json['email'] ?? '',
      phoneNumber: json['phone_number'] ?? json['phoneNumber'],
      country: countryCode,
      countryName: json['country_name'] ?? json['countryName'] ?? '',
      targetCurrency: targetCurr,
      status: rawStatus,
      failedStage: json['failed_stage'] ?? json['failedStage'],
      onboardingStatus:
          json['onboarding_status'] ?? json['onboardingStatus'] ?? rawStatus,
      walletStatus: derivedWalletStatus,
      cardStatus: derivedCardStatus,
      payrollAmount: payroll,
      usdPayrollAmount: usdPayroll,
      walletAddress: walletAddr,
      cardId: cardIdVal,
      // Only surface a real last-4; never invent one.
      cardLast4: json['card_last4'] ?? json['cardLast4'],
      failureReason: json['failure_reason'] ?? json['failureReason'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'bmoniUserId': bmoniUserId,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'phoneNumber': phoneNumber,
      'country': country,
      'countryName': countryName,
      'targetCurrency': targetCurrency.code,
      'status': status,
      'failedStage': failedStage,
      'onboardingStatus': onboardingStatus,
      'walletStatus': walletStatus,
      'cardStatus': cardStatus,
      'payrollAmountMinor': payrollAmount?.minorUnits,
      'usdPayrollAmountMinor': usdPayrollAmount?.minorUnits,
      'walletAddress': walletAddress,
      'cardId': cardId,
      'cardLast4': cardLast4,
      'failureReason': failureReason,
    };
  }
}

enum OnboardingStageState {
  notStarted('Not Started'),
  inProgress('In Progress'),
  ready('Ready'),
  failed('Failed');

  final String label;
  const OnboardingStageState(this.label);

  static OnboardingStageState fromString(String val) {
    final lower = val.toLowerCase().replaceAll(' ', '_');
    if (lower.contains('ready')) return OnboardingStageState.ready;
    if (lower.contains('fail')) return OnboardingStageState.failed;
    if (lower.contains('progress')) return OnboardingStageState.inProgress;
    return OnboardingStageState.notStarted;
  }
}

class StageDetailModel {
  final int stageNumber;
  final String title;
  final OnboardingStageState state;
  final Map<String, dynamic> details;
  final String description;

  const StageDetailModel({
    required this.stageNumber,
    required this.title,
    required this.state,
    this.details = const {},
    this.description = '',
  });

  factory StageDetailModel.fromJson(Map<String, dynamic> json) {
    return StageDetailModel(
      stageNumber: json['stageNumber'] ?? 2,
      title: json['title'] ?? '',
      state: OnboardingStageState.fromString(json['state'] ?? 'Not Started'),
      details: json['details'] != null
          ? Map<String, dynamic>.from(json['details'])
          : {},
    );
  }
}

class EmployeeOnboardingStatusModel {
  final String employeeId;
  final String bmoniUserId;
  final String country;
  final String targetCurrency;
  final String stablecoinToken;
  final OnboardingStageState overallState;
  final int currentStage; // 2, 3, or 4
  final int? failedStage;
  final String? failureReason;
  final StageDetailModel stage2Wallet;
  final StageDetailModel stage3Kyc;
  final StageDetailModel stage4Rail;

  const EmployeeOnboardingStatusModel({
    required this.employeeId,
    required this.bmoniUserId,
    required this.country,
    required this.targetCurrency,
    required this.stablecoinToken,
    required this.overallState,
    required this.currentStage,
    this.failedStage,
    this.failureReason,
    required this.stage2Wallet,
    required this.stage3Kyc,
    required this.stage4Rail,
  });

  List<StageDetailModel> get stages => [stage2Wallet, stage3Kyc, stage4Rail];

  factory EmployeeOnboardingStatusModel.fromJson(Map<String, dynamic> json) {
    final stages = json['stages'] ?? {};
    return EmployeeOnboardingStatusModel(
      employeeId: json['employeeId'] ?? '',
      bmoniUserId: json['bmoniUserId'] ?? '',
      country: json['country'] ?? 'NG',
      targetCurrency: json['targetCurrency'] ?? 'NGN',
      stablecoinToken: json['stablecoinToken'] ?? 'CNGN',
      overallState: OnboardingStageState.fromString(
          json['overallState'] ?? 'Not Started'),
      currentStage: json['currentStage'] ?? 2,
      failedStage: json['failedStage'],
      failureReason: json['failureReason'],
      stage2Wallet: StageDetailModel.fromJson(stages['stage2Wallet'] ??
          {
            'stageNumber': 2,
            'title': 'Smart Wallet Provisioning',
            'state': 'Not Started'
          }),
      stage3Kyc: StageDetailModel.fromJson(stages['stage3Kyc'] ??
          {
            'stageNumber': 3,
            'title': 'Identity & KYC Verification',
            'state': 'Not Started'
          }),
      stage4Rail: StageDetailModel.fromJson(stages['stage4Rail'] ??
          {
            'stageNumber': 4,
            'title': 'Rail Activation',
            'state': 'Not Started'
          }),
    );
  }
}

abstract class EmployeeRepository {
  Future<List<EmployeeModel>> getEmployees();
  Future<EmployeeModel> getEmployeeById(String id);

  /// Primary employee creation method calling POST /api/employees
  Future<String> createEmployee({
    required String firstName,
    required String lastName,
    required String email,
    String? phoneNumber,
    required String country,
    String? countryName,
    required Currency targetCurrency,
    required Money payrollAmount,
    Money? usdPayrollAmount,
  });

  /// Backward compatible legacy wrapper
  @Deprecated('Use createEmployee instead.')
  Future<String> inviteEmployee({
    required String firstName,
    required String lastName,
    required String email,
    required String country,
    String? countryName,
    required Currency targetCurrency,
    Money? payrollAmount,
    Money? usdPayrollAmount,
  });

  // --- Multi-Stage Onboarding Methods ---
  Future<Map<String, dynamic>> requestOwnerChallenge(
      String employeeId, String userOwnerAddress);

  Future<Map<String, dynamic>> provisionSmartWallet(
    String employeeId, {
    required String userOwnerAddress,
    required String ownerProofChallengeId,
    required String ownerProofSignature,
  });

  Future<Map<String, dynamic>> getKycOptions(String employeeId);

  Future<Map<String, dynamic>> submitCountryKyc(
      String employeeId, Map<String, dynamic> kycPayload);

  Future<Map<String, dynamic>> checkKycReadiness(String employeeId);

  Future<Map<String, dynamic>> activateKyc(String employeeId);

  Future<Map<String, dynamic>> getMexicoAgreements(String employeeId);

  Future<Map<String, dynamic>> activateRail(String employeeId,
      {Map<String, dynamic>? options});

  Future<EmployeeOnboardingStatusModel> getOnboardingStatus(String employeeId);

  Future<EmployeeOnboardingStatusModel> retryOnboarding(String employeeId);

  Future<EmployeeOnboardingStatusModel> retryStage(
          String employeeId, int stage) =>
      retryOnboarding(employeeId);

  Future<EmployeeOnboardingStatusModel> simulateWebhookCompleted(
      String employeeId);

  /// Resolves employee invitation details (email, company, salary, currency) by inviteToken or inviteCode.
  Future<Map<String, dynamic>> getInviteDetails(String codeOrId);

  /// Re-attempts BMONI user creation for an employee stuck at FAILED /
  /// BMONI_USER_CREATION. Returns the updated employee record.
  Future<EmployeeModel> retryUserCreation(String employeeId);

  /// Links the employee's on-device self-custody smart wallet to the invited employee record.
  Future<Map<String, dynamic>> linkEmployeeWallet({
    required String employeeId,
    required String inviteToken,
    required String bmoniUserId,
    required String walletAddress,
    String? walletId,
    String? sessionToken,
  });
}

