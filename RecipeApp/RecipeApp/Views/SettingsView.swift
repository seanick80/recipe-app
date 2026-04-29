import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @EnvironmentObject private var authService: AuthService
    @AppStorage("improvementReportingEnabled") private var improvementReporting = false
    @State private var showingDeletedRecipes = false
    @State private var showingForceSync = false

    var body: some View {
        NavigationStack {
            Form {
                if let user = authService.currentUser {
                    Section("Account") {
                        LabeledContent("Name", value: user.name)
                        LabeledContent("Email", value: user.email)
                        LabeledContent("Role", value: user.role.capitalized)
                    }

                    Section("Sync") {
                        if let lastSync = syncService.lastSyncDate {
                            LabeledContent("Last synced", value: lastSync.formatted(.relative(presentation: .named)))
                        } else {
                            LabeledContent("Last synced", value: "Never")
                        }
                        if syncService.isSyncing {
                            HStack {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Syncing...")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Button("Sync Now") {
                            Task { await syncService.sync() }
                        }
                        .disabled(syncService.isSyncing)
                        Button("Force Full Sync") {
                            showingForceSync = true
                        }
                        .disabled(syncService.isSyncing)
                        NavigationLink("Recently Deleted") {
                            RecentlyDeletedView()
                        }
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
            .alert("Force Full Sync", isPresented: $showingForceSync) {
                Button("Cancel", role: .cancel) {}
                Button("Re-download All") {
                    Task { await syncService.forceFullSync() }
                }
            } message: {
                Text(
                    "This clears all sync timestamps and re-downloads every recipe from the server. Local-only recipes will be uploaded."
                )
            }
        }
    }
}

// MARK: - Recently Deleted View

struct RecentlyDeletedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(SyncService.self) private var syncService
    @Query(
        filter: #Predicate<Recipe> { $0.locallyDeleted == true },
        sort: \Recipe.deletedAt,
        order: .reverse
    ) private var deletedRecipes: [Recipe]

    var body: some View {
        List {
            if deletedRecipes.isEmpty {
                ContentUnavailableView(
                    "No Deleted Recipes",
                    systemImage: "trash",
                    description: Text("Deleted recipes appear here for 30 days.")
                )
            } else {
                ForEach(deletedRecipes) { recipe in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.name)
                            .font(.headline)
                        if let deletedAt = recipe.deletedAt {
                            Text("Deleted \(deletedAt.formatted(.relative(presentation: .named)))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Restore") {
                            recipe.locallyDeleted = false
                            recipe.deletedAt = nil
                            recipe.needsSync = true
                        }
                        .tint(.green)
                    }
                }
            }
        }
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
    }
}
