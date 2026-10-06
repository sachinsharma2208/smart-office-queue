import 'package:flutter/material.dart';

import '../core/status_style.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge({super.key, required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = statusStyle(status);
    return _Pill(color: s.color, icon: s.icon, label: s.label);
  }
}

class PriorityBadge extends StatelessWidget {
  const PriorityBadge({super.key, required this.isPriority});
  final bool isPriority;

  @override
  Widget build(BuildContext context) {
    return isPriority
        ? const _Pill(color: Color(0xFFC2410C), icon: Icons.bolt, label: 'Priority')
        : _Pill(color: Colors.blueGrey.shade600, icon: Icons.person_outline, label: 'Normal');
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.color, required this.icon, required this.label});
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ],
      ),
    );
  }
}
