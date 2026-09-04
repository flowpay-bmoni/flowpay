import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/auth/app_auth_gate.dart';
import 'core/design_system/design_system.dart';
import 'core/navigation/app_router.dart';
import 'core/state/app_state.dart';
import 'modules/business/business_shell.dart';
import 'modules/personal/personal_shell.dart';

class FlowPayApp extends StatefulWidget {
  final AppState? appState;

  const FlowPayApp({super.key, this.appState});

  @override
  State<FlowPayApp> createState() => _FlowPayAppState();
}

class _FlowPayAppState extends State<FlowPayApp> {
  late final AppState _appState;

  @override
  void initState() {
    super.initState();
    _appState = widget.appState ?? AppState();
    _appState.addListener(_onAppStateChanged);
  }

  void _onAppStateChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _appState.removeListener(_onAppStateChanged);
    if (widget.appState == null) {
      _appState.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = MaterialApp(
      title: 'FlowPay',
      debugShowCheckedModeBanner: false,
      themeMode: _appState.themeMode,
      theme: FlowPayTheme.light(),
      darkTheme: FlowPayTheme.dark(),
      onGenerateRoute: (settings) =>
          FlowPayRouter.onGenerateRoute(settings, _appState),
      home: AppAuthGate(
        personalShell: PersonalShell(appState: _appState),
        businessShell: BusinessShell(appState: _appState),
        appState: _appState,
      ),
    );

    try {
      ProviderScope.containerOf(context, listen: false);
      return app;
    } catch (_) {
      return ProviderScope(child: app);
    }
  }
}
