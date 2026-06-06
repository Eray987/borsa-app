import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';

String get baseUrl {
	if (kIsWeb) {
		return 'http://localhost:8001';
	}
	if (Platform.isAndroid) {
		return 'http://10.0.2.2:8001';
	}
	return 'http://localhost:8001';
}
