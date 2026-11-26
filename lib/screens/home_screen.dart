import 'package:flutter/material.dart';

import '../data/user_data.dart';
import '../models/category.dart';
import '../models/date_keys.dart';
import '../models/daily_insight.dart';
import '../models/expense.dart';
import '../models/money.dart';
import '../models/month_stats.dart';
import '../models/monthly_budget.dart';
import '../services/auth_service.dart';
import '../widgets/data_scope.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.auth, required this.user});

  final AuthService auth;
  final AuthUser user;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;
  late final String _monthKey = DateKeys.ofMonth(DateTime.now());

  MonthlyBudget? _demoBudget;
  MonthStats? _demoStats;
  final List<Expense> _demoExpenses = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _demoBudget = MonthlyBudget(
      monthKey: _monthKey,
      income: Money.fromMajor(100000),
      categories: [
        CategoryBudget(
            categoryId: 'rent',
            name: 'Rent',
            iconKey: 'home',
            colorValue: 0xFF4E342E,
            kind: CategoryKind.fixed,
            limit: Money.fromMajor(30000)),
        CategoryBudget(
            categoryId: 'bills',
            name: 'Bills & utilities',
            iconKey: 'receipt_long',
            colorValue: 0xFF455A64,
            kind: CategoryKind.fixed,
            limit: Money.fromMajor(12000)),
        CategoryBudget(
            categoryId: 'savings',
            name: 'Savings',
            iconKey: 'savings',
            colorValue: 0xFF00695C,
            kind: CategoryKind.savings,
            limit: Money.fromMajor(15000)),
        CategoryBudget(
            categoryId: 'food',
            name: 'Food & dining',
            iconKey: 'restaurant',
            colorValue: 0xFFEF6C00,
            kind: CategoryKind.flexible,
            limit: Money.fromMajor(18000)),
        CategoryBudget(
            categoryId: 'groceries',
            name: 'Groceries',
            iconKey: 'shopping_basket',
            colorValue: 0xFF2E7D32,
            kind: CategoryKind.flexible,
            limit: Money.fromMajor(12000)),
        CategoryBudget(
            categoryId: 'transport',
            name: 'Transport',
            iconKey: 'directions_bus',
            colorValue: 0xFF1565C0,
            kind: CategoryKind.flexible,
            limit: Money.fromMajor(8000)),
        CategoryBudget(
            categoryId: 'shopping',
            name: 'Shopping',
            iconKey: 'shopping_bag',
            colorValue: 0xFFAD1457,
            kind: CategoryKind.flexible,
            limit: Money.fromMajor(5000)),
      ],
    );
    _demoStats = MonthStats(
      monthKey: _monthKey,
      totalSpent: Money.fromMajor(43750),
      flexibleSpent: Money.fromMajor(22750),
      expenseCount: 12,
      spentByCategory: const {
        'rent': 3000000,
        'bills': 1200000,
        'food': 1250000,
        'groceries': 720000,
        'transport': 305000,
      },
    );
    _demoExpenses.addAll([
      Expense(
          id: '1',
          amount: Money.fromMajor(1850),
          categoryId: 'groceries',
          categoryName: 'Groceries',
          categoryKind: CategoryKind.flexible,
          note: 'Weekly groceries',
          date: now.subtract(const Duration(days: 1))),
      Expense(
          id: '2',
          amount: Money.fromMajor(840),
          categoryId: 'food',
          categoryName: 'Food & dining',
          categoryKind: CategoryKind.flexible,
          note: 'Lunch',
          date: now.subtract(const Duration(days: 1))),
      Expense(
          id: '3',
          amount: Money.fromMajor(450),
          categoryId: 'transport',
          categoryName: 'Transport',
          categoryKind: CategoryKind.flexible,
          note: 'Ride',
          date: now.subtract(const Duration(days: 2))),
      Expense(
          id: '4',
          amount: Money.fromMajor(12000),
          categoryId: 'bills',
          categoryName: 'Bills & utilities',
          categoryKind: CategoryKind.fixed,
          note: 'Monthly utilities',
          date: now.subtract(const Duration(days: 4))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final data = DataScope.maybeOf(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 900;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop) _buildNavigationRail(context),
          Expanded(
            child: SafeArea(
              child: Column(
                children: [
                  _buildTopBar(context),
                  Expanded(
                    child: data == null
                        ? _buildDemoContent(context)
                        : _buildLiveContent(context, data),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isDesktop ? null : _buildBottomNavigation(context),
      floatingActionButton: _selectedIndex != 3
          ? FloatingActionButton.extended(
              onPressed: () => _openAddExpense(context, data),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add expense'),
            )
          : null,
    );
  }

  Widget _buildNavigationRail(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 112,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(right: BorderSide(color: scheme.outlineVariant)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.account_balance_wallet_rounded,
                color: scheme.onPrimary),
          ),
          const SizedBox(height: 32),
          Expanded(
            child: NavigationRail(
              selectedIndex: _selectedIndex,
              onDestinationSelected: (index) =>
                  setState(() => _selectedIndex = index),
              labelType: NavigationRailLabelType.all,
              backgroundColor: Colors.transparent,
              destinations: const [
                NavigationRailDestination(
                    icon: Icon(Icons.dashboard_outlined),
                    selectedIcon: Icon(Icons.dashboard_rounded),
                    label: Text('Overview')),
                NavigationRailDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long_rounded),
                    label: Text('Expenses')),
                NavigationRailDestination(
                    icon: Icon(Icons.pie_chart_outline_rounded),
                    selectedIcon: Icon(Icons.pie_chart_rounded),
                    label: Text('Budget')),
                NavigationRailDestination(
                    icon: Icon(Icons.lightbulb_outline_rounded),
                    selectedIcon: Icon(Icons.lightbulb_rounded),
                    label: Text('Insights')),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: widget.auth.signOut,
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation(BuildContext context) {
    return NavigationBar(
      selectedIndex: _selectedIndex,
      onDestinationSelected: (index) => setState(() => _selectedIndex = index),
      destinations: const [
        NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Overview'),
        NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'Expenses'),
        NavigationDestination(
            icon: Icon(Icons.pie_chart_outline_rounded),
            selectedIcon: Icon(Icons.pie_chart_rounded),
            label: 'Budget'),
        NavigationDestination(
            icon: Icon(Icons.lightbulb_outline_rounded),
            selectedIcon: Icon(Icons.lightbulb_rounded),
            label: 'Insights'),
      ],
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final names = ['Overview', 'Expenses', 'Budget', 'Insights'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('SafeSpend',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text(names[_selectedIndex],
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
              ],
            ),
          ),
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: scheme.primaryContainer, shape: BoxShape.circle),
            child: Text(
              widget.user.firstName.isNotEmpty
                  ? widget.user.firstName[0].toUpperCase()
                  : 'U',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimaryContainer),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDemoContent(BuildContext context) {
    switch (_selectedIndex) {
      case 1:
        return _ExpensesPage(
            expenses: _demoExpenses, categories: defaultCategories);
      case 2:
        return _BudgetPage(
          budget: _demoBudget,
          stats: _demoStats ?? MonthStats.empty(_monthKey),
          onEdit: () => _openBudgetSetup(context, null, null),
        );
      case 3:
        return const _InsightsPage(insight: null, demo: true);
      default:
        return _DashboardPage(
          budget: _demoBudget,
          stats: _demoStats ?? MonthStats.empty(_monthKey),
          expenses: _demoExpenses,
          categories: defaultCategories,
          insight: null,
          onSetup: () => _openBudgetSetup(context, null, null),
          onViewExpenses: () => setState(() => _selectedIndex = 1),
          demo: true,
        );
    }
  }

  Widget _buildLiveContent(BuildContext context, UserData data) {
    return StreamBuilder<MonthlyBudget?>(
      stream: data.budgets.watchBudget(_monthKey),
      builder: (context, budgetSnapshot) {
        final budget = budgetSnapshot.data;
        return StreamBuilder<MonthStats>(
          stream: data.expenses.watchStats(_monthKey),
          builder: (context, statsSnapshot) {
            final stats = statsSnapshot.data ?? MonthStats.empty(_monthKey);
            return StreamBuilder<List<ExpenseCategory>>(
              stream: data.categories.watchCategories(),
              builder: (context, categorySnapshot) {
                final categories = categorySnapshot.data ?? defaultCategories;
                return StreamBuilder<List<Expense>>(
                  stream: data.expenses.watchRecent(limit: 20),
                  builder: (context, expenseSnapshot) {
                    final expenses = expenseSnapshot.data ?? const <Expense>[];
                    if (budget == null) {
                      return _EmptyBudgetPage(
                          onSetup: () =>
                              _openBudgetSetup(context, data, categories));
                    }
                    switch (_selectedIndex) {
                      case 1:
                        return _ExpensesPage(
                            expenses: expenses, categories: categories);
                      case 2:
                        return _BudgetPage(
                          budget: budget,
                          stats: stats,
                          onEdit: () =>
                              _openBudgetSetup(context, data, categories),
                        );
                      case 3:
                        return StreamBuilder<DailyInsight?>(
                          stream: data.insights.watchLatest(),
                          builder: (context, insightSnapshot) =>
                              _InsightsPage(insight: insightSnapshot.data),
                        );
                      default:
                        return StreamBuilder<DailyInsight?>(
                          stream: data.insights.watchLatest(),
                          builder: (context, insightSnapshot) => _DashboardPage(
                            budget: budget,
                            stats: stats,
                            expenses: expenses,
                            categories: categories,
                            insight: insightSnapshot.data,
                            onSetup: () =>
                                _openBudgetSetup(context, data, categories),
                            onViewExpenses: () =>
                                setState(() => _selectedIndex = 1),
                          ),
                        );
                    }
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  Future<void> _openBudgetSetup(BuildContext context, UserData? data,
      List<ExpenseCategory>? categories) async {
    final result = await showModalBottomSheet<MonthlyBudget>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => BudgetSetupSheet(
        monthKey: _monthKey,
        categories: categories ?? defaultCategories,
        initial: data == null ? _demoBudget : null,
        liveData: data,
      ),
    );
    if (result == null) return;
    if (data == null) {
      setState(() => _demoBudget = result);
    } else {
      await data.budgets.saveBudget(result);
    }
  }

  Future<void> _openAddExpense(BuildContext context, UserData? data) async {
    final categories = data == null
        ? defaultCategories
        : await data.categories.getCategories();
    if (!context.mounted) return;
    final expense = await showModalBottomSheet<Expense>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => AddExpenseSheet(categories: categories),
    );
    if (expense == null) return;
    if (data == null) {
      setState(() {
        _demoExpenses.insert(0, expense);
        _demoStats = MonthStats(
          monthKey: _monthKey,
          totalSpent: (_demoStats?.totalSpent ?? 0) + expense.amount,
          flexibleSpent: expense.categoryKind == CategoryKind.flexible
              ? (_demoStats?.flexibleSpent ?? 0) + expense.amount
              : (_demoStats?.flexibleSpent ?? 0),
          expenseCount: (_demoStats?.expenseCount ?? 0) + 1,
          spentByCategory:
              Map<String, int>.from(_demoStats?.spentByCategory ?? {}),
        );
      });
    } else {
      await data.expenses.addExpense(expense);
    }
  }
}

class _DashboardPage extends StatelessWidget {
  const _DashboardPage({
    required this.budget,
    required this.stats,
    required this.expenses,
    required this.categories,
    required this.insight,
    required this.onSetup,
    required this.onViewExpenses,
    this.demo = false,
  });

  final MonthlyBudget? budget;
  final MonthStats stats;
  final List<Expense> expenses;
  final List<ExpenseCategory> categories;
  final DailyInsight? insight;
  final VoidCallback onSetup;
  final VoidCallback onViewExpenses;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final now = DateTime.now();
    final monthBudget = budget;
    final remainingDays =
        DateKeys.daysInMonth(DateKeys.ofMonth(now)) - now.day + 1;
    final remainingPool = monthBudget == null
        ? 0
        : monthBudget.flexiblePool - stats.flexibleSpent;
    final safeToday =
        remainingDays <= 0 ? 0 : (remainingPool / remainingDays).round();

    return ListView(
      padding: EdgeInsets.fromLTRB(
          width >= 900 ? 32 : 20, 8, width >= 900 ? 32 : 20, 100),
      children: [
        if (monthBudget == null)
          _SetupBanner(onSetup: onSetup)
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 720;
              final left = Expanded(
                child: _SafeToSpendCard(
                  amount: safeToday,
                  remainingPool: remainingPool,
                  remainingDays: remainingDays,
                ),
              );
              final right = Expanded(
                child: _MonthProgressCard(
                  budget: monthBudget,
                  stats: stats,
                ),
              );
              return wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [left, const SizedBox(width: 16), right])
                  : Column(children: [left, const SizedBox(height: 16), right]);
            },
          ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 720;
            final spending =
                _CategorySpendingCard(budget: monthBudget, stats: stats);
            final insightCard = _InsightCard(insight: insight, demo: demo);
            return wide
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(flex: 3, child: spending),
                    const SizedBox(width: 16),
                    Expanded(flex: 2, child: insightCard)
                  ])
                : Column(children: [
                    spending,
                    const SizedBox(height: 16),
                    insightCard
                  ]);
          },
        ),
        const SizedBox(height: 16),
        _RecentExpensesCard(expenses: expenses, onViewAll: onViewExpenses),
      ],
    );
  }
}

class _SetupBanner extends StatelessWidget {
  const _SetupBanner({required this.onSetup});
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [scheme.primary, scheme.tertiary]),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your monthly plan starts here',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white, fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                const Text(
                    'Set income, savings and category limits to calculate today’s safe spending.',
                    style: TextStyle(color: Colors.white70)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: onSetup,
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white, foregroundColor: scheme.primary),
            child: const Text('Set up'),
          ),
        ],
      ),
    );
  }
}

