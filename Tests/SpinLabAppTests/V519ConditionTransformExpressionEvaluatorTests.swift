import Foundation
import Testing
@testable import SpinLabApp

@Suite("V5.1.9 ConditionTransformExpressionEvaluator")
struct V519ConditionTransformExpressionEvaluatorTests {

    private let evaluator = ConditionTransformExpressionEvaluator()

    @Test("+ expression adds to input value")
    func plusExpressionAddsToInputValue() throws {
        let result = try evaluator.evaluate("+273", value: 27)
        #expect(result == 300)
    }

    @Test("- expression subtracts from input value")
    func minusExpressionSubtractsFromInputValue() throws {
        let result = try evaluator.evaluate("-273", value: 100)
        #expect(result == -173)
    }

    @Test("* expression scales input value")
    func multiplyExpressionScalesInputValue() throws {
        let result = try evaluator.evaluate("*0.001", value: 2310)
        #expect(abs(result - 2.31) < 1e-10)
    }

    @Test("*+expression: multiply then add respects implicit input and precedence")
    func multiplyThenAddExpressionRespectsImplicitInput() throws {
        let result = try evaluator.evaluate("*1000+5", value: 2.31)
        #expect(abs(result - 2315) < 1e-6)
    }

    @Test("/- expression: division then subtract evaluates")
    func divisionThenSubtractExpressionEvaluates() throws {
        let result = try evaluator.evaluate("/1000-2", value: 5000)
        #expect(result == 3)
    }

    @Test("operator precedence: * before +")
    func operatorPrecedenceMultipliesBeforeAdding() throws {
        // +2*3 with value 10 → 10 + (2*3) = 16
        let result = try evaluator.evaluate("+2*3", value: 10)
        #expect(result == 16)
    }

    @Test("empty expression returns input value")
    func emptyExpressionReturnsInputValue() throws {
        let result = try evaluator.evaluate("", value: 42)
        #expect(result == 42)
    }

    @Test("whitespace-only expression returns input value")
    func whitespaceExpressionReturnsInputValue() throws {
        let result = try evaluator.evaluate("   ", value: 7)
        #expect(result == 7)
    }

    @Test("double operator throws unexpectedCharacter")
    func invalidDoubleOperatorThrows() throws {
        #expect(throws: ConditionTransformExpressionError.self) {
            _ = try evaluator.evaluate("**2", value: 5)
        }
    }

    @Test("trailing non-numeric characters throw trailingInput")
    func trailingCharactersThrow() throws {
        #expect(throws: ConditionTransformExpressionError.trailingInput) {
            _ = try evaluator.evaluate("*1000abc", value: 1)
        }
    }

    @Test("division by zero throws divisionByZero")
    func divisionByZeroThrows() throws {
        #expect(throws: ConditionTransformExpressionError.divisionByZero) {
            _ = try evaluator.evaluate("/0", value: 100)
        }
    }
}
