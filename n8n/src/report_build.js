// Combines the deterministic numbers with the AI's words (or a rule-based fallback) into monthSummaries/{monthKey}.
/* @@LIB@@ */
const cfg = cfgOf();
const c = $('Compute report').first().json;
const ai = $input.first().json;
const money = (n) => `${c.symbol} ${Math.round(toRupees(n)).toLocaleString('en-US')}`;
let rep = null;
const t = parseAi(ai).data;
if (t && t.headline && t.narrative) {
  const pts = (arr) => (Array.isArray(arr) ? arr : []).slice(0, 3).map((p) => ({ title: cleanText(p.title, 80), detail: cleanText(p.detail, 300), ...(p.categoryId && typeof p.categoryId === 'string' ? { categoryId: p.categoryId } : {}) })).filter((p) => p.title && p.detail);
  rep = {
    headline: cleanText(t.headline, 80), narrative: String(t.narrative).slice(0, 1500), overspent: pts(t.overspent), saved: pts(t.saved),
    improvements: (Array.isArray(t.improvements) ? t.improvements : []).slice(0, 3).map((i) => ({ title: cleanText(i.title, 80), action: cleanText(i.action, 300), ...(Number(i.estimatedSavingRupees) > 0 ? { estimatedSaving: toMinor(i.estimatedSavingRupees) } : {}) })).filter((i) => i.title && i.action),
    generatedBy: 'n8n', suggestion: cleanText(t.suggestion, 200),
  };
}
if (!rep) { // AI unavailable: still give the user a useful, honest report from the numbers
  const red = c.ruleFacts.cats.filter((x) => x.flag === 'red').sort((a, b) => (b.spent - b.limit) - (a.spent - a.limit));
  const green = c.ruleFacts.cats.filter((x) => x.flag === 'green');
  rep = {
    headline: c.partial ? 'Your month so far' : 'Your month in review',
    narrative: `You spent ${money(c.summary.totalSpent)} ${c.partial ? 'so far this month' : 'this month'}.` + (c.ruleFacts.hasBudget ? ` ${c.summary.saved >= 0 ? 'You have ' + money(c.summary.saved) + ' left from your flexible budget.' : 'You went over your flexible budget by ' + money(-c.summary.saved) + '.'}` : ' Set a budget to see where you can save.'),
    overspent: red.slice(0, 3).map((x) => ({ categoryId: x.categoryId, title: x.name, detail: `Spent ${money(x.spent)} against a limit of ${money(x.limit)}.` })),
    saved: green.slice(0, 3).map((x) => ({ categoryId: x.categoryId, title: x.name, detail: `Spent ${money(x.spent)} of ${money(x.limit)}.` })),
    improvements: red.slice(0, 2).map((x) => ({ title: `Rein in ${x.name}`, action: `Aim to stay within ${money(x.limit)} next month.`, estimatedSaving: x.spent - x.limit })),
    generatedBy: 'rules',
    suggestion: red.length ? `Keep ${red[0].name} within ${money(red[0].limit)} next month.` : 'Keep logging every expense so next month\'s report is even more accurate.',
  };
}
const suggestion = rep.suggestion; delete rep.suggestion;
rep.partial = c.partial;
const summary = { ...c.summary, suggestion, report: rep };
const name = `${docRoot(cfg)}/users/${c.uid}/monthSummaries/${c.monthKey}`;
const write = { update: { name, fields: fsEncodeFields(summary) }, updateTransforms: [{ fieldPath: 'generatedAt', setToServerValue: SERVER_TIME }] };
if (!c.force) write.currentDocument = { exists: false };
return [{ json: { commit: { writes: [write] }, summary, statsDrift: c.statsDrift } }];
