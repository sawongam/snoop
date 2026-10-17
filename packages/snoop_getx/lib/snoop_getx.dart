/// GetX adapter for snoop: controller lifecycle, Rx values and GetConnect
/// calls in the inspector overlay.
///
/// ```dart
/// void main() {
///   SnoopGetx.install();
///   runApp(
///     GetMaterialApp(
///       builder: (context, child) => SnoopOverlay(child: child!),
///       navigatorObservers: [SnoopRouteObserver()],
///       home: const Home(),
///     ),
///   );
/// }
/// ```
library;

export 'src/snoop_getconnect.dart' show SnoopGetConnect;
export 'src/snoop_getx.dart' show SnoopGetx;
export 'src/snoop_getx_controller.dart' show SnoopGetxController;
