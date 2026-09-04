import 'package:flutter/material.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/state/business_provider.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/radii.dart';
import '../../../core/theme/typography.dart';

class CountryOption {
  final String code;
  final String name;
  final String flag;
  final Currency currency;
  final String defaultSalary;

  const CountryOption({
    required this.code,
    required this.name,
    required this.flag,
    required this.currency,
    required this.defaultSalary,
  });
}

/// Add Employee Modal
/// Powered by bkey_uikit design system:
/// - BMoniTextFormField.filled for input fields
/// - SelectorBottomSheet<CountryOption> via BMoniBottomSheet.show for country & rail selection
/// - BMoniButton(variant: BMoniButtonVariant.primary) for submission
/// - BMoniToastOverlay for rich feedback
class AddEmployeeModal extends StatefulWidget {
  final BusinessProvider businessProvider;

  const AddEmployeeModal({super.key, required this.businessProvider});

  static Future<void> show(BuildContext context, BusinessProvider provider) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddEmployeeModal(businessProvider: provider),
    );
  }

  @override
  State<AddEmployeeModal> createState() => _AddEmployeeModalState();
}

class _AddEmployeeModalState extends State<AddEmployeeModal> {
  final _formKey = GlobalKey<FormState>();
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _salaryCtrl = TextEditingController(text: '3100000.00');

  static const List<CountryOption> _countries = [
    CountryOption(
      code: 'NG',
      name: 'Nigeria (NGN / CNGN)',
      flag: '🇳🇬',
      currency: Currency.ngn,
      defaultSalary: '3100000.00',
    ),
    CountryOption(
      code: 'MX',
      name: 'Mexico (MXN / MEXe)',
      flag: '🇲🇽',
      currency: Currency.mxn,
      defaultSalary: '35000.00',
    ),
  ];

  CountryOption _selectedCountry = _countries.first;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _salaryCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCountry() async {
    try {
      final picked = await BMoniBottomSheet.show<CountryOption>(
        context: context,
        child: SelectorBottomSheet<CountryOption>(
          items: _countries,
          selected: _selectedCountry,
          title: 'Select Destination Country & Rail',
          label: (c) => '${c.flag} ${c.name}',
          value: (c) => c.code,
          showIcon: false,
        ),
      );

      if (picked != null && mounted) {
        setState(() {
          _selectedCountry = picked;
          _salaryCtrl.text = picked.defaultSalary;
        });
      }
    } catch (_) {
      // Fallback simple dialog if bottom sheet is constrained
      _showSimpleCountryPicker();
    }
  }

