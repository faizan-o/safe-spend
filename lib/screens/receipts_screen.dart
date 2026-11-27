import 'dart:async';

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/category.dart';
import '../models/expense.dart';
import '../models/money.dart';
import '../models/receipt.dart';
import '../utils/formatters.dart';
import '../utils/platform_support.dart';
import '../widgets/expense_sheet.dart';
import '../utils/responsive.dart';

/// Every receipt the user scanned, newest first, with the time it was
/// uploaded. Pictures live in Firestore.
class ReceiptsScreen extends StatelessWidget {
  const ReceiptsScreen({super.key, required this.data, required this.onScan});

  final UserData data;

  /// Starts a new scan (the Voice tab owns the camera flow).
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Receipts')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'scan-fab',
        onPressed: onScan,
        icon: Icon(canUseCamera ? Icons.photo_camera_outlined : Icons.upload_file_outlined),
        label: Text(canUseCamera ? 'Scan receipt' : 'Upload receipt'),
      ),
      body: StreamBuilder<List<Receipt>>(
        stream: data.receipts.watchReceipts(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('Receipts could not be loaded. Check your connection and that the Firestore rules are deployed.',
                    textAlign: TextAlign.center),
              ),
            );
          }
          final receipts = [
            for (final r in snapshot.data ?? const <Receipt>[])
              if (r.status != ReceiptStatus.discarded) r,
          ];
          if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
          if (receipts.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.receipt_long_outlined, size: 56, color: theme.colorScheme.primary),
                    const SizedBox(height: 16),
                    Text('No receipts yet', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    Text(
                      canUseCamera
                          ? 'Scan a receipt and it is kept here with the time you added it.'
                          : 'Upload a receipt and it is kept here with the time you added it.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            );
          }

          final children = <Widget>[];
          String? currentMonth;
          for (final receipt in receipts) {
            final month = receipt.monthKey.isNotEmpty ? receipt.monthKey : '';
            if (month != currentMonth) {
              currentMonth = month;
              if (month.isNotEmpty) {
                children.add(Padding(
                  padding: const EdgeInsets.fromLTRB(4, 16, 4, 4),
                  child: Text(monthTitle(month), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                ));
              }
            }
            children.add(_ReceiptTile(
              receipt: receipt,
              data: data,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => ReceiptDetailScreen(receipt: receipt, data: data)),
              ),
            ));
          }
          return ListView(padding: Responsive.listPadding(context, maxWidth: 800, bottom: 96), children: children);
        },
      ),
    );
  }
}

/// Full pictures are loaded once per receipt.
final Map<String, Future<Uint8List?>> _imageCache = {};

Future<Uint8List?> _imageFor(UserData data, Receipt receipt) {
  return _imageCache.putIfAbsent(receipt.id, () {
    final future = data.receipts.loadImage(receipt.id);
    future.then((bytes) {
      if (bytes == null) _imageCache.remove(receipt.id);
    }, onError: (Object _) => _imageCache.remove(receipt.id));
    return future;
  });
}

/// The picture of a receipt. In lists it shows the small thumbnail; with
/// [full] it loads the whole picture.
class _Picture extends StatelessWidget {
  const _Picture({required this.receipt, required this.data, this.size = 56, this.fit = BoxFit.cover, this.full = false});

  final Receipt receipt;
  final UserData data;
  final double? size;
  final BoxFit fit;
  final bool full;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget placeholder(IconData icon) => Container(
          width: size,
          height: size,
          color: scheme.surfaceContainerHighest,
          child: Icon(icon, color: scheme.onSurfaceVariant),
        );
    if (!receipt.hasImage || receipt.mimeType == 'application/pdf') {
      return placeholder(receipt.mimeType == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.receipt_long_outlined);
    }
    if (!full && receipt.thumbnail != null) {
      return Image.memory(receipt.thumbnail!, width: size, height: size, fit: fit, gaplessPlayback: true);
    }
    return FutureBuilder<Uint8List?>(
      future: _imageFor(data, receipt),
      builder: (context, snapshot) {
        if (snapshot.hasError || (snapshot.connectionState == ConnectionState.done && snapshot.data == null)) {
          return placeholder(Icons.broken_image_outlined);
        }
        final bytes = snapshot.data;
        if (bytes == null) return placeholder(Icons.hourglass_empty);
        return Image.memory(
          bytes,
          width: size,
          height: size,
          fit: fit,
          errorBuilder: (_, __, ___) => placeholder(Icons.broken_image_outlined),
        );
      },
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);

