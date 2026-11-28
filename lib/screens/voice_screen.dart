import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../data/user_data.dart';
import '../services/auth_service.dart';
import '../theme.dart';
import '../utils/formatters.dart';
import '../utils/platform_support.dart';
import '../utils/receipt_image.dart';
import '../voice/receipt_client.dart';
import '../voice/speech_recognizer.dart';
import '../config/voice_config.dart';
import '../voice/audio_capture.dart';
import '../voice/voice_controller.dart';
import '../voice/voice_workflow_client.dart';
import '../widgets/auth_widgets.dart';
import 'settings_screen.dart';
import '../models/budget_period.dart';
import '../models/category.dart';
import '../models/monthly_budget.dart';
import '../models/date_keys.dart';
import '../models/debt.dart';
import '../models/income.dart';
import '../models/money.dart';
import '../models/recurring.dart';
import '../widgets/bill_sheets.dart';
import '../widgets/debt_sheets.dart';
import '../widgets/expense_sheet.dart';
import '../widgets/income_sheet.dart';
import '../widgets/opening_balance_sheet.dart';
import '../widgets/voice/voice_entry_card.dart';
import '../voice/voice_models.dart';
import '../widgets/voice/mic_button.dart';
import '../widgets/voice/voice_result_card.dart';

/// The first screen after signing in: tap the microphone, say an expense, income, bill or debt,
/// and the words go through the workflow to become an expense.
class VoiceScreen extends StatefulWidget {
  const VoiceScreen({
    super.key,
    required this.auth,
    required this.user,
    required this.data,
    required this.isActive,
    this.onOpenDashboard,
  });

  final AuthService auth;
  final AuthUser user;
  final UserData data;

  /// False while another tab is showing; the microphone is turned off then.
  final bool isActive;
  /// Null on wide screens, where the side navigation already has a Dashboard entry.
  final VoidCallback? onOpenDashboard;

  @override
  State<VoiceScreen> createState() => VoiceScreenState();
}

/// The state is public so the Receipts tab can start a scan.
class VoiceScreenState extends State<VoiceScreen> {
  static const List<String> _examples = [
    'Spent 500 on lunch',
    'Received 50,000 salary',
    'Rent 25,000 due on the 1st',
    'Lent Ali 3,000',
    'Ali paid back 1,000',
    'Paid the electricity bill',
    'Food budget 20,000',
    'My monthly budget is 60,000',
  ];

  late final VoiceController _controller;
  final TextEditingController _typed = TextEditingController();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  String? _profileName;

  bool _showMicDetails = false;

  @override
  void initState() {
    super.initState();
    _controller = VoiceController(
      userId: widget.user.uid,
      recognizer: PluginSpeechRecognizer(),
      workflow: createVoiceWorkflowClient(widget.auth),
      receipts: createReceiptClient(widget.auth),
      vault: widget.data.receipts,
      // With n8n connected, the voice is recorded and Gemini listens to it, so it works
      // on every phone, in the browser and on desktop. Otherwise the phone's own recognizer is used.
      capture: VoiceConfig.hasBackend ? PcmAudioCapture() : null,
      saveExpense: (expense) => widget.data.expenses.addExpense(expense),
    );
    _subscriptions.add(widget.data.categories
        .watchCategories()
        .listen(_controller.setCategories, onError: (Object _) {}));
    _subscriptions.add(widget.data.profile.watchProfile().listen((profile) {
      _profileName = profile?.name;
      _controller.setProfile(profile);
      if (mounted) setState(() {});
    }, onError: (Object _) {}));
    unawaited(_controller.init());
  }

