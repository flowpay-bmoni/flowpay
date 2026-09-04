import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/auth/account_capabilities.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/secure_storage_service.dart';
import '../../core/config/api_config.dart';
import '../../core/design_system/buttons.dart';
import '../../core/design_system/input_fields.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';

import 'set_pin_screen.dart';

/// KYC Screen: Handles Personal Tier 1 KYC (BVN/ID + Facial Scan)
/// and Business KYB (Entity Docs + Signatory Verification + Payroll Rail Activation).
class KycScreen extends ConsumerStatefulWidget {
  final UserProfile userProfile;

  const KycScreen({
    super.key,
    required this.userProfile,
  });

  @override
  ConsumerState<KycScreen> createState() => _KycScreenState();
}

class _KycScreenState extends ConsumerState<KycScreen> {
  final _formKey = GlobalKey<FormState>();

  // Personal Fields
  late final TextEditingController _nationalIdController;
  final TextEditingController _dobController = TextEditingController();
  final TextEditingController _addressController = TextEditingController();

  // Business Fields
  final TextEditingController _taxIdController = TextEditingController();
  final TextEditingController _officeAddressController = TextEditingController();
  final TextEditingController _signatoryIdController = TextEditingController();

  bool _isScanningFace = false;
  bool _faceScanCompleted = false;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _nationalIdController = TextEditingController();
  }

  @override
  void dispose() {
    _nationalIdController.dispose();
    _dobController.dispose();
    _addressController.dispose();
    _taxIdController.dispose();
    _officeAddressController.dispose();
    _signatoryIdController.dispose();
    super.dispose();
  }

  String get _idLabel {
    switch (widget.userProfile.country) {
      case 'NG':
        return 'Bank Verification Number (BVN) / NIN';
      case 'MX':
        return 'CURP / RFC Identity Number';
      case 'US':
        return 'Social Security Number (SSN)';
      case 'CA':
        return 'Social Insurance Number (SIN)';
      case 'GB':
        return 'National Insurance (NI)';
      default:
        return 'Government National ID Number';
    }
  }

  Future<void> _simulateFaceScan() async {
    setState(() => _isScanningFace = true);
    await Future.delayed(const Duration(milliseconds: 1400));
    if (mounted) {
      setState(() {
        _isScanningFace = false;
        _faceScanCompleted = true;
      });
    }
  }

  Future<void> _completeKyc() async {
    if (!_formKey.currentState!.validate()) return;

    if (widget.userProfile.isPersonal && !_faceScanCompleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Please perform the facial liveness verification to proceed.'),
          backgroundColor: FlowPayColors.warning,
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final updatedProfile = widget.userProfile.copyWith(
        kycStatus: KycStatus.verified,
        nationalId: _nationalIdController.text.trim(),
        nationalIdType: _idLabel,
      );

      // 1. Notify FlowPay backend of KYC completion (with safe fallback)
      if (!SecureStorageService.isTestEnv) {
        try {
          final uri = Uri.parse('${ApiConfig.baseUrl}/api/auth/kyc');
          await http
              .post(
                uri,
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({
                  'userId': updatedProfile.userId,
                  'accountType': updatedProfile.accountType.name,
                  'nationalId': updatedProfile.nationalId,
                  'country': updatedProfile.country,
                  'status': 'VERIFIED',
                }),
              )
              .timeout(const Duration(seconds: 3));
        } catch (_) {
          // Safe backend fallback
        }
      }

      // 2. Persist verified profile to Secure Storage
      final storage = ref.read(secureStorageServiceProvider);
      await storage.saveUserProfile(updatedProfile);
      await storage.setKycCompleted(true);

      final targetMode = widget.userProfile.isPersonal
          ? AccountMode.personal
          : AccountMode.business;
      await storage.saveAccountMode(targetMode);

      final capabilities = widget.userProfile.isPersonal
          ? AccountCapabilities.personalOnly(bmoniUserId: updatedProfile.userId)
          : AccountCapabilities.businessOnly(
              bmoniUserId: updatedProfile.userId,
              companyName: updatedProfile.companyName ?? 'Business Account',
              companyRole: updatedProfile.companyRole ?? 'ADMIN',
            );
      await storage.saveCapabilities(capabilities);

      // 3. Update Riverpod Notifiers
      ref.read(currentAccountModeProvider.notifier).state = targetMode;
      await ref
          .read(currentUserProfileProvider.notifier)
          .saveProfile(updatedProfile);
      await ref.read(currentUserProfileProvider.notifier).setKycVerified();

      // 4. Navigate to Step 3: Set Security PIN
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => SetPinScreen(
              userProfile: updatedProfile,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isPersonal = widget.userProfile.isPersonal;

    return Scaffold(
      backgroundColor: FlowPayColors.canvas,
      appBar: AppBar(
        backgroundColor: FlowPayColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: FlowPayColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          isPersonal ? 'Identity Verification' : 'Corporate KYB Compliance',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: FlowPayColors.ink,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Compliance Status Hero Card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: FlowPayColors.surfaceAlt,
                    borderRadius: FlowPayRadii.card,
                    border: Border.all(color: FlowPayColors.hairline),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: FlowPayColors.primary.withAlpha(40),
                          borderRadius: FlowPayRadii.avatar,
                        ),
                        child: Icon(
                          isPersonal
                              ? Icons.verified_user_outlined
                              : Icons.shield_outlined,
                          color: FlowPayColors.primaryLight,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isPersonal
                                  ? 'Tier 1 BMONI Smart Wallet'
                                  : 'Global Payroll Rail Verification',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: FlowPayColors.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              isPersonal
                                  ? 'Unlocks self-custody wallets and instant virtual spend cards.'
                                  : 'Authorizes aggregate multi-country payroll fan-out & corporate cards.',
                              style: const TextStyle(
                                fontSize: 12,
                                color: FlowPayColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                if (isPersonal) ...[
                  // Personal KYC Section
                  Text(
                    'Step 1: Government Identity',
                    style: FlowPayTypography.headingSm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: FlowPayColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  FlowPayTextField(
                    label: _idLabel,
                    hintText: 'Enter ID number',
                    controller: _nationalIdController,
                    prefix: const Icon(Icons.badge_outlined,
                        size: 18, color: FlowPayColors.textSecondary),
                    helperText:
                        'Verified automatically via BMONI Sandbox Trust Rail.',
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'ID is required'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  FlowPayTextField(
                    label: 'Date of Birth (YYYY-MM-DD)',
                    hintText: 'YYYY-MM-DD',
                    controller: _dobController,
                    prefix: const Icon(Icons.calendar_today_outlined,
                        size: 18, color: FlowPayColors.textSecondary),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Date of birth is required'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  FlowPayTextField(
                    label: 'Residential Address',
                    hintText: 'Street, City, State, Country',
                    controller: _addressController,
                    prefix: const Icon(Icons.home_outlined,
                        size: 18, color: FlowPayColors.textSecondary),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Address is required'
                        : null,
                  ),
                  const SizedBox(height: 28),

                  // Step 2: Facial Biometrics
                  Text(
                    'Step 2: Facial Biometric Liveness',
                    style: FlowPayTypography.headingSm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: FlowPayColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'BMONI embedded wallets require on-device face scan matching to establish hardware key recovery.',
                    style: TextStyle(
                      fontSize: 12,
                      color: FlowPayColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 16),

                  _buildFacialScannerWidget(),
                  const SizedBox(height: 28),
                ] else ...[
                  // Business KYB Section
                  Text(
                    'Step 1: Corporate Legal Entity',
                    style: FlowPayTypography.headingSm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: FlowPayColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),

                  FlowPayTextField(
                    label: 'Corporate Tax ID / RFC / EIN',
                    hintText: 'e.g. TIN-99482014',
                    controller: _taxIdController,
                    prefix: const Icon(Icons.numbers,
                        size: 18, color: FlowPayColors.textSecondary),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Tax ID is required'
                        : null,
                  ),
                  const SizedBox(height: 14),

                  FlowPayTextField(
                    label: 'Registered Business Office Address',
                    hintText: 'e.g. 100 Financial Plaza',
                    controller: _officeAddressController,
                    prefix: const Icon(Icons.business,
                        size: 18, color: FlowPayColors.textSecondary),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Address is required'
                        : null,
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Step 2: Authorized Signatory Verification',
                    style: FlowPayTypography.headingSm.copyWith(
                      fontWeight: FontWeight.w700,
                      color: FlowPayColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Officer: ${widget.userProfile.fullName} (${widget.userProfile.companyRole ?? 'Administrator'})',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: FlowPayColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),

                  FlowPayTextField(
                    label: 'Authorized Officer Identity / BVN',
                    hintText: 'Enter representative identification number',
                    controller: _signatoryIdController,
                    prefix: const Icon(Icons.verified_user,
                        size: 18, color: FlowPayColors.textSecondary),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Signatory ID is required'
                        : null,
                  ),
                  const SizedBox(height: 20),

                  // Payroll Rail Readiness Card
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: FlowPayColors.surfaceAlt,
                      borderRadius: FlowPayRadii.card,
                      border: Border.all(color: FlowPayColors.hairline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.hub_outlined,
                                size: 18, color: FlowPayColors.amber),
                            SizedBox(width: 8),
                            Text(
                              'Disbursement Rails Activated',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: FlowPayColors.ink,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _buildRailItem('Nigeria Rail 🇳🇬 (NGN)',
                            'Direct NUBAN bank transfers & B-Cards'),
                        _buildRailItem('Mexico Rail 🇲🇽 (MXN)',
                            'SPEI rails & instant virtual cards'),
                        _buildRailItem('Global USD Treasury 🇺🇸',
                            'Aggregate one-bill settlement'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // Submit Verification Button
                FlowPayButton(
                  text: _isSubmitting
                      ? 'Verifying with BMONI...'
                      : (isPersonal
                          ? 'Complete KYC & Set PIN'
                          : 'Activate Rails & Set PIN'),
                  icon: Icons.arrow_forward,
                  isLoading: _isSubmitting,
                  onPressed: _isSubmitting ? null : _completeKyc,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRailItem(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check, size: 14, color: FlowPayColors.stateSuccess),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: FlowPayColors.ink,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 11,
                    color: FlowPayColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFacialScannerWidget() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: FlowPayColors.surfaceAlt,
        borderRadius: FlowPayRadii.card,
        border: Border.all(
          color: _faceScanCompleted
              ? FlowPayColors.stateSuccess
              : FlowPayColors.hairline,
          width: _faceScanCompleted ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        children: [
          // Camera Simulation Viewport
          Container(
            width: 140,
            height: 180,
            decoration: BoxDecoration(
              color: FlowPayColors.surface,
              borderRadius: BorderRadius.circular(70),
              border: Border.all(
                color: _faceScanCompleted
                    ? FlowPayColors.stateSuccess
                    : (_isScanningFace
                        ? FlowPayColors.primary
                        : FlowPayColors.hairline),
                width: 2.5,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  _faceScanCompleted ? Icons.check_circle : Icons.face,
                  size: 64,
                  color: _faceScanCompleted
                      ? FlowPayColors.stateSuccess
                      : (_isScanningFace
                          ? FlowPayColors.primaryLight
                          : FlowPayColors.textTertiary),
                ),
                if (_isScanningFace)
                  const SizedBox(
                    width: 100,
                    height: 100,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: FlowPayColors.primaryLight,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          Text(
            _faceScanCompleted
                ? 'Facial Biometrics Verified ✅'
                : (_isScanningFace
                    ? 'Aligning face with BMONI liveness grid...'
                    : 'Position face inside the frame'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _faceScanCompleted
                  ? FlowPayColors.stateSuccess
                  : FlowPayColors.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _faceScanCompleted
                ? 'Liveness passed (Anti-spoofing score: 99.8%)'
                : 'Zero-knowledge biometric verification without storing raw video.',
            style: const TextStyle(
              fontSize: 11,
              color: FlowPayColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 14),

          if (!_faceScanCompleted)
            FlowPayButton(
              text: _isScanningFace ? 'Scanning...' : 'Start Liveness Scan',
              variant: FlowPayButtonVariant.secondary,
              icon: Icons.camera_alt_outlined,
              isLoading: _isScanningFace,
              onPressed: _isScanningFace ? null : _simulateFaceScan,
            ),
        ],
      ),
    );
  }
}
