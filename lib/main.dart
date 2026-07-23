import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';

import 'firebase_options.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(const FinmoApp());
}

class FinmoApp extends StatelessWidget {
  const FinmoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Finmo',
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Firebase Auth Test'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton(
                onPressed: () async {
                  try {
                    await AuthService.instance.signUp(
                      email: "test@example.com",
                      password: "password123",
                    );

                    debugPrint("Signup successful");
                  } catch (e) {
                    debugPrint(e.toString());
                  }
                },
                child: const Text("Sign Up"),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: () async {
                  try {
                    await AuthService.instance.signIn(
                      email: "test@example.com",
                      password: "password123",
                    );

                    debugPrint("Signed in");
                  } catch (e) {
                    debugPrint(e.toString());
                  }
                },
                child: const Text("Sign In"),
              ),

              const SizedBox(height: 20),

              ElevatedButton(
                onPressed: () async {
                  try {
                    await AuthService.instance.signOut();
                    debugPrint("Signed out");
                  } catch (e) {
                    debugPrint(e.toString());
                  }
                },
                child: const Text("Sign Out"),
              ),
            ],
          ),
        ),
      ),
    );
  }
}