import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:snoop_playground/demos/demo_page.dart';

/// A counter notifier.
class Counter extends Notifier<int> {
  @override
  int build() => 0;

  /// Adds one.
  void increment() => state++;
}

/// The counter, named so it reads well in the State tab.
final counterProvider = NotifierProvider<Counter, int>(Counter.new, name: 'counter');

/// Loads after a short delay. No retries, so a failure shows up once.
final greetingProvider = FutureProvider<String>(
  (ref) async {
    await Future<void>.delayed(const Duration(milliseconds: 400));
    return 'Hello from a FutureProvider';
  },
  name: 'greeting',
  retry: (_, _) => null,
);

/// One entry per argument. User 3 fails.
final userProvider = FutureProvider.family<String, int>(
  (ref, id) async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (id == 3) throw Exception('user $id not found');
    return 'User $id';
  },
  name: 'user',
  retry: (_, _) => null,
);

/// Lives only while a screen watches it.
final scratchProvider = NotifierProvider.autoDispose<Counter, int>(Counter.new, name: 'scratch');

/// Riverpod: a Notifier, FutureProviders, a family and an autoDispose provider.
class RiverpodDemo extends ConsumerStatefulWidget {
  /// Creates the screen.
  const RiverpodDemo({super.key});

  @override
  ConsumerState<RiverpodDemo> createState() => _RiverpodDemoState();
}

class _RiverpodDemoState extends ConsumerState<RiverpodDemo> {
  int _userId = 1;

  @override
  Widget build(BuildContext context) {
    final greeting = ref.watch(greetingProvider);
    final user = ref.watch(userProvider(_userId));
    return DemoPage(
      title: 'Riverpod',
      children: <Widget>[
        const DemoSection('Notifier'),
        Text('Count: ${ref.watch(counterProvider)}', key: const Key('count')),
        DemoButtons(<String, VoidCallback?>{'+1': ref.read(counterProvider.notifier).increment}),
        const DemoSection('FutureProvider', hint: 'Loading, then data.'),
        Text(
          greeting.when(data: (v) => v, loading: () => 'loading ...', error: (e, _) => 'error: $e'),
          key: const Key('greeting'),
        ),
        DemoButtons(<String, VoidCallback?>{'Refresh': () => ref.invalidate(greetingProvider)}),
        const DemoSection('Family', hint: 'User 3 fails with an error.'),
        Text(
          user.when(data: (v) => v, loading: () => 'loading ...', error: (e, _) => 'error: $e'),
          key: const Key('user'),
        ),
        DemoButtons(<String, VoidCallback?>{
          'Next user': () => setState(() => _userId = _userId % 3 + 1),
        }),
        const DemoSection(
          'autoDispose',
          hint: 'Push the screen, then pop it: the entry greys out.',
        ),
        DemoButtons(<String, VoidCallback?>{
          'Push scratch screen': () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              settings: const RouteSettings(name: '/riverpod/scratch'),
              builder: (_) => const _ScratchScreen(),
            ),
          ),
        }),
      ],
    );
  }
}

class _ScratchScreen extends ConsumerWidget {
  const _ScratchScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) => DemoPage(
    title: 'autoDispose scratch',
    children: <Widget>[
      Text('Scratch: ${ref.watch(scratchProvider)}', key: const Key('scratch')),
      DemoButtons(<String, VoidCallback?>{'+1': ref.read(scratchProvider.notifier).increment}),
    ],
  );
}