  @override
  void didUpdateWidget(VoiceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isActive && !widget.isActive) {
      unawaited(_controller.cancelListening());
    }
  }

  @override
  void dispose() {
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    unawaited(_controller.cancelListening());
    _controller.dispose();
    _typed.dispose();
    super.dispose();
  }

  void _submitTyped() {
    final text = _typed.text;
    if (text.trim().isEmpty) return;
    _typed.clear();
    FocusScope.of(context).unfocus();
    unawaited(_controller.submitText(text));
  }

  final ImagePicker _picker = ImagePicker();

  /// Lets the user take a photo of a receipt or pick one from the gallery.
  Future<void> scanReceipt() async {
    // Phones can take a photo; desktop and web can only upload a file.
    ImageSource? source = ImageSource.gallery;
    if (canUseCamera) {
      source = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Upload from gallery'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
    }
    if (source == null || !mounted) return;

    try {
      final file = await _picker.pickImage(source: source, maxWidth: 3200, maxHeight: 3200, imageQuality: 92);
      if (file == null) return; // cancelled
      final raw = await file.readAsBytes();
      final prepared = await prepareReceiptImage(
        raw,
        _mimeTypeOf(file),
        longestSide: readingLongestSide,
        maxBytes: readingMaxBytes,
        quality: 85,
      );
      if (!mounted) return;
      unawaited(_controller.submitReceipt(prepared.bytes, prepared.mimeType));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(
          content: Text(canUseCamera
              ? 'Could not open the camera or gallery. Check the app permissions in your phone settings.'
              : 'Could not open that file. Choose a JPG or PNG picture.'),
        ));
    }
  }

  String _mimeTypeOf(XFile file) {
    final declared = file.mimeType;
    if (declared != null && declared.startsWith('image/')) return declared;
    final name = file.path.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    if (name.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  Future<void> _editDraft() async {
    final draft = _controller.draft;
    if (draft == null) return;
    final saved = await showExpenseSheet(
      context,
      data: widget.data,
      categories: _controller.categories,
      symbol: _controller.symbol,
      existing: draft,
      onAdded: (id) => _controller.linkSaved(draft, id),
    );
    if (saved == true) _controller.markSaved();
  }

  /// A day that was said (no time) becomes midday; today keeps the real time.
  DateTime _when(DateTime? day) {
    final now = DateTime.now();
    if (day == null) return now;
    if (DateKeys.ofDay(day) == DateKeys.ofDay(now)) return now;
    return DateTime(day.year, day.month, day.day, 12);
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// "My monthly budget is 60,000": changes the budget of the current week,
  /// month or year, or starts one (copying the category limits of the latest).
  Future<bool> _applyBudget(VoiceEntry entry, int amount) async {
    var type = PeriodType.monthly;
    for (final t in PeriodType.values) {
      if (t.name == entry.frequency && t != PeriodType.custom) type = t;
    }
    final symbol = _controller.symbol;
    final repo = widget.data.budgets;
    final budgets = await repo.getBudgets();
    if (!mounted) return false;
    final today = DateTime.now();
    final start = BudgetPeriod.defaultStart(type, today);
    final period = BudgetPeriod.starting(type, start);
    final label = type.label.toLowerCase();

    MonthlyBudget? existing;
    for (final b in budgets) {
      if (b.periodType == type && b.startDay == period.startDay) existing = b;
    }
    if (existing != null) {
      final ok = await _confirm(
        'Change your $label budget?',
        'From ${formatMoney(existing.income, symbol)} to ${formatMoney(amount, symbol)}.',
      );
      if (!ok) return false;
      await repo.saveBudget(existing.copyWith(income: amount));
      return true;
    }
    final ok = await _confirm(
      'Start a $label budget?',
      '${formatMoney(amount, symbol)} for ${period.startDay} to ${period.endDay}. '
          '${budgets.isEmpty ? 'You can set category limits afterwards, in the Dashboard.' : 'Category limits are copied from your latest budget.'}',
    );
    if (!ok) return false;
    final latest = budgets.isEmpty ? null : budgets.first;
    await repo.saveBudget(MonthlyBudget(
      id: repo.newIdFor(period),
      monthKey: DateKeys.ofMonth(period.start),
      income: amount,
      categories: latest?.categories ?? const [],
      periodType: type,
      startDay: period.startDay,
      endDay: period.endDay,
    ));
    return true;
  }

  /// "Food budget 20,000": sets one category's limit in the budget that covers today.
  Future<bool> _applyCategoryLimit(VoiceEntry entry, int limit) async {
    final symbol = _controller.symbol;
    final budgets = await widget.data.budgets.getBudgets();
    if (!mounted) return false;
    final today = DateTime.now();
    MonthlyBudget? budget;
    for (final b in budgets) {
      if (b.period.contains(today)) {
        budget = b;
        break;
      }
    }
    if (budget == null) {
      _say('There is no budget for today yet. Say "my monthly budget is 60,000" first.');
      return false;
    }
    ExpenseCategory? category;
    for (final item in _controller.categories) {
      if (item.id == entry.categoryId) category = item;
    }
    final line = budget.forCategory(entry.categoryId ?? '');
    final name = line?.name ?? category?.name;
    if (name == null) {
      _say('I could not tell which category that is. Try "food budget 20,000".');
      return false;
    }
    final ok = await _confirm(
      line == null ? 'Add a limit for $name?' : 'Change the $name limit?',
      line == null
          ? '${formatMoney(limit, symbol)} for $name in your ${budget.periodType.label.toLowerCase()} budget.'
          : 'From ${formatMoney(line.limit, symbol)} to ${formatMoney(limit, symbol)}.',
    );
    if (!ok) return false;
    final lines = [
      for (final c in budget.categories)
        if (c.categoryId == entry.categoryId)
          CategoryBudget.fromCategory(
            category ?? ExpenseCategory(id: c.categoryId, name: c.name, iconKey: c.iconKey, colorValue: c.colorValue, kind: c.kind),
            limit,
          )
        else
          c,
      if (line == null && category != null) CategoryBudget.fromCategory(category, limit),
    ];
    await widget.data.budgets.saveBudget(budget.copyWith(categories: lines));
    return true;
  }

  /// Opens the matching form, filled in with what was said.
  Future<void> _reviewEntry() async {
    final entry = _controller.result?.entry;
    if (entry == null) return;
    final c = _controller;
    final symbol = c.symbol;
    final minor = Money.fromMajor(entry.amount);
    final data = widget.data;
    bool? saved;
    var message = 'Saved.';

    switch (entry.type) {
      case VoiceEntryType.income:
        saved = await showIncomeSheet(
          context,
          data: data,
          symbol: symbol,
          existing: Income(amount: minor, source: entry.source ?? '', note: entry.note ?? '', date: _when(entry.date)),
        );
        message = 'Income saved.';
      case VoiceEntryType.bill:
        final billDue = DateKeys.startOfDay(entry.dueDate ?? DateTime.now());
        final dueDay = DateKeys.ofDay(billDue);
        var frequency = Frequency.once;
        for (final f in Frequency.values) {
          if (f.name == entry.frequency) frequency = f;
        }
        ExpenseCategory? category;
        for (final item in c.categories) {
          if (item.id == entry.categoryId) category = item;
        }
        saved = await showRecurringSheet(
          context,
          data: data,
          categories: c.categories,
          symbol: symbol,
          existing: RecurringItem(
            title: entry.title ?? '',
            amount: minor,
            categoryId: category?.id,
            categoryName: category?.name,
            categoryKind: category?.kind,
            frequency: frequency,
            startDay: dueDay,
            nextDueDay: dueDay,
            note: entry.note ?? '',
          ),
        );
        message = 'Bill saved.';
      case VoiceEntryType.billPaid:
        final bills = await data.recurring.getAll();
        if (!mounted) return;
        final said = (entry.title ?? '').toLowerCase().trim();
        RecurringItem? bill;
        for (final item in bills) {
          if (!item.active || said.isEmpty) continue;
          final name = item.title.toLowerCase();
          if (name.contains(said) || said.contains(name)) {
            bill = item;
            break;
          }
        }
        if (bill == null) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text(said.isEmpty
                  ? 'Say which bill, for example "paid the electricity bill".'
                  : 'No open bill called "${entry.title}". Add it first in the Bills tab.'),
            ));
          return;
        }
        saved = await showMarkPaidSheet(context, data: data, item: bill, symbol: symbol);
        message = 'Bill marked as paid.';
      case VoiceEntryType.budget:
        saved = await _applyBudget(entry, minor);
        message = 'Budget saved.';
      case VoiceEntryType.categoryBudget:
        saved = await _applyCategoryLimit(entry, minor);
        message = 'Category limit saved.';
      case VoiceEntryType.debt:
      case VoiceEntryType.loan:
        final lent = entry.type == VoiceEntryType.loan;
        final debtDue = entry.dueDate;
        saved = await showDebtSheet(
          context,
          data: data,
          symbol: symbol,
          existing: Debt(
            direction: lent ? DebtDirection.owedToMe : DebtDirection.owedByMe,
            person: entry.person ?? '',
            amount: minor,
            date: _when(entry.date),
            dueDay: debtDue == null ? null : DateKeys.ofDay(debtDue),
            note: entry.note ?? '',
          ),
        );
        message = lent ? 'Loan saved.' : 'Debt saved.';
      case VoiceEntryType.repayment:
        final debts = await data.debts.watchAll().first;
        if (!mounted) return;
        final name = (entry.person ?? '').toLowerCase();
        Debt? match;
        for (final debt in debts) {
          if (debt.isSettled || name.isEmpty) continue;
          final other = debt.person.toLowerCase();
          if (other.contains(name) || name.contains(other)) {
            match = debt;
            break;
          }
        }
        if (match == null) {
          ScaffoldMessenger.of(context)
            ..clearSnackBars()
            ..showSnackBar(SnackBar(
              content: Text(name.isEmpty
                  ? 'Say who it was, for example "Ali paid back 500".'
                  : 'No open debt or loan with "${entry.person}". Add it first in the Debts tab.'),
            ));
          return;
        }
        saved = await showRepaymentSheet(context, data: data, debt: match, symbol: symbol, amount: minor);
        message = 'Repayment saved.';
      case VoiceEntryType.openingBalance:
        saved = await showOpeningBalanceSheet(
          context,
          data: data,
          symbol: symbol,
          currentAmount: minor,
          currentDay: DateKeys.startOfDay(entry.date ?? DateTime.now()),
        );
        message = 'Opening balance saved.';
    }
    if (saved == true) _controller.markEntrySaved(message);
  }

  String get _name {
    final name = _profileName?.trim();
    if (name != null && name.isNotEmpty) return name.split(RegExp(r'\s+')).first;
    return widget.user.firstName;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppConfig.appName),
        actions: [
          if (widget.onOpenDashboard != null)
            TextButton.icon(
              onPressed: widget.onOpenDashboard,
              icon: const Icon(Icons.dashboard_outlined),
              label: const Text('Dashboard'),
            ),
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) {
              if (value == 'settings') openSettings(context, widget.auth, widget.user, data: widget.data);
              if (value == 'signout') unawaited(widget.auth.signOut());
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'signout', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => _body(context),
      ),
    );
  }

  Widget _body(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final c = _controller;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;
    final canType = c.state == VoiceState.ready || c.state == VoiceState.result;

    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + keyboard),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Hi, $_name',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  _prompt(c.state),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 24),
                Center(
                  child: MicButton(
                    state: c.state,
                    soundLevel: c.soundLevel,
                    onPressed: () => unawaited(c.toggleListening()),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _statusLabel(c),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                if (canType) ...[
                  const SizedBox(height: 8),
                  Center(
                    child: TextButton.icon(
                      onPressed: scanReceipt,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: Text(canUseCamera ? 'Scan a receipt' : 'Upload a receipt'),
                    ),
                  ),
                ],
                Center(
                  child: TextButton(
                    onPressed: () {
                      setState(() => _showMicDetails = !_showMicDetails);
                      if (_showMicDetails) unawaited(c.refreshMicDetails());
                    },
                    child: Text(_showMicDetails ? 'Hide mic details' : 'Mic not working? Mic details'),
                  ),
                ),
                if (_showMicDetails)
                  Card(
                    elevation: 0,
                    color: scheme.surfaceContainerHighest,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        c.micLog.isEmpty ? 'Nothing recorded yet. Tap the mic and speak.' : c.micLog.join('\n'),
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ),
                if (c.languages.length > 1) ...[
                  const SizedBox(height: 16),
                  Center(child: _languagePicker(c)),
                ],
                if (c.state == VoiceState.listening || c.state == VoiceState.sending) ...[
                  const SizedBox(height: 20),
                  _TranscriptBox(
                    text: c.transcript,
                    placeholder: c.state == VoiceState.listening ? 'Say an expense, income, bill or debt…' : '',
                  ),
                  if (c.state == VoiceState.sending)
                    TextButton(onPressed: c.cancelSending, child: const Text('Cancel')),
                ],
                if (c.notice != null) ...[
                  const SizedBox(height: 16),
                  MessageBanner(message: c.notice!, isError: false),
                ],
                if (c.errorMessage != null) ...[
                  const SizedBox(height: 16),
                  MessageBanner(message: c.errorMessage!),
                ] else if (!c.speechAvailable &&
                    c.state == VoiceState.ready &&
                    c.speechProblem != null) ...[
                  const SizedBox(height: 16),
                  MessageBanner(message: c.speechProblem!),
                ],
                if (c.state == VoiceState.result) ...[
                  const SizedBox(height: 20),
                  if (c.result?.entry != null)
                    VoiceEntryCard(controller: c, entry: c.result!.entry!, onReview: _reviewEntry)
                  else
                    VoiceResultCard(controller: c, onEdit: _editDraft),
                ],
                if (c.state == VoiceState.ready) ...[
                  const SizedBox(height: 24),
                  Text(
                    'Or tap an example',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final example in _examples)
                        ActionChip(
                          label: Text(example),
                          onPressed: () => unawaited(c.submitText(example)),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 24),
                TextField(
                  controller: _typed,
                  enabled: canType,
                  textInputAction: TextInputAction.send,
                  textCapitalization: TextCapitalization.sentences,
                  onSubmitted: (_) => _submitTyped(),
                  decoration: InputDecoration(
                    hintText: 'Or type it, e.g. 250 on groceries',
                    suffixIcon: IconButton(
                      tooltip: 'Send',
                      icon: const Icon(Icons.send),
                      onPressed: canType ? _submitTyped : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _languagePicker(VoiceController c) {
    final selected = c.languages.any((l) => l.localeId == c.selectedLocaleId)
        ? c.selectedLocaleId!
        : c.languages.first.localeId;
    return SegmentedButton<String>(
      showSelectedIcon: false,
      segments: [
        for (final language in c.languages)
          ButtonSegment<String>(value: language.localeId, label: Text(language.label)),
      ],
      selected: {selected},
      onSelectionChanged: (values) => c.selectLanguage(values.first),
    );
  }

  String _prompt(VoiceState state) {
    switch (state) {
      case VoiceState.initializing:
        return 'Getting the microphone ready…';
      case VoiceState.ready:
        return 'Tap the mic and say an expense, income, bill or loan, or scan a receipt.';
      case VoiceState.listening:
        return 'Listening. Try "500 on lunch".';
      case VoiceState.sending:
        return 'Working out your expense…';
      case VoiceState.result:
        return 'Check the details, then save.';
    }
  }

  String _statusLabel(VoiceController c) {
    switch (c.state) {
      case VoiceState.initializing:
        return 'Please wait';
      case VoiceState.ready:
        return c.speechAvailable ? 'Tap to speak' : 'Voice not available';
      case VoiceState.listening:
        return 'Listening… tap to stop';
      case VoiceState.sending:
        return 'Understanding…';
      case VoiceState.result:
        return 'Tap to speak again';
    }
  }
}

class _TranscriptBox extends StatelessWidget {
  const _TranscriptBox({required this.text, required this.placeholder});

  final String text;
  final String placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final showing = text.isNotEmpty;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        showing ? '“$text”' : placeholder,
        textAlign: TextAlign.center,
        style: theme.textTheme.titleMedium?.copyWith(
          color: showing ? scheme.onSurface : scheme.onSurfaceVariant,
          fontStyle: showing ? FontStyle.normal : FontStyle.italic,
        ),
      ),
    );
  }
}
