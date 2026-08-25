import 'package:flutter/material.dart';

import 'app/app.dart';
import 'core/services/theme_controller.dart';
import 'data/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Services.init();
  await ThemeController.instance.load();
  runApp(const MatrixApp());
}
