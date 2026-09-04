import 'package:flutter/material.dart';
import '../network/api_client.dart';
import '../providers/bmoni/bmoni_activity_repo.dart';
import '../providers/bmoni/bmoni_approval_repo.dart';
import '../providers/bmoni/bmoni_business_audit_repo.dart';
import '../providers/bmoni/bmoni_card_repo.dart';
import '../providers/bmoni/bmoni_employee_repo.dart';
import '../providers/bmoni/bmoni_mission_repo.dart';
import '../providers/bmoni/bmoni_payroll_repo.dart';
import '../providers/bmoni/bmoni_transfer_repo.dart';
import '../providers/bmoni/bmoni_wallet_repo.dart';
import '../providers/demo/demo_activity_repo.dart';
import '../providers/demo/demo_approval_repo.dart';
import '../providers/demo/demo_business_audit_repo.dart';
import '../providers/demo/demo_card_repo.dart';
import '../providers/demo/demo_employee_repo.dart';
import '../providers/demo/demo_mission_repo.dart';
import '../providers/demo/demo_payroll_repo.dart';
import '../providers/demo/demo_transfer_repo.dart';
import '../providers/demo/demo_wallet_repo.dart';
import '../repositories/activity_repository.dart';
import '../repositories/approval_repository.dart';
import '../repositories/business_audit_repository.dart';
import '../repositories/card_repository.dart';
import '../repositories/employee_repository.dart';
import '../repositories/mission_repository.dart';
import '../repositories/payroll_repository.dart';
import '../repositories/transfer_repository.dart';
import '../repositories/wallet_repository.dart';
import 'business_provider.dart';
import 'personal_provider.dart';

enum AppRole { personal, business }

enum ProviderMode { demo, bmoniSandbox }

class AppState extends ChangeNotifier {
  AppRole _activeRole = AppRole.personal;
  ProviderMode _providerMode;
  ThemeMode _themeMode = ThemeMode.dark;
  int _personalTabIndex = 0;

  final FlowPayApiClient _apiClient = FlowPayApiClient();

  // Demo Repositories (for isolated widget testing)
  final DemoWalletRepository _demoWallet = DemoWalletRepository();
  final DemoActivityRepository _demoActivity = DemoActivityRepository();
  late final DemoTransferRepository _demoTransfer = DemoTransferRepository(
    activityRepo: _demoActivity,
    walletRepo: _demoWallet,
  );
  final DemoCardRepository _demoCard = DemoCardRepository();
  final DemoEmployeeRepository _demoEmployee = DemoEmployeeRepository();
  final DemoPayrollRepository _demoPayroll = DemoPayrollRepository();
  late final DemoMissionRepository _demoMission = DemoMissionRepository(
    activityRepo: _demoActivity,
    walletRepo: _demoWallet,
  );
  final DemoApprovalRepository _demoApproval = DemoApprovalRepository();
  late final DemoBusinessAuditRepository _demoAudit =
      DemoBusinessAuditRepository(
    payrollRepo: _demoPayroll,
    cardRepo: _demoCard,
    walletRepo: _demoWallet,
    activityRepo: _demoActivity,
  );

  // BMONI Live Repositories (connected to FlowPay backend & Supabase DB)
  late final BmoniWalletRepository _bmoniWallet =
      BmoniWalletRepository(apiClient: _apiClient);
  late final BmoniTransferRepository _bmoniTransfer =
      BmoniTransferRepository(apiClient: _apiClient);
  late final BmoniCardRepository _bmoniCard =
      BmoniCardRepository(apiClient: _apiClient);
  late final BmoniEmployeeRepository _bmoniEmployee =
      BmoniEmployeeRepository(apiClient: _apiClient);
  late final BmoniPayrollRepository _bmoniPayroll =
      BmoniPayrollRepository(apiClient: _apiClient);
  late final BmoniActivityRepository _bmoniActivity =
      BmoniActivityRepository(apiClient: _apiClient);
  late final BmoniMissionRepository _bmoniMission =
      BmoniMissionRepository(apiClient: _apiClient);
  late final BmoniApprovalRepository _bmoniApproval =
      BmoniApprovalRepository(apiClient: _apiClient);
  late final BmoniBusinessAuditRepository _bmoniAudit =
      BmoniBusinessAuditRepository(
    payrollRepo: _bmoniPayroll,
    cardRepo: _bmoniCard,
    walletRepo: _bmoniWallet,
    activityRepo: _bmoniActivity,
  );

