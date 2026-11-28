// One result per user, whichever way the run ended.
/* @@LIB@@ */
const u = $('Current user').first().json;
const j = $input.first().json;
let response;
if (j.skip) response = { status: 'skipped', monthKey: j.monthKey || u.monthKey, reason: j.reason };
else if (!j.statusCode && j.summary) response = { status: 'generated', monthKey: u.monthKey, statsDrift: !!j.statsDrift, summary: j.summary }; // app-supplied data: the app saves it
else {
  const built = $('Build summary').first().json;
  if (j.statusCode === 200) response = { status: 'generated', monthKey: u.monthKey, statsDrift: !!built.statsDrift, summary: built.summary };
  else if (isAlreadyExists(j)) response = { status: 'skipped', monthKey: u.monthKey, reason: 'already_generated' };
  else response = { status: 'failed', monthKey: u.monthKey, reason: 'could_not_save', message: 'The report could not be saved. Please try again.' };
}
return [{ json: { via: u.via, uid: u.uid, httpStatus: response.status === 'failed' ? 502 : 200, response: { workflow: 'n8n-report', ...response } } }];
