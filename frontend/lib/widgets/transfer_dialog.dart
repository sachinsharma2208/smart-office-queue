import 'package:flutter/material.dart';

import '../core/status_style.dart';
import '../models/department.dart';
import '../models/token.dart';

/// Lets staff pick the target department. Returns its id, or null if cancelled.
/// Paused departments are shown but disabled (the backend also rejects them).
Future<String?> showTransferDialog(
  BuildContext context, {
  required TokenModel token,
  required List<Department> departments,
}) {
  final targets = departments.where((d) => d.id != token.departmentId).toList();
  String? selected;
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text('Transfer ${token.tokenNumber}'),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'The token leaves this queue and receives a new number in the target department.',
              ),
              const SizedBox(height: 12),
              for (final d in targets)
                ListTile(
                  enabled: !d.isPaused,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(departmentIcon(d.code)),
                  title: Text(d.name),
                  subtitle: Text(d.isPaused ? 'Paused - unavailable' : '${d.waitingCount} waiting'),
                  trailing: Icon(selected == d.id ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                  onTap: d.isPaused ? null : () => setState(() => selected = d.id),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: selected == null ? null : () => Navigator.pop(ctx, selected),
            child: const Text('Transfer'),
          ),
        ],
      ),
    ),
  );
}
