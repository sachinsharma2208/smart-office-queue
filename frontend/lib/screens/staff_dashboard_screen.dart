import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routes.dart';
import '../core/status_style.dart';
import '../models/token.dart';
import '../providers/auth_provider.dart';
import '../providers/load_state.dart';
import '../providers/staff_provider.dart';
import '../utils/formatters.dart';
import '../utils/ui_helpers.dart';
import '../widgets/centered_body.dart';
import '../widgets/stat_card.dart';
import '../widgets/state_views.dart';
import '../widgets/status_badge.dart';
import '../widgets/token_detail_dialog.dart';
import '../widgets/transfer_dialog.dart';
import '../widgets/waiting_token_tile.dart';

/// The service desk: call next, complete, no-show, transfer.
class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  late final StaffProvider _staff;

  @override
  void initState() {
    super.initState();
    _staff = context.read<StaffProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final user = context.read<AuthProvider>().user;
      if (user == null) return;
      await _staff.init(user);
      if (!mounted) return; // screen closed while loading: do not start pollers
      _staff.queuePoller.start();
      _staff.departmentPoller.start();
    });
  }

  @override
  void dispose() {
    _staff.queuePoller.stop();
    _staff.departmentPoller.stop();
    super.dispose();
  }

  Future<void> _callNext() => runAction<TokenModel>(context, _staff.callNext, success: (t) => 'Called ${t.tokenNumber}');

  Future<void> _complete(TokenModel t) =>
      runAction(context, () => _staff.complete(t.id), success: (_) => '${t.tokenNumber} completed');

  Future<void> _noShow(TokenModel t) async {
    final ok = await confirmDialog(
      context,
      title: 'Mark ${t.tokenNumber} as no-show?',
      message: t.noShowCount == 0
          ? 'First no-show: the token goes back to the end of the waiting queue.'
          : 'This is the second no-show: the token will be cancelled.',
      confirmLabel: 'Mark no-show',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await runAction(
      context,
      () => _staff.noShow(t.id),
      success: (r) => r.status == 'CANCELLED'
          ? '${r.tokenNumber} cancelled (2nd no-show)'
          : '${r.tokenNumber} moved to the end of the queue',
    );
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

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    Navigator.pushNamedAndRemoveUntil(context, Routes.home, (r) => false);
    _staff.reset();
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final staff = context.watch<StaffProvider>();
    final user = auth.user!;

    return Scaffold(
      appBar: AppBar(
        title: Text(user.isAdmin ? 'Service desk (admin)' : 'Service desk'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => staff.refreshQueue()),
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'admin') Navigator.pushNamed(context, Routes.admin);
              if (v == 'manage') Navigator.pushNamed(context, Routes.manage);
              if (v == 'logout') _logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(enabled: false, child: Text('${user.name}\n${user.email}')),
              if (user.isAdmin) const PopupMenuItem(value: 'admin', child: Text('Admin dashboard')),
              if (user.isAdmin) const PopupMenuItem(value: 'manage', child: Text('Department management')),
              const PopupMenuItem(value: 'logout', child: Text('Log out')),
            ],
          ),
        ],
      ),
      body: _body(staff, user.isAdmin, user.departmentName),
    );
  }

  Widget _body(StaffProvider staff, bool isAdmin, String? ownDepartmentName) {
    final q = staff.queue;
    if (q == null) {
      if (staff.queueState == LoadState.error) {
        return ErrorView(message: staff.queueError ?? 'Unknown error', onRetry: staff.refreshQueue);
      }
      return const LoadingView(message: 'Loading queue…');
    }
    final serving = q.serving;
    final stats = q.stats;
    final preview = q.waiting.take(5).toList();
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: staff.refreshQueue,
      child: CenteredBody(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            // ---- department selector (admins) / label (staff)
            Row(children: [
              Icon(departmentIcon(q.department.code), color: scheme.primary),
              const SizedBox(width: 8),
              if (isAdmin)
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: staff.selectedDepartmentId,
                    decoration: const InputDecoration(labelText: 'Department', border: OutlineInputBorder(), isDense: true),
                    items: [for (final d in staff.departments) DropdownMenuItem(value: d.id, child: Text(d.name))],
                    onChanged: (id) {
                      if (id != null) staff.selectDepartment(id);
                    },
                  ),
                )
              else
                Expanded(child: Text(ownDepartmentName ?? q.department.name, style: Theme.of(context).textTheme.titleLarge)),
              if (q.department.isPaused) ...[
                const SizedBox(width: 8),
                Chip(label: const Text('Paused'), avatar: Icon(Icons.pause_circle, color: scheme.error, size: 18)),
              ],
            ]),
            if (q.department.isPaused) ...[
              const SizedBox(height: 12),
              InfoBanner(
                icon: Icons.pause_circle_outline,
                color: scheme.error,
                message: 'This department is paused: visitors cannot take new tokens. Existing tokens can still be served.'
                    '${isAdmin ? '' : ' Ask an admin to resume it.'}',
              ),
            ],
            const SizedBox(height: 16),

            // ---- statistics
            Wrap(spacing: 12, runSpacing: 12, children: [
              StatCard(label: 'Waiting', value: '${stats.waiting}', icon: Icons.hourglass_top, color: const Color(0xFFB26A00)),
              StatCard(label: 'Serving', value: '${stats.serving}', icon: Icons.campaign, color: const Color(0xFF1B7F3B)),
              StatCard(label: 'Completed', value: '${stats.completed}', icon: Icons.check_circle, color: const Color(0xFF1565C0)),
              StatCard(label: 'No-shows', value: '${stats.noShows}', icon: Icons.person_off, color: scheme.error),
              StatCard(label: 'Cancelled', value: '${stats.cancelled}', icon: Icons.cancel, color: Colors.blueGrey),
              StatCard(label: 'Avg wait', value: formatAvg(stats.avgWaitingMinutes), icon: Icons.timer_outlined),
            ]),
            const SizedBox(height: 20),

            // ---- currently serving
            Text('Now serving', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            _servingCard(staff, serving),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: staff.busy ? null : _callNext,
              icon: staff.busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.skip_next),
              label: const Text('Call next token'),
            ),
            const SizedBox(height: 24),

            // ---- waiting preview
            Row(children: [
              Text('Waiting queue (${q.waiting.length})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(onPressed: () => Navigator.pushNamed(context, Routes.queue), child: const Text('View full queue')),
            ]),
            const SizedBox(height: 8),
            if (preview.isEmpty)
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: EmptyView(icon: Icons.inbox_outlined, title: 'Nobody is waiting'))
            else
              for (final t in preview)
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

  Widget _servingCard(StaffProvider staff, TokenModel? serving) {
    final scheme = Theme.of(context).colorScheme;
    if (serving == null) {
      return Card(
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
        child: const Padding(padding: EdgeInsets.all(20), child: Text('No token is being served. Press "Call next token".')),
      );
    }
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF1B7F3B), width: 1.5)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(serving.tokenNumber, style: Theme.of(context).textTheme.displaySmall?.copyWith(fontWeight: FontWeight.w800, color: const Color(0xFF1B7F3B))),
              StatusBadge(status: serving.status),
              PriorityBadge(isPriority: serving.isPriority),
            ]),
            const SizedBox(height: 4),
            Text('Called at ${formatClock(serving.calledAt)}${serving.noShowCount > 0 ? ' · missed ${serving.noShowCount}x before' : ''}'),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: staff.busy ? null : () => _complete(serving),
                icon: const Icon(Icons.check),
                label: const Text('Complete'),
              ),
              OutlinedButton.icon(
                onPressed: staff.busy ? null : () => _noShow(serving),
                icon: const Icon(Icons.person_off_outlined),
                label: const Text('No show'),
              ),
              TextButton.icon(
                onPressed: () => showTokenDetailsDialog(context, serving.id),
                icon: const Icon(Icons.info_outline),
                label: const Text('Details'),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
