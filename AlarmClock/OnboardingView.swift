import SwiftUI

// MARK: - OnboardingView
//
// Explains the Wake-Up Check concept. Shown automatically at first launch and
// on demand via the info button in the toolbar menu.

struct OnboardingView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 32) {
                    VStack(spacing: 12) {
                        Image(systemName: "alarm.waves.left.and.right.fill")
                            .font(.system(size: 56))
                            .foregroundStyle(.orange)
                        Text(verbatim: "Wstałem!")
                            .font(.largeTitle)
                            .fontWeight(.bold)
                        Text("The alarm that checks you're really up")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding(.top, 48)
                    .padding(.horizontal, 28)

                    VStack(alignment: .leading, spacing: 26) {
                        featureRow(icon: "alarm.fill", color: .orange,
                                   title: "A real alarm",
                                   text: "Rings full-screen even when the app is closed and breaks through silent mode.")
                        featureRow(icon: "checkmark.circle.fill", color: .green,
                                   title: "Wake-Up Check",
                                   text: "After you stop the alarm, it asks whether you actually got up.")
                        featureRow(icon: "timer", color: .blue,
                                   title: "Live countdown",
                                   text: "A countdown on the Lock Screen shows how much time is left to confirm.")
                        featureRow(icon: "bell.and.waves.left.and.right.fill", color: .red,
                                   title: "No response? It rings again",
                                   text: "If you don't confirm in time, a real alarm rings again. No mercy. 😈")
                    }
                    .padding(.horizontal, 28)
                }
                .padding(.bottom, 16)
            }

            Button {
                dismiss()
            } label: {
                Text("Got it!")
                    .font(.headline)
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
    }

    private func featureRow(
        icon: String,
        color: Color,
        title: LocalizedStringKey,
        text: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 38)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                Text(text)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    OnboardingView()
}
