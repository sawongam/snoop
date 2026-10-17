## 0.1.0

- Initial release: `SnoopDioInterceptor` records Dio calls into snoop's Network tab.
- Handles stream, bytes and `FormData` bodies, cancellation, retries, redirects, errors
  resolved by later interceptors and an interceptor installed twice on one Dio.
