// Search, token indexing, batch/sample sorting, and filtering for the SpinLab Web Library.

const NATURAL_COLLATOR = new Intl.Collator(undefined, {
  numeric: true,
  sensitivity: "base",
});

const SEARCH_TOKEN_RE = /[\p{L}\p{N}]+/gu;
const SEARCH_COMPACT_RE = /[^\p{L}\p{N}]+/gu;
const SEARCH_QUERY_TOKEN_RE = /-?\d+(?:\.\d+)?(?:[°µμ]?[a-z]+)?|[\p{L}\p{N}]+/gu;
const NUMERIC_QUERY_RE = /^(-?\d+(?:\.\d+)?)([a-z°µμ]+)$/i;
const NUMERIC_VALUE_RE = /^(-?\d+(?:\.\d+)?)\s*(?:([°µμ]))?\s*([\p{L}]+)$/u;
const MODIFIER_QUERY_TOKENS = new Set(["o", "b", "hf"]);

function sampleCharts(sampleKey) {
  return (state.report?.assetStats?.assets ?? []).filter((asset) => asset.sample_key === sampleKey);
}

function naturalCompare(left, right) {
  return NATURAL_COLLATOR.compare(String(left ?? ""), String(right ?? ""));
}

function naturalSort(values) {
  return [...values].sort(naturalCompare);
}

function inferSeriesToken(value) {
  const text = String(value ?? "").normalize("NFKC").trim();
  if (!text) {
    return "";
  }
  const token = text.match(/^[\p{L}\p{N}]+/u)?.[0] ?? "";
  if (!token) {
    return "";
  }
  const prefix = token.match(/^[\p{L}]+/u)?.[0] ?? "";
  if (prefix.length < 2 || (prefix.length > 4 && !/\d/.test(token))) {
    return "";
  }
  return prefix.toUpperCase();
}

function sampleSeriesValues(sample) {
  return naturalSort(
    Array.from(
      new Set([
        inferSeriesToken(sample.id),
        inferSeriesToken(sample.batchId),
        inferSeriesToken(sample.displayName),
      ].filter(Boolean)),
    ),
  );
}

function librarySeriesValues(samples) {
  const values = new Set();
  for (const sample of samples) {
    for (const series of sampleSeriesValues(sample)) {
      values.add(series);
    }
  }
  return naturalSort(Array.from(values));
}

function normalizeSearchText(value) {
  return String(value ?? "").normalize("NFKC").toLowerCase();
}

function tokenizeSearchText(value) {
  return normalizeSearchText(value).match(SEARCH_TOKEN_RE) ?? [];
}

function compactSearchToken(value) {
  return normalizeSearchText(value).replace(SEARCH_COMPACT_RE, "");
}

function addSearchText(index, value) {
  if (value == null) {
    return;
  }
  const text = String(value);
  if (!text) {
    return;
  }
  for (const token of tokenizeSearchText(text)) {
    index.tokens.add(token);
  }
  const compact = compactSearchToken(text);
  if (compact) {
    index.tokens.add(compact);
  }
}

function addStructuredIdentifierTokens(index, value) {
  const text = String(value ?? "").normalize("NFKC").trim();
  if (!text) {
    return;
  }

  const segments = text
    .split(/[|/]+/)
    .map((segment) => segment.trim())
    .filter(Boolean);
  if (segments.length === 0) {
    return;
  }

  for (const segment of segments) {
    addSearchText(index, segment);
    index.modifierTokens.add(tokenizeSearchText(segment)[0] ?? compactSearchToken(segment));
  }

  const tail = segments.slice(-2);
  if (tail.length === 2) {
    const material = tail[0].replace(/[^A-Za-z]+/g, "").toLowerCase();
    const orientation = tail[1].replace(/[^A-Za-z0-9]+/g, "").toLowerCase();
    if (material && orientation) {
      index.tokens.add(`${material}${orientation}`);
    }
  }

  const compact = compactSearchToken(text);
  if (compact) {
    index.tokens.add(compact);
  }
}

function normalizeNumericUnit(unit) {
  const compact = normalizeSearchText(unit).replace(/[^a-z0-9°]+/g, "").replace(/^°/, "");
  if (compact === "ps" || compact === "p") {
    return "p";
  }
  if (compact === "c" || compact === "°c") {
    return "c";
  }
  if (compact === "mt") {
    return "mt";
  }
  if (compact === "mj") {
    return "mj";
  }
  return compact;
}

function parseNumericValue(value) {
  const text = normalizeSearchText(value).trim();
  if (!text) {
    return null;
  }
  const match = text.match(NUMERIC_VALUE_RE);
  if (!match) {
    return null;
  }
  const amount = Number.parseFloat(match[1]);
  if (!Number.isFinite(amount)) {
    return null;
  }
  const unit = normalizeNumericUnit(`${match[2] ?? ""}${match[3] ?? ""}`);
  if (!unit) {
    return null;
  }
  return { amount, unit };
}

