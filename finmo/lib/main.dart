import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FinmoApp());
}

class FinmoApp extends StatefulWidget {
  const FinmoApp({super.key});

  @override
  State<FinmoApp> createState() => _FinmoAppState();
}

class _FinmoAppState extends State<FinmoApp> {
  @override
  Widget build(BuildContext context) {
    return const Placeholder();
  }
}