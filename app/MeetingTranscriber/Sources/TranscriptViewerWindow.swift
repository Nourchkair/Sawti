import SwiftUI
import UniformTypeIdentifiers

struct TranscriptViewerWindow: View {
    let fileURL: URL?

    @State private var transcript = ""
    @State private var loadError: String?
    @State private var exportError: String?

    var body: some View {
        Group {
            if let loadError {
                ContentUnavailableView(
                    "Transcript Unavailable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text(loadError),
                )
            } else {
                ScrollView {
                    Text(transcript)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(20)
                }
                .overlay(alignment: .bottom) {
                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(8)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 8)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Export Copy…", systemImage: "square.and.arrow.down", action: exportCopy)
                    .disabled(fileURL == nil || loadError != nil)
            }
        }
        .task(id: fileURL) {
            loadTranscript()
        }
        .frame(minWidth: 560, minHeight: 420)
    }

    private func loadTranscript() {
        guard let fileURL else {
            loadError = "No transcript was selected."
            return
        }
        let accessed = fileURL.startAccessingSecurityScopedResource()
        defer { if accessed { fileURL.stopAccessingSecurityScopedResource() } }
        do {
            transcript = try String(contentsOf: fileURL, encoding: .utf8)
            loadError = nil
        } catch {
            loadError = "Sawti could not read this transcript file."
        }
    }

    private func exportCopy() {
        guard let fileURL else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = fileURL.lastPathComponent
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        do {
            try TranscriptExport.writeCopy(transcript, to: destination)
            exportError = nil
        } catch {
            exportError = "Could not export this transcript. Check the destination and try again."
        }
    }
}
