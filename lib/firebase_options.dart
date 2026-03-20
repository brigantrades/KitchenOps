import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'replace_me',
    appId: 'replace_me',
    messagingSenderId: 'replace_me',
    projectId: 'replace_me',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDSq7NyFkTnIYYl3E-4B5uaco_ijEph2KY',
    appId: '1:1040237027470:android:e4fbc647f4901ce40929df',
    messagingSenderId: '1040237027470',
    projectId: 'forkflow-4e529',
    storageBucket: 'forkflow-4e529.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'replace_me',
    appId: 'replace_me',
    messagingSenderId: 'replace_me',
    projectId: 'replace_me',
    iosBundleId: 'com.example.leckerly',
  );
}