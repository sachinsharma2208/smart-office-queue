import 'package:flutter/material.dart';

import '../core/status_style.dart';
import '../models/department.dart';
import '../utils/formatters.dart';

/// Card shown on the department-selection screen.
class DepartmentCard extends StatelessWidget {
  const DepartmentCard({super.key, required this.department, required this.onTap});

  final Department department;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final d = department;
    final statusColor = d.isPaused ? scheme.error : const Color(0xFF1B7F3B);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Icon(departmentIcon(d.code)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(d.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      d.isPaused ? 'Paused' : 'Open',
                      style: TextStyle(color: statusColor, fontWeight: FontWeight.w600, fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (d.isPaused)
                Text(
                  'Temporarily unavailable. New tokens cannot be generated right now.',
                  style: TextStyle(color: scheme.error),
                )
              else
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    _Meta(icon: Icons.people_outline, text: '${d.waitingCount} waiting'),
                    _Meta(icon: Icons.timer_outlined, text: formatEstimate(d.estimatedWaitMinutes)),
                    if (d.servingToken != null) _Meta(icon: Icons.campaign_outlined, text: 'Serving ${d.servingToken}'),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Theme.of(context).colorScheme.outline),
        const SizedBox(width: 4),
        Text(text),
      ],
    );
  }
}
