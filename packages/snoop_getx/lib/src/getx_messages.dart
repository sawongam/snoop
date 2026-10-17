/// What a `Get.log` line says about an instance, parsed from the strings in
/// `get_instance/src/get_instance.dart` (get 4.6.x and 4.7.x).
sealed class GetxMessage {
  const GetxMessage();
}

/// `Instance "X" has been initialized` (with an optional `with tag "T"`).
final class GetxInitialized extends GetxMessage {
  /// Creates the message.
  const GetxInitialized(this.type, this.tag);

  /// The type name.
  final String type;

  /// The tag, or `null`.
  final String? tag;

  /// The registry key GetX uses for later messages: the type name followed
  /// directly by the tag, with no separator.
  String get key => tag == null ? type : '$type$tag';
}

/// A message about the instance registered under [key] (type name + tag).
final class GetxInstanceEvent extends GetxMessage {
  /// Creates the message.
  const GetxInstanceEvent(this.kind, this.key);

  /// What happened.
  final GetxInstanceEventKind kind;

  /// Type name + tag, as GetX builds it.
  final String key;
}

/// The instance events GetX logs.
enum GetxInstanceEventKind {
  /// `"K" onDelete() called`.
  onDelete('onDelete() called'),

  /// `"K" onClose() called` (from `GetWidget`).
  onClose('onClose() called'),

  /// `"K" deleted from memory`.
  deleted('deleted from memory'),

  /// `Instance "K" is permanent. Skipping reload`.
  permanentSkipped('permanent, reload skipped'),

  /// `Instance "K" was reloaded.`.
  reloaded('reloaded'),

  /// `Instance "K" was restarted.`.
  restarted('restarted');

  const GetxInstanceEventKind(this.label);

  /// Text for the history entry.
  final String label;
}

final RegExp _initializedTag = RegExp(r'^Instance "(.+?)" with tag "(.*)" has been initialized$');
final RegExp _initialized = RegExp(r'^Instance "(.+)" has been initialized$');
final RegExp _onDelete = RegExp(r'^"(.+)" onDelete\(\) called$');
final RegExp _onClose = RegExp(r'^"(.+)" onClose\(\) called$');
final RegExp _deleted = RegExp(r'^"(.+)" deleted from memory$');
final RegExp _permanent = RegExp(r'^Instance "(.+)" is permanent\. Skipping reload$');
final RegExp _reloaded = RegExp(r'^Instance "(.+)" was reloaded\.$');
final RegExp _restarted = RegExp(r'^Instance "(.+)" was restarted\.$');

/// Parses [text], or returns `null` when it isn't a lifecycle line.
GetxMessage? parseGetxMessage(String text) {
  final tagged = _initializedTag.firstMatch(text);
  if (tagged != null) return GetxInitialized(tagged.group(1)!, tagged.group(2));
  final plain = _initialized.firstMatch(text);
  if (plain != null) return GetxInitialized(plain.group(1)!, null);
  for (final (pattern, kind) in <(RegExp, GetxInstanceEventKind)>[
    (_onDelete, GetxInstanceEventKind.onDelete),
    (_onClose, GetxInstanceEventKind.onClose),
    (_deleted, GetxInstanceEventKind.deleted),
    (_permanent, GetxInstanceEventKind.permanentSkipped),
    (_reloaded, GetxInstanceEventKind.reloaded),
    (_restarted, GetxInstanceEventKind.restarted),
  ]) {
    final m = pattern.firstMatch(text);
    if (m != null) return GetxInstanceEvent(kind, m.group(1)!);
  }
  return null;
}
