import 'dart:async';

import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/date_keys.dart';
import '../models/money.dart';
import '../models/month_summary.dart';
import '../report/report_client.dart';
import '../services/auth_service.dart';
import '../utils/formatters.dart';
import '../voice/voice_workflow_client.dart';
import '../widgets/auth_widgets.dart';
import '../utils/responsive.dart';

/// The month-end report: where you spent more, where you saved and what to
/// improve. It is written by the n8n report workflow into Firestore.
class ReportScreen extends StatefulWidget {
  const ReportScreen({
    super.key,
    required this.auth,
    required this.user,
    required this.data,
    required this.symbol,
  });

  final AuthService auth;
  final AuthUser user;
  final UserData data;
  final String symbol;

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> {
  static const int _monthsBack = 11;

  late final ReportClient _client = createReportClient(widget.auth, widget.user.uid);
  late final String _currentMonth = DateKeys.ofMonth(DateTime.now());
  late String _monthKey = _currentMonth;
  bool _busy = false;
  String? _error;
  String? _info;

  String _shift(String monthKey, int delta) {
    final start = DateKeys.startOfMonth(monthKey);
    return DateKeys.ofMonth(DateTime(start.year, start.month + delta));
  }

  bool get _canGoBack => _monthKey.compareTo(_shift(_currentMonth, -_monthsBack)) > 0;
  bool get _canGoForward => _monthKey.compareTo(_currentMonth) < 0;

  void _go(int delta) {
    setState(() {
      _monthKey = _shift(_monthKey, delta);
      _error = null;
      _info = null;
    });
  }

  /// The month's numbers, read here with the user's own sign-in and sent to the workflow.
  Future<Map<String, dynamic>> _collect(String month) async {
    final repo = widget.data;
    final expenses = await repo.expenses.getRange(
      DateKeys.startOfMonth(month),
      DateKeys.endOfMonthExclusive(month),
    );
    final budget = await repo.budgets.getBudget(month);
    final stats = await repo.expenses.getStats(month);
    final previous = await repo.expenses.getStats(_shift(month, -1));
    return {
      'currencySymbol': widget.symbol,
      'budget': budget == null
          ? null
          : {
              'income': budget.income,
              'categories': [
                for (final c in budget.categories)
                  {'categoryId': c.categoryId, 'name': c.name, 'kind': c.kind.name, 'limit': c.limit},
              ],
            },
      'stats': stats.expenseCount > 0 ? stats.toExpenseMap() : null,
      'prevStats': previous.expenseCount > 0 ? previous.toExpenseMap() : null,
      'expenses': [
        for (final e in expenses.take(2000))
          {
            'amount': e.amount,
            'categoryId': e.categoryId,
            'categoryName': e.categoryName,
            'categoryKind': e.categoryKind.name,
            'note': e.note,
            if (e.merchant != null) 'merchant': e.merchant,
            'dayKey': e.dayKey,
            'monthKey': e.monthKey,
            'source': e.source.name,
          },
      ],
    };
  }

  Future<void> _generate() async {
    setState(() {
      _busy = true;
      _error = null;
      _info = null;
    });
    final month = _monthKey;
    try {
      final status = await _client.generate(month, data: await _collect(month));
      if (!mounted) return;
      final summary = _client.lastSummary;
      if (status == 'generated' && summary != null) {
        // The workflow only writes the report; the app saves it under its own account.
        await widget.data.summaries
            .saveSummary(MonthSummary.fromMap(month, summary))
            .timeout(const Duration(seconds: 20));
      }
      if (!mounted) return;
      if (status == 'skipped') {
        final reason = _client.lastReason ?? '';
        final String text;
        if (reason == 'no_data') {
          text = 'There are no expenses or budget for ${monthTitle(month)} yet. Add some (or the sample data in Settings) and try again.';
        } else if (reason == 'already_generated') {
          text = 'A report for ${monthTitle(month)} already exists.';
        } else if (reason.isNotEmpty) {
          text = 'The report could not be built for ${monthTitle(month)}: $reason';
        } else {
          text = 'There is nothing to report for ${monthTitle(month)} yet. Add some expenses first.';
        }
        setState(() => _info = text);
      }
    } on VoiceWorkflowException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Expense report')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Previous month',
                    onPressed: _canGoBack && !_busy ? () => _go(-1) : null,
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Expanded(
                    child: Text(
                      monthTitle(_monthKey),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Next month',
                    onPressed: _canGoForward && !_busy ? () => _go(1) : null,
                    icon: const Icon(Icons.chevron_right),
                  ),
                ],
              ),
            ),
            Expanded(
              child: StreamBuilder<MonthSummary?>(
                key: ValueKey(_monthKey),
                stream: widget.data.summaries.watchSummary(_monthKey),
                builder: (context, snapshot) {
                  final summary = snapshot.data;
                  return ListView(
                    padding: Responsive.listPadding(context, maxWidth: 760, top: 8, bottom: 32),
                    children: [
                      if (_error != null) ...[MessageBanner(message: _error!), const SizedBox(height: 12)],
                      if (_info != null) ...[MessageBanner(message: _info!, isError: false), const SizedBox(height: 12)],
                      if (snapshot.connectionState == ConnectionState.waiting && summary == null)
                        const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()))
                      else if (summary == null)
                        _Empty(monthKey: _monthKey, busy: _busy, available: _client.available, onGenerate: _generate)
                      else ...[
                        _ReportBody(summary: summary, symbol: widget.symbol),
                        const SizedBox(height: 16),
                        if (_client.available)
                          OutlinedButton.icon(
                            onPressed: _busy ? null : _generate,
                            icon: _busy ? const _Spinner() : const Icon(Icons.refresh),
                            label: Text(_busy ? 'Updating…' : 'Refresh report'),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Spinner extends StatelessWidget {
  const _Spinner();

  @override
  Widget build(BuildContext context) =>
      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));
}

class _Empty extends StatelessWidget {
  const _Empty({required this.monthKey, required this.busy, required this.available, required this.onGenerate});

  final String monthKey;
  final bool busy;
  final bool available;
  final VoidCallback onGenerate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          Icon(Icons.insights_outlined, size: 56, color: scheme.primary),
          const SizedBox(height: 16),
          Text('No report for ${monthTitle(monthKey)} yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            available
                ? 'Reports are made automatically at the start of each month. You can also make one now.'
                : 'Reports need the n8n workflow, which is not connected in this build.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
          if (available) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: busy ? null : onGenerate,
              icon: busy ? const _Spinner() : const Icon(Icons.auto_awesome),
              label: Text(busy ? 'Writing your report…' : 'Generate report'),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReportBody extends StatelessWidget {
  const _ReportBody({required this.summary, required this.symbol});

  final MonthSummary summary;
  final String symbol;

  String _money(int minor) => Money.format(minor, symbol: symbol);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final report = summary.report;
    final reds = summary.redFlags;
    final greens = summary.greenFlags;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (report != null && report.headline.isNotEmpty) ...[
          Text(report.headline, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
        ],
        if (report?.partial ?? false)
          Align(
            alignment: Alignment.centerLeft,
            child: Chip(
              avatar: const Icon(Icons.hourglass_bottom, size: 16),
              label: const Text('Progress so far — month not finished'),
              backgroundColor: scheme.tertiaryContainer,
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Income', value: _money(summary.income))),
            const SizedBox(width: 8),
            Expanded(child: _Stat(label: 'Spent', value: _money(summary.totalSpent))),
            const SizedBox(width: 8),
            Expanded(
              child: _Stat(
                label: summary.saved >= 0 ? 'Left over' : 'Over by',
                value: _money(summary.saved.abs()),
                color: summary.saved >= 0 ? StatusColors.green(context) : scheme.error,
              ),
            ),
          ],
        ),
        if (report != null && report.narrative.isNotEmpty) ...[
          const SizedBox(height: 16),
          _Markdownish(report.narrative),
        ],
        if (reds.isNotEmpty) _Section(title: 'Where you spent more', icon: Icons.flag, color: scheme.error, children: [
          for (final c in reds) _FlagRow(result: c, symbol: symbol, report: report?.overspent),
        ]),
        if (greens.isNotEmpty) _Section(title: 'Where you saved', icon: Icons.flag, color: StatusColors.green(context), children: [
          for (final c in greens) _FlagRow(result: c, symbol: symbol, report: report?.saved),
        ]),
        if (report != null && report.improvements.isNotEmpty)
          _Section(title: 'What you can improve', icon: Icons.lightbulb_outline, color: scheme.primary, children: [
            for (final a in report.improvements)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(a.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(a.action),
                trailing: a.estimatedSaving != null ? Text('~${_money(a.estimatedSaving!)}/mo') : null,
              ),
          ]),
        if (summary.suggestion.isNotEmpty) ...[
          const SizedBox(height: 20),
          Card(
            elevation: 0,
            color: scheme.primaryContainer,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.tips_and_updates_outlined, color: scheme.onPrimaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(summary.suggestion, style: TextStyle(color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (report != null && report.generatedBy == 'rules')
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              'The AI writer was unavailable, so this is a basic report from your numbers.',
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color)),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.icon, required this.color, required this.children});

  final String title;
  final IconData icon;
  final Color color;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

class _FlagRow extends StatelessWidget {
  const _FlagRow({required this.result, required this.symbol, this.report});

  final CategoryResult result;
  final String symbol;
  final List<ReportPoint>? report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final red = result.flag == FlagType.red;
    final color = red ? theme.colorScheme.error : StatusColors.green(context);
    String? detail;
    for (final point in report ?? const <ReportPoint>[]) {
      if (point.categoryId == result.categoryId) detail = point.detail;
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text(result.name, style: const TextStyle(fontWeight: FontWeight.w600))),
            Text('${Money.format(result.spent, symbol: symbol)} / ${Money.format(result.limit, symbol: symbol)}'),
          ]),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: result.limit > 0 ? (result.spent / result.limit).clamp(0.0, 1.0) : 0,
            color: color,
            backgroundColor: color.withValues(alpha: 0.15),
            minHeight: 6,
            borderRadius: BorderRadius.circular(3),
          ),
          if (detail != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
        ],
      ),
    );
  }
}

/// Shows the narrative, turning **bold** and "- " bullets into formatting.
class _Markdownish extends StatelessWidget {
  const _Markdownish(this.text);

  final String text;

  List<InlineSpan> _spans(String line, TextStyle? base) {
    final spans = <InlineSpan>[];
    final parts = line.split('**');
    for (var i = 0; i < parts.length; i++) {
      if (parts[i].isEmpty) continue;
      spans.add(TextSpan(text: parts[i], style: i.isOdd ? base?.copyWith(fontWeight: FontWeight.w700) : base));
    }
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.4);
    final lines = text.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final raw in lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text.rich(
              TextSpan(
                children: _spans(
                  raw.startsWith('- ') || raw.startsWith('* ') ? '•  ${raw.substring(2)}' : raw.replaceFirst(RegExp(r'^#+\s*'), ''),
                  base,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
