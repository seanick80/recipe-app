import SwiftUI
import UniformTypeIdentifiers

/// Share Extension entry point. Receives a URL from Safari's share sheet,
/// fetches the page HTML, extracts recipe data via JSON-LD/heuristics,
/// and writes a pending import file to the shared App Group container.
/// The main app picks it up on next launch.
@objc(ShareViewController)
class ShareViewController: UIViewController {
    private let log = DebugLog.shared

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        log.log(category: "share", message: "Share extension launched")

        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
            let provider = item.attachments?.first
        else {
            log.log(category: "share", message: "No input items from extension context")
            showError("Nothing to import.")
            return
        }

        // Try URL first (most common from Safari)
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.url.identifier) { [weak self] data, error in
                if let error = error {
                    self?.log.log(
                        category: "share.error",
                        message: "loadItem URL failed",
                        details: ["error": "\(error)"]
                    )
                }
                guard let url = data as? URL else {
                    self?.log.log(
                        category: "share.error",
                        message: "Could not cast data to URL",
                        details: ["dataType": "\(type(of: data))"]
                    )
                    Task { @MainActor in self?.showError("Could not read URL.") }
                    return
                }
                self?.log.log(category: "share", message: "Received URL", details: ["url": url.absoluteString])
                Task { @MainActor in self?.fetchAndParse(url) }
            }
        } else if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            // Some apps share as plain text
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) { [weak self] data, error in
                if let error = error {
                    self?.log.log(
                        category: "share.error",
                        message: "loadItem text failed",
                        details: ["error": "\(error)"]
                    )
                }
                guard let text = data as? String, let url = URL(string: text) else {
                    self?.log.log(
                        category: "share.error",
                        message: "Could not parse URL from text",
                        details: ["text": data.map { "\($0)" } ?? "nil"]
                    )
                    Task { @MainActor in self?.showError("Not a valid URL.") }
                    return
                }
                self?.log.log(category: "share", message: "Parsed URL from text", details: ["url": url.absoluteString])
                Task { @MainActor in self?.fetchAndParse(url) }
            }
        } else {
            let types = provider.registeredTypeIdentifiers.joined(separator: ", ")
            log.log(category: "share.error", message: "Unsupported content type", details: ["types": types])
            showError("Unsupported content type.")
        }
    }

    private func fetchAndParse(_ url: URL) {
        showLoading("Fetching recipe...")

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                log.log(
                    category: "share",
                    message: "Fetched page",
                    details: ["bytes": "\(data.count)", "url": url.absoluteString]
                )
                guard
                    let html = String(data: data, encoding: .utf8)
                        ?? String(data: data, encoding: .ascii)
                else {
                    log.log(category: "share.error", message: "Could not decode page content as text")
                    showError("Could not read page content.")
                    return
                }

                let result = parseRecipeFromHTML(html, sourceURL: url.absoluteString)
                switch result {
                case .success(let recipe):
                    log.log(
                        category: "share",
                        message: "Parsed recipe",
                        details: [
                            "title": recipe.title,
                            "ingredients": "\(recipe.ingredients.count)",
                            "instructions": "\(recipe.instructions.count)",
                        ]
                    )
                    savePendingImport(recipe)
                    showSuccess(recipe.title)
                case .failure(let error):
                    log.log(category: "share.error", message: "Recipe parse failed", details: ["error": "\(error)"])
                    switch error {
                    case .noRecipeFound:
                        showError("No recipe found on this page.\nTry a page with a specific recipe.")
                    case .missingTitle:
                        showError("Found recipe data but no title.\nThis page may not have proper recipe markup.")
                    case .missingIngredients:
                        showError(
                            "Found a recipe title but no ingredients.\nThe recipe data on this page may be incomplete."
                        )
                    case .noHTML:
                        showError("Page returned empty content.")
                    }
                }
            } catch {
                log.log(category: "share.error", message: "Network fetch failed", details: ["error": "\(error)"])
                showError("Could not load page.\n\(error.localizedDescription)")
            }
        }
    }

    private func savePendingImport(_ recipe: ImportedRecipe) {
        guard
            let containerURL = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.com.seanick80.recipeapp"
            )
        else {
            log.log(category: "share.error", message: "App Group container URL is nil — group not provisioned?")
            return
        }

        let pendingDir = containerURL.appendingPathComponent("PendingImports", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        } catch {
            log.log(
                category: "share.error",
                message: "Failed to create PendingImports dir",
                details: ["error": "\(error)"]
            )
        }

        let filename = UUID().uuidString + ".json"
        let fileURL = pendingDir.appendingPathComponent(filename)

        do {
            let data = try JSONEncoder().encode(recipe)
            try data.write(to: fileURL)
            log.log(
                category: "share",
                message: "Saved pending import",
                details: ["file": fileURL.lastPathComponent, "bytes": "\(data.count)", "path": fileURL.path]
            )
        } catch {
            log.log(category: "share.error", message: "Failed to write pending import", details: ["error": "\(error)"])
        }
    }

    // MARK: - UI States

    private func showLoading(_ message: String) {
        clearSubviews()
        let stack = makeStack()
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.startAnimating()
        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(makeLabel(message, style: .body))
    }

    private func showSuccess(_ title: String) {
        clearSubviews()
        let stack = makeStack()
        let checkmark = UIImageView(image: UIImage(systemName: "checkmark.circle.fill"))
        checkmark.tintColor = .systemGreen
        checkmark.contentMode = .scaleAspectFit
        checkmark.heightAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(checkmark)
        stack.addArrangedSubview(makeLabel("Recipe Imported!", style: .headline))
        stack.addArrangedSubview(makeLabel(title, style: .subheadline))
        stack.addArrangedSubview(makeLabel("Open Recipe App to review.", style: .caption1))

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func showError(_ message: String) {
        clearSubviews()
        let stack = makeStack()
        let xmark = UIImageView(image: UIImage(systemName: "xmark.circle.fill"))
        xmark.tintColor = .systemRed
        xmark.contentMode = .scaleAspectFit
        xmark.heightAnchor.constraint(equalToConstant: 48).isActive = true
        stack.addArrangedSubview(xmark)
        stack.addArrangedSubview(makeLabel("Import Failed", style: .headline))
        stack.addArrangedSubview(makeLabel(message, style: .body))

        let dismiss = UIButton(type: .system)
        dismiss.setTitle("Done", for: .normal)
        dismiss.addTarget(self, action: #selector(dismissExtension), for: .touchUpInside)
        stack.addArrangedSubview(dismiss)

        // Auto-dismiss after 3 seconds so the extension doesn't hang the
        // share sheet when invoked for unsupported content types (GM-19).
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    @objc private func dismissExtension() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    // MARK: - UI Helpers

    private func clearSubviews() {
        view.subviews.forEach { $0.removeFromSuperview() }
    }

    private func makeStack() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])
        return stack
    }

    private func makeLabel(_ text: String, style: UIFont.TextStyle) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.textAlignment = .center
        label.numberOfLines = 0
        label.textColor = style == .caption1 ? .secondaryLabel : .label
        return label
    }
}
