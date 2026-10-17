import 'package:get/get.dart';
import 'package:snoop_getx/snoop_getx.dart';

class PlainController extends GetxController {
  int closed = 0;

  @override
  void onClose() {
    closed++;
    super.onClose();
  }
}

class CartController extends GetxController with SnoopGetxController {
  CartController({this.tag});

  final String? tag;
  final items = <String>[].obs;
  final total = 0.0.obs;

  @override
  String? get snoopTag => tag;

  @override
  bool get snoopEnabled => true;

  @override
  Map<String, RxInterface<Object?>> get snoopFields => <String, RxInterface<Object?>>{
    'items': items,
    'total': total,
  };
}

class Disabled extends GetxController with SnoopGetxController {
  @override
  bool get snoopEnabled => false;
}

class Hostile {
  @override
  String toString() => throw StateError('toString');
}

class HostileController extends GetxController with SnoopGetxController {
  final value = Hostile().obs;

  @override
  bool get snoopEnabled => true;

  @override
  Map<String, RxInterface<Object?>> get snoopFields => <String, RxInterface<Object?>>{
    'value': value,
  };
}