  // Business Providers
  late final BusinessProvider _demoBusinessProvider = BusinessProvider(
    employeeRepo: _demoEmployee,
    payrollRepo: _demoPayroll,
    walletRepo: _demoWallet,
    cardRepo: _demoCard,
    auditRepo: _demoAudit,
  );

  late final BusinessProvider _bmoniBusinessProvider = BusinessProvider(
    employeeRepo: _bmoniEmployee,
    payrollRepo: _bmoniPayroll,
    walletRepo: _bmoniWallet,
    cardRepo: _bmoniCard,
    auditRepo: _bmoniAudit,
  );

  // Personal Providers
  late final PersonalProvider _demoPersonalProvider = PersonalProvider(
    walletRepo: _demoWallet,
    activityRepo: _demoActivity,
    missionRepo: _demoMission,
    approvalRepo: _demoApproval,
    transferRepo: _demoTransfer,
  );

  late final PersonalProvider _bmoniPersonalProvider = PersonalProvider(
    walletRepo: _bmoniWallet,
    activityRepo: _bmoniActivity,
    missionRepo: _bmoniMission,
    approvalRepo: _bmoniApproval,
    transferRepo: _bmoniTransfer,
  );

  AppState({ProviderMode providerMode = ProviderMode.demo})
      : _providerMode = providerMode;

  AppRole get activeRole => _activeRole;
  ProviderMode get providerMode => _providerMode;
  ThemeMode get themeMode => _themeMode;
  bool get isDemo => _providerMode == ProviderMode.demo;
  bool get isDarkMode => _themeMode == ThemeMode.dark;
  int get personalTabIndex => _personalTabIndex;

  FlowPayApiClient get apiClient => _apiClient;

  void setUserId(String? userId) {
    _apiClient.setUserId(userId);
  }

  // Active Repositories
  WalletRepository get walletRepo => isDemo ? _demoWallet : _bmoniWallet;
  TransferRepository get transferRepo =>
      isDemo ? _demoTransfer : _bmoniTransfer;
  CardRepository get cardRepo => isDemo ? _demoCard : _bmoniCard;
  EmployeeRepository get employeeRepo =>
      isDemo ? _demoEmployee : _bmoniEmployee;
  PayrollRepository get payrollRepo => isDemo ? _demoPayroll : _bmoniPayroll;
  ActivityRepository get activityRepo =>
      isDemo ? _demoActivity : _bmoniActivity;
  MissionRepository get missionRepo => isDemo ? _demoMission : _bmoniMission;
  ApprovalRepository get approvalRepo =>
      isDemo ? _demoApproval : _bmoniApproval;
  BusinessAuditRepository get auditRepo => isDemo ? _demoAudit : _bmoniAudit;

  // Active Providers
  BusinessProvider get businessProvider =>
      isDemo ? _demoBusinessProvider : _bmoniBusinessProvider;
  PersonalProvider get personalProvider =>
      isDemo ? _demoPersonalProvider : _bmoniPersonalProvider;

  void setRole(AppRole role) {
    if (_activeRole != role) {
      _activeRole = role;
      notifyListeners();
    }
  }

  void setPersonalTabIndex(int index) {
    if (_personalTabIndex != index) {
      _personalTabIndex = index;
      notifyListeners();
    }
  }

  void toggleRole() {
    setRole(
        _activeRole == AppRole.personal ? AppRole.business : AppRole.personal);
  }

  void setProviderMode(ProviderMode mode) {
    if (_providerMode != mode) {
      _providerMode = mode;
      notifyListeners();
    }
  }

  void setThemeMode(ThemeMode mode) {
    if (_themeMode != mode) {
      _themeMode = mode;
      notifyListeners();
    }
  }

  void toggleTheme() {
    setThemeMode(
        _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);
  }
}
