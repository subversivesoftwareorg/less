import SwiftUI

enum ConsumptionType: String, CaseIterable, Identifiable {
    case money
    case electricity
    case gas
    case water
    case waste

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .money: "Spending"
        case .electricity: "Electricity"
        case .gas: "Natural Gas"
        case .water: "Water"
        case .waste: "Waste"
        }
    }

    var icon: String {
        switch self {
        case .money: "dollarsign.circle"
        case .electricity: "bolt"
        case .gas: "flame"
        case .water: "drop"
        case .waste: "trash"
        }
    }

    var color: Color {
        switch self {
        case .money: .blue
        case .electricity: .yellow
        case .gas: .orange
        case .water: .cyan
        case .waste: .brown
        }
    }

    var defaultUnit: String {
        switch self {
        case .money: "$"
        case .electricity: "kWh"
        case .gas: "therms"
        case .water: "gallons"
        case .waste: "bags"
        }
    }

    var allUnits: [String] {
        switch self {
        case .money: ["$"]
        case .electricity: ["kWh"]
        case .gas: ["therms", "CCF"]
        case .water: ["gallons", "cuft"]
        case .waste: ["bags", "lbs", "pickups"]
        }
    }

    /// Derive consumption type from a unit string.
    static func from(unit: String) -> ConsumptionType {
        let u = unit.lowercased()
        switch u {
        case "kwh": return .electricity
        case "therms", "ccf": return .gas
        case "gallons", "gal", "cuft", "cubic feet", "cf": return .water
        case "bags", "lbs", "lb", "pickups": return .waste
        default: return .money
        }
    }

    func format(_ value: Double) -> String {
        switch self {
        case .money: value.formatted(.currency(code: "USD"))
        case .electricity: "\(Int(value)) kWh"
        case .gas: String(format: "%.1f therms", value)
        case .water: "\(Int(value)) gal"
        case .waste: "\(Int(value)) bags"
        }
    }

    func formatWithUnit(_ value: Double, unit: String) -> String {
        if self == .money { return value.formatted(.currency(code: "USD")) }
        return "\(Int(value)) \(unit)"
    }
}
