/// Guards for running user code (`toString`, `==`, `toJson`) while
/// recording, so a broken model class can never crash the app being
/// inspected.
abstract final class SnoopSafe {
  /// The text of [v], cut to [max] characters. Falls back to the type name
  /// when `toString` throws.
  static String string(Object? v, {int max = 2000}) {
    String text;
    try {
      text = '$v';
    } on Object {
      text = '<${run(() => '${v.runtimeType}') ?? 'object'}: toString threw>';
    }
    return text.length <= max ? text : '${text.substring(0, max)}…';
  }

  /// Runs [f], returning `null` instead of throwing.
  static T? run<T>(T Function() f) {
    try {
      return f();
    } on Object {
      return null;
    }
  }
}
