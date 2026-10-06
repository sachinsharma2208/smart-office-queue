import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routes.dart';
import '../core/status_style.dart';
import '../models/department.dart';
import '../providers/visitor_provider.dart';
import '../utils/formatters.dart';
import '../utils/ui_helpers.dart';
import '../widgets/centered_body.dart';
import '../widgets/state_views.dart';

class GenerateTokenScreen extends StatefulWidget {
  const GenerateTokenScreen({super.key, required this.department});
  final Department department;

  @override
  State<GenerateTokenScreen> createState() => _GenerateTokenScreenState();
}

class _GenerateTokenScreenState extends State<GenerateTokenScreen> {
  bool _priority = false;
  late final VisitorProvider _visitor;

  @override
  void initState() {
    super.initState();
    _visitor = context.read<VisitorProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _visitor.departmentPoller.start());
  }

  @override
  void dispose() {
    _visitor.departmentPoller.stop();
    super.dispose();
  }

  Future<void> _generate(Department dept) async {
    final confirmed = await confirmDialog(
      context,
      title: 'Generate token?',
      message: 'Get a ${_priority ? 'PRIORITY' : 'normal'} token for ${dept.name}?',
      confirmLabel: 'Generate',
    );
    if (!confirmed || !mounted) return;
    final token = await runAction(
      context,
      () => _visitor.generateToken(dept, priority: _priority),
      success: (t) => 'Token ${t.tokenNumber} created',
    );
    if (token != null && mounted) {
      Navigator.pushReplacementNamed(context, Routes.token);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visitor = context.watch<VisitorProvider>();
    // Use the live copy of the department so a pause shows up immediately.
    final dept = visitor.departments.firstWhere(
      (d) => d.id == widget.department.id,
      orElse: () => widget.department,
    );
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(dept.name)),
      body: CenteredBody(
        maxWidth: 560,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Row(children: [
              CircleAvatar(radius: 28, backgroundColor: scheme.primaryContainer, child: Icon(departmentIcon(dept.code), size: 28)),
              const SizedBox(width: 16),
              Expanded(child: Text(dept.name, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700))),
            ]),
            const SizedBox(height: 20),
            if (dept.isPaused)
              InfoBanner(
                icon: Icons.pause_circle_outline,
                color: scheme.error,
                message: '${dept.name} is temporarily unavailable. Tokens cannot be generated until staff resume the queue.',
              )
            else
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    _Row(label: 'People waiting', value: '${dept.waitingCount}'),
                    _Row(label: 'Estimated wait if you join now', value: formatEstimate(dept.estimatedWaitMinutes)),
                    _Row(label: 'Now serving', value: dept.servingToken ?? '—'),
                  ]),
                ),
              ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
              child: SwitchListTile(
                value: _priority,
                onChanged: dept.isPaused ? null : (v) => setState(() => _priority = v),
                title: const Text('Priority token'),
                subtitle: const Text('For urgent cases. Served before normal tokens, but never interrupts the person currently being served.'),
                secondary: const Icon(Icons.bolt),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: dept.isPaused || visitor.busy ? null : () => _generate(dept),
              icon: visitor.busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.confirmation_number),
              label: Text(visitor.busy ? 'Generating…' : 'Generate token'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}
