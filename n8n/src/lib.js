// ===== SafeSpend shared helpers (inlined into every Code node by build.py) =====
// Mirrors the Dart models in lib/models. Source of truth: n8n/schema/safespend.schema.json.
/* @@DEFAULT_CATEGORIES@@ */
const MAX_NOTE = 500;
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function cfgOf() { return $('Config').first().json; }
function docRoot(cfg) { return `projects/${cfg.projectId}/databases/(default)/documents`; }

// ---- Firestore REST typed values <-> plain JSON ----
function fsDecodeValue(v) {
  if (v === undefined || v === null || 'nullValue' in v) return null;
  if ('stringValue' in v) return v.stringValue;
  if ('integerValue' in v) return Number(v.integerValue);
  if ('doubleValue' in v) return v.doubleValue;
  if ('booleanValue' in v) return v.booleanValue;
  if ('timestampValue' in v) return v.timestampValue;
  if ('arrayValue' in v) return (v.arrayValue.values || []).map(fsDecodeValue);
  if ('mapValue' in v) return fsDecodeFields(v.mapValue.fields || {});
  if ('referenceValue' in v) return v.referenceValue;
  return null;
}
function fsDecodeFields(fields) {
  const out = {};
  for (const [k, v] of Object.entries(fields || {})) out[k] = fsDecodeValue(v);
  return out;
}
function fsDecodeDoc(doc) { return doc && doc.fields ? fsDecodeFields(doc.fields) : null; }
function fsIdOf(doc) { return String(doc.name).split('/').pop(); }
// A plain object {__timestamp: iso} becomes a Firestore timestamp.
function fsEncode(v) {
  if (v === null || v === undefined) return { nullValue: null };
  if (typeof v === 'boolean') return { booleanValue: v };
  if (typeof v === 'number') return Number.isInteger(v) ? { integerValue: String(v) } : { doubleValue: v };
  if (typeof v === 'string') return { stringValue: v };
  if (Array.isArray(v)) return { arrayValue: { values: v.map(fsEncode) } };
  if (v.__timestamp) return { timestampValue: v.__timestamp };
  return { mapValue: { fields: fsEncodeFields(v) } };
}
function fsEncodeFields(obj) {
  const out = {};
  for (const [k, v] of Object.entries(obj)) if (v !== undefined) out[k] = fsEncode(v);
  return out;
}
// Field paths must be quoted when a key (a category id, or a day like "05") is not a plain identifier.
function fp(key) { return '`' + String(key).replace(/\\/g, '\\\\').replace(/`/g, '\\`') + '`'; }
const SERVER_TIME = 'REQUEST_TIME';
function inc(fieldPath, n) { return { fieldPath, increment: { integerValue: String(n) } }; }

// ---- Dates: the app groups by the user's LOCAL day, so everything derives from sentAt + offset ----
function isLocalDate(s) {
  if (typeof s !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(s)) return false;
  const d = new Date(s + 'T00:00:00Z');
  return !isNaN(d.getTime()) && d.toISOString().slice(0, 10) === s;
}
function isMonthKey(s) { return typeof s === 'string' && /^\d{4}-(0[1-9]|1[0-2])$/.test(s); }
function addDays(s, n) { const d = new Date(s + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); }
function weekdayOf(s) { return DAY_NAMES[new Date(s + 'T00:00:00Z').getUTCDay()]; }
function daysInMonth(monthKey) { const [y, m] = monthKey.split('-').map(Number); return new Date(Date.UTC(y, m, 0)).getUTCDate(); }
function prevMonthKey(monthKey) { const [y, m] = monthKey.split('-').map(Number); return m === 1 ? `${y - 1}-12` : `${y}-${String(m - 1).padStart(2, '0')}`; }
function buildCtx(body, cfg) {
  let sentAtMs = Date.parse(body.sentAt);
  if (!Number.isFinite(sentAtMs) || Math.abs(sentAtMs - Date.now()) > 36 * 3600 * 1000) sentAtMs = Date.now();
  let off = Number(body.timeZoneOffsetMinutes);
  if (!Number.isFinite(off) || off < -720 || off > 840) off = Number(cfg.defaultUtcOffsetMinutes) || 0;
  const localDate = new Date(sentAtMs + off * 60000).toISOString().slice(0, 10);
  return { sentAtMs, offsetMin: off, localDate, weekday: weekdayOf(localDate) };
}
// Turns the date the model found into the timestamp + keys the app would have stored.
function resolveWhen(dateStr, ctx) {
  let day = isLocalDate(dateStr) ? dateStr : ctx.localDate;
  let clamped = false;
  if (day > ctx.localDate) { day = ctx.localDate; clamped = true; }
  let ms;
  if (day === ctx.localDate) ms = ctx.sentAtMs;
  else { const [y, m, d] = day.split('-').map(Number); ms = Date.UTC(y, m - 1, d, 12, 0, 0) - ctx.offsetMin * 60000; }
  const daysAgo = Math.round((Date.parse(ctx.localDate + 'T00:00:00Z') - Date.parse(day + 'T00:00:00Z')) / 86400000);
  return { day, iso: new Date(ms).toISOString(), monthKey: day.slice(0, 7), dd: day.slice(8, 10), clamped, daysAgo, given: isLocalDate(dateStr) };
}

// ---- Categories: the user's own (from Firestore), else the fixed-id defaults ----
function activeCategories(docs) {
  const list = [];
  for (const d of docs || []) {
    const f = fsDecodeDoc(d);
    if (!f || f.archived === true) continue;
    list.push({ id: fsIdOf(d), name: String(f.name || ''), kind: ['fixed', 'flexible', 'savings'].includes(f.kind) ? f.kind : 'flexible', sortOrder: Number(f.sortOrder) || 0 });
  }
  if (!list.length) return DEFAULT_CATEGORIES.map((c, i) => ({ ...c, sortOrder: i }));
  return list.sort((a, b) => a.sortOrder - b.sortOrder);
}
function pickCategory(cats, id) {
  const exact = cats.find((c) => c.id === id);
  if (exact) return { cat: exact, exact: true };
  const other = cats.find((c) => c.id === 'other') || cats.find((c) => c.kind === 'flexible') || cats[0];
  return { cat: other, exact: false };
}

// ---- Money ----
function toMinor(rupees) { return Math.round(Number(rupees) * 100); }
function toRupees(minor) { return Math.round(minor) / 100; }
function cleanText(s, max) { return String(s == null ? '' : s).replace(/[\u0000-\u001f\u007f]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max); }

// ---- Atomic commit: the expense AND its month totals, exactly like ExpenseRepository.addExpense ----
// Fails with ALREADY_EXISTS when the same clientRequestId was already saved (safe against retries).
function buildExpenseCommit({ cfg, uid, expenseId, expense, when }) {
  const root = docRoot(cfg);
  const fields = {
    amount: expense.amount, categoryId: expense.categoryId, categoryName: expense.categoryName,
    categoryKind: expense.categoryKind, note: expense.note, date: { __timestamp: when.iso },
    dayKey: when.day, monthKey: when.monthKey, source: expense.source, transcript: expense.transcript || null,
  };
  for (const k of ['merchant', 'confidence', 'requestId', 'receiptId', 'items']) {
    if (expense[k] !== undefined && expense[k] !== null && !(Array.isArray(expense[k]) && !expense[k].length)) fields[k] = expense[k];
  }
  const flexible = expense.categoryKind === 'flexible' ? expense.amount : 0;
  // A scanned receipt: link its record (users/{uid}/receipts/{id}) to the expense in the same commit.
  const receiptFields = expense.receiptId ? {
    status: 'saved', expenseId, amount: expense.amount, categoryId: expense.categoryId, categoryName: expense.categoryName,
    message: expense.receiptMessage || '', ...(expense.merchant ? { merchant: expense.merchant } : {}),
  } : null;
  const commit = {
    writes: [
      {
        update: { name: `${root}/users/${uid}/expenses/${expenseId}`, fields: fsEncodeFields(fields) },
        currentDocument: { exists: false },
        updateTransforms: [
          { fieldPath: 'createdAt', setToServerValue: SERVER_TIME },
          { fieldPath: 'updatedAt', setToServerValue: SERVER_TIME },
        ],
      },
      {
        update: { name: `${root}/users/${uid}/monthStats/${when.monthKey}`, fields: { monthKey: { stringValue: when.monthKey } } },
        updateMask: { fieldPaths: ['monthKey'] },
        updateTransforms: [
          inc('totalSpent', expense.amount), inc('flexibleSpent', flexible), inc('expenseCount', 1),
          inc(`spentByCategory.${fp(expense.categoryId)}`, expense.amount),
          inc(`spentByDay.${fp(when.dd)}`, expense.amount),
          { fieldPath: 'updatedAt', setToServerValue: SERVER_TIME },
        ],
      },
    ],
  };
  if (receiptFields) {
    commit.writes.push({
      update: { name: `${root}/users/${uid}/receipts/${expense.receiptId}`, fields: fsEncodeFields(receiptFields) },
      updateMask: { fieldPaths: Object.keys(receiptFields) },
      updateTransforms: [{ fieldPath: 'updatedAt', setToServerValue: SERVER_TIME }],
    });
  }
  return commit;
}
function expenseIdFor(kind, requestId) { return `${kind}_${String(requestId).replace(/[^A-Za-z0-9_-]/g, '_').slice(0, 100)}`; }
function isAlreadyExists(res) {
  const st = res && res.body && res.body.error && res.body.error.status;
  return res.statusCode === 409 || st === 'ALREADY_EXISTS';
}
function fail(httpStatus, message, workflow) {
  return { ok: false, httpStatus, response: { status: 'failed', message, workflow, saved: false } };
}

// ---- Gemini: structured JSON output ----
// Gemini wants upper-case type names and understands only a subset of JSON Schema.
function geminiSchema(s) {
  if (Array.isArray(s)) return s.map(geminiSchema);
  if (!s || typeof s !== 'object') return s;
  const out = {};
  for (const [k, v] of Object.entries(s)) {
    if (k === 'type') out.type = String(v).toUpperCase();
    else if (k === 'properties') out.properties = Object.fromEntries(Object.entries(v).map(([n, p]) => [n, geminiSchema(p)]));
    else if (k === 'items') out.items = geminiSchema(v);
    else if (k === 'propertyOrdering') out.propertyOrdering = v;
    else if (['description', 'enum', 'required', 'minimum', 'maximum', 'maxItems', 'minItems', 'nullable'].includes(k)) out[k] = v;
  }
  return out;
}
function geminiBody({ system, parts, schema, maxTokens, vision, levelKey }) {
  const generationConfig = { responseMimeType: 'application/json', responseSchema: geminiSchema(schema), maxOutputTokens: maxTokens || 4096 };
  // Vision: read at full resolution. (Temperature and thinking are left at the model defaults, which newer Gemini models prefer.)
  if (vision) generationConfig.mediaResolution = 'MEDIA_RESOLUTION_HIGH';
  // Less thinking = much faster answers. Config field thinkingLevel: minimal | low | medium | high, or default to leave it to the model.
  let level = 'low';
  try { const c = cfgOf()[levelKey || 'thinkingLevel']; if (c !== undefined && c !== null && String(c).trim() !== '') level = String(c).trim().toLowerCase(); } catch (e) { /* keep low */ }
  if (level !== 'default') generationConfig.thinkingConfig = { thinkingLevel: level };
  return {
    systemInstruction: { parts: [{ text: system }] },
    contents: [{ role: 'user', parts }],
    generationConfig,
  };
}
// -> { data } on success, { busy } when rate-limited/overloaded, {} otherwise
function parseAi(res) {
  if (!res || res.statusCode === 429 || res.statusCode === 503) return { busy: true };
  const cand = res.statusCode === 200 && res.body && Array.isArray(res.body.candidates) ? res.body.candidates[0] : null;
  const parts = cand && cand.content && Array.isArray(cand.content.parts) ? cand.content.parts : [];
  const text = parts.map((p) => p.text || '').join('').trim();
  if (!text) return {};
  try { const data = JSON.parse(text); return data && typeof data === 'object' && !Array.isArray(data) ? { data } : {}; } catch (e) { return {}; }
}
