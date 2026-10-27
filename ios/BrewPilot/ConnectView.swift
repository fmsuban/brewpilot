import SwiftUI

struct ConnectView: View {
    @EnvironmentObject var session: BrewSession

    var body: some View {
        NavigationStack {
            ZStack {
                Color.espressoBlack.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 14) {
                        VStack(spacing: 14) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(session.scaleConnected ? Color.brewGreen : Color.caramel)
                                    .frame(width: 12, height: 12)
                                Text(session.scaleConnected ? "Scale connected" : "Looking for scale…")
                                    .font(.title3.weight(.semibold))
                                    .foregroundStyle(Color.cream)
                                Spacer()
                            }
                            HStack(spacing: 10) {
                                Image(systemName: "scalemass")
                                Text(session.scale.peripheralName ?? "BrewPilot-Scale")
                                Spacer()
                            }
                            .font(.subheadline)
                            .foregroundStyle(Color.creamDim)
                            Button("Tare") { session.scale.tare() }
                                .buttonStyle(BrewButtonStyle(
                                    accent: session.scaleConnected ? .caramel : .espressoLine,
                                    label: session.scaleConnected ? .black : .creamDim
                                ))
                                .disabled(!session.scaleConnected)
                        }
                        .brewCard()

                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Camera framing")
                            ZStack {
                                RoundedRectangle(cornerRadius: 10)
                                    .fill(Color.espressoDeep)
                                    .frame(height: 120)
                                VStack(spacing: 6) {
                                    Image(systemName: "viewfinder")
                                        .font(.largeTitle)
                                        .foregroundStyle(Color.creamDim)
                                    Text("Point the rear camera at the dripper")
                                        .font(.caption)
                                        .foregroundStyle(Color.creamDim)
                                }
                            }
                        }
                        .brewCard()

                        VStack(alignment: .leading, spacing: 10) {
                            SectionTitle(text: "Rig checklist")
                            ForEach(rigTips, id: \.self) { tip in
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.brewGreen)
                                    Text(tip)
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
            .navigationTitle("Setup")
            .toolbarBackground(Color.espressoBlack, for: .navigationBar)
            .onAppear { session.scale.startScanning() }
        }
    }

    private var rigTips: [String] {
        [
            "Scale under mug + dripper, nothing touching",
            "iPhone on stand, 30 cm from the brewer",
            "Kettle hot, filter rinsed",
        ]
    }
}
