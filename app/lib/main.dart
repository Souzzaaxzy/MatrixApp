import 'package:flutter/material.dart';

import 'app/app.dart';
import 'data/services.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Services.init();
  runApp(const MatrixApp());
}
