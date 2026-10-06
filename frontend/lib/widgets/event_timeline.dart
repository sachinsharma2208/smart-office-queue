import 'package:flutter/material.dart';

import '../models/token.dart';
import '../utils/formatters.dart';

String _label(QueueEvent e) {
  switch (e.eventType) {
    case 'CREATED':
      return 'Token created';
    case 'CALLED':
      return 'Called to the counter';
    case 'COMPLETED':
      return 'Service completed';
    case 'CANCELLED':
      return 'Cancelled';
    case 'NO_SHOW_REQUEUED':
      return 'No-show: moved to the end of the queue';
    case 'NO_SHOW_CANCELLED':
      return 'Second no-show: token cancelled';
    case 'TRANSFERRED_OUT':
      return 'Transferred to another department';
    case 'TRANSFERRED_IN':
      return 'Transferred in from another department';
    default:
      return e.eventType;
  }
}

String? _detail(QueueEvent e) {
  if (e.eventType == 'TRANSFERRED_OUT' || e.eventType == 'TRANSFERRED_IN') {
    final m = e.metadata;
    return '${m['from_department']} (${m['from_token']}) → ${m['to_department']} (${m['to_token']})';
  }
  return null;
}

/// Vertical history of what happened to a token (from queue_events).
class EventTimeline extends StatelessWidget {
  const EventTimeline({super.key, required this.events});
  final List<QueueEvent> events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) return const Text('No history yet.');
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final e in events)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Icon(Icons.circle, size: 10, color: scheme.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_label(e), style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (_detail(e) != null) Text(_detail(e)!, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text(formatDateTime(e.createdAt), style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
      ],
    );
  }
}
