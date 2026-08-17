import 'package:flutter/material.dart';

import 'src/api/backend_api_client.dart';
import 'src/repositories/imdb_repository.dart';
import 'src/repositories/mock_auth_repository.dart';
import 'src/ui/home_page.dart';
import 'src/ui/server_connection_monitor.dart';

const String imdbBackendBaseUrl = 'http://52.16.58.211:8000';

void main() {
  runApp(const ImdbNormalApp());
}

class ImdbNormalApp extends StatefulWidget {
  const ImdbNormalApp({
    super.key,
    this.autoLoadHome = true,
    this.enableServerConnectionMonitor = true,
  });

  final bool autoLoadHome;
  final bool enableServerConnectionMonitor;

  @override
  State<ImdbNormalApp> createState() => _ImdbNormalAppState();
}

class _ImdbNormalAppState extends State<ImdbNormalApp> {
  late final BackendApiClient _backendClient = BackendApiClient(
    baseUrl: imdbBackendBaseUrl,
  );

  late final MockAuthRepository _authRepository = MockAuthRepository(
    backendClient: _backendClient,
  );

  late final ImdbRepository _imdbRepository = ImdbRepository(
    backendClient: _backendClient,
  );

  @override
  void dispose() {
    _imdbRepository.close();
    _authRepository.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final home = HomePage(
      autoLoad: widget.autoLoadHome,
      repository: _imdbRepository,
      authRepository: _authRepository,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'IMDb Normal Project',
      locale: const Locale('fa'),
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFF5C518)),
        useMaterial3: true,
        inputDecorationTheme: const InputDecorationTheme(
          isDense: true,
          filled: true,
        ),
      ),
      home: widget.enableServerConnectionMonitor
          ? ServerConnectionMonitor(client: _backendClient, child: home)
          : home,
    );
  }
}
