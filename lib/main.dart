import 'package:flutter/material.dart';

import 'app.dart';
import 'storage.dart';
import 'store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(GiriStairApp(store: GiriStore(storage: FileGiriStorage())));
}
