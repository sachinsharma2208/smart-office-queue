import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/status_style.dart';
import '../models/department.dart';
import '../providers/staff_provider.dart';
import '../utils/ui_helpers.dart';
import '../widgets/centered_body.dart';
import '../widgets/state_views.dart';

/// Admin: pause / resume departments.
class DepartmentManagementScreen extends StatefulWidget {
  const DepartmentManagementScreen({super.key});

  @override
  State<DepartmentManagementScreen> createState() => _DepartmentManagementScreenState();
}

class _DepartmentManagementScreenState extends State<DepartmentManagementScreen> {
  late final StaffProvider _staff;

  @override
  void initState() {
    super.initState();
    _staff = context.read<StaffProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _staff.loadDepartments();
      _staff.departmentPoller.start();
    });
  }

  @override
  void dispose() {
    _staff.departmentPoller.stop();
    super.dispose();
  }

  Future<void> _toggle(Department d) async {
    final pausing = !d.isPaused;
    final ok = await confirmDialog(
      context,
      title: pausing ? 'Pause ${d.name}?' : 'Resume ${d.name}?',
      message: pausing
          ? 'Visitors will not be able to take new tokens. Tokens already in the queue stay where they are.'
          : 'Visitors will be able to take new tokens again.',
      confirmLabel: pausing ? 'Pause' : 'Resume',
      destructive: pausing,
    );
    if (!ok || !mounted) return;
    await runAction(
      context,
      () => _staff.setPaused(d.id, paused: pausing),
      success: (_) => '${d.name} ${pausing ? 'paused' : 'resumed'}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final staff = context.watch<StaffProvider>();
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Department management')),
      body: staff.departments.isEmpty
          ? const LoadingView()
          : RefreshIndicator(
              onRefresh: staff.loadDepartments,
              child: CenteredBody(
                maxWidth: 760,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    for (final d in staff.departments)
                      Card(
                        elevation: 0,
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: d.isPaused ? scheme.error : scheme.outlineVariant),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              foregroundColor: scheme.onPrimaryContainer,
                              child: Icon(departmentIcon(d.code)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(d.name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                Text(
                                  '${d.isPaused ? 'PAUSED' : 'Open'} · ${d.waitingCount} waiting'
                                  '${d.servingToken != null ? ' · serving ${d.servingToken}' : ''}',
                                  style: TextStyle(color: d.isPaused ? scheme.error : null),
                                ),
                              ]),
                            ),
                            d.isPaused
                                ? FilledButton.icon(
                                    onPressed: staff.busy ? null : () => _toggle(d),
                                    icon: const Icon(Icons.play_arrow),
                                    label: const Text('Resume'),
                                  )
                                : OutlinedButton.icon(
                                    onPressed: staff.busy ? null : () => _toggle(d),
                                    icon: const Icon(Icons.pause),
                                    label: const Text('Pause'),
                                  ),
                          ]),
                        ),
                      ),
                  ],
                ),
              ),
            ),
    );
  }
}
