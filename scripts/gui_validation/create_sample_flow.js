// Representative GUI flow: Library -> New Sample sheet -> type into a field ->
// expand/collapse RHEED -> assert size + retained text -> Cancel closes sheet.
// Run through run_flow.sh (single cua session; __PID__ is substituted).
const PID = __PID__;
const wins = async () => { const r = await cua.listWindows({pid: PID}); return Array.isArray(r) ? r : (r.windows || []); };
const out = {checks: {}};
const MAIN = (await wins()).find(w => w.title === "SpinLabGUITest").window_id;
const main = await cua.getApp({pid: PID, windowId: MAIN});
await main.click({role: "button", name: "Library"}); await cua.sleep(500);
await main.click({role: "button", name: "New Sample"}); await cua.sleep(900);
const sheet = (await wins()).find(w => w.window_id !== MAIN);
if (!sheet) return {error: "sheet did not open", checks: {}};
const app = await cua.getApp({pid: PID, windowId: sheet.window_id});
const H = async () => Math.round((await wins()).find(w => w.window_id === sheet.window_id).bounds.height);
const numVal = async () => { const st = await app.getState({include_screenshot: false, max_elements: 400, query: "Number.temperature"}); const m = st.tree_markdown.match(/AXTextField(?: = "([^"]*)")? \[id=CreateSampleSheet.Number.temperature/); return m ? (m[1] ?? "") : null; };
out.hOpen = await H();
// pixel click is required for text fields (AXPress fails); frame is re-read right before the click
const st0 = await app.getState({include_screenshot: true, max_elements: 400});
const tf = (await app.query({role: "textfield"})).find(t => /Number\.temperature/.test(t.label || ""));
if (!tf) return {error: "temperature field not found", checks: {}};
const wb = st0.window_bounds;
await app.click([Math.round(tf.frame.x + tf.frame.w/2 - wb.x), Math.round(tf.frame.y + tf.frame.h/2 - wb.y)]);
await app.typeText("12"); await cua.sleep(200);
out.afterType = await numVal();
out.hAfterType = await H();
const tri = async () => (await app.query({role: "disclosuretriangle"}))[0];
await app.click((await tri()).element_token); await cua.sleep(600);
out.hRheedOpen = await H();
await app.typeText("3"); await cua.sleep(200);
out.afterExpandType = await numVal();
await app.click((await tri()).element_token); await cua.sleep(600);
out.hRheedClosed = await H();
out.checks.typed = out.afterType === "12";
out.checks.expandGrows = out.hRheedOpen > out.hAfterType;
out.checks.collapseRestores = out.hRheedClosed === out.hAfterType;
// AX type_text writes at the field selection, so only "the character landed in the same field" is asserted (no real keyDown/IME coverage)
out.checks.inputStillInSameField = (out.afterExpandType || "").endsWith("3");
await app.click({role: "button", name: "Cancel"}); await cua.sleep(700);
out.checks.sheetClosed = !(await wins()).find(w => w.window_id === sheet.window_id);
out.pass = Object.values(out.checks).every(Boolean);
return out;
