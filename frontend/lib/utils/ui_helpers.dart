import 'package:flutter/material.dart';

import '../services/api_client.dart';

void showSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.of(context);
  final scheme = Theme.of(context).colorScheme;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message, style: TextStyle(color: error ? scheme.onError : null)),
        backgroundColor: error ? scheme.error : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

/// Confirmation dialog. Returns true only if the user confirms.
Future<bool> confirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final scheme = Theme.of(context).colorScheme;
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: scheme.error, foregroundColor: scheme.onError)
              : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Runs an API action, showing a success snackbar or the backend's error
/// message. Returns the result, or null if it failed.
Future<T?> runAction<T>(
  BuildContext context,
  Future<T> Function() action, {
  String Function(T result)? success,
}) async {
  try {
    final result = await action();
    if (context.mounted && success != null) {
      showSnack(context, success(result));
    }
    return result;
  } on ApiException catch (e) {
    if (context.mounted) showSnack(context, e.message, error: true);
  } catch (_) {
    if (context.mounted) showSnack(context, 'Something went wrong. Please try again.', error: true);
  }
  return null;
}
