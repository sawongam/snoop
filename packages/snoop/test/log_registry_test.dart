import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

void main() {
  final registry = Snoop.logs;

  setUp(() {
    Snoop.reset();
    registry.maxRecords = 500;
  });

  test('records newest first', () {
    registry
      ..log('first', level: SnoopLogLevel.debug)
      ..log('second', level: SnoopLogLevel.info);

    expect(registry.records.map((r) => r.message), ['second', 'first']);
  });

  test('counts errors and warnings separately, with fatal as an error', () {
    registry
      ..log('a', level: SnoopLogLevel.debug)
      ..log('b', level: SnoopLogLevel.warning)
      ..log('c', level: SnoopLogLevel.error)
      ..log('d', level: SnoopLogLevel.fatal);

    expect(registry.errorCount, 2);
    expect(registry.warningCount, 1);
  });

  test('records nothing when disabled', () {
    registry.enabled = false;
    addTearDown(() => registry.enabled = true);
    registry.log('ignored');

    expect(registry.isEmpty, isTrue);
  });

  test('drops the oldest line over the cap', () {
    registry.maxRecords = 2;
    registry
      ..log('one', level: SnoopLogLevel.info)
      ..log('two', level: SnoopLogLevel.info)
      ..log('three', level: SnoopLogLevel.info);

    expect(registry.records.map((r) => r.message), ['three', 'two']);
  });

  test('matches a query across message, source and error', () {
    final record = SnoopLogRecord(
      timestamp: DateTime.utc(2026),
      level: SnoopLogLevel.error,
      message: 'could not load',
      source: 'DishCubit',
      error: 'SocketException: refused',
    );

    expect(record.matches('load'), isTrue);
    expect(record.matches('dishcubit'), isTrue);
    expect(record.matches('socket'), isTrue);
    expect(record.matches('unrelated'), isFalse);
  });

  test('a level filter reads as a floor, not a selection', () {
    expect(SnoopLogLevel.error >= SnoopLogLevel.warning, isTrue);
    expect(SnoopLogLevel.fatal >= SnoopLogLevel.error, isTrue);
    expect(SnoopLogLevel.debug >= SnoopLogLevel.info, isFalse);
  });

  test('copyable text carries the level, source, error and stack', () {
    final record = SnoopLogRecord(
      timestamp: DateTime.utc(2026),
      level: SnoopLogLevel.warning,
      message: 'slow read',
      source: 'MenuBrowseCubit',
      error: StateError('boom'),
      stackTrace: StackTrace.fromString('#0 somewhere'),
    );

    expect(record.text, contains('[WARNING]'));
    expect(record.text, contains('MenuBrowseCubit:'));
    expect(record.text, contains('slow read'));
    expect(record.text, contains('Bad state: boom'));
    expect(record.text, contains('#0 somewhere'));
  });
}
