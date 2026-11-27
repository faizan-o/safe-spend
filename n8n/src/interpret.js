// Validates the model's answer against the user's real categories and builds the atomic Firestore commit.
/* @@LIB@@ */
const KIND = '__KIND__';
const WORKFLOW = `n8n-${KIND}`;
const cfg = cfgOf();
const a = $('Auth').first().json;
const p = $('Build prompt').first().json;
const ai = $input.first().json;
const minConf = Number(cfg.autoSaveMinConfidence) || 0.8;
const maxAuto = Number(cfg.maxAutoSaveRupees) || 100000;
const maxAmount = Number(cfg.maxAmountRupees) || 10000000;
const respond = (httpStatus, response, extra = {}) => [{ json: { shouldSave: false, httpStatus, response: { workflow: WORKFLOW, saved: false, ...response }, ...extra } }];

const parsedAi = parseAi(ai);
if (!parsedAi.data) {
  // Answer 200 (not 502/503) so browsers keep the response (error pages carry no CORS headers) and the app can show the reason.
  const err = ai && ai.body && ai.body.error && ai.body.error.message ? String(ai.body.error.message) : '';
  const cand = ai && ai.body && Array.isArray(ai.body.candidates) ? ai.body.candidates[0] : null;
  const why = err || (cand && cand.finishReason && cand.finishReason !== 'STOP' ? `finish reason ${cand.finishReason}` : '') || (ai && ai.statusCode ? `HTTP ${ai.statusCode}` : '');
  const base = parsedAi.busy ? 'The assistant is busy. Please try again in a moment.' : 'The assistant is unavailable right now. Please try again.';
  return respond(200, { status: 'failed', message: why ? `${base} (${cleanText(why, 220)})` : base });
}
const t = parsedAi.data;

let status, message = cleanText(t.message, 300), rupees, dateStr, merchant, note, catId, items = [];
const conf = Math.min(1, Math.max(0, Number(t.confidence) || 0));
if (KIND === 'voice') {
  status = ['parsed', 'needs_clarification', 'failed'].includes(t.status) ? t.status : 'failed';
  rupees = Number(t.amount); dateStr = t.date; merchant = cleanText(t.merchant, 100); note = cleanText(t.note, MAX_NOTE); catId = t.categoryId;
} else {
  rupees = Number(t.total); dateStr = t.date; merchant = cleanText(t.merchant, 100); note = cleanText(t.note, MAX_NOTE); catId = t.categoryId;
  if (t.documentType === 'not_financial') { status = 'failed'; message = message || 'This does not look like a receipt or a payment.'; }
  else if (t.direction === 'income_or_refund') { status = 'failed'; message = 'This looks like money you received or a refund, which is not an expense.'; }
  else if (t.legible === false || !(rupees > 0)) { status = 'needs_clarification'; message = message || 'I could not read the total. Please retake the photo closer and in good light.'; }
  else status = 'parsed';
  items = (Array.isArray(t.items) ? t.items : []).slice(0, 30).map((i) => ({ description: cleanText(i && i.description, 100), amount: toMinor(i && i.amount), quantity: Math.max(1, Math.round(Number(i && i.quantity) || 1)) })).filter((i) => i.description && Number.isFinite(i.amount) && i.amount > 0);
}
if (status !== 'parsed') return respond(200, { status, message: message || 'I need a bit more detail.', confidence: conf });
if (!Number.isFinite(rupees) || rupees <= 0 || rupees > maxAmount) return respond(200, { status: 'needs_clarification', message: 'I could not work out a valid amount. How much was it?', confidence: conf });

const { cat, exact } = pickCategory(p.cats, catId);
const when = resolveWhen(dateStr, a.ctx);
const reasons = [];
if (!exact) reasons.push('category_uncertain');
if (conf < minConf) reasons.push('low_confidence');
if (rupees > maxAuto) reasons.push('large_amount');
if (when.clamped) reasons.push('future_date');
if (when.daysAgo > 60) reasons.push('old_date');
if (KIND === 'receipt') {
  const cur = String(t.currency || '').toUpperCase().replace(/[^A-Z₨$€£]/g, '');
  const pk = ['', 'PKR', 'RS', 'RS.', '₨'];
  const mine = String(p.currency.code).toUpperCase();
  if (cur && !(mine === 'PKR' ? pk.includes(cur) : cur === mine || cur === String(p.currency.symbol).toUpperCase())) reasons.push('currency_mismatch');
}
const amount = toMinor(rupees);
const expense = {
  amount, categoryId: cat.id, categoryName: cat.name, categoryKind: cat.kind,
  note: note || merchant || (KIND === 'voice' ? '' : 'Receipt'), date: when.iso,
  source: KIND === 'voice' ? 'voice' : 'receipt', transcript: KIND === 'voice' ? a.transcript : null,
  merchant: merchant || null, confidence: Math.round(conf * 100) / 100, requestId: a.requestId, items,
  receiptId: KIND === 'receipt' ? a.receiptId : null, receiptMessage: message,
};
const needsReview = reasons.length > 0;
const shouldSave = a.save && !needsReview;
const expenseId = expenseIdFor(KIND, a.requestId);
const response = {
  workflow: WORKFLOW, saved: false, status: 'parsed', message: message || 'Got it.', confidence: expense.confidence, needsReview, reviewReasons: reasons, expenseId: shouldSave ? expenseId : null, receiptId: KIND === 'receipt' ? a.receiptId : null,
  expense: { amount: toRupees(amount), categoryId: cat.id, categoryName: cat.name, note: expense.note, merchant: merchant || null, date: when.day, items: items.map((i) => ({ description: i.description, amount: toRupees(i.amount), quantity: i.quantity })) },
};
const out = { shouldSave, httpStatus: 200, response, expenseId };
if (shouldSave) out.commit = buildExpenseCommit({ cfg, uid: a.uid, expenseId, expense: { ...expense, date: undefined }, when });
return [{ json: out }];
