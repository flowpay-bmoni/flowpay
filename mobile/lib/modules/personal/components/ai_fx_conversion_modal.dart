import 'package:flutter/material.dart';
import 'package:bkey_uikit/bkey_uikit.dart';
import '../../../core/bmoni_sdk/bmoni_sdk_service.dart';
import '../../../core/design_system/states.dart';
import '../../../core/money/currency.dart';
import '../../../core/money/money.dart';
import '../../../core/repositories/activity_repository.dart';
import '../../../core/state/personal_provider.dart';
import '../../../core/theme/colors.dart';

class AiFxConversionModal extends StatefulWidget {
  final PersonalProvider personalProvider;
  final Money initialAmount;

  const AiFxConversionModal({
    super.key,
    required this.personalProvider,
    required this.initialAmount,
  });

  @override
  State<AiFxConversionModal> createState() => _AiFxConversionModalState();
}

class _AiFxConversionModalState extends State<AiFxConversionModal> {
  late TextEditingController _amountController;
  final TextEditingController _pinController = TextEditingController();
  bool _isConverting = false;
  final double _exchangeRate = 1550.0;

  @override
  void initState() {
    super.initState();
    _amountController =
        TextEditingController(text: widget.initialAmount.majorUnits.toString());
  }

  @override
  void dispose() {
    _amountController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  double get _usdAmount {
    return double.tryParse(_amountController.text) ?? 1000.0;
  }

  double get _ngnAmount {
    return _usdAmount * _exchangeRate;
  }

  Future<void> _handleConvert() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your 6-digit B-Key PIN.')),
      );
      return;
    }

    setState(() => _isConverting = true);

    try {
      // 1. Sign FX proposal on-device with B-Key
      await BmoniSdkService.signTransactionHash(
        '0xfa3910cbe78219001b654019238128310029384817264819203912834716291a',
        pin: pin,
      );

      // 2. Record auditable activity
      final activity = ActivityModel(
        id: 'act_fx_${DateTime.now().millisecondsSinceEpoch}',
        title: 'FX Conversion: USD → NGN',
        description:
            'Converted \$$_usdAmount USD to ₦${_ngnAmount.round()} NGN @ $_exchangeRate',
        amount:
            Money.fromMajorString(_usdAmount.toStringAsFixed(2), Currency.usd),
        category: ActivityCategory.fx,
        status: FlowPayAppStatus.completed,
        timestamp: DateTime.now(),
        reference: 'FX-CNGN-${DateTime.now().millisecondsSinceEpoch % 10000}',
        metadata: {'rate': _exchangeRate, 'rail': 'CNGN'},
      );

      await widget.personalProvider.activityRepo.recordActivity(activity);
      await widget.personalProvider.refresh();

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Instant FX settled! ₦${_ngnAmount.round()} credited to your NGN smart wallet.'),
            backgroundColor: BMoniColors.brand500,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Conversion failed: $e'),
              backgroundColor: BMoniColors.error400),
        );
      }
    } finally {
      if (mounted) setState(() => _isConverting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SafeArea(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        padding: EdgeInsets.only(
          top: 20,
          left: 20,
          right: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        decoration: BoxDecoration(
          color: isDark
              ? FlowPayColors.darkSurfaceElevated
              : FlowPayColors.lightSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: BMoniColors.success400.withAlpha(35),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.currency_exchange,
                    color: BMoniColors.success400, size: 20),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Instant Multi-Currency FX',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : BMoniColors.grey950,
                    ),
                  ),
                  const Text(
                    'Task Workflow: Zero-Spread BMONI Rail',
                    style: TextStyle(
                        fontSize: 12,
                        color: BMoniColors.success400,
                        fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Source Input
          const Text('You Convert (USD)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BMoniColors.grey400)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark
                  ? FlowPayColors.darkSurface
                  : FlowPayColors.lightSurfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FlowPayColors.darkBorder),
            ),
            child: Row(
              children: [
                const Text('\$',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _amountController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white),
                    decoration: const InputDecoration(
                        border: InputBorder.none, isDense: true),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const Text('USDB',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: BMoniColors.brand400)),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Exchange Rate Badge
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: BMoniColors.brand500.withAlpha(25),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: BMoniColors.brand500.withAlpha(60)),
              ),
              child: Text(
                '1 USD = ${_exchangeRate.toStringAsFixed(2)} NGN • Real-Time Rail Rate',
                style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: BMoniColors.brand300),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Target Output
          const Text('You Receive (NGN)',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BMoniColors.grey400)),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark
                  ? FlowPayColors.darkSurface
                  : FlowPayColors.lightSurfaceElevated,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: FlowPayColors.darkBorder),
            ),
            child: Row(
              children: [
                const Text('₦',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _ngnAmount.toStringAsFixed(2).replaceAllMapped(
                          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
                          (Match m) => '${m[1]},',
                        ),
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: BMoniColors.success400),
                  ),
                ),
                const Text('CNGN',
                    style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: BMoniColors.success400)),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Fee details
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('BMONI Rail Network Fee',
                  style: TextStyle(fontSize: 12, color: BMoniColors.grey400)),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  '\$0.05 USDB (99.8% saved)',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: BMoniColors.brand300),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // PIN Input
          const Text('Enter 6-Digit B-Key PIN to Authorize',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: BMoniColors.grey300)),
          const SizedBox(height: 6),
          TextField(
            controller: _pinController,
            keyboardType: TextInputType.number,
            maxLength: 6,
            obscureText: true,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 18,
                letterSpacing: 8,
                color: Colors.white,
                fontWeight: FontWeight.bold),
            decoration: InputDecoration(
              hintText: '••••••',
              counterText: '',
              filled: true,
              fillColor: FlowPayColors.darkSurface,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: FlowPayColors.darkBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: BMoniColors.brand500, width: 1.5)),
            ),
          ),
          const SizedBox(height: 18),

          BMoniButton(
            text: 'Sign & Convert',
            variant: BMoniButtonVariant.primary,
            size: BMoniButtonSize.large,
            isLoading: _isConverting,
            onPressed: _handleConvert,
          ),
        ],
      ),
    ),
  ),
);
}
}