class _SafeToSpendCard extends StatelessWidget {
  const _SafeToSpendCard(
      {required this.amount,
      required this.remainingPool,
      required this.remainingDays});
  final int amount;
  final int remainingPool;
  final int remainingDays;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F766E),
            scheme.primary,
            const Color(0xFF115E59)
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
              color: scheme.primary.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, 10))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                  child: Text('Safe to spend today',
                      style: TextStyle(
                          color: Colors.white70, fontWeight: FontWeight.w600))),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bolt_rounded, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text('Live',
                      style: TextStyle(color: Colors.white, fontSize: 12))
                ]),
              ),
            ],
          ),
          const Spacer(),
          Text(Money.format(amount),
              style: Theme.of(context)
                  .textTheme
                  .displayMedium
                  ?.copyWith(color: Colors.white, fontWeight: FontWeight.w900)),
          const SizedBox(height: 10),
          Text('${Money.format(remainingPool)} left across $remainingDays days',
              style: const TextStyle(color: Colors.white70)),
        ],
      ),
    );
  }
}

class _MonthProgressCard extends StatelessWidget {
  const _MonthProgressCard({required this.budget, required this.stats});
  final MonthlyBudget budget;
  final MonthStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress = budget.flexiblePool <= 0
        ? 0.0
        : (stats.flexibleSpent / budget.flexiblePool).clamp(0.0, 1.0);
    return Container(
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Monthly overview',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                  child: _Metric(
                      label: 'Spent',
                      value: Money.format(stats.flexibleSpent))),
              Expanded(
                  child: _Metric(
                      label: 'Flexible pool',
                      value: Money.format(budget.flexiblePool))),
            ],
          ),
          const SizedBox(height: 18),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
                value: progress,
                minHeight: 9,
                backgroundColor: scheme.surfaceContainerHighest),
          ),
          const SizedBox(height: 10),
          Text(
              '${(progress * 100).toStringAsFixed(0)}% of flexible budget used',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
        const SizedBox(height: 5),
        Text(value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _CategorySpendingCard extends StatelessWidget {
  const _CategorySpendingCard({required this.budget, required this.stats});
  final MonthlyBudget? budget;
  final MonthStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final categoryBudgets = budget?.categories
            .where((c) => c.kind == CategoryKind.flexible)
            .toList() ??
        [];
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Spending by category',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 16),
          if (categoryBudgets.isEmpty)
            const Text('Set up your budget to see category progress.')
          else
            ...categoryBudgets.take(5).map((category) {
              final spent = stats.spentIn(category.categoryId);
              final ratio = category.limit <= 0
                  ? 0.0
                  : (spent / category.limit).clamp(0.0, 1.0);
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                              color: Color(category.colorValue)
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10)),
                          child: Icon(categoryIcon(category.iconKey),
                              size: 18, color: Color(category.colorValue)),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(category.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700))),
                        Text(
                            '${Money.format(spent)} / ${Money.format(category.limit)}',
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                          value: ratio,
                          minHeight: 7,
                          backgroundColor: scheme.surfaceContainerHighest,
                          color: ratio >= 1
                              ? scheme.error
                              : Color(category.colorValue)),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({required this.insight, required this.demo});
  final DailyInsight? insight;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = insight?.message ??
        (demo
            ? 'Your transport spending is 18% lower than last month. Keep it up!'
            : 'Your first insight will appear here as spending patterns develop.');
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: scheme.tertiary,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(Icons.auto_awesome_rounded,
                color: scheme.onTertiary, size: 20),
          ),
          const SizedBox(height: 14),
          Text('Today’s insight',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(message,
              style:
                  TextStyle(color: scheme.onTertiaryContainer, height: 1.45)),
        ],
      ),
    );
  }
}

