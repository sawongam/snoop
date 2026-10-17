import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:snoop/src/adapters.dart';
import 'package:snoop/src/network/network_conditions.dart';
import 'package:snoop/src/network/network_registry.dart';
import 'package:snoop/src/network/network_view.dart';
import 'package:snoop/src/widgets/inspector_shared.dart';
import 'package:snoop/src/widgets/live_builder.dart';

/// Opens the detail page of call [id] on the inspector's navigator.
void openCall(BuildContext context, int id, {bool replace = false}) {
  final route = MaterialPageRoute<void>(builder: (_) => NetworkCallDetailPage(id: id));
  final navigator = Navigator.of(context);
  replace ? navigator.pushReplacement(route) : navigator.push(route);
}

// --- Replay ------------------------------------------------------------------

/// "Replay" and "Edit & resend" under a call's status line.
class ReplayActions extends StatefulWidget {
  /// Creates the actions for [record].
  const ReplayActions({required this.record, super.key});

  /// The call to resend.
  final SnoopCallRecord record;

  @override
  State<ReplayActions> createState() => _ReplayActionsState();
}

class _ReplayActionsState extends State<ReplayActions> {
  bool _busy = false;

  Future<void> _replay() async {
    setState(() => _busy = true);
    final replayed = await widget.record.replay();
    if (!mounted) return;
    setState(() => _busy = false);
    if (replayed != null) openCall(context, replayed.id);
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.record.canReplay) {
      return const Text(
        "Streamed payloads can't be replayed",
        style: TextStyle(color: Colors.white38, fontSize: 10),
      );
    }
    return Row(
      children: <Widget>[
        inspectorTextAction(
          _busy ? 'Sending…' : 'Replay',
          _busy
              ? const SizedBox.square(
                  dimension: 13,
                  child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.white54),
                )
              : const Icon(Icons.replay),
          _busy ? null : _replay,
        ),
        inspectorTextAction(
          'Edit & resend',
          const Icon(Icons.edit_outlined),
          _busy
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => ReplayEditorPage(record: widget.record)),
                ),
        ),
      ],
    );
  }
}

/// Edits a recorded call's method, URL, headers and body, then sends it.
///
/// Redacted header values can be left as they are: the values actually sent
/// go out in their place.
class ReplayEditorPage extends StatefulWidget {
  /// Creates the editor, prefilled from [record].
  const ReplayEditorPage({required this.record, super.key});

  /// The call to start from.
  final SnoopCallRecord record;

  @override
  State<ReplayEditorPage> createState() => _ReplayEditorPageState();
}

class _ReplayEditorPageState extends State<ReplayEditorPage> {
  static const List<String> _methods = <String>['GET', 'POST', 'PUT', 'PATCH', 'DELETE'];

