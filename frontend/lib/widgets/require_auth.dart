import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routes.dart';
import '../providers/auth_provider.dart';
import 'state_views.dart';

/// Route guard: shows the child only for a logged-in user (and admins for
/// admin-only pages). The backend enforces the same rules independently.
class RequireAuth extends StatelessWidget {
  const RequireAuth({super.key, required this.child, this.adminOnly = false});

  final Widget child;
  final bool adminOnly;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    if (!auth.isLoggedIn) {
      return Scaffold(
        appBar: AppBar(title: const Text('Staff area')),
        body: EmptyView(
          icon: Icons.lock_outline,
          title: auth.sessionExpired ? 'Your session has expired' : 'Please sign in',
          subtitle: 'Staff and admin pages require a login.',
          action: FilledButton(
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, Routes.staffLogin, (r) => r.isFirst),
            child: const Text('Go to login'),
          ),
        ),
      );
    }
    if (adminOnly && !auth.user!.isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin only')),
        body: EmptyView(
          icon: Icons.block,
          title: 'Admin access required',
          subtitle: 'Your account does not have permission to open this page.',
          action: FilledButton(
            onPressed: () => Navigator.pushNamedAndRemoveUntil(context, Routes.staff, (r) => r.isFirst),
            child: const Text('Back to my desk'),
          ),
        ),
      );
    }
    return child;
  }
}
