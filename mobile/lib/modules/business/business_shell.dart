import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/account_capabilities.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/navigation/business_routes.dart';
import '../../core/state/app_state.dart';
import '../../core/theme/colors.dart';
import '../../core/theme/components.dart';

/// Independent Navigation Shell for Business Account Mode.
/// Maintains its own navigation stack, active tab state, and app bar.
class BusinessShell extends ConsumerStatefulWidget {
  final AppState? appState;

  const BusinessShell({super.key, this.appState});

  @override
  ConsumerState<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends ConsumerState<BusinessShell> {
  int _currentIndex = 0;
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = widget.appState ?? AppState();
  }

  @override
  Widget build(BuildContext context) {
    final capabilitiesAsync = ref.watch(accountCapabilitiesProvider);
    final capabilities = capabilitiesAsync.asData?.value;
    final hasBothModes = capabilities?.hasBothModes ?? true;

    return Scaffold(
      backgroundColor: FlowPayColors.canvas,
      appBar: AppBar(
        backgroundColor: FlowPayColors.canvas,
        scrolledUnderElevation: 0,
        elevation: 0,
        title: hasBothModes
            ? FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Revolut-style Segmented Role Switch
                    SegmentedRoleSwitch(
                      isPersonal: false,
                      onRoleChanged: (isPersonal) {
                        ref.read(appLockStateProvider.notifier).setAccountMode(
                              isPersonal
                                  ? AccountMode.personal
                                  : AccountMode.business,
                            );
                      },
                    ),
                    const SizedBox(width: 8),
                    const PoweredByBmoniBadge(),
                  ],
                ),
              )
            : const PoweredByBmoniBadge(),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline,
                color: FlowPayColors.ink, size: 20),
            tooltip: 'Lock FlowPay',
            onPressed: () {
              ref.read(appLockStateProvider.notifier).lockApp();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: BusinessRoutes.buildScreen(_currentIndex, _appState),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: FlowPayColors.surface,
          border: Border(
            top: BorderSide(color: FlowPayColors.hairline, width: 1),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _currentIndex,
          backgroundColor: FlowPayColors.surface,
          indicatorColor: FlowPayColors.surfaceAlt,
          elevation: 0,
          onDestinationSelected: (idx) => setState(() => _currentIndex = idx),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard, color: FlowPayColors.ink),
              label: 'Dashboard',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline),
              selectedIcon: Icon(Icons.people, color: FlowPayColors.ink),
              label: 'Team',
            ),
            NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments, color: FlowPayColors.ink),
              label: 'Payroll',
            ),
            NavigationDestination(
              icon: Icon(Icons.receipt_long_outlined),
              selectedIcon: Icon(Icons.receipt_long, color: FlowPayColors.ink),
              label: 'Audit',
            ),
          ],
        ),
      ),
    );
  }
}
