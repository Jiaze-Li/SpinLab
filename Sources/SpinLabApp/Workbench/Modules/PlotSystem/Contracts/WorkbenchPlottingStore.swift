import SwiftUI

// MARK: - WorkbenchPlottingStore

/// 所有 workflow workspace store 必须实现的 canvas 交互合约。
/// 确保任何新 workflow 都能接入 WorkbenchPlotCanvas 的拖拽、行内编辑等交互。
@MainActor
protocol WorkbenchPlottingStore: AnyObject {
    /// 用户拖拽图例后回调，point 为 plot 归一化坐标（x,y ∈ [0,1]，Y-up）。
    func updateLegendPoint(_ point: CGPoint)
    /// 用户行内编辑图表标题后回调。
    func updatePlotTitle(_ title: String)
    /// 用户行内编辑 X 轴标签后回调。
    func updateXAxisLabel(_ label: String)
    /// 用户行内编辑 Y 轴标签后回调。
    func updateYAxisLabel(_ label: String)
    /// 用户重命名图例标签后回调。key 为稳定系列身份键（sourceRef / sampleID / index fallback）。
    func updateSeriesLabel(identityKey: String, newLabel: String)
    /// 用户点击点位圆点后切换 point label 显隐。key 为 sampleID 或整数字符串。
    func togglePointLabelVisibility(sampleID: String, pointIndex: Int)
    /// Re-render the active chart at the given pixel scale and return PNG data.
    func renderPNGAtScale(_ scale: CGFloat) -> Data?
}

// MARK: - WorkbenchGlobalPlotDefaultsProviding

/// Shared plot defaults used by the Cartesian render path.
/// Heatmap workflows do not need to own this state.
@MainActor
protocol WorkbenchGlobalPlotDefaultsProviding: AnyObject {
    var globalPlotDefaults: [String: String] { get set }
}

// MARK: - WorkbenchCartesianXYPlottingStore

/// Cartesian XY-specific shared plot state.
///
/// Heatmap workflows should not conform to this protocol. It exists so the
/// shell-level XY controls stay tied to the Cartesian render path rather than
/// the generic workbench surface.
@MainActor
protocol WorkbenchCartesianXYPlottingStore: WorkbenchPlottingStore, WorkbenchGlobalPlotDefaultsProviding {
    /// 是否显示网格线。
    var showPlotGrid: Bool { get set }
    /// 全局序列渲染模式覆盖。
    var seriesRenderMode: SeriesRenderMode { get set }
    /// Chart style overrides (font sizes, tick density).
    var chartStyleOverrides: [String: String] { get set }
}

extension WorkbenchPlottingStore {
    func updateLegendPoint(_ point: CGPoint) {}
    func updatePlotTitle(_ title: String) {}
    func updateXAxisLabel(_ label: String) {}
    func updateYAxisLabel(_ label: String) {}
    func updateSeriesLabel(identityKey: String, newLabel: String) {}
    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {}
    func renderPNGAtScale(_ scale: CGFloat) -> Data? { nil }
}
