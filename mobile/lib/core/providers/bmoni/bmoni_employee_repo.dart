import '../../config/api_config.dart';
import '../../money/currency.dart';
import '../../money/money.dart';
import '../../network/api_client.dart';
import '../../repositories/employee_repository.dart';

class BmoniEmployeeRepository implements EmployeeRepository {
  final FlowPayApiClient apiClient;

  BmoniEmployeeRepository({required this.apiClient});

  @override
  Future<List<EmployeeModel>> getEmployees() async {
    try {
      final res = await apiClient.get('/api/employees');
      final list = (res is Map && res['data'] is List)
          ? res['data'] as List
          : (res is Map && res['data'] is Map && res['data']['items'] is List)
              ? res['data']['items'] as List
              : (res is Map && res['items'] is List)
                  ? res['items'] as List
                  : (res is List ? res : []);

      return list
          .map((e) => EmployeeModel.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      return [];
    }
  }

  @override
  Future<EmployeeModel> getEmployeeById(String id) async {
    final res = await apiClient.get('/api/employees/$id');
    final data = (res is Map && res['data'] is Map)
        ? res['data'] as Map<String, dynamic>
        : (res as Map<String, dynamic>);
    return EmployeeModel.fromJson(data);
  }

  @override
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
  }) async {
    final res = await apiClient.post('/api/employees', body: {
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      if (phoneNumber != null) 'phoneNumber': phoneNumber,
      'country': country,
      if (countryName != null) 'countryName': countryName,
      'targetCurrency': targetCurrency.code,
      'payrollAmountMinor': payrollAmount.minorUnits,
      if (usdPayrollAmount != null)
        'usdPayrollAmountMinor': usdPayrollAmount.minorUnits,
    });

    final rawUrl = res['data']?['inviteUrl'] ?? res['inviteUrl'];
    final rawToken = res['data']?['inviteToken'] ??
        res['inviteToken'] ??
        res['data']?['employee']?['id'];
    final inviteUrl = rawUrl ??
        (rawToken != null
            ? '${ApiConfig.baseUrl}/invite/$rawToken'
            : '${ApiConfig.baseUrl}/invite');
    return inviteUrl.toString();
  }

  @override
  Future<String> inviteEmployee({
    required String firstName,
    required String lastName,
    required String email,
    required String country,
    String? countryName,
    required Currency targetCurrency,
    Money? payrollAmount,
    Money? usdPayrollAmount,
  }) {
    return createEmployee(
      firstName: firstName,
      lastName: lastName,
      email: email,
      country: country,
      countryName: countryName,
      targetCurrency: targetCurrency,
      payrollAmount:
          payrollAmount ?? Money.fromMajorString('2000.00', targetCurrency),
      usdPayrollAmount: usdPayrollAmount,
    );
  }

  // --- Multi-Stage Onboarding Implementations ---

  @override
  Future<Map<String, dynamic>> requestOwnerChallenge(
      String employeeId, String userOwnerAddress) async {
    final res = await apiClient
        .post('/api/employees/$employeeId/onboarding/challenge', body: {
      'userOwnerAddress': userOwnerAddress,
    });
    return (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : {};
  }

  @override
  Future<Map<String, dynamic>> provisionSmartWallet(
    String employeeId, {
    required String userOwnerAddress,
    required String ownerProofChallengeId,
    required String ownerProofSignature,
  }) async {
    final res = await apiClient
        .post('/api/employees/$employeeId/onboarding/wallet', body: {
      'userOwnerAddress': userOwnerAddress,
      'ownerProofChallengeId': ownerProofChallengeId,
      'ownerProofSignature': ownerProofSignature,
    });
    return (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : {};
  }

  @override
  Future<Map<String, dynamic>> getKycOptions(String employeeId) async {
    final res = await apiClient
        .get('/api/employees/$employeeId/onboarding/kyc/options');
    return (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : {};
  }

  @override
  Future<Map<String, dynamic>> submitCountryKyc(
      String employeeId, Map<String, dynamic> kycPayload) async {
    final res = await apiClient.post(
        '/api/employees/$employeeId/onboarding/kyc/submit',
        body: kycPayload);
    return (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : {};
  }

  @override
  Future<Map<String, dynamic>> checkKycReadiness(String employeeId) async {
    final res = await apiClient
        .get('/api/employees/$employeeId/onboarding/kyc/readiness');
    return (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : {'ready': true};
  }

  @override
  Future<Map<String, dynamic>> activateKyc(String employeeId) async {
    final res = await apiClient
        .post('/api/employees/$employeeId/onboarding/kyc/activate', body: {});
    return (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : {'success': true};
  }

  @override
  Future<Map<String, dynamic>> getMexicoAgreements(String employeeId) async {
    final res = await apiClient
        .get('/api/employees/$employeeId/onboarding/mx/agreements');
    return (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : {};
  }

  @override
  Future<Map<String, dynamic>> activateRail(String employeeId,
      {Map<String, dynamic>? options}) async {
    final res = await apiClient.post(
        '/api/employees/$employeeId/onboarding/activate-rail',
        body: options ?? {});
    return (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : {};
  }

  @override
  Future<EmployeeOnboardingStatusModel> getOnboardingStatus(
      String employeeId) async {
    final res =
        await apiClient.get('/api/employees/$employeeId/onboarding/status');
    final data = (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : <String, dynamic>{};
    return EmployeeOnboardingStatusModel.fromJson(data);
  }

  @override
  Future<EmployeeOnboardingStatusModel> retryOnboarding(
      String employeeId) async {
    final res = await apiClient
        .post('/api/employees/$employeeId/onboarding/retry', body: {});
    final data = (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : <String, dynamic>{};
    return EmployeeOnboardingStatusModel.fromJson(data);
  }

  @override
  Future<EmployeeOnboardingStatusModel> retryStage(
          String employeeId, int stage) =>
      retryOnboarding(employeeId);

  @override
  Future<EmployeeOnboardingStatusModel> simulateWebhookCompleted(
      String employeeId) async {
    final res = await apiClient.post(
        '/api/employees/$employeeId/onboarding/simulate-complete',
        body: {});
    final data = (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'])
        : <String, dynamic>{};
    return EmployeeOnboardingStatusModel.fromJson(data);
  }

  @override
  Future<Map<String, dynamic>> getInviteDetails(String codeOrId) async {
    final res = await apiClient.get('/api/employees/invite/$codeOrId');
    if (res is Map && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    throw StateError('Invalid response when fetching invite details');
  }

  @override
  Future<EmployeeModel> retryUserCreation(String employeeId) async {
    final res =
        await apiClient.post('/api/employees/$employeeId/retry-user-creation');
    final data = (res is Map && res['data'] is Map)
        ? Map<String, dynamic>.from(res['data'] as Map)
        : (res is Map ? Map<String, dynamic>.from(res) : <String, dynamic>{});
    return EmployeeModel.fromJson(data);
  }

  @override
  Future<Map<String, dynamic>> linkEmployeeWallet({
    required String employeeId,
    required String inviteToken,
    required String bmoniUserId,
    required String walletAddress,
    String? walletId,
    String? sessionToken,
  }) async {
    final headers = <String, String>{};
    if (sessionToken != null && sessionToken.isNotEmpty) {
      headers['Authorization'] = 'Bearer $sessionToken';
    }
    headers['x-user-id'] = bmoniUserId;

    final res = await apiClient.post(
      '/api/employees/link-wallet',
      headers: headers,
      body: {
        'employeeId': employeeId,
        'inviteToken': inviteToken,
        'bmoniUserId': bmoniUserId,
        'walletAddress': walletAddress,
        if (walletId != null) 'walletId': walletId,
        'requestingUserId': bmoniUserId,
      },
    );

    if (res is Map && res['data'] is Map) {
      return Map<String, dynamic>.from(res['data'] as Map);
    }
    return (res is Map) ? Map<String, dynamic>.from(res) : {};
  }
}

