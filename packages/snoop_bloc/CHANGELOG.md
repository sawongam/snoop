## 0.1.0

- Initial release: `SnoopBlocObserver` feeds every bloc and cubit into snoop's State tab.
- Supports `bloc >=8.1.0 <10.0.0`.
- Events whose handler emits nothing show up as `(no state change)` entries (bloc 9.1+).
- Each emit of a handler keeps the event and the place that added it.
