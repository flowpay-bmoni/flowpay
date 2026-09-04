import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../../core/auth/account_capabilities.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/secure_storage_service.dart';
import '../../core/config/api_config.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/components.dart';
import '../../core/theme/radii.dart';
import '../../core/theme/typography.dart';
import 'signup_screen.dart';

/// FlowPay Log In Screen.
/// Used when authentication has expired or user wants to sign in to an existing account.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _pinController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final pin = _pinController.text.trim();

    if (SecureStorageService.isTestEnv) {
      final profile = UserProfile(
        userId: 'usr_test_${email.contains('business') ? 'business' : 'personal'}_1',
        fullName: 'FlowPay User',
        email: email,
        phone: '+2348012345678',
        country: 'NG',
        accountType: email.contains('business') ? AccountType.business : AccountType.personal,
        kycStatus: KycStatus.verified,
        createdAt: DateTime.now(),
      );
      await ref
          .read(appLockStateProvider.notifier)
          .loginAsPersona(profile, pin: pin);
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
      return;
    }

    try {
      // 1. Authenticate against FlowPay backend & Supabase
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({
          'email': email,
          'pin': pin,
        }),
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        String msg = 'Login failed. Please check your credentials.';
        try {
          final errBody = jsonDecode(response.body);
          if (errBody['message'] != null) {
            msg = errBody['message'].toString();
          }
        } catch (_) {}
        setState(() {
          _isLoading = false;
          _errorMessage = msg;
        });
        return;
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final userJson = data['user'] as Map<String, dynamic>;

      final profile = UserProfile(
        userId: userJson['userId'] ?? userJson['id'],
        fullName: userJson['fullName'] ?? 'FlowPay User',
        email: userJson['email'] ?? email,
        phone: userJson['phone'] ?? '',
        country: userJson['country'] ?? 'US',
        accountType: userJson['accountType'] == 'business'
            ? AccountType.business
            : AccountType.personal,
        companyName: userJson['companyName'],
        companyRole: userJson['companyRole'],
        kycStatus: userJson['kycStatus'] == 'verified'
            ? KycStatus.verified
            : (userJson['kycStatus'] == 'pending'
                ? KycStatus.pending
                : KycStatus.unverified),
        createdAt: DateTime.now(),
      );

      // 2. Establish active session and save credentials
      await ref
          .read(appLockStateProvider.notifier)
          .loginAsPersona(profile, pin: pin);

      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Unable to connect to FlowPay server. Please check your network connection.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: FlowPayColors.canvas,
      appBar: AppBar(
        backgroundColor: FlowPayColors.canvas,
        scrolledUnderElevation: 0,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: FlowPayColors.ink),
          onPressed: () => Navigator.pop(context),
        ),
        title: const PoweredByBmoniBadge(),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 12),

                // Hero Icon
                Center(
                  child: Container(
                    width: 60,
                    height: 60,
                    decoration: BoxDecoration(
                      color: FlowPayColors.surfaceAlt,
                      borderRadius: FlowPayRadii.card,
                      border: Border.all(color: FlowPayColors.hairline),
                    ),
                    child: const Icon(
                      Icons.login_rounded,
                      color: FlowPayColors.primary,
                      size: 28,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Text(
                  'Log In to FlowPay',
                  style: FlowPayTypography.headline(),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Enter your account email and 6-digit signing PIN.',
                  style: TextStyle(
                    fontSize: 13,
                    color: FlowPayColors.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 28),

                if (_errorMessage != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: FlowPayColors.stateError.withAlpha(25),
                      borderRadius: FlowPayRadii.input,
                      border: Border.all(color: FlowPayColors.stateError),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: FlowPayColors.stateError,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Email
                const Text(
                  'Account Email',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FlowPayColors.ink),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  style:
                      const TextStyle(color: FlowPayColors.ink, fontSize: 14),
                  decoration: const InputDecoration(
                    hintText: 'name@company.com',
                    prefixIcon: Icon(Icons.email_outlined,
                        color: FlowPayColors.textSecondary, size: 18),
                    filled: true,
                    fillColor: FlowPayColors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: FlowPayRadii.input,
                      borderSide: BorderSide(color: FlowPayColors.hairline),
                    ),
                  ),
                  validator: (v) => v == null || !v.contains('@')
                      ? 'Enter a valid email address'
                      : null,
                ),

                const SizedBox(height: 18),

                // PIN
                const Text(
                  '6-Digit PIN',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: FlowPayColors.ink),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _pinController,
                  keyboardType: TextInputType.number,
                  obscureText: true,
                  maxLength: 6,
                  style: const TextStyle(
                      color: FlowPayColors.ink, fontSize: 18, letterSpacing: 4),
                  decoration: const InputDecoration(
                    counterText: '',
                    hintText: '••••••',
                    prefixIcon: Icon(Icons.lock_outline,
                        color: FlowPayColors.textSecondary, size: 18),
                    filled: true,
                    fillColor: FlowPayColors.surfaceAlt,
                    border: OutlineInputBorder(
                      borderRadius: FlowPayRadii.input,
                      borderSide: BorderSide(color: FlowPayColors.hairline),
                    ),
                  ),
                  validator: (v) => v == null || v.length != 6
                      ? 'PIN must be 6 digits'
                      : null,
                ),

                const SizedBox(height: 24),

                // Submit Button
                FlowPayButton(
                  text: _isLoading ? 'Authenticating...' : 'Log In',
                  icon: Icons.login,
                  onPressed: _isLoading ? null : _login,
                ),

                const SizedBox(height: 16),

                // Go to signup
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      );
                    },
                    child: const Text(
                      'Don\'t have an account? Sign Up',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: FlowPayColors.primary),
                    ),
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
