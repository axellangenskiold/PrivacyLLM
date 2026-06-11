import Foundation

// Local utility tools (TL-3): useful on their own and a safe way to validate
// tool calling before anything that touches the network exists.

nonisolated struct DateTimeTool: LocalTool {
    var spec: ToolSpec {
        ToolSpec(
            name: "current_datetime",
            summary: "Returns the current date and time on the user's device, including weekday and timezone.",
            parametersJSONSchema: #"{"type":"object","properties":{},"required":[]}"#,
            causesEgress: false
        )
    }

    func execute(argumentsJSON: String) async -> ToolOutput {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE yyyy-MM-dd HH:mm zzz"
        return ToolOutput(content: formatter.string(from: .now))
    }
}

nonisolated struct CalculatorTool: LocalTool {
    private struct Arguments: Decodable {
        var expression: String
    }

    var spec: ToolSpec {
        ToolSpec(
            name: "calculate",
            summary: "Evaluates an arithmetic expression with + - * / % ^ and parentheses, e.g. \"(12.5 * 4) / 3\".",
            parametersJSONSchema: #"{"type":"object","properties":{"expression":{"type":"string","description":"The arithmetic expression to evaluate"}},"required":["expression"]}"#,
            causesEgress: false
        )
    }

    func execute(argumentsJSON: String) async -> ToolOutput {
        guard let arguments = decodeArguments(Arguments.self, from: argumentsJSON) else {
            return ToolOutput(content: "Missing \"expression\" argument.", isError: true)
        }
        do {
            let value = try ExpressionEvaluator.evaluate(arguments.expression)
            let formatted = value == value.rounded() && abs(value) < 1e15
                ? String(format: "%.0f", value)
                : String(value)
            return ToolOutput(content: "\(arguments.expression) = \(formatted)")
        } catch {
            return ToolOutput(content: "Could not evaluate \"\(arguments.expression)\": \(error)", isError: true)
        }
    }
}

/// Tiny recursive-descent arithmetic evaluator. Deliberately not NSExpression,
/// which crashes the process on malformed input.
nonisolated enum ExpressionEvaluator {
    enum EvaluationError: Error, CustomStringConvertible {
        case unexpectedCharacter(Character)
        case unexpectedEnd
        case divisionByZero

        var description: String {
            switch self {
            case .unexpectedCharacter(let character): "unexpected character '\(character)'"
            case .unexpectedEnd: "incomplete expression"
            case .divisionByZero: "division by zero"
            }
        }
    }

    static func evaluate(_ expression: String) throws -> Double {
        var characters = Array(expression.filter { !$0.isWhitespace })
        var index = 0
        let value = try parseSum(&characters, &index)
        guard index == characters.count else {
            throw EvaluationError.unexpectedCharacter(characters[index])
        }
        return value
    }

    private static func parseSum(_ chars: inout [Character], _ index: inout Int) throws -> Double {
        var value = try parseProduct(&chars, &index)
        while index < chars.count, chars[index] == "+" || chars[index] == "-" {
            let op = chars[index]
            index += 1
            let rhs = try parseProduct(&chars, &index)
            value = op == "+" ? value + rhs : value - rhs
        }
        return value
    }

    private static func parseProduct(_ chars: inout [Character], _ index: inout Int) throws -> Double {
        var value = try parsePower(&chars, &index)
        while index < chars.count, chars[index] == "*" || chars[index] == "/" || chars[index] == "%" {
            let op = chars[index]
            index += 1
            let rhs = try parsePower(&chars, &index)
            switch op {
            case "*":
                value *= rhs
            case "/":
                guard rhs != 0 else { throw EvaluationError.divisionByZero }
                value /= rhs
            default:
                guard rhs != 0 else { throw EvaluationError.divisionByZero }
                value = value.truncatingRemainder(dividingBy: rhs)
            }
        }
        return value
    }

    private static func parsePower(_ chars: inout [Character], _ index: inout Int) throws -> Double {
        let base = try parseUnary(&chars, &index)
        if index < chars.count, chars[index] == "^" {
            index += 1
            let exponent = try parsePower(&chars, &index)
            return pow(base, exponent)
        }
        return base
    }

    private static func parseUnary(_ chars: inout [Character], _ index: inout Int) throws -> Double {
        if index < chars.count, chars[index] == "-" {
            index += 1
            return try -parseUnary(&chars, &index)
        }
        return try parsePrimary(&chars, &index)
    }

    private static func parsePrimary(_ chars: inout [Character], _ index: inout Int) throws -> Double {
        guard index < chars.count else { throw EvaluationError.unexpectedEnd }
        if chars[index] == "(" {
            index += 1
            let value = try parseSum(&chars, &index)
            guard index < chars.count, chars[index] == ")" else { throw EvaluationError.unexpectedEnd }
            index += 1
            return value
        }
        var digits = ""
        while index < chars.count, chars[index].isNumber || chars[index] == "." {
            digits.append(chars[index])
            index += 1
        }
        guard let value = Double(digits) else {
            throw index < chars.count
                ? EvaluationError.unexpectedCharacter(chars[index])
                : EvaluationError.unexpectedEnd
        }
        return value
    }
}

