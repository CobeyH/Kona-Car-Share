import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'data/repository.dart';
import 'data/demo_repository.dart';
import 'data/phone_service.dart';
import 'ui/app_model.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones();
  try {
    final configured = await initializeFirebase();
    final preferences = await SharedPreferences.getInstance();
    final Repository repository = configured
        ? FirebaseRepository(preferences)
        : DemoRepository();
    runApp(KonaApp(model: AppModel(repository, PhoneService())));
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Firebase could not start. Check the project configuration using the setup instructions, then rebuild the app.',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