function parseSearchToken(token) {
  const normalized = normalizeSearchText(token);
  const match = normalized.match(NUMERIC_QUERY_RE);
  if (!match) {
    return { kind: "text", token: normalized };
  }
  const amount = Number.parseFloat(match[1]);
  if (!Number.isFinite(amount)) {
    return { kind: "text", token: normalized };
  }
  return {
    kind: "numeric",
    amount,
    unit: normalizeNumericUnit(match[2]),
    token: normalized,
  };
}

function sampleSearchIndex(sample) {
  const index = {
    tokens: new Set(),
    modifierTokens: new Set(),
    numericValues: [],
  };
  const textValues = [
    sample.displayName,
    sample.id,
    sample.batchId,
    sample.substrateRaw,
    sample.substrateDisplay,
    ...(sample.substrateTokens ?? []),
    ...(sample.substrateTags ?? []),
  ];

  addStructuredIdentifierTokens(index, sample.id);
  addStructuredIdentifierTokens(index, sample.batchId);
  addStructuredIdentifierTokens(index, sample.displayName);

  const metadataEntries = Array.isArray(sample.orderedMetadata) && sample.orderedMetadata.length
    ? sample.orderedMetadata.map((item) => [item.key, item.value])
    : Object.entries(sample.metadata ?? {});

  for (const [key, value] of metadataEntries) {
    textValues.push(key, value);
  }
  for (const [key, value] of Object.entries(sample.metadata ?? {})) {
    textValues.push(key, value);
  }
  for (const [key, value] of Object.entries(sample.numericDisplay ?? {})) {
    textValues.push(key, value);
  }
  for (const [key, value] of Object.entries(sample.numericTags ?? {})) {
    textValues.push(key, value);
  }

  for (const value of textValues) {
    addSearchText(index, value);
    const parsed = parseNumericValue(value);
    if (parsed) {
      index.numericValues.push(parsed);
    }
  }

  return index;
}

function sampleSearchQueryMatches(sample, search) {
  const query = search.trim();
  if (!query) {
    return true;
  }

  const { numericValues, modifierTokens, tokens } = sampleSearchIndex(sample);
  const queryTokens = query.match(SEARCH_QUERY_TOKEN_RE) ?? [];
  if (queryTokens.length === 0) {
    return true;
  }

  for (const rawToken of queryTokens) {
    const token = parseSearchToken(rawToken);
    if (token.kind === "numeric") {
      const isFuzzyUnit = token.unit === "mt" || token.unit === "mj";
      const numericMatch = numericValues.some((candidate) => {
        if (candidate.unit !== token.unit) {
          return false;
        }
        return isFuzzyUnit
          ? Math.abs(candidate.amount - token.amount) <= 8
          : candidate.amount === token.amount;
      });
      if (numericMatch) {
        continue;
      }
    }

    if (MODIFIER_QUERY_TOKENS.has(token.token)) {
      if (!modifierTokens.has(token.token)) {
        return false;
      }
      continue;
    }

    if (!tokens.has(token.token)) {
      return false;
    }
  }

  return true;
}

// Same order as the SpinLab Library: batch prefix, batch number, suffix, then the substrate line.
function batchSortKey(batchId) {
  const match = /^([A-Za-z]+)(\d+)?(.*)$/.exec(String(batchId ?? "").trim());
  if (!match) return { prefix: String(batchId ?? ""), number: null, suffix: "" };
  return { prefix: match[1].toUpperCase(), number: match[2] === undefined ? null : Number(match[2]), suffix: match[3] };
}

function compareBatchIds(left, right) {
  const a = batchSortKey(left);
  const b = batchSortKey(right);
  if (a.prefix !== b.prefix) return a.prefix < b.prefix ? -1 : 1;
  if (a.number !== null && b.number !== null && a.number !== b.number) return a.number - b.number;
  if (a.number !== null && b.number === null) return -1;
  if (a.number === null && b.number !== null) return 1;
  if (a.suffix !== b.suffix) return a.suffix < b.suffix ? -1 : 1;
  return naturalCompare(left, right);
}

function compareSamples(left, right) {
  const batchCompare = compareBatchIds(left.batchId, right.batchId);
  if (batchCompare !== 0) {
    return batchCompare;
  }
  return naturalCompare(left.displayName, right.displayName);
}

function sampleMatchesSeries(sample, series) {
  if (series === "all") {
    return true;
  }
  return sampleSeriesValues(sample).includes(series);
}

function sampleMatches(sample) {
  const search = state.filters.search.trim();
  const charts = sampleCharts(sample.id);
  if (!sampleMatchesSeries(sample, state.filters.series)) {
    return false;
  }
  if (state.filters.batch !== "all" && sample.batchId !== state.filters.batch) {
    return false;
  }
  if (state.filters.assetGroup !== "all" && !charts.some((asset) => asset.sample_key === state.filters.assetGroup)) {
    return false;
  }
  if (state.filters.chartsOnly && charts.length === 0) {
    return false;
  }
  if (!search) {
    return true;
  }
  return sampleSearchQueryMatches(sample, search);
}

function filteredSamples() {
  return (state.library?.samples ?? []).filter(sampleMatches).sort(compareSamples);
}

function assetGroupLabel(sampleKey) {
  if (!sampleKey) {
    return "Orphan charts";
  }
  if (sampleKey === "multi-sample") {
    return "Multi-sample charts";
  }
  return sampleKey;
}