  void _showSimpleCountryPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: FlowPayColors.surface,
      shape: const RoundedRectangleBorder(borderRadius: FlowPayRadii.sheet),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Select Destination Rail',
                style: FlowPayTypography.title(color: FlowPayColors.ink),
              ),
            ),
            ..._countries.map((c) => ListTile(
                  leading: Text(c.flag, style: const TextStyle(fontSize: 22)),
                  title: Text(c.name,
                      style: const TextStyle(color: FlowPayColors.ink)),
                  trailing: c.code == _selectedCountry.code
                      ? const Icon(Icons.check_circle_rounded,
                          color: FlowPayColors.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    setState(() {
                      _selectedCountry = c;
                      _salaryCtrl.text = c.defaultSalary;
                    });
                  },
                )),
          ],
        ),
      ),
    );
  }

  Future<void> _handleSubmit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    final email = _emailCtrl.text.trim().toLowerCase();
    final salaryStr = _salaryCtrl.text.trim();

    setState(() => _isSubmitting = true);

    try {
      final salaryMoney =
          Money.fromMajorString(salaryStr, _selectedCountry.currency);
      final usdSalary = Money.fromMajorString('2000.00', Currency.usd);

      await widget.businessProvider.addEmployee(
        firstName: first,
        lastName: last,
        email: email,
        country: _selectedCountry.code,
        countryName: _selectedCountry.code == 'NG' ? 'Nigeria' : 'Mexico',
        targetCurrency: _selectedCountry.currency,
        payrollAmount: salaryMoney,
        usdPayrollAmount: usdSalary,
      );

      if (mounted) {
        Navigator.pop(context);
        try {
          BMoniToastOverlay.showSuccess(
            context: context,
            title: 'Employee Onboarded',
            message:
                '$first $last added with BMONI on-chain identity and smart wallet!',
          );
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: FlowPayColors.ink,
              content: Text(
                '$first $last onboarded successfully! Smart wallet provisioned.',
                style: const TextStyle(color: Colors.white),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        try {
          BMoniToastOverlay.showError(
            context: context,
            title: 'Onboarding Failed',
            message: 'Failed to create employee: $e',
          );
        } catch (_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to add employee: $e')),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        decoration: const BoxDecoration(
          color: FlowPayColors.surface,
          borderRadius: FlowPayRadii.sheet,
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: bottomInset + 24,
        ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: const BoxDecoration(
                      color: FlowPayColors.surfaceAlt,
                      borderRadius: FlowPayRadii.avatar,
                    ),
                    child: const Icon(Icons.person_add_rounded,
                        color: FlowPayColors.ink, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Remote Employee',
                          style:
                              FlowPayTypography.title(color: FlowPayColors.ink)
                                  .copyWith(fontSize: 17),
                        ),
                        Text(
                          'Stages: Created → Wallet → KYC → Ready',
                          style: FlowPayTypography.captionStyle(
                              color: FlowPayColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: FlowPayColors.textSecondary),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Country & Currency Selector using SelectorBottomSheet
              Text(
                'DESTINATION COUNTRY & SETTLEMENT RAIL',
                style: FlowPayTypography.captionStyle(
                        color: FlowPayColors.textTertiary)
                    .copyWith(
                  fontSize: 11,
                  letterSpacing: 0.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: _pickCountry,
                borderRadius: FlowPayRadii.input,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: FlowPayColors.surfaceAlt,
                    borderRadius: FlowPayRadii.input,
                    border: Border.all(color: FlowPayColors.hairline),
                  ),
                  child: Row(
                    children: [
                      Text(_selectedCountry.flag,
                          style: const TextStyle(fontSize: 22)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _selectedCountry.name,
                              style: FlowPayTypography.body(
                                      color: FlowPayColors.ink)
                                  .copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Disbursement currency: ${_selectedCountry.currency.code}',
                              style: FlowPayTypography.captionStyle(
                                  color: FlowPayColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.keyboard_arrow_down_rounded,
                          color: FlowPayColors.textSecondary),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Name Row with BMoniTextFormField.filled
              Row(
                children: [
                  Expanded(
                    child: BMoniTextFormField.filled(
                      label: 'First Name',
                      hintText: 'e.g. Bunch / Samson',
                      controller: _firstCtrl,
                      size: BMoniTextFieldSize.medium,
                      prefixIcon:
                          const Icon(Icons.person_outline_rounded, size: 18),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: BMoniTextFormField.filled(
                      label: 'Last Name',
                      hintText: 'e.g. Dillon / Jabo',
                      controller: _lastCtrl,
                      size: BMoniTextFieldSize.medium,
                      prefixIcon:
                          const Icon(Icons.person_outline_rounded, size: 18),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Work Email Field with BMoniTextFormField.filled
              BMoniTextFormField.filled(
                label: 'Work Email Address',
                hintText: 'employee@company.com',
                controller: _emailCtrl,
                keyboardType: TextInputType.emailAddress,
                size: BMoniTextFieldSize.medium,
                prefixIcon: const Icon(Icons.mail_outline_rounded, size: 18),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Email is required';
                  }
                  final emailRegex = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');
                  if (!emailRegex.hasMatch(v.trim())) {
                    return 'Enter a valid email';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Phone Number (Optional E.164)
              BMoniTextFormField.filled(
                label: 'Phone Number (E.164 format)',
                hintText: _selectedCountry.code == 'NG'
                    ? '+2348011112222'
                    : '+525512345678',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                size: BMoniTextFieldSize.medium,
                prefixIcon: const Icon(Icons.phone_outlined, size: 18),
              ),
              const SizedBox(height: 16),

              // Monthly Salary Field
              BMoniTextFormField.filled(
                label: 'Monthly Net Salary (${_selectedCountry.currency.code})',
                hintText: '0.00',
                controller: _salaryCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                size: BMoniTextFieldSize.medium,
                prefixIcon: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  child: Text(
                    _selectedCountry.currency.symbol,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Salary is required';
                  }
                  final numVal = double.tryParse(v.trim());
                  if (numVal == null || numVal <= 0) {
                    return 'Must be a positive amount';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 24),

              // Primary Submission Button using BMoniButton
              SizedBox(
                width: double.infinity,
                child: BMoniButton(
                  onPressed: _isSubmitting ? null : _handleSubmit,
                  text: 'Create Employee & Provision Rails',
                  variant: BMoniButtonVariant.primary,
                  size: BMoniButtonSize.large,
                  isLoading: _isSubmitting,
                  icon: Icons.check_circle_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
}
