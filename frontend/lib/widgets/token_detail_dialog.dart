import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/token.dart';
import '../providers/staff_provider.dart';
import '../services/api_client.dart';
import '../utils/formatters.dart';
import 'event_timeline.dart';
import 'state_views.dart';
import 'status_badge.dart';

/// Staff view of one token: details + full history (loaded from the backend).
Future<void> showTokenDetailsDialog(BuildContext context, String tokenId) {
  final staff = context.read<StaffProvider>();
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Token details'),
      content: SizedBox(
        width: 420,
        child: FutureBuilder<TokenModel>(
          future: staff.fetchToken(tokenId),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(height: 120, child: LoadingView());
            }
            if (snap.hasError) {
              final e = snap.error;
              return ErrorView(message: e is ApiException ? e.message : 'Could not load the token.');
            }
            final t = snap.data!;
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t.tokenNumber, style: Theme.of(ctx).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [StatusBadge(status: t.status), PriorityBadge(isPriority: t.isPriority)]),
                  const SizedBox(height: 12),
                  Text('Department: ${t.departmentName}'),
                  if (t.isWaiting) Text('Position: #${t.queuePosition}  ·  wait ${formatEstimate(t.estimatedWaitMinutes)}'),
                  Text('Missed calls: ${t.noShowCount}'),
                  Text('Issued: ${formatDateTime(t.createdAt)}'),
                  if (t.transferredToTokenNumber != null) Text('Transferred to: ${t.transferredToTokenNumber}'),
                  const Divider(height: 24),
                  Text('History', style: Theme.of(ctx).textTheme.titleSmall),
                  EventTimeline(events: t.events),
                ],
              ),
            );
          },
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
    ),
  );
}
