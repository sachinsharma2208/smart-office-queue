import 'package:flutter/material.dart';

import '../core/status_style.dart';
import '../models/token.dart';
import '../utils/formatters.dart';
import 'status_badge.dart';

/// Large card showing everything about one token (visitor view).
class TokenCard extends StatelessWidget {
  const TokenCard({super.key, required this.token});
  final TokenModel token;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final style = statusStyle(token.status);
    final t = token;

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: style.color.withOpacity(0.5), width: 1.5),
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
            color: style.color.withOpacity(0.08),
            child: Column(
              children: [
                Text('YOUR TOKEN', style: Theme.of(context).textTheme.labelMedium?.copyWith(letterSpacing: 2)),
                const SizedBox(height: 6),
                Text(
                  t.tokenNumber,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(fontWeight: FontWeight.w800, color: style.color),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  alignment: WrapAlignment.center,
                  children: [StatusBadge(status: t.status), PriorityBadge(isPriority: t.isPriority)],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 24,
              runSpacing: 16,
              children: [
                _Info(label: 'Department', value: t.departmentName, icon: departmentIcon(t.departmentCode)),
                if (t.isWaiting) ...[
                  _Info(label: 'Queue position', value: '#${t.queuePosition ?? '—'}', icon: Icons.format_list_numbered),
                  _Info(label: 'People ahead', value: '${t.peopleAhead ?? '—'}', icon: Icons.people_outline),
                  _Info(label: 'Estimated wait', value: formatEstimate(t.estimatedWaitMinutes), icon: Icons.timer_outlined),
                ],
                if (t.noShowCount > 0)
                  _Info(label: 'Missed calls', value: '${t.noShowCount}', icon: Icons.warning_amber, color: scheme.error),
                _Info(label: 'Issued at', value: formatClock(t.createdAt), icon: Icons.schedule),
                if (t.calledAt != null) _Info(label: 'Called at', value: formatClock(t.calledAt), icon: Icons.campaign_outlined),
                if (t.completedAt != null) _Info(label: 'Completed at', value: formatClock(t.completedAt), icon: Icons.check),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value, required this.icon, this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color ?? scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
                Text(value, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
