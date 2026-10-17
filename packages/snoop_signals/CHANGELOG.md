## 0.1.0

- Initial release: `SnoopSignals.install` chains a `SnoopSignalsObserver` in front of
  `SignalsObserver.instance` and feeds signals into snoop's State tab.
- Optional tracking of computed signals and effects; `shouldTrack` filter.
- Supports `signals_core >=6.0.0 <8.0.0`.
