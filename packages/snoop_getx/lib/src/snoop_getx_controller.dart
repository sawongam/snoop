import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:snoop/snoop.dart';
import 'package:snoop_getx/src/snoop_getx.dart';

/// Shows a controller's Rx values in the State tab.
///
/// ```dart
/// class CartController extends GetxController with SnoopGetxController {
///   final items = <Item>[].obs;
///   final total = 0.0.obs;
///
///   @override
///   Map<String, RxInterface<Object?>> get snoopFields => {'items': items, 'total': total};
/// }
/// ```
///
/// Every change of a field records the map of all fields; `update()` records
/// an `update(ids)` entry. Values are stored as snapshots, so an `RxList`
/// mutated in place still shows its old and new contents.
mixin SnoopGetxController on GetxController {
  /// The Rx fields to follow, by name.
  Map<String, RxInterface<Object?>> get snoopFields => const <String, RxInterface<Object?>>{};

  /// The tag this controller is registered under, when it has one: lets the
  /// lifecycle hook (`SnoopGetx.install`) match it to the right instance.
  String? get snoopTag => null;

  /// Whether this controller is recorded. Defaults to [kDebugMode].
  bool get snoopEnabled => kDebugMode;

  final List<StreamSubscription<Object?>> _snoopSubscriptions = <StreamSubscription<Object?>>[];

  bool _snoopTracked = false;

  Map<String, Object?> _snoopSnapshot() =>
      SnoopSafe.run(
        () => <String, Object?>{
          for (final e in snoopFields.entries) e.key: SnoopGetx.readRx(e.value),
        },
      ) ??
      <String, Object?>{};

  @override
  void onInit() {
    super.onInit();
    if (!snoopEnabled) return;
    SnoopAdapters.register(
      'getx',
      SnoopAdapterKind.state,
      ignoredLocations: const <String>['package:get/', 'package:snoop_getx/'],
    );
    SnoopGetx.ensureTreeHooks();
    _snoopTracked = true;
    Snoop.state.track(
      this,
      name: '$runtimeType',
      kind: 'controller',
      library: 'getx',
      snapshot: true,
      initialState: _snoopSnapshot(),
      definedAt: SnoopCallSite.resolve(),
      details: <String, Object?>{if (snoopTag != null) 'tag': snoopTag},
    );
    for (final entry in snoopFields.entries) {
      final field = entry.key;
      _snoopSubscriptions.add(
        entry.value.listen((_) => Snoop.state.change(this, null, _snoopSnapshot(), event: field)),
      );
    }
    SnoopGetx.offer(this);
  }

  @override
  void update([List<Object>? ids, bool condition = true]) {
    super.update(ids, condition);
    if (!_snoopTracked || !condition) return;
    Snoop.state.change(this, null, _snoopSnapshot(), event: 'update(${ids?.join(', ') ?? ''})');
  }

  @override
  void onClose() {
    for (final subscription in _snoopSubscriptions) {
      unawaited(subscription.cancel());
    }
    _snoopSubscriptions.clear();
    if (_snoopTracked) {
      SnoopGetx.withdraw(this);
      Snoop.state.markDisposed(this);
    }
    super.onClose();
  }
}
