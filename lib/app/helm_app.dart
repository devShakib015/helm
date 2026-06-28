import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'shell/home_shell.dart';

class HelmApp extends StatelessWidget {
  const HelmApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Helm',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeShell(),
    );
  }
}
