import Foundation

// Mirrors server/app.py schemas. Decode with .convertFromSnakeCase.

struct PourStep: Codable, Identifiable, Hashable {
    var id: String
    var type: String
    var targetAddG: Double?
    var targetTotalG: Double?
    var flowMlS: [Double]
    var durationS: Int?
    var instruction: String?
}

struct Recipe: Codable, Hashable {
    var name: String
    var coffeeG: Double
    var waterG: Double
    var tempC: Int
    var grind: String
    var steps: [PourStep]

    static let canned = Recipe(
        name: "House Pour-Over (offline)",
        coffeeG: 22, waterG: 350, tempC: 94,
        grind: "medium-fine (table salt)",
        steps: [
            PourStep(id: "bloom", type: "pour", targetAddG: 50, targetTotalG: nil,
                     flowMlS: [4, 6], durationS: 45,
                     instruction: "Saturate all grounds gently. Swirl once."),
            PourStep(id: "p1", type: "pour", targetAddG: nil, targetTotalG: 150,
                     flowMlS: [5, 7], durationS: 30,
                     instruction: "Pour in slow spirals from the center out."),
            PourStep(id: "p2", type: "pour", targetAddG: nil, targetTotalG: 250,
                     flowMlS: [5, 7], durationS: nil, instruction: nil),
            PourStep(id: "p3", type: "pour", targetAddG: nil, targetTotalG: 350,
                     flowMlS: [4, 6], durationS: nil, instruction: nil),
        ]
    )
}

struct VisionContext: Codable {
    var step: String
    var elapsedS: Double
    var targetG: Double
}

struct VisionResult: Codable {
    var bloomActive: Bool
    var bubbles: String
    var pourPosition: String
    var bedEven: Bool
    var channeling: Bool
    var bedDrained: Bool? // nil from proxies deployed before the field existed
    var coaching: String
    var severity: String
}

/// One finished pour: what the recipe asked for vs. what landed on the scale.
struct StepResult: Codable, Hashable {
    var id: String
    var targetG: Double
    var actualG: Double
    var durationS: Double
}

struct BrewSample: Codable {
    var tMs: Int
    var phase: String
    var weightG: Double
    var flowMlS: Double
}

enum CoachOrigin: String, Codable {
    case local, vision
}

struct CoachMessage: Identifiable, Hashable {
    var id = UUID()
    var text: String
    var severity: String
    var origin: CoachOrigin = .local
}
