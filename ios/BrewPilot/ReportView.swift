import SwiftUI

struct ReportView: View {
    @EnvironmentObject var session: BrewSession

    var body: some View {
        NavigationStack {
            ZStack {
                Color.espressoBlack.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible())],
                            spacing: 12
                        ) {
                            StatCard(title: "Samples", value: "\(session.eventLog.count)")
                            StatCard(
                                title: "Final",
                                value: "\(session.displayWeight(session.weightG)) \(session.unitLabel)"
                            )
                            StatCard(title: "Phase", value: session.phase.rawValue.capitalized)
                            StatCard(title: "Notes", value: "\(session.coachMessages.count)")
                        }
                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Weight chart")
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.espressoDeep)
                                    .frame(height: 130)
                                VStack(spacing: 6) {
                                    Image(systemName: "chart.xyaxis.line")
                                        .font(.largeTitle)
                                        .foregroundStyle(Color.creamDim)
                                    Text("Chart lands day 7")
                                        .font(.caption)
                                        .foregroundStyle(Color.creamDim)
                                }
                            }
                        }
                        .brewCard()
                        VStack(alignment: .leading, spacing: 8) {
                            SectionTitle(text: "Coach notes")
                            if session.coachMessages.isEmpty {
                                Text("No notes yet — finish a brew to get your report card.")
                                    .font(.subheadline)
                                    .foregroundStyle(Color.creamDim)
                            }
                            ForEach(session.coachMessages) { msg in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•")
                                        .foregroundStyle(Color.caramel)
                                    Text(msg.text)
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
            .navigationTitle("Report")
            .toolbarBackground(Color.espressoBlack, for: .navigationBar)
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(Color.cream)
            Text(title)
                .font(.caption)
                .foregroundStyle(Color.creamDim)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Color.espressoCard)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
