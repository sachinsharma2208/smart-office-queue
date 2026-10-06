const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

String formatClock(DateTime? d) => d == null ? '—' : '${_two(d.hour)}:${_two(d.minute)}';

String formatDateTime(DateTime? d) =>
    d == null ? '—' : '${d.day} ${_months[d.month - 1]}, ${formatClock(d)}';

/// Estimated wait for display: "No wait", "~15 min".
String formatEstimate(int? minutes) {
  if (minutes == null) return '—';
  if (minutes <= 0) return 'No wait';
  return '~$minutes min';
}

String formatAvg(double minutes) => '${minutes.toStringAsFixed(1)} min';
