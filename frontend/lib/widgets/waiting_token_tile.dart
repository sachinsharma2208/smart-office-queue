import 'package:flutter/material.dart';

import '../models/token.dart';
import '../utils/formatters.dart';
import 'status_badge.dart';

/// One row of the waiting queue (staff view).
class WaitingTokenTile extends StatelessWidget {
  const WaitingTokenTile({
    super.key,
    required this.token,
    required this.onDetails,
    required this.onTransfer,
  });

  final TokenModel token;
  final VoidCallback onDetails;
  final VoidCallback onTransfer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = token;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: ListTile(
        onTap: onDetails,
        leading: CircleAvatar(
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text('${t.queuePosition ?? '-'}'),
        ),
        title: Wrap(
          spacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(t.tokenNumber, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            if (t.isPriority) const PriorityBadge(isPriority: true),
          ],
        ),
        subtitle: Text(
          'In queue since ${formatClock(t.createdAt)} · wait ${formatEstimate(t.estimatedWaitMinutes)}'
          '${t.noShowCount > 0 ? ' · missed ${t.noShowCount}x' : ''}',
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (v) => v == 'details' ? onDetails() : onTransfer(),
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'details', child: Text('View details')),
            PopupMenuItem(value: 'transfer', child: Text('Transfer…')),
          ],
        ),
      ),
    );
  }
}
