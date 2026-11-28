// Works out every number of the month deterministically (same rules as the app), then prepares the AI request.
/* @@LIB@@ */
const cfg = cfgOf();
const u = $('Current user').first().json;
const bodyOf = (name) => { try { const r = $(name).first().json; return r.statusCode === 200 ? r.body : null; } catch (e) { return null; } };
const skip = (reason) => [{ json: { skip: true, reason, uid: u.uid, monthKey: u.monthKey } }];
try {
  // Two ways in: the app sends the month's data itself (u.data, plain JSON), or the workflow reads Firestore (monthly schedule).
  const sent = u.data && typeof u.data === 'object' ? u.data : null;
  const profile = sent ? { currencySymbol: sent.currencySymbol } : (fsDecodeDoc(bodyOf('Get profile')) || {});
  const budget = sent ? (sent.budget && typeof sent.budget === 'object' ? sent.budget : null) : fsDecodeDoc(bodyOf('Get budget'));
  const stored = sent ? (sent.stats && typeof sent.stats === 'object' ? sent.stats : null) : fsDecodeDoc(bodyOf('Get stats'));
  const prevStats = sent ? (sent.prevStats && typeof sent.prevStats === 'object' ? sent.prevStats : null) : fsDecodeDoc(bodyOf('Get previous stats'));
  const symbol = String(profile.currencySymbol || 'Rs.').slice(0, 8);
  const monthKey = u.monthKey, days = daysInMonth(monthKey);

  const expenses = [];
  if (sent) {
    for (const e of (Array.isArray(sent.expenses) ? sent.expenses : []).slice(0, 2000)) {
      if (e && typeof e === 'object' && String(e.monthKey || monthKey) === monthKey) expenses.push(e);
    }
  } else {
    const q = $input.first().json;
    // A failed read must not look like "no data": say what Firestore answered.
    if (q.statusCode !== 200) {
      const m = q.body && (Array.isArray(q.body) ? q.body[0] : q.body);
      const msg = m && m.error && m.error.message ? m.error.message : '';
      return skip(`could not read expenses (HTTP ${q.statusCode}) ${String(msg).slice(0, 140)} - check the Config projectId and the Google service account credential`);
    }
    for (const row of Array.isArray(q.body) ? q.body : []) {
      if (row.document && row.document.fields) expenses.push({ id: fsIdOf(row.document), ...fsDecodeFields(row.document.fields) });
    }
  }
  if (!expenses.length && !budget) return skip('no_data');

  // Totals recomputed from the expenses (n8n has full access), compared with the stored running totals.
  const d = { total: 0, flexible: 0, count: 0, byCat: {}, byDay: {}, catName: {}, catKind: {} };
  for (const e of expenses) {
    const amt = Number(e.amount) || 0;
    d.total += amt; d.count += 1; if (e.categoryKind === 'flexible') d.flexible += amt;
    d.byCat[e.categoryId] = (d.byCat[e.categoryId] || 0) + amt;
    const dd = String(e.dayKey || '').slice(8, 10); if (dd) d.byDay[dd] = (d.byDay[dd] || 0) + amt;
    d.catName[e.categoryId] = e.categoryName; d.catKind[e.categoryId] = e.categoryKind;
  }
  const truncated = expenses.length >= 2000;
  const useStored = truncated && stored;
  const total = useStored ? stored.totalSpent : d.total;
  const flexibleSpent = useStored ? stored.flexibleSpent : d.flexible;
  const byCat = useStored ? stored.spentByCategory || {} : d.byCat;
  const byDay = useStored ? stored.spentByDay || {} : d.byDay;
  const statsDrift = !!stored && !truncated && (stored.totalSpent !== d.total || stored.expenseCount !== d.count);

  // Budget
  const lines = budget && Array.isArray(budget.categories) ? budget.categories : [];
  const income = budget ? Number(budget.income) || 0 : 0;
  const sumKind = (k) => lines.filter((l) => l.kind === k).reduce((s, l) => s + (Number(l.limit) || 0), 0);
  const fixed = sumKind('fixed'), goal = sumKind('savings'), pool = income - fixed - goal;
  const saved = budget ? pool - flexibleSpent : 0;

  // Flags: same thresholds as the app (red over limit or >115% of pace, green <=85%), pace only from day 5 of a month in progress.
  const elapsed = u.partial ? Math.max(1, Number(String(u.localDate).slice(8, 10))) : days;
  const pace = elapsed / days, usePace = u.partial && elapsed >= 5;
  const cats = lines.filter((l) => (Number(l.limit) || 0) > 0).map((l) => {
    const limit = Number(l.limit), spent = byCat[l.categoryId] || 0;
    let flag = 'none';
    if (l.kind === 'savings') { if (spent >= limit) flag = 'green'; }
    else {
      const expected = limit * (usePace ? pace : 1);
      if (spent > limit || (usePace && spent > expected * 1.15)) flag = 'red';
      else if ((usePace || !u.partial) && spent <= expected * 0.85) flag = 'green';
    }
    return { categoryId: l.categoryId, name: l.name, limit, spent, flag, kind: l.kind };
  });
  const budgeted = new Set(lines.map((l) => l.categoryId));
  const unbudgeted = Object.entries(byCat).filter(([id, v]) => !budgeted.has(id) && v > 0)
    .map(([id, v]) => ({ categoryId: id, name: d.catName[id] || id, spent: v })).sort((x, y) => y.spent - x.spent);

  // Patterns the AI can talk about
  const wd = {}; let weekendSpend = 0, weekdaySpend = 0;
  for (const e of expenses) {
    if (e.dayKey && isLocalDate(e.dayKey) && e.categoryKind === 'flexible') {
      const name = weekdayOf(e.dayKey); wd[name] = (wd[name] || 0) + (Number(e.amount) || 0);
      if (name === 'Saturday' || name === 'Sunday') weekendSpend += Number(e.amount) || 0; else weekdaySpend += Number(e.amount) || 0;
    }
  }
  const spendDays = Object.keys(byDay).filter((k) => byDay[k] > 0).length;
  const top = [...expenses].sort((x, y) => (Number(y.amount) || 0) - (Number(x.amount) || 0)).slice(0, 5)
    .map((e) => ({ amount: toRupees(e.amount), category: e.categoryName, note: e.note || e.merchant || '', date: e.dayKey }));
  const prevByCat = prevStats && prevStats.spentByCategory ? prevStats.spentByCategory : {};
  const changes = Object.keys({ ...byCat, ...prevByCat }).map((id) => ({ category: d.catName[id] || (lines.find((l) => l.categoryId === id) || {}).name || id, now: toRupees(byCat[id] || 0), before: toRupees(prevByCat[id] || 0) }))
    .filter((c) => c.now || c.before).sort((x, y) => Math.abs(y.now - y.before) - Math.abs(x.now - x.before)).slice(0, 6);
  const sources = { voice: 0, receipt: 0, manual: 0 };
  for (const e of expenses) sources[e.source] = (sources[e.source] || 0) + 1;

  const facts = {
    month: monthKey, partialMonth: !!u.partial, daysElapsed: elapsed, daysInMonth: days, currency: symbol, hasBudget: !!budget,
    incomeDeclared: toRupees(income), totalSpent: toRupees(total), flexibleSpent: toRupees(flexibleSpent), fixedBudgeted: toRupees(fixed), savingsGoal: toRupees(goal),
    flexiblePool: toRupees(pool), leftFromFlexiblePool: toRupees(saved), expenseCount: expenses.length || (stored ? stored.expenseCount : 0), daysWithSpending: spendDays,
    averagePerSpendingDay: spendDays ? toRupees(Math.round(flexibleSpent / spendDays)) : 0,
    categories: cats.map((c) => ({ category: c.name, kind: c.kind, limit: toRupees(c.limit), spent: toRupees(c.spent), percentUsed: Math.round((c.spent / c.limit) * 100), flag: c.flag })),
    spendingWithoutABudget: unbudgeted.slice(0, 5).map((x) => ({ category: x.name, spent: toRupees(x.spent) })),
    flexibleSpendByWeekday: Object.fromEntries(Object.entries(wd).map(([k, v]) => [k, toRupees(v)])),
    weekendVsWeekdayFlexible: { weekend: toRupees(weekendSpend), weekday: toRupees(weekdaySpend) },
    biggestExpenses: top, changeVsPreviousMonth: changes, entryMethods: sources,
  };

  const system = [
    'You write a friendly, honest month-end money report for one person using a budgeting app. Their data is in the JSON facts.',
    'Rules: use ONLY numbers present in the facts (or simple sums/differences of them); never invent amounts, categories or events. Amounts are in the currency given; write them like "Rs. 12,500".',
    'Be specific and kind: no shaming, no generic advice. If partialMonth is true, say it is a progress report so far, not a final verdict.',
    'overspent: up to 3 points where spending went over the limit, over pace, or grew a lot versus last month. saved: up to 3 points where they stayed under budget or saved. improvements: up to 3 concrete actions for next month tied to their own data; give estimatedSavingRupees only when it follows from the facts (e.g. trimming the overspend).',
    'If hasBudget is false, say a budget would unlock flags and comparisons, and base the report on spending patterns only.',
    'narrative: Markdown, 80-130 words. suggestion: ONE sentence, max 160 characters, the single most useful thing to do next month. headline: max 70 characters.',
  ].join('\n');
  const point = { type: 'object', properties: { categoryId: { type: 'string', enum: [...new Set([...Object.keys(byCat), ...lines.map((l) => l.categoryId)])] }, title: { type: 'string' }, detail: { type: 'string' } }, required: ['title', 'detail'] };
  const schema = { type: 'object', properties: {
    headline: { type: 'string' }, narrative: { type: 'string' }, suggestion: { type: 'string' },
    overspent: { type: 'array', maxItems: 3, items: point }, saved: { type: 'array', maxItems: 3, items: point },
    improvements: { type: 'array', maxItems: 3, items: { type: 'object', properties: { title: { type: 'string' }, action: { type: 'string' }, estimatedSavingRupees: { type: 'number' } }, required: ['title', 'action'] } },
  }, required: ['headline', 'narrative', 'suggestion', 'overspent', 'saved', 'improvements'] };
  const aiBody = geminiBody({ system, schema, maxTokens: 4096, parts: [{ text: `<facts>\n${JSON.stringify(facts)}\n</facts>` }] });

  return [{ json: { skip: false, uid: u.uid, monthKey, partial: !!u.partial, force: !!u.force, symbol, statsDrift, truncated,
    summary: { monthKey, income, totalSpent: total, flexibleSpent, saved, categories: cats.map(({ kind, ...c }) => c) },
    ruleFacts: { cats, unbudgeted, changes, saved, hasBudget: !!budget }, aiBody } }];
} catch (err) {
  return skip('error: ' + String(err && err.message || err).slice(0, 200));
}