nonisolated struct UnitConversionTool: LocalTool {
    private struct Arguments: Decodable {
        var value: Double
        var from: String
        var to: String
    }

    var spec: ToolSpec {
        ToolSpec(
            name: "convert_units",
            summary: "Converts a value between units (length, mass, temperature, volume, speed, duration), e.g. value 5, from \"km\", to \"mi\".",
            parametersJSONSchema: #"{"type":"object","properties":{"value":{"type":"number"},"from":{"type":"string"},"to":{"type":"string"}},"required":["value","from","to"]}"#,
            causesEgress: false
        )
    }

    func execute(argumentsJSON: String) async -> ToolOutput {
        guard let arguments = decodeArguments(Arguments.self, from: argumentsJSON) else {
            return ToolOutput(content: "Expected arguments: value (number), from (unit), to (unit).", isError: true)
        }
        guard let fromUnit = Self.unit(for: arguments.from), let toUnit = Self.unit(for: arguments.to) else {
            return ToolOutput(content: "Unknown unit. Supported: m, km, cm, mm, mi, yd, ft, in, kg, g, mg, lb, oz, st, c, f, kelvin, l, ml, gal, qt, pt, cup, floz, kmh, mph, ms, knot, sec, min, hr.", isError: true)
        }
        guard type(of: fromUnit) == type(of: toUnit) else {
            return ToolOutput(content: "Cannot convert \(arguments.from) to \(arguments.to): different kinds of unit.", isError: true)
        }
        let converted = Measurement(value: arguments.value, unit: fromUnit).converted(to: toUnit)
        let formatted = String(format: "%g", converted.value)
        return ToolOutput(content: "\(String(format: "%g", arguments.value)) \(fromUnit.symbol) = \(formatted) \(toUnit.symbol)")
    }

    private static func unit(for raw: String) -> Dimension? {
        let key = raw.lowercased()
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "/", with: "")
        let table: [String: Dimension] = [
            "m": UnitLength.meters, "meter": UnitLength.meters, "meters": UnitLength.meters,
            "km": UnitLength.kilometers, "kilometer": UnitLength.kilometers, "kilometers": UnitLength.kilometers,
            "cm": UnitLength.centimeters, "mm": UnitLength.millimeters,
            "mi": UnitLength.miles, "mile": UnitLength.miles, "miles": UnitLength.miles,
            "yd": UnitLength.yards, "yard": UnitLength.yards, "yards": UnitLength.yards,
            "ft": UnitLength.feet, "foot": UnitLength.feet, "feet": UnitLength.feet,
            "in": UnitLength.inches, "inch": UnitLength.inches, "inches": UnitLength.inches,
            "kg": UnitMass.kilograms, "g": UnitMass.grams, "mg": UnitMass.milligrams,
            "lb": UnitMass.pounds, "lbs": UnitMass.pounds, "pound": UnitMass.pounds, "pounds": UnitMass.pounds,
            "oz": UnitMass.ounces, "ounce": UnitMass.ounces, "ounces": UnitMass.ounces,
            "st": UnitMass.stones, "stone": UnitMass.stones,
            "c": UnitTemperature.celsius, "celsius": UnitTemperature.celsius,
            "f": UnitTemperature.fahrenheit, "fahrenheit": UnitTemperature.fahrenheit,
            "k": UnitTemperature.kelvin, "kelvin": UnitTemperature.kelvin,
            "l": UnitVolume.liters, "liter": UnitVolume.liters, "liters": UnitVolume.liters,
            "ml": UnitVolume.milliliters,
            "gal": UnitVolume.gallons, "gallon": UnitVolume.gallons, "gallons": UnitVolume.gallons,
            "qt": UnitVolume.quarts, "pt": UnitVolume.pints, "cup": UnitVolume.cups, "cups": UnitVolume.cups,
            "floz": UnitVolume.fluidOunces,
            "kmh": UnitSpeed.kilometersPerHour, "kph": UnitSpeed.kilometersPerHour,
            "mph": UnitSpeed.milesPerHour, "ms": UnitSpeed.metersPerSecond,
            "knot": UnitSpeed.knots, "knots": UnitSpeed.knots,
            "s": UnitDuration.seconds, "sec": UnitDuration.seconds, "second": UnitDuration.seconds, "seconds": UnitDuration.seconds,
            "min": UnitDuration.minutes, "minute": UnitDuration.minutes, "minutes": UnitDuration.minutes,
            "h": UnitDuration.hours, "hr": UnitDuration.hours, "hour": UnitDuration.hours, "hours": UnitDuration.hours,
        ]
        return table[key]
    }
}
