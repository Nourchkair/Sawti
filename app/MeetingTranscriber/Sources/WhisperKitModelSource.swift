import Foundation
import WhisperKit

/// WhisperKit itself is not Sendable, but loading it is CPU-heavy and must not
/// block the app's main actor. This wrapper is used only to transfer a newly
/// constructed instance back to the main-actor-owned engine; all later access
/// remains on that actor.
struct WhisperKitPipeTransfer: @unchecked Sendable {
    let pipe: WhisperKit
}

/// The three steps `WhisperKitEngine.loadModel()` takes to reach a usable pipe,
/// named so a test can observe which of them ran. Production resolves every step
/// against WhisperKit itself. Why the local step comes first is written down once,
/// on `WhisperKitLocalSnapshot`.
@MainActor
struct WhisperKitModelSource {
    /// The folder holding a complete local copy of the variant, or nil when it has
    /// to be fetched. Never touches the network.
    let locateLocal: @Sendable (String) -> URL?
    /// WhisperKit's own downloader, which reaches the Hub before it inspects any
    /// local file.
    let download: (String, @escaping ProgressCallback) async throws -> URL
    /// Build the WhisperKit pipe from an on-disk model folder. It is also the
    /// completeness judge: `loadModels` checks its three CoreML bundles here, so a
    /// copy the locator waved through but CoreML cannot use still fails into the
    /// download.
    let makePipe: (String, URL) async throws -> WhisperKit
    /// Optional production builder for the synchronous CoreML/model setup.
    /// The returned instance is transferred to the main actor only after setup
    /// finishes; test sources can keep using `makePipe` and its actor-bound hooks.
    let makePipeOffMain: (@Sendable (String, URL) async throws -> WhisperKitPipeTransfer)?

    init(
        locateLocal: @escaping @Sendable (String) -> URL?,
        download: @escaping (String, @escaping ProgressCallback) async throws -> URL,
        makePipe: @escaping (String, URL) async throws -> WhisperKit,
        makePipeOffMain: (@Sendable (String, URL) async throws -> WhisperKitPipeTransfer)? = nil,
    ) {
        self.locateLocal = locateLocal
        self.download = download
        self.makePipe = makePipe
        self.makePipeOffMain = makePipeOffMain
    }

    /// The folder as WhisperKit needs it. Named and separate because the conversion
    /// is load-bearing and wrong by default. `WhisperKitConfig` takes a `String` and
    /// WhisperKit turns it straight back into `URL(fileURLWithPath:)`, while
    /// `URL.path()` percent-encodes: an account name with a space or a non-ASCII
    /// character would make the model this locator just found look absent, and
    /// offline that ends in a failed download instead of a loaded model.
    nonisolated static func modelFolderArgument(_ folder: URL) -> String {
        folder.path(percentEncoded: false)
    }

    static let production = Self(
        locateLocal: { variant in
            WhisperKitLocalSnapshot.locate(variant: variant, in: WhisperKitLocalSnapshot.defaultRepoRoot)
        },
        download: { variant, progress in
            // `from:` passed explicitly although it matches the library default:
            // the locator derives its root from the same constant, and a changed
            // default would otherwise have the two point at different repositories,
            // which shows up as "the model is never found".
            try await WhisperKit.download(
                variant: variant,
                downloadBase: WhisperKitLocalSnapshot.defaultDownloadBase,
                from: WhisperKitLocalSnapshot.repoID,
                progressCallback: progress,
            )
        },
        makePipe: { variant, folder in
            try await WhisperKit(WhisperKitConfig(
                model: variant,
                downloadBase: WhisperKitLocalSnapshot.defaultDownloadBase,
                modelFolder: modelFolderArgument(folder),
                tokenizerFolder: WhisperKitLocalSnapshot.defaultDownloadBase,
            ))
        },
        makePipeOffMain: { variant, folder in
            try await Task.detached(priority: .userInitiated) {
                try await WhisperKitPipeTransfer(
                    pipe: WhisperKit(WhisperKitConfig(
                        model: variant,
                        downloadBase: WhisperKitLocalSnapshot.defaultDownloadBase,
                        modelFolder: modelFolderArgument(folder),
                        tokenizerFolder: WhisperKitLocalSnapshot.defaultDownloadBase,
                    )),
                )
            }.value
        },
    )
}