  late String _method = widget.record.method.toUpperCase();
  late final TextEditingController _url = TextEditingController(text: '${widget.record.uri}');
  late final TextEditingController _headers = TextEditingController(
    text: widget.record.requestHeaders.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
  );
  late final String _initialBody = _bodyText(widget.record.requestBody);
  late final TextEditingController _body = TextEditingController(text: _initialBody);
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _url.dispose();
    _headers.dispose();
    _body.dispose();
    super.dispose();
  }

  static String _bodyText(Object? body) => switch (body) {
    null => '',
    String() => body,
    _ => inspectorPretty(body),
  };

  Future<void> _send() async {
    final uri = Uri.tryParse(_url.text.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      setState(() => _error = 'Enter a full URL, including https://');
      return;
    }
    final headers = <String, String>{};
    for (final line in const LineSplitter().convert(_headers.text)) {
      if (line.trim().isEmpty) continue;
      final colon = line.indexOf(':');
      if (colon <= 0) {
        setState(() => _error = 'Header lines read "Name: value". Check "${line.trim()}".');
        return;
      }
      headers[line.substring(0, colon).trim()] = line.substring(colon + 1).trim();
    }
    final request = widget.record.toReplayRequest()
      ..method = _method
      ..uri = uri
      ..headers = headers;
    // An untouched body keeps the recorded value, so the original payload
    // (FormData included) is sent.
    if (_body.text != _initialBody) request.body = _parseBody(_body.text);

    setState(() {
      _error = null;
      _busy = true;
    });
    final replayed = await widget.record.replay(request);
    if (!mounted) return;
    setState(() => _busy = false);
    if (replayed != null) openCall(context, replayed.id, replace: true);
  }

  static Object? _parseBody(String text) {
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  @override
  Widget build(BuildContext context) {
    final methods = _methods.contains(_method) ? _methods : <String>[..._methods, _method];
    return InspectorDetailPage(
      title: 'Edit & resend',
      actions: <Widget>[
        Padding(
          padding: const EdgeInsets.only(right: 4),
          child: FilledButton(
            key: const ValueKey<String>('snoop.replay_send'),
            onPressed: _busy ? null : _send,
            style: FilledButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 14),
            ),
            child: Text(_busy ? 'Sending…' : 'Send'),
          ),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          inspectorLabel('METHOD'),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: InspectorSegmented<String>(
              value: _method,
              segments: <(String, String)>[for (final m in methods) (m, m)],
              onChanged: (m) => setState(() => _method = m),
            ),
          ),
          const SizedBox(height: 12),
          inspectorLabel('URL'),
          _EditorField(controller: _url, hint: 'https://…', maxLines: 3),
          const SizedBox(height: 12),
          inspectorLabel('HEADERS'),
          _EditorField(controller: _headers, hint: 'Name: value, one per line', maxLines: 8),
          const Padding(
            padding: EdgeInsets.only(top: 4),
            child: Text(
              'Redacted values are sent as they were recorded.',
              style: TextStyle(color: Colors.white38, fontSize: 10),
            ),
          ),
          const SizedBox(height: 12),
          inspectorLabel('BODY'),
          _EditorField(controller: _body, hint: 'JSON or text; empty sends none', maxLines: 14),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: InspectorColors.error, fontSize: 11)),
          ],
        ],
      ),
    );
  }
}

class _EditorField extends StatelessWidget {
  const _EditorField({required this.controller, required this.hint, required this.maxLines});

  final TextEditingController controller;
  final String hint;
  final int maxLines;

