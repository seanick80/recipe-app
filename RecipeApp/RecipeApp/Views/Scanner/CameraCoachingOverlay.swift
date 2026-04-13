import SwiftUI

/// Overlay that coaches the user on phone positioning:
/// tilt warnings, brightness warnings, and a shutter button.
struct CameraCoachingOverlay: View {
    let tiltWarning: String?
    let brightnessWarning: String?
    let onCapture: () -> Void

    var body: some View {
        VStack {
            // Top warnings
            VStack(spacing: 8) {
                if let tilt = tiltWarning {
                    CoachingBadge(icon: "rotate.3d", text: tilt, color: .orange)
                }
                if let brightness = brightnessWarning {
                    CoachingBadge(icon: "sun.max", text: brightness, color: .yellow)
                }
            }
            .padding(.top, 60)

            Spacer()

            // Shutter button
            Button(action: onCapture) {
                ZStack {
                    Circle()
                        .fill(.white)
                        .frame(width: 72, height: 72)
                    Circle()
                        .stroke(.white, lineWidth: 4)
                        .frame(width: 80, height: 80)
                }
            }
            .padding(.bottom, 40)
        }
    }
}

/// Pill-shaped warning badge shown during camera capture.
struct CoachingBadge: View {
    let icon: String
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
            Text(text)
                .font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(color.opacity(0.85))
        .foregroundStyle(.black)
        .clipShape(Capsule())
    }
}
