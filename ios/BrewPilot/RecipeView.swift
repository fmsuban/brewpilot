import SwiftUI

struct RecipeView: View {
    @EnvironmentObject var session: BrewSession
    @State private var roast = "medium"
    @State private var cups = 1
    @State private var strength = "medium"
    @State private var isGenerating = false
    @State private var usedFallback = false

    var body: some View {
        NavigationStack {
            ZStack {
                Color.espressoBlack.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(alignment: .leading, spacing: 12) {
                            SectionTitle(text: "Beans")
                            OptionChips(
                                options: [("light", "Light"), ("medium", "Medium"), ("dark", "Dark")],
                                selection: $roast
                            )
                            SectionTitle(text: "Strength")
                            OptionChips(
                                options: [("light", "Tea-like"), ("medium", "Medium"), ("strong", "Strong")],
                                selection: $strength
                            )
                            HStack {
                                SectionTitle(text: "Cups")
                                Spacer()
                                Stepper("", value: $cups, in: 1...2)
                                    .labelsHidden()
                                Text("\(cups)")
                                    .font(.title3.weight(.bold))
                                    .foregroundStyle(Color.cream)
                                    .frame(width: 28)
                            }
                            Button(isGenerating ? "Brewing plan…" : "Generate recipe") {
                                Task { await generate() }
                            }
                            .buttonStyle(BrewButtonStyle())
                            .disabled(isGenerating)
                        }
                        .brewCard()

                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(session.recipe.name)
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.cream)
                                Spacer()
                                if usedFallback {
                                    Text("Offline")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(Color.black)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.caramel)
                                        .clipShape(Capsule())
                                }
                            }
                            Text("\(Int(session.recipe.coffeeG)) g coffee · \(Int(session.recipe.waterG)) g water · \(session.recipe.tempC)°C")
                                .font(.subheadline)
                                .foregroundStyle(Color.creamDim)
                            Text(session.recipe.grind)
                                .font(.subheadline)
                                .foregroundStyle(Color.creamDim)
                            Divider()
                                .background(Color.espressoLine)
                            ForEach(session.recipe.steps) { step in
                                HStack(alignment: .top, spacing: 10) {
                                    Text(step.id)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(Color.caramel)
                                        .frame(width: 48, alignment: .leading)
                                    Text(step.instruction ?? defaultInstruction(for: step))
                                        .font(.subheadline)
                                        .foregroundStyle(Color.cream)
                                    Spacer()
                                }
                            }
                        }
                        .brewCard()
                    }
                    .padding()
                }
            }
            .navigationTitle("Recipe")
            .toolbarBackground(Color.espressoBlack, for: .navigationBar)
        }
    }

    private func defaultInstruction(for step: PourStep) -> String {
        if let total = step.targetTotalG { return "Pour to \(Int(total)) g." }
        if let add = step.targetAddG { return "Add \(Int(add)) g." }
        return "Pour."
    }

    private func generate() async {
        isGenerating = true
        defer { isGenerating = false }
        do {
            let recipe = try await ProxyClient.shared.fetchRecipe(
                roast: roast, cups: cups, strength: strength
            )
            session.recipe = recipe
            usedFallback = false
        } catch {
            session.recipe = .canned
            usedFallback = true
        }
    }
}
