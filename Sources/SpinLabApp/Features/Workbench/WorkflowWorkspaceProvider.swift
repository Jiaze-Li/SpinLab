import SwiftUI

/// Marker protocol for all per-workflow workspace views.
///
/// Each workflow (AHE, RT, 3W …) provides one concrete conforming view.
/// `WorkbenchView` never references concrete workspace types directly —
/// it resolves the correct view through `WorkflowWorkspaceRegistry`.
///
/// ## Shell regions
/// Every workspace view is expected to own the following UI regions
/// (layout and ordering within each region are up to the concrete view):
///
/// | Region          | Purpose                                          |
/// |-----------------|--------------------------------------------------|
/// | `queryBar`      | Workflow search input + library-root label       |
/// | `actionBar`     | Primary action buttons (search, plot, clear …)   |
/// | `statusArea`    | Progress indicators and status messages          |
/// | `plotCanvas`    | Rendered chart image                             |
/// | `plotControls`  | Axis / style / legend controls                   |
/// | `tracePanel`    | Last-run trace details                           |
/// | `resultsList`   | Selectable measurement hit rows                  |
protocol WorkflowWorkspaceProvider: View {}
