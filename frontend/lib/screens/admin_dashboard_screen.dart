import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routes.dart';
import '../core/status_style.dart';
import '../models/stats.dart';
import '../providers/auth_provider.dart';
import '../providers/load_state.dart';
import '../providers/staff_provider.dart';
import '../utils/formatters.dart';
import '../widgets/bar_chart.dart';
import '../widgets/centered_body.dart';
import '../widgets/stat_card.dart';
import '../widgets/state_views.dart';

/// Admin overview: totals, department-wise statistics and a simple chart.
class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  late final StaffProvider _staff;

  @override
  void initState() {
    super.initState();
    _staff = context.read<StaffProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staff.loadDashboard();
      _staff.dashboardPoller.start();
    });
  }

  @override
  void dispose() {
    _staff.dashboardPoller.stop();
    super.dispose();
  }

  Future<void> _logout() async {
    final auth = context.read<AuthProvider>();
    Navigator.pushNamedAndRemoveUntil(context, Routes.home, (r) => false);
    _staff.reset();
    await auth.logout();
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<StaffProvider>();
    final dash = staff.dashboard;

    Widget body;
    if (dash == null) {
      body = staff.dashboardState == LoadState.error
          ? ErrorView(message: staff.dashboardError ?? 'Unknown error', onRetry: staff.loadDashboard)
          : const LoadingView();
    } else {
      body = _content(dash, staff);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin dashboard'),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: () => staff.loadDashboard()),
          IconButton(
            tooltip: 'Department management',
            icon: const Icon(Icons.tune),
            onPressed: () => Navigator.pushNamed(context, Routes.manage),
          ),
          IconButton(
            tooltip: 'Service desk',
            icon: const Icon(Icons.support_agent),
            onPressed: () => Navigator.pushNamed(context, Routes.staff),
          ),
          IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: body,
    );
  }

  Widget _content(Dashboard dash, StaffProvider staff) {
    final t = dash.totals;
    final scheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      onRefresh: staff.loadDashboard,
      child: CenteredBody(
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Text('Overall', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 12, children: [
              StatCard(label: 'Waiting', value: '${t.waiting}', icon: Icons.hourglass_top, color: const Color(0xFFB26A00)),
              StatCard(label: 'Serving now', value: '${t.serving}', icon: Icons.campaign, color: const Color(0xFF1B7F3B)),
              StatCard(label: 'Completed', value: '${t.completed}', icon: Icons.check_circle, color: const Color(0xFF1565C0)),
              StatCard(label: 'No-shows', value: '${t.noShows}', icon: Icons.person_off, color: scheme.error),
              StatCard(label: 'Cancelled', value: '${t.cancelled}', icon: Icons.cancel, color: Colors.blueGrey),
              StatCard(label: 'Avg waiting time', value: formatAvg(t.avgWaitingMinutes), icon: Icons.timer_outlined),
              StatCard(
                label: 'Paused departments',
                value: '${t.pausedDepartments}/${t.totalDepartments}',
                icon: Icons.pause_circle_outline,
                color: t.pausedDepartments > 0 ? scheme.error : Colors.green,
              ),
            ]),
            const SizedBox(height: 24),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Tokens by department', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 12),
                  SimpleBarChart(
                    groups: [
                      for (final d in dash.departments)
                        ChartGroup(d.code, [d.waiting.toDouble(), d.completed.toDouble(), d.noShows.toDouble()]),
                    ],
                    seriesLabels: const ['Waiting', 'Completed', 'No-shows'],
                    seriesColors: [const Color(0xFFB26A00), const Color(0xFF1565C0), scheme.error],
                  ),
                ]),
              ),
            ),
            const SizedBox(height: 24),
            Text('Departments', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(spacing: 12, runSpacing: 12, children: [
              for (final d in dash.departments) _DepartmentStatsCard(stats: d, onOpen: () {
                staff.selectDepartment(d.departmentId);
                Navigator.pushNamed(context, Routes.staff);
              }),
            ]),
          ],
        ),
      ),
    );
  }
}

class _DepartmentStatsCard extends StatelessWidget {
  const _DepartmentStatsCard({required this.stats, required this.onOpen});
  final DeptStats stats;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = stats;
    return SizedBox(
      width: 300,
      child: Card(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: s.isPaused ? scheme.error : scheme.outlineVariant),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(departmentIcon(s.code), color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(s.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                Text(s.isPaused ? 'Paused' : 'Open', style: TextStyle(color: s.isPaused ? scheme.error : const Color(0xFF1B7F3B), fontWeight: FontWeight.w600)),
              ]),
              const Divider(height: 20),
              _line('Waiting', '${s.waiting}'),
              _line('Serving', '${s.serving}'),
              _line('Completed', '${s.completed}'),
              _line('No shows', '${s.noShows}'),
              _line('Cancelled', '${s.cancelled}'),
              _line('Average waiting time', formatAvg(s.avgWaitingMinutes)),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: TextButton(onPressed: onOpen, child: const Text('Open desk'))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(label), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))]),
      );
}