class _RecentExpensesCard extends StatelessWidget {
  const _RecentExpensesCard({required this.expenses, required this.onViewAll});
  final List<Expense> expenses;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text('Recent expenses',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800))),
              TextButton(onPressed: onViewAll, child: const Text('View all')),
            ],
          ),
          if (expenses.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 18),
                child: Text('No expenses this month yet.'))
          else
            ...expenses
                .take(5)
                .map((expense) => _ExpenseTile(expense: expense)),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense});
  final Expense expense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12)),
            child: Icon(categoryIcon(expenseCategoryIcon(expense.categoryId)),
                size: 20, color: scheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(expense.categoryName,
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                if (expense.note.isNotEmpty)
                  Text(expense.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: scheme.onSurfaceVariant, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('- ${Money.format(expense.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              Text(_shortDate(expense.date),
                  style:
                      TextStyle(color: scheme.onSurfaceVariant, fontSize: 11)),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyBudgetPage extends StatelessWidget {
  const _EmptyBudgetPage({required this.onSetup});
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.account_balance_wallet_outlined,
                  size: 68, color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 18),
              Text('Set your monthly budget',
                  textAlign: TextAlign.center,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              const Text(
                  'Add your income and spending limits to unlock the dashboard.',
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                  onPressed: onSetup,
                  icon: const Icon(Icons.edit_calendar_rounded),
                  label: const Text('Create budget')),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpensesPage extends StatelessWidget {
  const _ExpensesPage({required this.expenses, required this.categories});
  final List<Expense> expenses;
  final List<ExpenseCategory> categories;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = expenses.fold<int>(0, (sum, expense) => sum + expense.amount);
    return ListView(
      padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 900 ? 32 : 20,
          8,
          MediaQuery.sizeOf(context).width >= 900 ? 32 : 20,
          100),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(20)),
          child: Row(
            children: [
              Expanded(
                  child: Text('This month',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800))),
              Text(Money.format(total),
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (expenses.isEmpty)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text('No expenses recorded yet')))
        else
          ...expenses.map((expense) => Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant)),
                child: _ExpenseTile(expense: expense),
              )),
      ],
    );
  }
}

