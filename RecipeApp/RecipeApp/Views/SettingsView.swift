import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var authService: AuthService
    @AppStorage("improvementReportingEnabled") private var improvementReporting = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = authService.currentUser {
                    Section("Account") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: user.role.capitalized)
                    }

                    Section {
                        Button("Sign Out", role: .destructive) {
                            authService.logout()
                            dismiss()
                        }
                    }
                }

                Section {
                    Toggle("Help improve imports", isOn: $improvementReporting)
                } footer: {
                    Text(
                        "When enabled, anonymous data about recipe import "
                            + "normalizations (e.g. ingredient formatting fixes) "
                            + "is sent to help improve the app. No personal data "
                            + "or recipe content is shared — only the text "
                            + "transformations applied during import."
                    )
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
