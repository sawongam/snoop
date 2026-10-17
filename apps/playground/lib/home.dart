import 'package:flutter/material.dart';
import 'package:snoop_playground/demos/bloc_demo.dart';
import 'package:snoop_playground/demos/chopper_demo.dart';
import 'package:snoop_playground/demos/dio_demo.dart';
import 'package:snoop_playground/demos/getx_demo.dart';
import 'package:snoop_playground/demos/http_demo.dart';
import 'package:snoop_playground/demos/mobx_demo.dart';
import 'package:snoop_playground/demos/provider_demo.dart';
import 'package:snoop_playground/demos/riverpod_demo.dart';
import 'package:snoop_playground/demos/signals_demo.dart';

/// One demo screen and where it shows up.
class DemoEntry {
  /// Creates an entry.
  const DemoEntry(this.title, this.subtitle, this.builder);

  /// The list title, also the route name.
  final String title;

  /// What the demo records and in which tab.
  final String subtitle;

  /// Builds the screen.
  final WidgetBuilder builder;
}

/// Every demo, in list order.
final List<DemoEntry> demoEntries = <DemoEntry>[
  DemoEntry('Dio', 'Network: GET, POST, upload, error, cancel, retry', (_) => const DioDemo()),
  DemoEntry('http', 'Network: client, runZoned, streaming', (_) => const HttpDemo()),
  DemoEntry('Chopper', 'Network: hand-written service', (_) => const ChopperDemo()),
  DemoEntry('Bloc', 'State: cubit, bloc with events, errors', (_) => const BlocDemo()),
  DemoEntry(
    'Riverpod',
    'State: Notifier, FutureProvider, family, autoDispose',
    (_) => const RiverpodDemo(),
  ),
  DemoEntry('Provider', 'State: ChangeNotifier cart', (_) => const ProviderDemo()),
  DemoEntry(
    'GetX',
    'State, Network, Routes: controller, Get.to, GetConnect',
    (_) => const GetxDemo(),
  ),
  DemoEntry('MobX', 'State: store, actions, ObservableList', (_) => const MobxDemo()),
  DemoEntry('Signals', 'State: signal, ListSignal, computed', (_) => const SignalsDemo()),
];

/// Lists the demos. Tap the bubble on the edge to open the inspector.
class HomeScreen extends StatelessWidget {
  /// Creates the screen.
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('snoop playground')),
    body: ListView(
      children: <Widget>[
        for (final entry in demoEntries)
          ListTile(
            title: Text(entry.title),
            subtitle: Text(entry.subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                settings: RouteSettings(name: '/${entry.title.toLowerCase()}'),
                builder: entry.builder,
              ),
            ),
          ),
      ],
    ),
  );
}
