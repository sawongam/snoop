import 'package:flutter_test/flutter_test.dart';
import 'package:snoop_getx/src/getx_messages.dart';

void main() {
  GetxInitialized initialized(String text) => parseGetxMessage(text)! as GetxInitialized;
  GetxInstanceEvent event(String text) => parseGetxMessage(text)! as GetxInstanceEvent;

  test('Instance "X" has been initialized', () {
    final m = initialized('Instance "CartController" has been initialized');
    expect(m.type, 'CartController');
    expect(m.tag, isNull);
    expect(m.key, 'CartController');
  });

  test('tagged initialization joins type and tag without a separator', () {
    final m = initialized('Instance "CartController" with tag "main" has been initialized');
    expect(m.type, 'CartController');
    expect(m.tag, 'main');
    // GetX's _getKey is type.toString() + tag.
    expect(m.key, 'CartControllermain');
  });

  test('generic types and tags with spaces parse', () {
    final m = initialized('Instance "Box<int>" with tag "a b" has been initialized');
    expect(m.type, 'Box<int>');
    expect(m.tag, 'a b');
  });

  test('an untagged name containing "with tag" text is not split wrongly', () {
    expect(initialized('Instance "A" has been initialized').tag, isNull);
  });

  test('onDelete, onClose, deleted', () {
    expect(event('"CartController" onDelete() called').kind, GetxInstanceEventKind.onDelete);
    expect(event('"CartController" onClose() called').kind, GetxInstanceEventKind.onClose);
    final deleted = event('"CartControllermain" deleted from memory');
    expect(deleted.kind, GetxInstanceEventKind.deleted);
    expect(deleted.key, 'CartControllermain');
  });

  test('permanent skip, reload, restart', () {
    expect(
      event('Instance "A" is permanent. Skipping reload').kind,
      GetxInstanceEventKind.permanentSkipped,
    );
    expect(event('Instance "A" was reloaded.').kind, GetxInstanceEventKind.reloaded);
    expect(event('Instance "A" was restarted.').kind, GetxInstanceEventKind.restarted);
  });

  test('other lines are not lifecycle messages', () {
    expect(parseGetxMessage('GOING TO ROUTE /home'), isNull);
    expect(parseGetxMessage('Instance "A" has been created'), isNull);
    expect(parseGetxMessage('Instance "A" is not registered.'), isNull);
    expect(parseGetxMessage('"A" has been marked as permanent'), isNull);
    expect(parseGetxMessage(''), isNull);
  });
}
