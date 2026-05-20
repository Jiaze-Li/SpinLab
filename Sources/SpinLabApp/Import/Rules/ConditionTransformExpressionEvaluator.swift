import Foundation

enum ConditionTransformExpressionError: Error, Equatable {
    case empty
    case unexpectedCharacter(Character)
    case expectedNumber
    case trailingInput
    case divisionByZero
}

struct ConditionTransformExpressionEvaluator {
    func evaluate(_ expression: String, value: Double) throws -> Double {
        let trimmed = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return value }
        var parser = Parser(input: trimmed, implicitInput: value)
        let result = try parser.parseExpression()
        guard parser.isAtEnd else { throw ConditionTransformExpressionError.trailingInput }
        return result
    }
}

private struct Parser {
    private let chars: [Character]
    private var pos: Int = 0
    private let implicitInput: Double

    var isAtEnd: Bool { pos >= chars.count }

    init(input: String, implicitInput: Double) {
        self.chars = Array(input)
        self.implicitInput = implicitInput
    }

    mutating func parseExpression() throws -> Double {
        // additive: term (('+' | '-') term)*
        var result = try parseTerm()
        while !isAtEnd {
            let ch = chars[pos]
            if ch == "+" {
                pos += 1
                result += try parseTerm()
            } else if ch == "-" {
                pos += 1
                result -= try parseTerm()
            } else {
                break
            }
        }
        return result
    }

    mutating func parseTerm() throws -> Double {
        // multiplicative: factor (('*' | '/') factor)*
        var result = try parseFactor()
        while !isAtEnd {
            let ch = chars[pos]
            if ch == "*" {
                pos += 1
                result *= try parseFactor()
            } else if ch == "/" {
                pos += 1
                let divisor = try parseFactor()
                guard divisor != 0 else { throw ConditionTransformExpressionError.divisionByZero }
                result /= divisor
            } else {
                break
            }
        }
        return result
    }

    mutating func parseFactor() throws -> Double {
        guard !isAtEnd else { throw ConditionTransformExpressionError.expectedNumber }
        let ch = chars[pos]
        // Implicit input: if the first factor is an operator (+/-/*//), insert implicit input
        if pos == 0, ch == "+" || ch == "-" || ch == "*" || ch == "/" {
            return implicitInput
        }
        // Numeric literal with optional leading minus
        if ch.isNumber || (ch == "-" && pos + 1 < chars.count && chars[pos + 1].isNumber) {
            return try parseNumber()
        }
        throw ConditionTransformExpressionError.unexpectedCharacter(ch)
    }

    mutating func parseNumber() throws -> Double {
        var start = pos
        if chars[pos] == "-" { pos += 1 }
        guard pos < chars.count, chars[pos].isNumber else {
            pos = start
            throw ConditionTransformExpressionError.expectedNumber
        }
        while pos < chars.count, chars[pos].isNumber { pos += 1 }
        if pos < chars.count, chars[pos] == "." {
            pos += 1
            while pos < chars.count, chars[pos].isNumber { pos += 1 }
        }
        let slice = String(chars[start..<pos])
        guard let value = Double(slice) else { throw ConditionTransformExpressionError.expectedNumber }
        return value
    }
}
