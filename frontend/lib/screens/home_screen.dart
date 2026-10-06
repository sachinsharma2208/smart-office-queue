import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routes.dart';
import '../core/status_style.dart';
import '../providers/auth_provider.dart';
import '../providers/visitor_provider.dart';
import '../widgets/centered_body.dart';
import '../widgets/status_badge.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Re-open the token saved on this device (if any).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<VisitorProvider>().restoreToken();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visitor = context.watch<VisitorProvider>();
    final auth = context.watch<AuthProvider>();
    final token = visitor.token;

    return Scaffold(
      body: SafeArea(
        child: CenteredBody(
          maxWidth: 640,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 32),
              Icon(Icons.confirmation_number_outlined, size: 64, color: scheme.primary),
              const SizedBox(height: 16),
              Text('Smart Office Queue',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text('Skip the line. Get a token, track your position live and arrive when it is your turn.',
                  textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
              const SizedBox(height: 32),
              if (token != null && token.isActive) ...[
                Card(
                  elevation: 0,
                  color: scheme.primaryContainer,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    leading: Icon(departmentIcon(token.departmentCode), color: scheme.onPrimaryContainer),
                    title: Text('Your token: ${token.tokenNumber}', style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        StatusBadge(status: token.status),
                        const SizedBox(width: 8),
                        if (token.isWaiting) Text('Position #${token.queuePosition ?? '-'}'),
                      ]),
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pushNamed(context, Routes.token),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              FilledButton.icon(
                onPressed: () => Navigator.pushNamed(context, Routes.departments),
                icon: const Icon(Icons.add),
                label: const Text('Get a token'),
              ),
              const SizedBox(height: 12),
              if (token != null && !token.isActive)
                OutlinedButton.icon(
                  onPressed: () => Navigator.pushNamed(context, Routes.token),
                  icon: const Icon(Icons.history),
                  label: Text('View last token (${token.tokenNumber})'),
                ),
              const SizedBox(height: 40),
              const Divider(),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () => Navigator.pushNamed(
                  context,
                  auth.isLoggedIn ? (auth.user!.isAdmin ? Routes.admin : Routes.staff) : Routes.staffLogin,
                ),
                icon: const Icon(Icons.badge_outlined),
                label: Text(auth.isLoggedIn ? 'Open staff dashboard' : 'Staff / Admin login'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
