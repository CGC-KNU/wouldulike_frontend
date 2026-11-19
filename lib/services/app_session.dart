import 'package:flutter/foundation.dart';

/// Synchronous account boundary for in-flight requests and private screens.
class AppSession {
  static final revision = ValueNotifier<int>(0);
  static bool changing = false;
  static int beginChange() {
    changing = true;
    final next = revision.value + 1;
    revision.value = next;
    return next;
  }

  static void endChange({int? expectedRevision}) {
    if (expectedRevision != null && expectedRevision != revision.value) return;
    changing = false;
    revision.value++;
  }
}
