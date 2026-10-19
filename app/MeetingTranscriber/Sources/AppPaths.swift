import Foundation
import os.log

/// Centralized path constants and logger subsystem for the app.
enum AppPaths {
    /// Logger subsystem for all os.log loggers.
    static let logSubsystem = "com.nourchkair.sawti"

    /// XCTest workers use a disposable home when one is supplied by
    /// `scripts/test-isolated.sh`. The explicit environment seam keeps normal
    /// app launches on the user's real home, while making every app-owned path
    /// in the test process resolve beneath the disposable test home.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["SAWTI_TEST_HOME"] != nil
            || environment["XCTestConfigurationFilePath"] != nil
            || ProcessInfo.processInfo.processName.hasSuffix(".xctest")
    }()

    static let homeDirectory: URL = {
        let environment = ProcessInfo.processInfo.environment
        guard isRunningTests else { return FileManager.default.homeDirectoryForCurrentUser }

        let temporaryDirectory = FileManager.default.temporaryDirectory
            .resolvingSymlinksInPath().standardizedFileURL
        let candidate: URL
        if let configuredHome = environment["SAWTI_TEST_HOME"] {
            candidate = URL(fileURLWithPath: configuredHome, isDirectory: true)
                .resolvingSymlinksInPath().standardizedFileURL
            let allowedPrefix = temporaryDirectory.path.hasSuffix("/")
                ? temporaryDirectory.path
                : temporaryDirectory.path + "/"
            guard candidate.path.hasPrefix(allowedPrefix) else {
                fatalError("SAWTI_TEST_HOME must be a child of the system temporary directory")
            }
        } else {
            // Keep direct XCTest launches away from the user's app-support
            // data even when the isolation wrapper was not used. This only
            // redirects app-owned file paths; macOS UserDefaults remains
            // managed separately by the test suite's DefaultsSuite helper.
            candidate = temporaryDirectory.appendingPathComponent(
                "MeetingTranscriberTests-\(ProcessInfo.processInfo.processIdentifier)",
                isDirectory: true,
            )
        }
        return candidate
    }()

    /// User Library/Application Support. Tests derive this from their isolated
    /// home instead of FileManager's real user-domain search result.
    static let applicationSupportDirectory: URL = {
        if isRunningTests {
            return homeDirectory
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
        }
        return FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? homeDirectory.appendingPathComponent("Library/Application Support", isDirectory: true)
    }()

    /// Sawti data directory: `~/Library/Application Support/Sawti/`.
    /// This separate namespace prevents the fork from reading, migrating, or
    /// modifying data created by an installed Meeting Transcriber app.
    /// In sandbox, this automatically resolves to the container path.
    /// Falls back to `~/.Sawti/` if Application Support is unavailable.
    static let dataDir: URL = {
        if isRunningTests || FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first != nil {
            return applicationSupportDirectory.appendingPathComponent("Sawti", isDirectory: true)
        }
        Logger(subsystem: logSubsystem, category: "AppPaths")
            .error("Application Support directory unavailable — falling back to home directory")
        return homeDirectory
            .appendingPathComponent(".Sawti", isDirectory: true)
    }()

    /// IPC directory: under `dataDir` for sandbox compatibility.
    static let ipcDir = dataDir.appendingPathComponent("ipc", isDirectory: true)

    /// Recordings directory.
    static let recordingsDir = dataDir.appendingPathComponent("recordings", isDirectory: true)

    /// Protocols output directory (legacy, inside Application Support).
    static let protocolsDir = dataDir.appendingPathComponent("protocols", isDirectory: true)

    /// Default transcripts output in Downloads: `~/Downloads/Sawti/`.
    /// In sandbox, `FileManager.urls(for: .downloadsDirectory)` resolves to the container-granted path.
    static let downloadsProtocolsDir: URL = {
        if isRunningTests {
            return homeDirectory
                .appendingPathComponent("Downloads", isDirectory: true)
                .appendingPathComponent("Sawti", isDirectory: true)
        }
        guard let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
        else {
            return protocolsDir
        }
        return downloads.appendingPathComponent("Sawti", isDirectory: true)
    }()

    /// Speaker voice profiles DB.
    static let speakersDB = dataDir.appendingPathComponent("speakers.json")

    /// Custom protocol prompt file.
    static let customPromptFile = dataDir.appendingPathComponent("protocol_prompt.md")

    /// Exists exactly while a run of this bundle is alive; see `LivenessMarker`.
    /// Named per bundle identifier because the dev and release builds share
    /// `dataDir`, and each must judge only its own previous run: one build's
    /// leftover must not read as the other's crash. Kept out of
    /// `recordingsDir`, which is scanned for crash signatures by filename.
    static let livenessMarker = dataDir
        .appendingPathComponent("\(Bundle.main.bundleIdentifier ?? "com.nourchkair.sawti").running")

    /// Sawti's own pre-sandbox IPC directory. Deliberately does not import
    /// `~/.meeting-transcriber/`, which belongs to the separate upstream app.
    static let legacyIpcDir = homeDirectory
        .appendingPathComponent(".sawti", isDirectory: true)

    private static let logger = Logger(subsystem: logSubsystem, category: "AppPaths")

    /// Migrate IPC files from Sawti's legacy `~/.sawti/` directory to `dataDir/ipc/`.
    /// Safe to call multiple times — copyItem fails gracefully if destination exists.
    static func migrateIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: legacyIpcDir.path) else { return }

        let filesToMigrate = [
            "processed_recordings.json",
            "pipeline_queue.json",
            "pipeline_log.jsonl",
        ]

        try? fm.createDirectory(at: ipcDir, withIntermediateDirectories: true)

        for name in filesToMigrate {
            let src = legacyIpcDir.appendingPathComponent(name)
            let dst = ipcDir.appendingPathComponent(name)
            do {
                try fm.copyItem(at: src, to: dst)
                logger.info("Migrated \(name) from legacy IPC directory")
            } catch CocoaError.fileWriteFileExists {
                // Already migrated — expected on subsequent launches
            } catch CocoaError.fileReadNoSuchFile {
                // Source doesn't exist — skip
            } catch {
                logger.error("Failed to migrate \(name): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