class _BudgetPage extends StatelessWidget {
  const _BudgetPage(
      {required this.budget, required this.stats, required this.onEdit});
  final MonthlyBudget? budget;
  final MonthStats stats;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (budget == null) return const SizedBox.shrink();
    return ListView(
      padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 900 ? 32 : 20,
          8,
          MediaQuery.sizeOf(context).width >= 900 ? 32 : 20,
          100),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: scheme.outlineVariant)),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                      child: Text('Monthly allocation',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800))),
                  OutlinedButton.icon(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_rounded),
                      label: const Text('Edit')),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _BudgetSummaryItem(
                      label: 'Income',
                      value: Money.format(budget!.income),
                      color: scheme.primary),
                  _BudgetSummaryItem(
                      label: 'Fixed',
                      value: Money.format(budget!.totalFixed),
                      color: scheme.secondary),
                  _BudgetSummaryItem(
                      label: 'Savings',
                      value: Money.format(budget!.savingsGoal),
                      color: const Color(0xFF00695C)),
                  _BudgetSummaryItem(
                      label: 'Flexible',
                      value: Money.format(budget!.flexiblePool),
                      color: const Color(0xFFEF6C00)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _CategorySpendingCard(budget: budget, stats: stats),
      ],
    );
  }
}

class _BudgetSummaryItem extends StatelessWidget {
  const _BudgetSummaryItem(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: TextStyle(color: color, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _InsightsPage extends StatelessWidget {
  const _InsightsPage({required this.insight, this.demo = false});
  final DailyInsight? insight;
  final bool demo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final message = insight?.message ??
        (demo
            ? 'You spend the most on weekends. A small midweek check-in could keep the month on track.'
            : 'Keep logging expenses to unlock personalized insights.');
    return ListView(
      padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 900 ? 32 : 20,
          8,
          MediaQuery.sizeOf(context).width >= 900 ? 32 : 20,
          100),
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: [scheme.tertiaryContainer, scheme.primaryContainer]),
              borderRadius: BorderRadius.circular(24)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_rounded, color: scheme.tertiary),
              const SizedBox(height: 14),
              Text('Daily guidance',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Text(message,
                  style: TextStyle(
                      fontSize: 16,
                      color: scheme.onTertiaryContainer,
                      height: 1.5)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _InfoCard(
            icon: Icons.trending_up_rounded,
            title: 'Spending trend',
            body: 'Review your category trends at the end of each week.'),
        const SizedBox(height: 12),
        const _InfoCard(
            icon: Icons.savings_outlined,
            title: 'Savings tip',
            body:
                'Move a portion of unused flexible money to savings before month-end.'),
      ],
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard(
      {required this.icon, required this.title, required this.body});
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: scheme.outlineVariant)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: scheme.primary),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text(body, style: TextStyle(color: scheme.onSurfaceVariant))
              ])),
        ],
      ),
    );
  }
}

