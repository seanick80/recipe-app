import SwiftUI

/// Viewer + exporter for the on-device debug log. The log records every
/// OCR scan's intermediate results (raw Vision output, quality gate
/// decision, handwriting split, block classification, final parsed
/// output). Use `Share` to email the full log file; use `Clear` to reset
/// after a successful debug session.
///
/// This is a debug-only surface and should be removed (or hidden behind
/// a build flag) before a public release.
struct DebugLogView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tailLines: [String] = []
    @State private var byteCount: Int = 0
    @State private var exportURL: URL?
    @State private var showingClearConfirm = false

    /// How many of the most recent log lines to render in the on-screen
    /// preview. Tuned low because SwiftUI `Text` with thousands of
    /// entries lags; the share export always contains the full log.
    private let previewLineCount = 200

    var body: some View {
        NavigationStack {
            Group {
                if tailLines.isEmpty {
                    ContentUnavailableView(
                        "No Log Entries Yet",
                        systemImage: "doc.text",
                        description: Text("Run a scan and its pipeline events will show up here.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(tailLines.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Debug Log")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let url = exportURL {
                            ShareLink(item: url) {
                                Label("Share Log File", systemImage: "square.and.arrow.up")
                            }
                        }
                        Button("Refresh", systemImage: "arrow.clockwise") { reload() }
                        Button("Clear", systemImage: "trash", role: .destructive) {
                            showingClearConfirm = true
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItem(placement: .bottomBar) {
                    Text("\(tailLines.count) lines shown · \(byteCount) bytes on disk")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .confirmationDialog(
                "Delete log?",
                isPresented: $showingClearConfirm,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    DebugLog.shared.clear()
                    reload()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This erases both the active log and the archive.")
            }
            .onAppear { reload() }
        }
    }

    private func reload() {
        tailLines = DebugLog.shared.tail(lines: previewLineCount)
        byteCount = DebugLog.shared.activeByteCount
        exportURL = DebugLog.shared.export()
    }
}
