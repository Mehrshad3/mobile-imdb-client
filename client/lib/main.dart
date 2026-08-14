import 'package:flutter/material.dart';

import 'src/ui/home_page.dart';

void main() {
  runApp(const ImdbNormalApp());
}

class ImdbNormalApp extends StatelessWidget {
  const ImdbNormalApp({super.key, this.autoLoadHome = true});

  final bool autoLoadHome;

  @override
  Widget build(BuildContext context) {
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
      home: HomePage(autoLoad: autoLoadHome),
    );
  }
}
