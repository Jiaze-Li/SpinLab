import SwiftUI

// MARK: - WorkbenchPlottingStore

/// 所有 workflow workspace store 必须实现的 canvas 交互合约。
/// 确保任何新 workflow 都能接入 WorkbenchPlotCanvas 的拖拽、行内编辑等交互。
@MainActor
protocol WorkbenchPlottingStore: AnyObject {
    /// 是否显示网格线。
    var showPlotGrid: Bool { get set }
    /// 全局序列渲染模式覆盖。
    var seriesRenderMode: SeriesRenderMode { get set }
    /// Chart style overrides (font sizes, tick density).
    var chartStyleOverrides: [String: String] { get set }
    /// 最近一次运行的 trace（nil = 尚未运行）。
    var currentRunTrace: WorkbenchRunTraceProjection? { get }
    /// 用户拖拽图例后回调，point 为 plot 归一化坐标（x,y ∈ [0,1]，Y-up）。
    func updateLegendPoint(_ point: CGPoint)
    /// 用户行内编辑图表标题后回调。
    func updatePlotTitle(_ title: String)
    /// 用户行内编辑 X 轴标签后回调。
    func updateXAxisLabel(_ label: String)
    /// 用户行内编辑 Y 轴标签后回调。
    func updateYAxisLabel(_ label: String)
    /// 用户重命名图例标签后回调。key 为 sampleID 或整数字符串（无 sampleID 的 workflow）。
    func updateSeriesLabel(sampleID: String, newLabel: String)
    /// 用户点击点位圆点后切换 point label 显隐。key 为 sampleID 或整数字符串。
    func togglePointLabelVisibility(sampleID: String, pointIndex: Int)
    /// Re-render the active chart at the given pixel scale and return PNG data.
    func renderPNGAtScale(_ scale: CGFloat) -> Data?
}

extension WorkbenchPlottingStore {
    func togglePointLabelVisibility(sampleID: String, pointIndex: Int) {}
    func renderPNGAtScale(_ scale: CGFloat) -> Data? { nil }
}
