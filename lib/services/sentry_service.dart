import 'package:sentry_flutter/sentry_flutter.dart';

/// Lightweight wrapper around Sentry initialisation.
///
/// When [SENTRY_DSN] is not provided via `--dart-define` (e.g. local
/// development) the wrapper degrades to a plain `appRunner()` call so the app
/// still boots without any observability.
class SentryService {
  static Future<void> init(
    Future<void> Function() appRunner, {
    required String? dsn,
  }) async {
    if (dsn == null || dsn.isEmpty) {
      await appRunner();
      return;
    }
    await SentryFlutter.init(
      (options) {
        options.dsn = dsn;
        options.tracesSampleRate = 0.1;
        options.environment = const String.fromEnvironment(
          'FLUTTER_ENV',
          defaultValue: 'development',
        );
        options.beforeSend = (event, hint) {
          // Drop spammy errors (network timeouts during foregrounding).
          if (event.exceptions
                  ?.any((e) => (e.value ?? '').contains('SocketException')) ??
              false) {
            return null;
          }
          return event;
        };
      },
      appRunner: () async {
        await appRunner();
      },
    );
  }

  /// Capture a non-fatal error. Safe to call when Sentry is not initialised —
  /// it becomes a no-op because the SDK silently swallows captures without a
  /// configured DSN.
  static Future<void> capture(Object error, [StackTrace? stack]) =>
      Sentry.captureException(error, stackTrace: stack);
}