class BudgetSetupSheet extends StatefulWidget {
  const BudgetSetupSheet({
    super.key,
    required this.monthKey,
    required this.categories,
    this.initial,
    this.liveData,
  });

  final String monthKey;
  final List<ExpenseCategory> categories;
  final MonthlyBudget? initial;
  final UserData? liveData;

  @override
  State<BudgetSetupSheet> createState() => _BudgetSetupSheetState();
}

class _BudgetSetupSheetState extends State<BudgetSetupSheet> {
  final _incomeController = TextEditingController();
  final Map<String, TextEditingController> _limitControllers = {};

  @override
  void initState() {
    super.initState();
    _incomeController.text = widget.initial == null
        ? ''
        : (widget.initial!.income / 100).toStringAsFixed(0);
    for (final category in widget.categories) {
      final existing = widget.initial?.forCategory(category.id);
      _limitControllers[category.id] = TextEditingController(
        text: existing == null ? '' : (existing.limit / 100).toStringAsFixed(0),
      );
    }
  }

  @override
  void dispose() {
    _incomeController.dispose();
    for (final controller in _limitControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.86,
      maxChildSize: 0.94,
      builder: (context, scrollController) {
        return ListView(
          controller: scrollController,
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 10,
            bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
          ),
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                    color: scheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 18),
            Text('Monthly budget',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(
                'Set your income and limits for ${_monthLabel(widget.monthKey)}'),
            const SizedBox(height: 20),
            TextField(
              controller: _incomeController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Monthly income',
                prefixText: 'Rs. ',
              ),
            ),
            const SizedBox(height: 20),
            Text('Category limits',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            ...widget.categories
                .where((category) => !category.archived)
                .map((category) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: TextField(
                  controller: _limitControllers[category.id],
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: category.name,
                    prefixText: 'Rs. ',
                    suffixIcon: Icon(categoryIcon(category.iconKey),
                        color: Color(category.colorValue)),
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: _save,
              child: const Text('Save budget'),
            ),
          ],
        );
      },
    );
  }

  void _save() {
    final income = Money.parse(_incomeController.text);
    if (income == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid monthly income')));
      return;
    }
    final categoryBudgets = <CategoryBudget>[];
    for (final category
        in widget.categories.where((category) => !category.archived)) {
      final text = _limitControllers[category.id]?.text ?? '';
      final limit = Money.parse(text) ?? 0;
      categoryBudgets.add(CategoryBudget.fromCategory(category, limit));
    }
    Navigator.pop(
      context,
      MonthlyBudget(
        monthKey: widget.monthKey,
        income: income,
        categories: categoryBudgets,
      ),
    );
  }
}

