import 'package:flutter/material.dart';

/// Colour / icon / label for each token status (used by badges and cards).
class StatusStyle {
  const StatusStyle(this.color, this.icon, this.label);
  final Color color;
  final IconData icon;
  final String label;
}

StatusStyle statusStyle(String status) {
  switch (status) {
    case 'WAITING':
      return const StatusStyle(Color(0xFFB26A00), Icons.hourglass_top, 'Waiting');
    case 'SERVING':
      return const StatusStyle(Color(0xFF1B7F3B), Icons.campaign, 'Now serving');
    case 'COMPLETED':
      return const StatusStyle(Color(0xFF1565C0), Icons.check_circle, 'Completed');
    case 'CANCELLED':
      return const StatusStyle(Color(0xFFB3261E), Icons.cancel, 'Cancelled');
    case 'TRANSFERRED':
      return const StatusStyle(Color(0xFF6750A4), Icons.swap_horiz, 'Transferred');
    default:
      return StatusStyle(Colors.grey.shade700, Icons.help_outline, status);
  }
}

IconData departmentIcon(String code) {
  switch (code) {
    case 'IT':
      return Icons.computer;
    case 'HR':
      return Icons.groups;
    case 'ACC':
      return Icons.account_balance;
    case 'ADM':
      return Icons.apartment;
    default:
      return Icons.business;
  }
}
