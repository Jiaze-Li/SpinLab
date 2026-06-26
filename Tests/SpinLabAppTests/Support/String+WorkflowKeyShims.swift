import Foundation
@testable import SpinLabApp

// Test-only shim: static String members matching WorkflowKey rawValues
// so tests can keep using `for: .ahe`, `for: .threeOmega`, etc. with String parameters.
extension String {
    static let ahe = WorkflowKey.ahe.rawValue
    static let threeOmega = WorkflowKey.threeOmega.rawValue
    static let xyRotation = WorkflowKey.xyRotation.rawValue
    static let iv = WorkflowKey.iv.rawValue
    static let rsm = WorkflowKey.rsm.rawValue
    static let rt = WorkflowKey.rt.rawValue
    static let mr = WorkflowKey.mr.rawValue
}
