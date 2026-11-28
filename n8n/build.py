#!/usr/bin/env python3
"""Generates the importable n8n workflows in n8n/workflows from n8n/src.

Run:  python3 n8n/build.py
The shared helpers (src/lib.js) and the default categories (schema/safespend.schema.json)
are inlined into every Code node, so each workflow file is fully self-contained.
"""
import json, pathlib, uuid

ROOT = pathlib.Path(__file__).parent
SRC, OUT = ROOT / "src", ROOT / "workflows"
schema = json.loads((ROOT / "schema" / "safespend.schema.json").read_text())
defaults = "const DEFAULT_CATEGORIES = " + json.dumps(
    [{"id": c["id"], "name": c["name"], "kind": c["kind"]} for c in schema["defaultCategories"]], ensure_ascii=False) + ";"
LIB = (SRC / "lib.js").read_text().replace("/* @@DEFAULT_CATEGORIES@@ */", defaults)

def code(name, **subs):
    text = (SRC / name).read_text().replace("/* @@LIB@@ */", LIB)
    for k, v in subs.items():
        text = text.replace(k, v)
    return text

def sid(workflow, name):  # stable ids so re-imports are predictable
    return str(uuid.uuid5(uuid.NAMESPACE_URL, f"safespend/{workflow}/{name}"))

class Flow:
    def __init__(self, key, name):
        self.key, self.name, self.nodes, self.conns, self.x = key, name, [], {}, {}
    def add(self, name, type_, params, pos, version=1, **extra):
        n = {"parameters": params, "id": sid(self.key, name), "name": name, "type": type_, "typeVersion": version, "position": list(pos)}
        n.update(extra)
        self.nodes.append(n)
        return name
    def link(self, a, b, out=0):
        self.conns.setdefault(a, {"main": []})
        m = self.conns[a]["main"]
        while len(m) <= out:
            m.append([])
        m[out].append({"node": b, "type": "main", "index": 0})
    def chain(self, *names):
        for a, b in zip(names, names[1:]):
            self.link(a, b)
    def json(self, tags):
        return {"name": self.name, "nodes": self.nodes, "connections": self.conns, "active": False,
                "settings": {"executionOrder": "v1", "timezone": "Asia/Karachi"}, "tags": [{"name": t} for t in tags],
                "meta": {"templateCredsSetupCompleted": False}, "pinData": {}}

# Optional local settings, so the files come out ready to import: copy local.config.example.json
# to local.config.json (git-ignored) and fill it in. Nothing here is required.
import json as _json, os as _os
_LOCAL = {}
_p = _os.path.join(_os.path.dirname(_os.path.abspath(__file__)), "local.config.json")
if _os.path.exists(_p):
    _LOCAL = _json.load(open(_p))

GOOGLE = {"googleApi": {"id": _LOCAL.get("googleCredentialId") or "REPLACE_WITH_YOUR_CREDENTIAL_ID", "name": _LOCAL.get("googleCredentialName") or "SafeSpend Firebase service account"}}
GEMINI = {"httpHeaderAuth": {"id": _LOCAL.get("geminiCredentialId") or "REPLACE_WITH_YOUR_CREDENTIAL_ID", "name": _LOCAL.get("geminiCredentialName") or "Gemini API key"}}
NEVER_ERROR = {"response": {"response": {"fullResponse": True, "neverError": True}}}  # keep non-2xx answers as data
FS = "=https://firestore.googleapis.com/v1/projects/{{ $('Config').first().json.projectId }}/databases/(default)/documents"

def config_node(f, pos, note):
    vals = [("projectId", _LOCAL.get("projectId") or "YOUR-FIREBASE-PROJECT-ID", "string"), ("firebaseApiKey", _LOCAL.get("firebaseApiKey") or "YOUR-FIREBASE-WEB-API-KEY", "string"),
            ("model", "gemini-3.8-flash", "string"), ("fallbackModel", "gemini-flash-lite-latest", "string"), ("thinkingLevel", "low", "string"), ("voiceThinkingLevel", "low", "string"), ("voiceModel", "gemini-3.8-flash", "string"), ("autoSaveAudio", "false", "string"), ("autoSaveMinConfidence", 0.8, "number"),
            ("maxAutoSaveRupees", 100000, "number"), ("maxAmountRupees", 10000000, "number"),
            ("maxImageBytes", 5000000, "number"), ("maxAudioBytes", 3000000, "number"), ("defaultUtcOffsetMinutes", 300, "number")]
    a = [{"id": sid(f.key, "cfg" + k), "name": k, "value": v, "type": t} for k, v, t in vals]
    return f.add("Config", "n8n-nodes-base.set", {"assignments": {"assignments": a}, "includeOtherFields": True, "options": {}}, pos, 3.4,
                 notes=note, notesInFlow=True)

