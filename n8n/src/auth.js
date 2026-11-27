// Checks the Firebase ID token (via Google's accounts:lookup) and validates the request body.
/* @@LIB@@ */
const KIND = '__KIND__';
const WORKFLOW = `n8n-${KIND}`;
const cfg = cfgOf();
const req = $('Config').first().json;
const body = (req.body && typeof req.body === 'object') ? req.body : {};
const verify = $input.first().json;
const out = (o) => [{ json: o }];

const user = verify.statusCode === 200 && verify.body && Array.isArray(verify.body.users) ? verify.body.users[0] : null;
if (!user || !user.localId || user.disabled) return out(fail(401, 'Please sign in again.', WORKFLOW));
const uid = String(user.localId);
if (body.userId && String(body.userId) !== uid) return out(fail(403, 'This request is for a different account.', WORKFLOW));

if (KIND === 'report') {
  const ctx = buildCtx(body, cfg);
  const current = ctx.localDate.slice(0, 7);
  const monthKey = body.monthKey === undefined ? current : body.monthKey;
  if (!isMonthKey(monthKey) || monthKey > current) return out(fail(400, 'monthKey must look like 2026-11 and not be in the future.', WORKFLOW));
  return out({ ok: true, items: [{ uid, monthKey, force: body.force !== false, via: 'webhook', partial: monthKey === current, localDate: ctx.localDate }] });
}

const requestId = cleanText(body.clientRequestId, 100) || `auto-${uid.slice(0, 8)}-${Date.now()}`;
const ctx = buildCtx(body, cfg);
const save = body.save !== false && body.save !== 'never';
const receiptId = /^[A-Za-z0-9_-]{1,64}$/.test(String(body.receiptId || '')) ? String(body.receiptId) : null;
const base = { ok: true, uid, requestId, ctx, save, receiptId, locale: cleanText(body.locale, 20) || null };

if (KIND === 'voice') {
  const transcript = cleanText(body.transcript, 1000);
  if (!transcript) return out(fail(400, 'Nothing to understand: the transcript is empty.', WORKFLOW));
  return out({ ...base, transcript });
}
// receipt
const ALLOWED = ['image/jpeg', 'image/png', 'image/webp', 'image/gif', 'application/pdf'];
const mime = String(body.mimeType || '').toLowerCase().replace('image/jpg', 'image/jpeg');
let b64 = typeof body.imageBase64 === 'string' ? body.imageBase64.replace(/^data:[^;]+;base64,/, '').replace(/\s+/g, '') : '';
if (!ALLOWED.includes(mime)) return out(fail(400, 'Unsupported file type. Send a JPEG, PNG, WebP, GIF or PDF.', WORKFLOW));
if (!b64 || !/^[A-Za-z0-9+/]+={0,2}$/.test(b64)) return out(fail(400, 'imageBase64 is missing or is not valid base64.', WORKFLOW));
if (b64.length > Math.ceil((Number(cfg.maxImageBytes) || 5000000) * 4 / 3)) return out(fail(413, 'The file is too large. Please send one under 5 MB.', WORKFLOW));
return out({ ...base, mimeType: mime });
