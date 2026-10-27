import SwiftUI

// MARK: - BrewPilot theme: dark espresso + caramel

extension Color {
    static let espressoBlack = Color(red: 0.07, green: 0.055, blue: 0.05)
    static let espressoCard = Color(red: 0.135, green: 0.105, blue: 0.09)
    static let espressoLine = Color(red: 0.26, green: 0.19, blue: 0.14)
    static let espressoDeep = Color(red: 0.05, green: 0.04, blue: 0.035)
    static let cream = Color(red: 0.96, green: 0.93, blue: 0.88)
    static let creamDim = Color(red: 0.64, green: 0.58, blue: 0.52)
    static let caramel = Color(red: 0.93, green: 0.62, blue: 0.27)
    static let brewGreen = Color(red: 0.35, green: 0.82, blue: 0.45)
    static let brewRed = Color(red: 0.95, green: 0.38, blue: 0.32)
}

extension Font {
    static func brewDisplay(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

struct BrewCard: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.espressoCard)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

extension View {
    func brewCard() -> some View { modifier(BrewCard()) }
}

struct BrewButtonStyle: ButtonStyle {
    var accent: Color = .caramel
    var label: Color = .black
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(label)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(accent)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

struct SectionTitle: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Color.creamDim)
    }
}

struct OptionChips: View {
    let options: [(String, String)]
    @Binding var selection: String
    var body: some View {
        HStack(spacing: 8) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, opt in
                Button(opt.1) { selection = opt.0 }
                    .buttonStyle(ChipStyle(selected: selection == opt.0))
            }
        }
    }
}

struct ChipStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(selected ? Color.black : Color.cream)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(selected ? Color.caramel : Color.espressoLine.opacity(0.55))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

func formatTimer(_ seconds: Double) -> String {
    let s = max(0, Int(seconds))
    return String(format: "%d:%02d", s / 60, s % 60)
}