def webhook(f, path, pos):
    return f.add("Webhook", "n8n-nodes-base.webhook", {"httpMethod": "POST", "path": path, "responseMode": "responseNode", "options": {}}, pos, 2,
                 webhookId=sid(f.key, "webhook"))

def verify_node(f, pos):
    return f.add("Verify token", "n8n-nodes-base.httpRequest", {
        "method": "POST", "url": "=https://identitytoolkit.googleapis.com/v1/accounts:lookup?key={{ $json.firebaseApiKey }}",
        "sendBody": True, "specifyBody": "json",
        "jsonBody": "={{ JSON.stringify({ idToken: String(($json.headers && $json.headers.authorization) || '').replace(/^Bearer\\s+/i, '') }) }}",
        "options": NEVER_ERROR}, pos, 4.2)

def if_node(f, name, expr, pos):
    return f.add(name, "n8n-nodes-base.if", {"conditions": {
        "options": {"caseSensitive": True, "leftValue": "", "typeValidation": "strict", "version": 2},
        "conditions": [{"id": sid(f.key, name + "c"), "leftValue": expr, "rightValue": True, "operator": {"type": "boolean", "operation": "true", "singleValue": True}}],
        "combinator": "and"}, "options": {}}, pos, 2.2)

def respond(f, name, pos):
    return f.add(name, "n8n-nodes-base.respondToWebhook", {"respondWith": "json", "responseBody": "={{ $json.response }}",
                 "options": {"responseCode": "={{ $json.httpStatus }}"}}, pos, 1.1)

def fs_get(f, name, path_expr, pos):
    return f.add(name, "n8n-nodes-base.httpRequest", {"url": FS + path_expr, "authentication": "predefinedCredentialType",
                 "nodeCredentialType": "googleApi", "options": NEVER_ERROR},
                 pos, 4.2, credentials=GOOGLE)

def fs_post(f, name, path_expr, body_expr, pos):
    return f.add(name, "n8n-nodes-base.httpRequest", {"method": "POST", "url": FS + path_expr, "authentication": "predefinedCredentialType",
                 "nodeCredentialType": "googleApi", "sendBody": True, "specifyBody": "json", "jsonBody": body_expr,
                 "options": NEVER_ERROR}, pos, 4.2, credentials=GOOGLE)

def gemini(f, pos, name="Gemini", model_key="model", body_expr="$json.aiBody", timeout=90000):
    params = {
        "method": "POST", "url": "=https://generativelanguage.googleapis.com/v1beta/models/{{ $('Config').first().json." + model_key + " }}:generateContent",
        "sendBody": True, "specifyBody": "json", "jsonBody": "={{ JSON.stringify(" + body_expr + ") }}",
        "options": {"timeout": timeout, **NEVER_ERROR}}
    key = _LOCAL.get("geminiApiKey")
    if key:  # key written straight into the node: no credential to create or attach
        params.update({"authentication": "none", "sendHeaders": True,
                       "headerParameters": {"parameters": [{"name": "x-goog-api-key", "value": key}]}})
        return f.add(name, "n8n-nodes-base.httpRequest", params, pos, 4.2, onError="continueRegularOutput")
    params.update({"authentication": "genericCredentialType", "genericAuthType": "httpHeaderAuth"})
    return f.add(name, "n8n-nodes-base.httpRequest", params, pos, 4.2, credentials=GEMINI, onError="continueRegularOutput")

def codenode(f, name, js, pos):
    return f.add(name, "n8n-nodes-base.code", {"jsCode": js}, pos, 2)

