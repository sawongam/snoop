import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snoop/snoop.dart';

Route<void> _route(String name, {Object? extra}) => PageRouteBuilder<void>(
  settings: RouteSettings(name: name, arguments: extra),
  pageBuilder: (_, _, _) => const SizedBox.shrink(),
);

void main() {
  final registry = Snoop.routes;

  setUp(Snoop.reset);

  test('records a push and a pop newest first, tracking depth', () {
    final observer = SnoopRouteObserver(enabled: true)
      ..didPush(_route('/user/dineout'), null)
      ..didPush(_route('/restaurant/menu'), _route('/user/dineout'));

    expect(registry.records.first.name, '/restaurant/menu');
    expect(registry.records.first.action, SnoopRouteAction.push);
    expect(registry.records.first.previousName, '/user/dineout');
    expect(registry.depth, 2);

    observer.didPop(_route('/restaurant/menu'), _route('/user/dineout'));

    expect(registry.records.first.action, SnoopRouteAction.pop);
    expect(registry.depth, 1);
  });

  test('carries the route extra through', () {
    SnoopRouteObserver(
      enabled: true,
    ).didPush(_route('/user/sign-in/otp', extra: {'phone': '555'}), null);

    expect(registry.records.single.arguments, {'phone': '555'});
  });

  test('a replace keeps the depth where it was', () {
    final observer = SnoopRouteObserver(enabled: true)..didPush(_route('/a'), null);
    observer.didReplace(newRoute: _route('/b'), oldRoute: _route('/a'));

    expect(registry.records.first.action, SnoopRouteAction.replace);
    expect(registry.depth, 1);
  });

  test('records nothing when disabled', () {
    SnoopRouteObserver(enabled: false).didPush(_route('/a'), null);

    expect(registry.isEmpty, isTrue);
  });

  test('depth never goes negative on an unbalanced pop', () {
    SnoopRouteObserver(enabled: true).didPop(_route('/a'), null);

    expect(registry.depth, 0);
  });
}
