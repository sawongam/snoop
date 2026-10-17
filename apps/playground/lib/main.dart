import 'package:bloc/bloc.dart';
import 'package:flutter/material.dart';
import 'package:snoop_bloc/snoop_bloc.dart';
import 'package:snoop_getx/snoop_getx.dart';
import 'package:snoop_http/snoop_http.dart';
import 'package:snoop_mobx/snoop_mobx.dart';
import 'package:snoop_playground/app.dart';
import 'package:snoop_signals/snoop_signals.dart';

/// The global hooks: libraries with a single global slot are installed here, once.
///
/// Per-instance hooks (Dio and Chopper interceptors, `SnoopHttpClient`, the Provider notifiers)
/// are set up by the screen that uses them, and the Riverpod observer by the app's
/// `ProviderScope`.
void installSnoop() {
  Bloc.observer = SnoopBlocObserver();
  SnoopGetx.install();
  SnoopMobx.install();
  SnoopSignals.install();
}

void main() {
  installSnoop();
  // Records top-level `http.get(...)` calls and `http.Client()` made anywhere in the app.
  SnoopHttp.runZoned(() => runApp(const PlaygroundApp()));
}
