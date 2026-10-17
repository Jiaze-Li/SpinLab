import Foundation

/// Title semantics of the heatmap workflows (spec 06 CS-9a), built on the one shared template
/// resolver: manual Plot title > Title Template result > source default title.
///
/// Pure functions over the heatmap display state; nothing here touches scientific data.
enum HeatmapTitleResolution {

    /// Tokens the selected sample actually provides. A token without data is not offered
    /// (and resolves to nothing).
    static func tokens(
        tab: String,
        hit: WorkflowMeasurementSearchHit?,
        numericDisplay: [String: [String: String]]
    ) -> [String: String] {
        var tokens = ["tab": tab]
        guard let hit else { return tokens }
        let sample = hit.sampleBatchAndSubstrate
        if !sample.isEmpty { tokens["sample"] = sample }
        for (key, value) in numericDisplay[hit.sampleKey] ?? [:] { tokens[key] = value }
        if let temperature = hit.conditions["temperature"], !temperature.isEmpty { tokens["测试温度"] = temperature }
        return tokens
    }

    /// Tokens for the Available hint, each with its leading `#`.
    static func availableTokens(from tokens: [String: String]) -> [String] {
        let fixed = ["tab", "sample", "测试温度"]
        let numeric = tokens.keys.filter { !fixed.contains($0) }.sorted()
        return (fixed.filter { tokens[$0] != nil } + numeric).map { "#\($0)" }
    }

    /// The template's title, or "" when there is no template or it resolves to nothing.
    static func templateTitle(_ template: String, tokens: [String: String]) -> String {
        guard !template.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
        return WorkbenchTitleResolver.resolve(template: template, tokens: tokens)
    }

    /// The override the renderers should draw: the manual title, else the template result,
    /// else "" (the payload builders then use the source default title).
    static func renderTitleOverride(for state: HeatmapTabRenderState, tokens: [String: String]) -> String {
        if !state.titleOverride.isEmpty { return state.titleOverride }
        return templateTitle(state.titleTemplate, tokens: tokens)
    }
}

extension WorkbenchHeatmapControlsStore {
    /// Display state to hand to a render or save: identical to the stored state except that the
    /// title override carries the effective title. Never written back, so clearing the manual
    /// title restores the template result.
    func heatmapRenderState(_ state: HeatmapTabRenderState, hit: WorkflowMeasurementSearchHit?) -> HeatmapTabRenderState {
        var render = state
        render.titleOverride = HeatmapTitleResolution.renderTitleOverride(
            for: state,
            tokens: HeatmapTitleResolution.tokens(
                tab: heatmapTitleTabToken, hit: hit, numericDisplay: cachedSampleNumericDisplay))
        return render
    }
}