def expense_flow(kind, title, path, prompt_file, note):
    f = Flow(kind, title)
    w = webhook(f, path, (0, 300)); c = config_node(f, (220, 300), note)
    v = verify_node(f, (440, 300)); a = codenode(f, "Auth", code("auth.js", __KIND__=kind), (660, 300))
    ok = if_node(f, "Authorized?", "={{ $json.ok }}", (880, 300)); err = respond(f, "Respond error", (1100, 440))
    pr = fs_get(f, "Load profile", "/users/{{ $('Auth').first().json.uid }}", (1100, 200))
    cats = fs_get(f, "Load categories", "/users/{{ $('Auth').first().json.uid }}/categories?pageSize=300", (1320, 200))
    bp = codenode(f, "Build prompt", code(prompt_file), (1540, 200)); cl = gemini(f, (1760, 200), model_key="voiceModel" if kind == "voice" else "model", timeout=40000 if kind == "voice" else 55000)
    it = codenode(f, "Interpret", code("interpret.js", __KIND__=kind), (1980, 200))
    sv = if_node(f, "Save it?", "={{ $json.shouldSave }}", (2200, 200))
    cm = fs_post(f, "Commit expense + month totals", ":commit", "={{ JSON.stringify($json.commit) }}", (2420, 100))
    fin = codenode(f, "Finalize", code("finalize_expense.js"), (2640, 100)); rs = respond(f, "Respond", (2860, 200))
    f.chain(w, c, v, a, ok); f.link(ok, err, 1)
    # If Gemini is overloaded (429/5xx), try the fallback model once before giving up.
    busy = if_node(f, "Gemini busy?", "={{ !$json.statusCode || [429, 500, 502, 503, 504].includes($json.statusCode) }}", (1870, 320))
    cl2 = gemini(f, (1980, 420), "Gemini fallback", "fallbackModel", "$('Build prompt').first().json.aiBody", timeout=15000 if kind == "voice" else 30000)
    if kind == "voice":
        f.link(ok, bp, 0)  # no Firestore reads: the app sends categories and currency
        f.nodes = [n for n in f.nodes if n["name"] not in (pr, cats)]
    else:
        f.link(ok, pr, 0); f.chain(pr, cats, bp)
    f.chain(bp, cl, busy); f.link(busy, cl2, 0); f.link(busy, it, 1); f.link(cl2, it)
    f.chain(it, sv); f.link(sv, cm, 0); f.link(sv, rs, 1); f.chain(cm, fin, rs)
    return f

