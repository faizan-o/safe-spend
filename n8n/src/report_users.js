// Scheduled path: works out the month that just ended and turns the users list into one item per user.
/* @@LIB@@ */
const cfg = cfgOf();
const off = Number(cfg.defaultUtcOffsetMinutes) || 0;
const localToday = new Date(Date.now() + off * 60000).toISOString().slice(0, 10);
const monthKey = prevMonthKey(localToday.slice(0, 7));
const items = [];
for (const page of $input.all()) {
  const docs = page.json.body && page.json.body.documents ? page.json.body.documents : [];
  for (const d of docs) items.push({ json: { uid: fsIdOf(d), monthKey, prevMonthKey: prevMonthKey(monthKey), force: false, via: 'schedule', partial: false, localDate: localToday } });
}
return items;
