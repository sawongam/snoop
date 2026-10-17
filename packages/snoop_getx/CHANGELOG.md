## 0.1.0

- Initial release.
- `SnoopGetx.install` follows controller lifecycles through a chained `Get.log` and sends GetX
  log lines to the Logs tab.
- `SnoopGetxController` mixin shows a controller's Rx fields and `update()` calls in the State tab.
- `SnoopGetx.track` follows an Rx outside controllers.
- `SnoopGetConnect.attach` records `GetConnect` calls in the Network tab.
- Supports `get ^4.7.1`.