  @override
  Widget build(BuildContext context) => TextField(
    controller: controller,
    minLines: 1,
    maxLines: maxLines,
    style: inspectorMono,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.multiline,
    decoration: InputDecoration(
      isDense: true,
      hintText: hint,
      hintStyle: const TextStyle(color: Colors.white30, fontSize: 11),
      filled: true,
      fillColor: InspectorColors.card,
      contentPadding: const EdgeInsets.all(8),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

// --- Network conditions ------------------------------------------------------

/// The amber strip over the call list while trouble is being simulated, so
/// it is never left on by accident.
class NetworkConditionsBanner extends StatelessWidget {
  /// Creates the banner.
  const NetworkConditionsBanner({super.key});

  @override
  Widget build(BuildContext context) =>
      LiveBuilder(listenable: SnoopNetworkConditions.instance, builder: _build);

  Widget _build(BuildContext context) {
    final conditions = SnoopNetworkConditions.instance;
    final summary = conditions.summary;
    if (summary == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Material(
        color: InspectorColors.warning.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => openNetworkConditions(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
            child: Row(
              children: <Widget>[
                const Icon(Icons.speed, size: 15, color: InspectorColors.warning),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Simulating  ·  $summary',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: InspectorColors.warning, fontSize: 11),
                  ),
                ),
                TextButton(
                  onPressed: conditions.reset,
                  style: TextButton.styleFrom(
                    foregroundColor: InspectorColors.warning,
                    visualDensity: VisualDensity.compact,
                    textStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  child: const Text('TURN OFF'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pushes the Network conditions page.
void openNetworkConditions(BuildContext context) => Navigator.of(
  context,
).push(MaterialPageRoute<void>(builder: (_) => const NetworkConditionsPage()));

/// Sets `Snoop.networkConditions`: extra latency and a share of calls that fail on
/// purpose, for every call or those matching a URL filter.
class NetworkConditionsPage extends StatefulWidget {
  /// Creates the page.
  const NetworkConditionsPage({super.key});

  @override
  State<NetworkConditionsPage> createState() => _NetworkConditionsPageState();
}

class _NetworkConditionsPageState extends State<NetworkConditionsPage> {
  static const List<(Duration, String)> _delays = <(Duration, String)>[
    (Duration.zero, 'None'),
    (Duration(milliseconds: 500), '0.5s'),
    (Duration(seconds: 1), '1s'),
    (Duration(seconds: 3), '3s'),
    (Duration(seconds: 10), '10s'),
  ];
  static const List<(double, String)> _rates = <(double, String)>[
    (0, 'Never'),
    (0.1, '10%'),
    (0.25, '25%'),
    (0.5, '50%'),
    (1, 'Always'),
  ];

  SnoopNetworkConditions get _conditions => SnoopNetworkConditions.instance;
  late final TextEditingController _filter = TextEditingController(text: _conditions.urlFilter)
    ..addListener(() => _conditions.urlFilter = _filter.text);

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  /// The preset nearest [value], so a value set from code still selects one.
  static T _nearest<T>(List<(T, String)> presets, double Function(T) measure, double value) {
    var best = presets.first.$1;
    for (final (preset, _) in presets) {
      if ((measure(preset) - value).abs() < (measure(best) - value).abs()) best = preset;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) => LiveBuilder(
    listenable: _conditions,
    builder: (context) => InspectorDetailPage(
      title: 'Network conditions',
      actions: <Widget>[
        if (_conditions.isActive || _conditions.urlFilter.isNotEmpty)
          inspectorTextAction('Reset', const Icon(Icons.restart_alt), () {
            _conditions.reset();
            _filter.clear();
          }),
      ],
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: <Widget>[
          const Text(
            'Applied by every snoop network adapter to new calls until you turn it '
            'off or restart the app.',
            style: TextStyle(color: Colors.white54, fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 14),
          inspectorLabel('EXTRA LATENCY'),
          _picker<Duration>(
            _delays,
            _nearest(
              _delays,
              (d) => d.inMilliseconds.toDouble(),
              _conditions.delay.inMilliseconds.toDouble(),
            ),
            (d) => _conditions.delay = d,
          ),
          const SizedBox(height: 14),
          inspectorLabel('FAIL CALLS'),
          _picker<double>(
            _rates,
            _nearest(_rates, (r) => r, _conditions.failureRate),
            (r) => _conditions.failureRate = r,
          ),
          if (SnoopAdapters.withoutFaults.isNotEmpty) ...<Widget>[
            const SizedBox(height: 4),
            Text(
              'Latency only for ${SnoopAdapters.withoutFaults.join(', ')}: '
              'its calls are never failed on purpose.',
              style: const TextStyle(color: InspectorColors.warning, fontSize: 10),
            ),
          ],
          const SizedBox(height: 14),
          inspectorLabel('FAIL WITH'),
          _picker<SnoopFault>(
            <(SnoopFault, String)>[for (final f in SnoopFault.values) (f, f.label)],
            _conditions.fault,
            (f) => _conditions.fault = f,
          ),
          const SizedBox(height: 4),
          Text(
            _faultHint(_conditions.fault),
            style: const TextStyle(color: Colors.white38, fontSize: 10),
          ),
          const SizedBox(height: 14),
          inspectorLabel('ONLY URLS CONTAINING'),
          InspectorSearchField(controller: _filter, hint: 'e.g. /orders  (empty: every call)'),
        ],
      ),
    ),
  );

  static String _faultHint(SnoopFault fault) => switch (fault) {
    SnoopFault.offline => 'A connection error, as with no network.',
    SnoopFault.timeout => 'A timeout, after the latency above.',
    SnoopFault.unauthorized => 'A 401 response: handy for testing token refresh.',
    _ => 'A ${fault.statusCode} response with a small JSON body.',
  };

  Widget _picker<T>(List<(T, String)> segments, T value, ValueChanged<T> onChanged) =>
      InspectorSegmented<T>(expand: true, value: value, segments: segments, onChanged: onChanged);
}
