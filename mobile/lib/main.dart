import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'core/auth/secure_storage_service.dart';
import 'core/bmoni_sdk/bmoni_sdk_service.dart';
import 'core/state/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SecureStorageService.isTestEnv = false;

  // Initialize BMONI Embedded SDK on-device with 6-digit PIN policy
  BmoniEmbeddedSdk.initialize(
    pinLength: 6,
    requirePin: true,
  );
  await BmoniSdkService.initialize(
    pinLength: 6,
    requirePin: true,
  );

  runApp(
    ProviderScope(
      child: FlowPayApp(
        appState: AppState(providerMode: ProviderMode.bmoniSandbox),
      ),
    ),
  );
}