  final ReceiptStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, background, foreground) = switch (status) {
      ReceiptStatus.processing => ('Reading…', scheme.secondaryContainer, scheme.onSecondaryContainer),
      ReceiptStatus.saved => ('Saved', StatusColors.green(context).withValues(alpha: 0.15), StatusColors.green(context)),
      ReceiptStatus.needsReview => ('Needs check', scheme.tertiaryContainer, scheme.onTertiaryContainer),
      ReceiptStatus.failed => ('Not read', scheme.errorContainer, scheme.onErrorContainer),
      ReceiptStatus.discarded => ('Discarded', scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(20)),
      child: Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: foreground)),
    );
  }
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.receipt, required this.data, required this.onTap});

  final Receipt receipt;
  final UserData data;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = receipt.timestamp;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(top: 8),
      color: theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipRRect(borderRadius: BorderRadius.circular(10), child: _Picture(receipt: receipt, data: data)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      receipt.merchant ?? 'Receipt',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      time == null ? 'Just now' : dateTimeLabel(time),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    if (receipt.categoryName != null)
                      Text(receipt.categoryName!, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (receipt.amount != null)
                    Text(
                      Money.format(receipt.amount!, symbol: 'Rs.', showDecimals: receipt.amount! % 100 != 0),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  const SizedBox(height: 4),
                  _StatusChip(receipt.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One receipt: the full picture, what was read, and what you can do with it.
class ReceiptDetailScreen extends StatelessWidget {
  const ReceiptDetailScreen({super.key, required this.receipt, required this.data});

  final Receipt receipt;
  final UserData data;

  Future<void> _addAsExpense(BuildContext context) async {
    final categories = await data.categories.watchCategories().first;
    final profile = await data.profile.watchProfile().first;
    if (!context.mounted) return;
    ExpenseCategory? pick() {
      for (final c in categories) {
        if (c.id == receipt.categoryId) return c;
      }
      for (final c in categories) {
        if (c.id == 'other') return c;
      }
      return categories.isEmpty ? null : categories.first;
    }

    final category = pick();
    if (category == null) return;
    final draft = Expense(
      amount: receipt.amount ?? 0,
      categoryId: category.id,
      categoryName: category.name,
      categoryKind: category.kind,
      note: receipt.merchant ?? '',
      date: receipt.capturedAt ?? DateTime.now(),
      source: ExpenseSource.receipt,
      merchant: receipt.merchant,
      receiptId: receipt.id,
    );
    final saved = await showExpenseSheet(
      context,
      data: data,
      categories: categories,
      symbol: profile?.currencySymbol ?? 'Rs.',
      existing: draft,
      onAdded: (id) => data.receipts.markSaved(receipt.id, id, draft.copyWith(amount: receipt.amount ?? 0)).then((_) {}, onError: (Object _) {}),
    );
    if (saved == true && context.mounted) Navigator.of(context).pop();
  }

  /// Opens the expense saved from this receipt so its total, category, shop,
  /// date and items can be corrected.
  Future<void> _editExpense(BuildContext context) async {
    final id = receipt.expenseId;
    if (id == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final expense = await data.expenses.getExpense(id);
    if (!context.mounted) return;
    if (expense == null) {
      messenger.showSnackBar(const SnackBar(content: Text('That expense was deleted, so there is nothing to edit.')));
      return;
    }
    final categories = await data.categories.watchCategories().first;
    final profile = await data.profile.watchProfile().first;
    if (!context.mounted) return;
    final saved = await showExpenseSheet(
      context,
      data: data,
      categories: categories,
      symbol: profile?.currencySymbol ?? 'Rs.',
      existing: expense,
      onSaved: (updated) => data.receipts
          .syncFromExpense(receipt.id, updated)
          .then((_) {}, onError: (Object _) {}),
    );
    if (saved == true && context.mounted) Navigator.of(context).pop();
  }

  Future<void> _delete(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this receipt?'),
        content: const Text('The picture is removed. An expense already saved from it stays.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await data.receipts.delete(receipt).timeout(const Duration(seconds: 15));
      navigator.pop();
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not delete it. Check your connection.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final time = receipt.timestamp;
    final canAdd = receipt.status == ReceiptStatus.needsReview || receipt.status == ReceiptStatus.failed;

    Widget row(String label, String? value) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 110, child: Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
                Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
              ],
            ),
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(receipt.merchant ?? 'Receipt'),
        actions: [
          IconButton(tooltip: 'Delete', icon: const Icon(Icons.delete_outline), onPressed: () => unawaited(_delete(context))),
        ],
      ),
      body: ListView(
        padding: Responsive.listPadding(context, maxWidth: 640, top: 16, bottom: 24),
        children: [
          if (receipt.hasImage && receipt.mimeType != 'application/pdf')
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                constraints: const BoxConstraints(maxHeight: 420),
                color: scheme.surfaceContainerHighest,
                child: InteractiveViewer(
                  child: _Picture(receipt: receipt, data: data, size: null, fit: BoxFit.contain, full: true),
                ),
              ),
            )
          else
            Container(
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(16)),
              child: Text(receipt.mimeType == 'application/pdf' ? 'PDF document (not kept)' : 'The picture was not stored', style: theme.textTheme.bodyMedium),
            ),
          const SizedBox(height: 16),
          Row(children: [_StatusChip(receipt.status)]),
          const SizedBox(height: 8),
          row('Added', time == null ? null : dateTimeLabel(time)),
          row('Taken', receipt.capturedAt == null ? null : dateTimeLabel(receipt.capturedAt!)),
          row('Shop', receipt.merchant),
          row('Total', receipt.amount == null ? null : Money.format(receipt.amount!, symbol: 'Rs.', showDecimals: receipt.amount! % 100 != 0)),
          row('Category', receipt.categoryName),
          row('Note', receipt.message),
          if (receipt.expenseId != null) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => unawaited(_editExpense(context)),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Edit expense details'),
            ),
          ],
          if (canAdd) ...[
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => unawaited(_addAsExpense(context)),
              icon: const Icon(Icons.add),
              label: const Text('Add as expense'),
            ),
          ],
        ],
      ),
    );
  }
}
