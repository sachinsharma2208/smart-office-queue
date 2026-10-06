import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/token.dart';
import '../providers/load_state.dart';
import '../providers/staff_provider.dart';
import '../utils/ui_helpers.dart';
import '../widgets/centered_body.dart';
import '../widgets/state_views.dart';
import '../widgets/token_detail_dialog.dart';
import '../widgets/transfer_dialog.dart';
import '../widgets/waiting_token_tile.dart';

/// Full waiting queue of the selected department, in the exact order the
/// backend will call tokens (priority first, then FIFO).
class QueueScreen extends StatefulWidget {
  const QueueScreen({super.key});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  late final StaffProvider _staff;

  @override
  void initState() {
    super.initState();
    _staff = context.read<StaffProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staff.refreshQueue(silent: true);
      _staff.queuePoller.start();
    });
  }

  @override
  void dispose() {
    _staff.queuePoller.stop();
    super.dispose();
  }

  Future<void> _transfer(TokenModel t) async {
    final target = await showTransferDialog(context, token: t, departments: _staff.departments);
    if (target == null || !mounted) return;
    await runAction(
      context,
      () => _staff.transfer(t.id, target),
      success: (n) => '${t.tokenNumber} transferred as ${n.tokenNumber}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<StaffProvider>();
    final q = staff.queue;

    Widget body;
    if (q == null) {
      body = staff.queueState == LoadState.error
          ? ErrorView(message: staff.queueError ?? 'Unknown error', onRetry: staff.refreshQueue)
          : const LoadingView();
    } else if (q.waiting.isEmpty) {
      body = const EmptyView(icon: Icons.inbox_outlined, title: 'The queue is empty', subtitle: 'New tokens will appear here automatically.');
    } else {
      body = RefreshIndicator(
        onRefresh: staff.refreshQueue,
        child: CenteredBody(
          maxWidth: 760,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            children: [
              if (q.serving != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: InfoBanner(icon: Icons.campaign, color: const Color(0xFF1B7F3B), message: 'Now serving ${q.serving!.tokenNumber}'),
                ),
              for (final t in q.waiting)
                WaitingTokenTile(
                  token: t,
                  onDetails: () => showTokenDetailsDialog(context, t.id),
                  onTransfer: () => _transfer(t),
                ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${q?.department.name ?? 'Queue'} - waiting${q == null ? '' : ' (${q.waiting.length})'}')),
      body: body,
    );
  }
}