def report_flow():
    f = Flow("report", "SafeSpend – Monthly report")
    w = webhook(f, "safespend/report", (0, 500))
    sch = f.add("Monthly schedule", "n8n-nodes-base.scheduleTrigger", {"rule": {"interval": [{"field": "months", "monthsInterval": 1, "triggerAtDayOfMonth": 1, "triggerAtHour": 3, "triggerAtMinute": 0}]}}, (0, 100), 1.2)
    c = config_node(f, (220, 300), "Edit these values first. Used by every node (via $('Config')).")
    isw = if_node(f, "From the app?", "={{ !!$json.headers }}", (440, 300))
    v = verify_node(f, (660, 400)); a = codenode(f, "Auth", code("auth.js", __KIND__="report"), (880, 400))
    ok = if_node(f, "Authorized?", "={{ $json.ok }}", (1100, 400)); err = respond(f, "Respond error", (1320, 560))
    ex = codenode(f, "One user", code("report_expand.js"), (1320, 400))
    lu = f.add("List users", "n8n-nodes-base.httpRequest", {"url": FS + "/users?pageSize=300&mask.fieldPaths=email", "authentication": "predefinedCredentialType",
               "nodeCredentialType": "googleApi", "options": {"response": {"response": {"fullResponse": True, "neverError": True}},
               "pagination": {"pagination": {"paginationMode": "updateAParameterInEachRequest", "parameters": {"parameters": [{"type": "qs", "name": "pageToken", "value": "={{ $response.body.nextPageToken }}"}]},
                              "paginationCompleteWhen": "other", "completeExpression": "={{ !$response.body.nextPageToken }}", "limitPagesFetched": False}}}}, (660, 200), 4.2, credentials=GOOGLE)
    ui = codenode(f, "Users to items", code("report_users.js"), (880, 200))
    loop = f.add("Loop users", "n8n-nodes-base.splitInBatches", {"batchSize": 1, "options": {}}, (1540, 300), 3)
    # The item that arrives here is the user being processed. Later nodes read it from this node
    # (an explicit copy of $input) instead of reaching back into the Loop node.
    cu = codenode(f, "Current user", "return $input.all().slice(0, 1).map((i) => ({ json: { ...i.json } }));", (1650, 300))
    U = "/users/{{ $('Current user').first().json.uid }}"
    g1 = fs_get(f, "Get profile", U, (1760, 300))
    g2 = fs_get(f, "Get budget", U + "/budgets/{{ $('Current user').first().json.monthKey }}", (1980, 300))
    g3 = fs_get(f, "Get stats", U + "/monthStats/{{ $('Current user').first().json.monthKey }}", (2200, 300))
    g4 = fs_get(f, "Get previous stats", U + "/monthStats/{{ $('Current user').first().json.prevMonthKey }}", (2420, 300))
    q = fs_post(f, "Query expenses", U + ":runQuery", "={{ JSON.stringify({ structuredQuery: { from: [{ collectionId: 'expenses' }], where: { fieldFilter: { field: { fieldPath: 'monthKey' }, op: 'EQUAL', value: { stringValue: $('Current user').first().json.monthKey } } }, limit: 2000 } }) }}", (2640, 300))
    cd = if_node(f, "App sent data?", "={{ !!$('Current user').first().json.data }}", (1650, 100))
    comp = codenode(f, "Compute report", code("report_compute.js"), (2860, 300))
    sk = if_node(f, "Skip?", "={{ $json.skip }}", (3080, 300))
    cl = gemini(f, (3300, 400)); bs = codenode(f, "Build summary", code("report_build.js"), (3520, 400))
    sv = if_node(f, "Save in Firestore?", "={{ !$('Current user').first().json.data }}", (3630, 400))
    cm = fs_post(f, "Save summary", ":commit", "={{ JSON.stringify($('Build summary').first().json.commit) }}", (3740, 400))
    res = codenode(f, "Result", code("report_result.js"), (3960, 300))
    via = if_node(f, "Answer the app?", "={{ $json.via === 'webhook' }}", (4180, 300)); rs = respond(f, "Respond", (4400, 200))
    f.link(w, c); f.link(sch, c); f.link(c, isw)
    f.link(isw, v, 0); f.link(isw, lu, 1)
    f.chain(v, a, ok); f.link(ok, ex, 0); f.link(ok, err, 1); f.link(ex, loop)
    f.chain(lu, ui); f.link(ui, loop)
    f.link(loop, cu, 1); f.link(cu, cd); f.link(cd, comp, 0); f.link(cd, g1, 1); f.chain(g1, g2, g3, g4, q, comp, sk)
    f.link(sk, res, 0); f.link(sk, cl, 1); f.chain(cl, bs, sv); f.link(sv, cm, 0); f.link(sv, res, 1); f.link(cm, res)
    f.link(res, via); f.link(via, rs, 0); f.link(via, loop, 1); f.link(rs, loop)
    return f

FLOWS = [
    (expense_flow("voice", "SafeSpend – Voice expense", "safespend/voice", "prompt_voice.js",
                  "Edit these values first. The app POSTs the speech-to-text transcript here."), ["safespend"], "safespend-voice-expense.json"),
    (expense_flow("receipt", "SafeSpend – Receipt scanner", "safespend/receipt", "prompt_receipt.js",
                  "Edit these values first. The app POSTs a base64 photo/PDF of a receipt here."), ["safespend"], "safespend-receipt-scanner.json"),
    (report_flow(), ["safespend"], "safespend-monthly-report.json"),
]
if __name__ == "__main__":
    OUT.mkdir(exist_ok=True)
    for flow, tags, fname in FLOWS:
        (OUT / fname).write_text(json.dumps(flow.json(tags), indent=2, ensure_ascii=False) + "\n")
        print("wrote", fname, len(flow.nodes), "nodes")
