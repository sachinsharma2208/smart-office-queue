import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/routes.dart';
import '../providers/load_state.dart';
import '../providers/visitor_provider.dart';
import '../utils/ui_helpers.dart';
import '../widgets/centered_body.dart';
import '../widgets/event_timeline.dart';
import '../widgets/state_views.dart';
import '../widgets/token_card.dart';

/// Visitor's token: live position + estimated wait (polled from the backend).
class TokenDetailsScreen extends StatefulWidget {
  const TokenDetailsScreen({super.key});

  @override
  State<TokenDetailsScreen> createState() => _TokenDetailsScreenState();
}

class _TokenDetailsScreenState extends State<TokenDetailsScreen> {
  late final VisitorProvider _visitor;

  @override
  void initState() {
    super.initState();
    _visitor = context.read<VisitorProvider>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visitor.refreshToken(silent: true);
      _visitor.tokenPoller.start();
    });
  }

  @override
  void dispose() {
    _visitor.tokenPoller.stop();
    super.dispose();
  }

  Future<void> _cancel() async {
    final ok = await confirmDialog(
      context,
      title: 'Cancel this token?',
      message: 'You will lose your place in the queue. This cannot be undone.',
      confirmLabel: 'Cancel token',
      destructive: true,
    );
    if (!ok || !mounted) return;
    await runAction(context, _visitor.cancelToken, success: (_) => 'Token cancelled');
    // The token may already have changed state (e.g. it was just called):
    // refresh so the screen always shows the backend's truth.
    if (mounted) await _visitor.refreshToken(silent: true);
  }

  @override
  Widget build(BuildContext context) {
    final visitor = context.watch<VisitorProvider>();
    final token = visitor.token;
    final scheme = Theme.of(context).colorScheme;

    Widget body;
    if (token == null) {
      if (visitor.tokenState == LoadState.loading) {
        body = const LoadingView();
      } else if (visitor.tokenState == LoadState.error) {
        body = ErrorView(message: visitor.tokenError ?? 'Unknown error', onRetry: visitor.restoreToken);
      } else {
        body = EmptyView(
          icon: Icons.confirmation_number_outlined,
          title: 'You do not have a token yet',
          action: FilledButton(
            onPressed: () => Navigator.pushReplacementNamed(context, Routes.departments),
            child: const Text('Get a token'),
          ),
        );
      }
    } else {
      body = RefreshIndicator(
        onRefresh: () => visitor.refreshToken(),
        child: CenteredBody(
          maxWidth: 560,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            children: [
              if (token.isServing) ...[
                const InfoBanner(
                  icon: Icons.campaign,
                  color: Color(0xFF1B7F3B),
                  message: 'It is your turn! Please proceed to the counter now.',
                ),
                const SizedBox(height: 12),
              ],
              if (token.isWaiting && token.departmentPaused) ...[
                InfoBanner(
                  icon: Icons.pause_circle_outline,
                  color: scheme.error,
                  message: '${token.departmentName} is paused for new visitors. Your place in the queue is kept.',
                ),
                const SizedBox(height: 12),
              ],
              if (token.noShowCount > 0 && token.isWaiting) ...[
                const InfoBanner(
                  icon: Icons.warning_amber,
                  color: Color(0xFFB26A00),
                  message: 'You missed your call and were moved to the end of the queue. Missing a second call cancels the token.',
                ),
                const SizedBox(height: 12),
              ],
              TokenCard(token: token),
              const SizedBox(height: 16),
              if (token.status == 'TRANSFERRED' && token.transferredToTokenNumber != null) ...[
                InfoBanner(
                  icon: Icons.swap_horiz,
                  color: const Color(0xFF6750A4),
                  message: 'Staff moved you to another department. Your new token is ${token.transferredToTokenNumber}.',
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: visitor.followTransfer,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text('Track ${token.transferredToTokenNumber}'),
                ),
              ],
              if (token.isWaiting)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: visitor.busy ? null : _cancel,
                  icon: const Icon(Icons.close),
                  label: const Text('Cancel token'),
                ),
              if (!token.isActive && token.status != 'TRANSFERRED') ...[
                FilledButton(
                  onPressed: () async {
                    await visitor.clearToken();
                    if (context.mounted) Navigator.pushReplacementNamed(context, Routes.departments);
                  },
                  child: const Text('Get a new token'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () async {
                    await visitor.clearToken();
                    if (context.mounted) Navigator.pushNamedAndRemoveUntil(context, Routes.home, (r) => false);
                  },
                  child: const Text('Back to home'),
                ),
              ],
              const SizedBox(height: 16),
              if (token.isActive)
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.sync, size: 14, color: scheme.outline),
                  const SizedBox(width: 6),
                  Text('Live - updates every 5 seconds', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.outline)),
                ]),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.outlineVariant)),
                child: ExpansionTile(
                  title: const Text('Token history'),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [EventTimeline(events: token.events)],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Token details'),
        leading: IconButton(
          icon: const Icon(Icons.home_outlined),
          onPressed: () => Navigator.pushNamedAndRemoveUntil(context, Routes.home, (r) => false),
        ),
      ),
      body: body,
    );
  }
}