class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({super.key, required this.categories});
  final List<ExpenseCategory> categories;

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  late ExpenseCategory _category = widget.categories.isNotEmpty
      ? widget.categories.firstWhere((category) => !category.archived,
          orElse: () => widget.categories.first)
      : const ExpenseCategory(
          id: 'other',
          name: 'Other',
          iconKey: 'category',
          colorValue: 0xFF546E7A);
  DateTime _date = DateTime.now();

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final available =
        widget.categories.where((category) => !category.archived).toList();
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 12,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(99)),
              ),
            ),
            const SizedBox(height: 18),
            Text('Add expense',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 18),
            TextField(
              controller: _amountController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Amount', prefixText: 'Rs. '),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ExpenseCategory>(
              initialValue: _category,
              decoration: const InputDecoration(labelText: 'Category'),
              items: available
                  .map((category) => DropdownMenuItem(
                        value: category,
                        child: Row(
                          children: [
                            Icon(categoryIcon(category.iconKey),
                                size: 20, color: Color(category.colorValue)),
                            const SizedBox(width: 10),
                            Text(category.name),
                          ],
                        ),
                      ))
                  .toList(),
              onChanged: (value) =>
                  setState(() => _category = value ?? _category),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  prefixIcon: Icon(Icons.notes_rounded)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _pickDate,
              icon: const Icon(Icons.calendar_today_rounded),
              label: Text(_shortDate(_date)),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: _save, child: const Text('Save expense')),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final result = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (result != null) setState(() => _date = result);
  }

  void _save() {
    final amount = Money.parse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter a valid expense amount')));
      return;
    }
    Navigator.pop(
      context,
      Expense(
        amount: amount,
        categoryId: _category.id,
        categoryName: _category.name,
        categoryKind: _category.kind,
        note: _noteController.text.trim(),
        date: _date,
      ),
    );
  }
}

IconData categoryIcon(String key) {
  switch (key) {
    case 'restaurant':
      return Icons.restaurant_rounded;
    case 'shopping_basket':
      return Icons.shopping_basket_rounded;
    case 'directions_bus':
      return Icons.directions_bus_rounded;
    case 'shopping_bag':
      return Icons.shopping_bag_rounded;
    case 'movie':
      return Icons.movie_rounded;
    case 'favorite':
      return Icons.favorite_rounded;
    case 'school':
      return Icons.school_rounded;
    case 'home':
      return Icons.home_rounded;
    case 'receipt_long':
      return Icons.receipt_long_rounded;
    case 'groups':
      return Icons.groups_rounded;
    case 'savings':
      return Icons.savings_rounded;
    default:
      return Icons.category_rounded;
  }
}

String expenseCategoryIcon(String categoryId) {
  for (final category in defaultCategories) {
    if (category.id == categoryId) return category.iconKey;
  }
  return 'category';
}

String _shortDate(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];
  return '${date.day} ${months[date.month - 1]}';
}

String _monthLabel(String monthKey) {
  final date = DateKeys.startOfMonth(monthKey);
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];
  return '${months[date.month - 1]} ${date.year}';
}
