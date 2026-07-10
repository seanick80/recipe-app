import SwiftData
import SwiftUI

/// Display-only unit mode for the recipe page. `auto` shows ingredients exactly
/// as stored; `metric`/`imperial` convert for display without mutating the recipe.
private enum UnitDisplay: String, CaseIterable, Identifiable {
    case auto = "Auto"
    case metric = "Metric"
    case imperial = "Imperial"
    var id: String { rawValue }
}

struct RecipeDetailView: View {
    let recipe: Recipe
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext
    @AppStorage("autoPublishEnabled") private var autoPublish = false
    @State private var showingEdit = false
    @State private var unitDisplay: UnitDisplay = .auto
    @State private var sharePayload: SharePayload?
    @State private var showingPublishPrompt = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let imageData = recipe.imageData,
                    let uiImage = UIImage(data: imageData)
                {
                    Image(uiImage: uiImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(maxHeight: 250)
                        .clipped()
                }

                VStack(alignment: .leading, spacing: 8) {
                    if !recipe.summary.isEmpty {
                        Text(recipe.summary)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 20) {
                        Label("\(recipe.prepTimeMinutes) min prep", systemImage: "clock")
                        Label("\(recipe.cookTimeMinutes) min cook", systemImage: "flame")
                        Label("\(recipe.servings) servings", systemImage: "person.2")
                    }
                    .font(.caption)

                    if !recipe.cuisine.isEmpty || !recipe.course.isEmpty || !recipe.difficulty.isEmpty {
                        HStack(spacing: 12) {
                            if !recipe.cuisine.isEmpty {
                                Label(recipe.cuisine, systemImage: "globe")
                            }
                            if !recipe.course.isEmpty {
                                Label(recipe.course, systemImage: "fork.knife")
                            }
                            if !recipe.difficulty.isEmpty {
                                Label(recipe.difficulty, systemImage: "chart.bar")
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    if !recipe.tags.isEmpty {
                        Text(recipe.tags)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    if !recipe.sourceURL.isEmpty {
                        // The source can be a web URL or a free-text cookbook
                        // name; only linkify real http(s) URLs (opens in the
                        // default browser), otherwise show plain text.
                        if let url = sourceLink(recipe.sourceURL) {
                            Link(destination: url) {
                                Text("Source: \(recipe.sourceURL)")
                                    .font(.caption2)
                            }
                        } else {
                            Text("Source: \(recipe.sourceURL)")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .padding(.horizontal)

                if let ingredients = recipe.ingredients, !ingredients.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Ingredients")
                                .font(.title2)
                                .bold()
                            Spacer()
                            Picker("Units", selection: $unitDisplay) {
                                ForEach(UnitDisplay.allCases) { option in
                                    Text(option.rawValue).tag(option)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .fixedSize()
                        }
                        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 6, verticalSpacing: 4) {
                            ForEach(ingredients.sorted { $0.displayOrder < $1.displayOrder }) { ingredient in
                                GridRow {
                                    if ingredient.quantity > 0 {
                                        let measure = displayMeasure(
                                            quantity: ingredient.quantity,
                                            unit: ingredient.unit
                                        )
                                        Text(measure.text)
                                            .bold()
                                            .gridColumnAlignment(.trailing)
                                        Text(measure.unit)
                                            .bold()
                                            .foregroundStyle(.secondary)
                                            .gridColumnAlignment(.leading)
                                    } else {
                                        Text("")
                                        Text("")
                                    }
                                    HStack(spacing: 4) {
                                        Text(ingredient.name)
                                        if !ingredient.notes.isEmpty {
                                            Text("(\(ingredient.notes))")
                                                .foregroundStyle(.secondary)
                                                .italic()
                                        }
                                    }
                                    .gridColumnAlignment(.leading)
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Instructions")
                        .font(.title2)
                        .bold()
                    Text(recipe.instructions)
                }
                .padding(.horizontal)
            }
        }
        .navigationTitle(recipe.name)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    handleShareTapped()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Edit") { showingEdit = true }
                    if recipe.serverId != nil {
                        Toggle("Published to web", isOn: publishedBinding)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Share recipe",
            isPresented: $showingPublishPrompt,
            titleVisibility: .visible
        ) {
            Button("Publish & share link") { publishAndShareLink() }
            Button("Share as text instead") {
                sharePayload = SharePayload(items: [shareText])
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Publishing makes this recipe viewable by anyone with the link.")
        }
        .sheet(item: $sharePayload) { payload in
            ShareSheet(activityItems: payload.items)
        }
        .sheet(isPresented: $showingEdit) {
            RecipeEditView(recipe: recipe)
        }
    }

    /// Two-way binding for the per-recipe "Published to web" toggle.
    private var publishedBinding: Binding<Bool> {
        Binding(
            get: { recipe.isPublished },
            set: { setPublished($0) }
        )
    }

    /// Decides what "Share" does based on sync + publish state:
    /// - not synced (no serverId): only plain text can be shared.
    /// - published: share the public web link directly.
    /// - unpublished + auto-publish on: publish, then share the link.
    /// - unpublished + auto-publish off: ask first.
    private func handleShareTapped() {
        guard recipe.serverId != nil else {
            sharePayload = SharePayload(items: [shareText])
            return
        }
        if recipe.isPublished {
            shareLink()
        } else if autoPublish {
            publishAndShareLink()
        } else {
            showingPublishPrompt = true
        }
    }

    private func publishAndShareLink() {
        setPublished(true)
        shareLink()
    }

    /// Shares the public web URL, falling back to text if one can't be built.
    private func shareLink() {
        if let url = recipeWebURL() {
            sharePayload = SharePayload(items: [url])
        } else {
            sharePayload = SharePayload(items: [shareText])
        }
    }

    /// Flips the recipe's published state and kicks a sync so the change reaches
    /// the server (which gates the public web view on `is_published`).
    private func setPublished(_ value: Bool) {
        guard recipe.isPublished != value else { return }
        recipe.isPublished = value
        recipe.needsSync = true
        try? modelContext.save()
        Task { await syncService.sync() }
    }

    /// Public web URL for this recipe, e.g.
    /// `https://recipes.ouryearofwander.com/recipes/{serverId}`. Nil until synced.
    private func recipeWebURL() -> URL? {
        guard let serverId = recipe.serverId else { return nil }
        return ServerConfig.webBaseURL
            .appendingPathComponent("recipes")
            .appendingPathComponent(serverId)
    }

    /// Plain-text rendering of the recipe suitable for sharing via Messages,
    /// Mail, etc. Uses stored (auto) units — the display-only unit toggle does
    /// not affect what is shared.
    private var shareText: String {
        var lines: [String] = [recipe.name]

        if !recipe.summary.isEmpty {
            lines.append("")
            lines.append(recipe.summary)
        }

        var meta: [String] = []
        if recipe.prepTimeMinutes > 0 { meta.append("Prep: \(recipe.prepTimeMinutes) min") }
        if recipe.cookTimeMinutes > 0 { meta.append("Cook: \(recipe.cookTimeMinutes) min") }
        if recipe.servings > 0 { meta.append("Serves: \(recipe.servings)") }
        if !meta.isEmpty {
            lines.append("")
            lines.append(meta.joined(separator: " · "))
        }

        if let ingredients = recipe.ingredients, !ingredients.isEmpty {
            lines.append("")
            lines.append("Ingredients")
            for ingredient in ingredients.sorted(by: { $0.displayOrder < $1.displayOrder }) {
                var parts: [String] = []
                if ingredient.quantity > 0 {
                    let measure = formatQuantityAsFraction(ingredient.quantity)
                    parts.append([measure, ingredient.unit].filter { !$0.isEmpty }.joined(separator: " "))
                }
                parts.append(ingredient.name)
                var line = "- " + parts.filter { !$0.isEmpty }.joined(separator: " ")
                if !ingredient.notes.isEmpty {
                    line += " (\(ingredient.notes))"
                }
                lines.append(line)
            }
        }

        if !recipe.instructions.isEmpty {
            lines.append("")
            lines.append("Instructions")
            lines.append(recipe.instructions)
        }

        if !recipe.sourceURL.isEmpty {
            lines.append("")
            lines.append("Source: \(recipe.sourceURL)")
        }

        return lines.joined(separator: "\n")
    }

    /// Returns a tappable URL only if the source string is a real http(s) URL.
    /// Free-text sources (e.g. a cookbook name) return nil and render as plain text.
    private func sourceLink(_ source: String) -> URL? {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            return nil
        }
        return url
    }

    /// Ingredient quantity + unit formatted for the current unit-display mode.
    /// Conversion is display-only (the stored recipe is never changed). Units
    /// that aren't convertible measures (e.g. "egg", "clove") fall back to the
    /// stored value regardless of mode.
    private func displayMeasure(quantity: Double, unit: String) -> (text: String, unit: String) {
        switch unitDisplay {
        case .auto:
            break
        case .metric:
            if let m = UnitConverter.convert(quantity: quantity, unit: unit, to: .metric) {
                return (formatMetric(m.quantity), m.unit)
            }
        case .imperial:
            if let m = UnitConverter.convert(quantity: quantity, unit: unit, to: .imperial) {
                return (formatQuantityAsFraction(m.quantity), m.unit)
            }
        }
        return (formatQuantityAsFraction(quantity), unit)
    }

    /// Compact decimal formatting for metric values, dropping trailing zeros
    /// (240 → "240", 3.8 → "3.8", 1.5 → "1.5").
    private func formatMetric(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(format: "%g", value)
    }

    private func formatQuantityAsFraction(_ value: Double) -> String {
        if value <= 0 { return "" }
        let whole = Int(value)
        let frac = value - Double(whole)

        let fractionStr: String?
        if abs(frac) < 0.01 {
            fractionStr = nil
        } else if abs(frac - 0.25) < 0.01 {
            fractionStr = "\u{00BC}"
        } else if abs(frac - 1.0 / 3) < 0.04 {
            fractionStr = "\u{2153}"
        } else if abs(frac - 0.5) < 0.01 {
            fractionStr = "\u{00BD}"
        } else if abs(frac - 2.0 / 3) < 0.04 {
            fractionStr = "\u{2154}"
        } else if abs(frac - 0.75) < 0.01 {
            fractionStr = "\u{00BE}"
        } else {
            fractionStr = nil
        }

        if let f = fractionStr {
            return whole > 0 ? "\(whole) \(f)" : f
        }
        return value.truncatingRemainder(dividingBy: 1) == 0
            ? "\(whole)"
            : String(format: "%.1f", value)
    }
}

/// Wraps the items handed to the system share sheet. Identifiable so it can
/// drive a `.sheet(item:)` presentation.
private struct SharePayload: Identifiable {
    let id = UUID()
    let items: [Any]
}

/// Minimal `UIActivityViewController` wrapper so the recipe share flow can
/// present either a URL or plain text after an async publish/sync step (which
/// the declarative `ShareLink` can't express).
private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
