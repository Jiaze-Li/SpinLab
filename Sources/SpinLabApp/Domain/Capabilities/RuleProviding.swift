import Foundation

protocol RuleProviding {
    @discardableResult func reloadCached() -> RuleLoader.LoadResult
    @discardableResult func bumpRuleSetVersion() -> Result<Int, Error>
}

extension RuleLoader: RuleProviding {}
