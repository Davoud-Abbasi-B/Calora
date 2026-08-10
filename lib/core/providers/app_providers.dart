import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/local_storage_service.dart';

final localStorageServiceProvider = Provider<LocalStorageService>(
  (ref) => LocalStorageService.instance,
);
