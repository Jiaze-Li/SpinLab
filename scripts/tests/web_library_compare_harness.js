// Test-only page script (never shipped). check_web_library_page.py injects it into a copy of the exported
// index.html, after the template scripts, so it exercises the same code the phone loads. It records what the
// page really showed into #check-result as JSON.
(function () {
  const result = { stage: "start", errors: [] };
  const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
  const q = (selector) => document.querySelector(selector);
  const count = (selector) => document.querySelectorAll(selector).length;

  function waitForReady() {
    const isReady = () => Boolean(q("#sample-list .sample-group-head") && q("#library-mode-tabs [data-library-mode]"));
    const isFailed = () => (q("#status")?.textContent || "").includes("Load failed");
    if (isReady() || isFailed()) return Promise.resolve();
    return new Promise((resolve) => {
      const observer = new MutationObserver(() => {
        if (isReady() || isFailed()) {
          observer.disconnect();
          resolve();
        }
      });
      observer.observe(document.body, { childList: true, subtree: true, characterData: true });
    });
  }

  function snapshot() {
    return {
      groupHeads: count("#sample-list .sample-group-head"),
      groupNames: Array.from(document.querySelectorAll("#sample-list .sample-group-name")).map((n) => n.textContent.trim()),
      flatRows: count("#sample-list > .sample-row:not(.pending)"),
      compareGroupCards: count("#sample-list .compare-group-card"),
      compareEmpty: count("#sample-list .compare-empty"),
      compareGroupRows: count("#sample-list [data-compare-sample-key]"),
      overviewCards: count(".compare-overview-card"),
      modeTabs: count("#library-mode-tabs [data-library-mode]"),
      activeMode: (q("#library-mode-tabs .library-mode-tab.active") || {}).dataset?.libraryMode ?? null,
      syncText: (q("#sync-info") || {}).textContent ?? null,
      syncHidden: q("#sync-info") ? q("#sync-info").hidden : null,
      newSampleHref: (q("a.new-sample-link") || {}).getAttribute?.("href") ?? null,
    };
  }

  // Raw markup of the regions the template scripts draw; used to prove a refactor leaves the page identical.
  function markup() {
    const html = (selector) => (q(selector) ? q(selector).innerHTML : null);
    return {
      sampleList: html("#sample-list"),
      tableCount: html("#table-count"),
      metadataBody: html("#metadata-body"),
      compareControls: html("#compare-controls"),
      chartNavPosition: html("#chart-nav-position"),
      panelTitle: html(".samples-panel .panel-head h2"),
    };
  }

  async function run() {
    window.addEventListener("error", (event) => result.errors.push(String(event.message)));
    await waitForReady();
    result.stage = "loaded";
    result.samples = snapshot();
    const compareTab = q('[data-library-mode="compare"]');
    if (compareTab) {
      compareTab.click();
      await sleep(100);
    }
    result.stage = "compare";
    result.compare = snapshot();
    const samplesTab = q('[data-library-mode="samples"]');
    if (samplesTab) {
      samplesTab.click();
      await sleep(100);
    }
    result.stage = "restored";
    result.restored = snapshot();
    // Extra interactions (markup only): open a compare group, go back to all groups, change a
    // dimension, then narrow with the shared search box.
    result.markup = { restored: markup() };
    if (compareTab) {
      compareTab.click();
      await sleep(100);
      result.markup.compare = markup();
      const card = q("#metadata-body [data-compare-group]");
      if (card) {
        card.click();
        await sleep(100);
        result.markup.group = markup();
        const back = q('[data-compare-action="all-groups"]');
        if (back) {
          back.click();
          await sleep(100);
          result.markup.allGroups = markup();
        }
      }
      const box = q('[data-compare-dimension="oxygen"]');
      if (box) {
        box.click();
        await sleep(100);
        result.markup.dimension = markup();
      }
      const search = q("#search");
      if (search) {
        search.value = "PN";
        search.dispatchEvent(new Event("input", { bubbles: true }));
        await sleep(100);
        result.markup.search = markup();
      }
    }
    result.stage = "done";
  }

  function start() {
    run()
      .catch((error) => result.errors.push(String(error && error.stack || error)))
      .finally(() => {
        const out = document.createElement("pre");
        out.id = "check-result";
        out.textContent = JSON.stringify(result);
        document.body.appendChild(out);
      });
  }

  if (document.readyState === "complete") {
    start();
  } else {
    window.addEventListener("load", start, { once: true });
  }
})();
