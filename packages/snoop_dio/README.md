# snoop_dio

[Dio](https://pub.dev/packages/dio) adapter for [snoop](https://pub.dev/packages/snoop). It
also covers Retrofit, which runs on Dio.

```dart
dio.interceptors.insert(0, SnoopDioInterceptor(replayClient: dio));
```

Insert it first, so its `onError` runs before any interceptor that swallows errors.
