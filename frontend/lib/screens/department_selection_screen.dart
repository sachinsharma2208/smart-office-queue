import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routes.dart';
import '../providers/load_state.dart';
import '../providers/visitor_provider.dart';
import '../utils/ui_helpers.dart';
import '../widgets/centered_body.dart';
import '../widgets/department_card.dart';
import '../widgets/state_views.dart';

class DepartmentSelectionScreen extends StatefulWidget {
  const DepartmentSelectionScreen({super.key});

  @override
  State<DepartmentSelectionScreen> createState() => _DepartmentSelectionScreenState();
}

class _DepartmentSelectionScreenState extends State<DepartmentSelectionScreen> {
  late final VisitorProvider _visitor;

  @override
  void initState() {
    super.initState();
    _visitor = context.read<VisitorProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visitor.loadDepartments();
      _visitor.departmentPoller.start(); // keep waiting counts / paused status live
    });
  }

  @override
  void dispose() {
    _visitor.departmentPoller.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visitor = context.watch<VisitorProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a department')),
      body: _body(visitor),
    );
  }

  Widget _body(VisitorProvider visitor) {
    if (visitor.departmentState == LoadState.loading && visitor.departments.isEmpty) {
      return const LoadingView(message: 'Loading departments…');
    }
    if (visitor.departmentState == LoadState.error && visitor.departments.isEmpty) {
      return ErrorView(message: visitor.departmentError ?? 'Unknown error', onRetry: visitor.loadDepartments);
    }
    if (visitor.departments.isEmpty) {
      return const EmptyView(icon: Icons.business, title: 'No departments available');
    }
    return RefreshIndicator(
      onRefresh: visitor.loadDepartments,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth > 960 ? 960.0 : constraints.maxWidth;
          const spacing = 16.0;
          final cols = width >= 800 ? 3 : (width >= 520 ? 2 : 1);
          final cardWidth = (width - 32 - spacing * (cols - 1)) / cols;
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: CenteredBody(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final d in visitor.departments)
                      SizedBox(
                        width: cardWidth,
                        child: DepartmentCard(
                          department: d,
                          onTap: () {
                            if (d.isPaused) {
                              showSnack(context, '${d.name} is temporarily unavailable. Please try again later.', error: true);
                            } else {
                              Navigator.pushNamed(context, Routes.generate, arguments: d);
                            }
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
