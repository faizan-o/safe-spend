// Webhook path: the validated single-user request becomes the loop's input.
/* @@LIB@@ */
const a = $input.first().json;
return a.items.map((j) => ({ json: { ...j, prevMonthKey: prevMonthKey(j.monthKey) } }));
