// Reads the commit result and completes the response sent back to the app.
/* @@LIB@@ */
const prev = $('Interpret').first().json;
const res = $input.first().json;
const response = { ...prev.response };
if (res.statusCode === 200) {
  response.saved = true;
  response.message = response.message || 'Saved.';
} else if (isAlreadyExists(res)) {
  response.saved = true; response.duplicate = true;
} else {
  // Could not write: hand the parsed expense back so the app can still save it itself.
  response.saved = false; response.expenseId = null; response.needsReview = true;
  response.reviewReasons = [...(response.reviewReasons || []), 'save_failed'];
}
return [{ json: { httpStatus: 200, response } }];
