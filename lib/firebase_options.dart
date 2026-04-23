import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError('DefaultFirebaseOptions not configured for this platform.');
    }
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyBVJ4DcOkY5FhyrJ_i-M-eOS1_Y-74pV44',
    appId: '1:127703901556:ios:410e9ea46d9517efa43821',
    messagingSenderId: '127703901556',
    projectId: 'spinner-e5775',
    storageBucket: 'spinner-e5775.appspot.com',
    iosBundleId: 'com.vinylspinner.collect',
  );
}
