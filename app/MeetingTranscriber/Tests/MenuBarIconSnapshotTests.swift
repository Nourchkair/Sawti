@testable import MeetingTranscriber
import SnapshotTesting
import XCTest

@MainActor
final class MenuBarIconSnapshotTests: XCTestCase {
    private var isCI: Bool {
        ProcessInfo.processInfo.environment["CI"] != nil
    }

    /// Byte-exact image comparison tests the rasteriser as much as the icon. An
    /// Xcode update re-renders every badge identically to the eye and fails all
    /// 29 references at once, which is exactly what happened between May and
    /// August and cost half an hour to prove harmless. A perceptual tolerance
    /// absorbs that.
    ///
    /// It is not blind: the smallest genuine difference in this suite is one
    /// animation frame against its neighbour, and those still fail against each
    /// other at these values. Anything a person would call a changed badge fails
    /// by a wide margin.
    private static let icon = Snapshotting<NSImage, NSImage>.image(
        precision: 0.99, perceptualPrecision: 0.98,
    )

    /// Snapshots are compared at the status-bar's logical size, regardless of
    /// whether a template is backed by a 36 px raster or the source logo's
    /// high-resolution representation.
    private func statusBarSized(_ image: NSImage) -> NSImage {
        let normalized = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            image.draw(
                in: rect,
                from: NSRect(origin: .zero, size: image.size),
                operation: .sourceOver,
                fraction: 1,
            )
            return true
        }
        normalized.isTemplate = image.isTemplate
        return normalized
    }

    override func invokeTest() {
        withSnapshotTesting(record: .missing) {
            super.invokeTest()
        }
    }

    func testStaticBadgeSnapshots() throws {
        try XCTSkipIf(isCI, "Snapshot tests are machine-dependent")
        let staticBadges: [BadgeKind] = [.inactive, .userAction, .done, .error, .updateAvailable]
        for badge in staticBadges {
            let image = statusBarSized(MenuBarIcon.image(badge: badge))
            assertSnapshot(of: image, as: Self.icon, named: "\(badge)")
        }
    }

    func testRecordingAnimationFrames() throws {
        try XCTSkipIf(isCI, "Snapshot tests are machine-dependent")
        for frame in 0 ..< MenuBarIcon.frameCount {
            let image = MenuBarIcon.image(badge: .recording, animationFrame: frame)
            assertSnapshot(of: image, as: Self.icon, named: "frame\(frame)")
        }
    }

    func testTranscribingAnimationFrames() throws {
        try XCTSkipIf(isCI, "Snapshot tests are machine-dependent")
        for frame in 0 ..< MenuBarIcon.frameCount {
            let image = MenuBarIcon.image(badge: .transcribing, animationFrame: frame)
            assertSnapshot(of: image, as: Self.icon, named: "frame\(frame)")
        }
    }

    func testDiarizingAnimationFrames() throws {
        try XCTSkipIf(isCI, "Snapshot tests are machine-dependent")
        for frame in 0 ..< MenuBarIcon.frameCount {
            let image = MenuBarIcon.image(badge: .diarizing, animationFrame: frame)
            assertSnapshot(of: image, as: Self.icon, named: "frame\(frame)")
        }
    }

    func testProcessingAnimationFrames() throws {
        try XCTSkipIf(isCI, "Snapshot tests are machine-dependent")
        for frame in 0 ..< MenuBarIcon.frameCount {
            let image = MenuBarIcon.image(badge: .processing, animationFrame: frame)
            assertSnapshot(of: image, as: Self.icon, named: "frame\(frame)")
        }
    }

    func testAllBadgesProduceNonEmptyImages() {
        for badge in BadgeKind.allCases {
            let frameCount = badge.isAnimated ? MenuBarIcon.frameCount : 1
            for frame in 0 ..< frameCount {
                let image = MenuBarIcon.image(badge: badge, animationFrame: frame)
                // Verify the image has actual pixel data (not a blank image)
                guard let tiff = image.tiffRepresentation,
                      let bitmap = NSBitmapImageRep(data: tiff)
                else {
                    XCTFail("Could not get bitmap for \(badge) frame \(frame)")
                    continue
                }
                // At least some pixels should be non-transparent
                var hasContent = false
                for y in 0 ..< bitmap.pixelsHigh {
                    for x in 0 ..< bitmap.pixelsWide {
                        if let color = bitmap.colorAt(x: x, y: y),
                           color.alphaComponent > 0 {
                            hasContent = true
                            break
                        }
                    }
                    if hasContent { break }
                }
                XCTAssertTrue(hasContent, "\(badge) frame \(frame) should have visible content")
            }
        }
    }

    func testInactiveUsesTheNativeSizedTemplateLogo() throws {
        let image = MenuBarIcon.image(badge: .inactive)

        XCTAssertTrue(image.isTemplate, "macOS must tint the idle mark for the current menu-bar appearance")
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))

        let bitmap = try XCTUnwrap(
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
            "the idle logo must retain its bitmap content",
        )
        let visiblePixels = (0 ..< bitmap.pixelsHigh).reduce(into: 0) { count, y in
            count += (0 ..< bitmap.pixelsWide).filter { x in
                (bitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.05
            }.count
        }
        XCTAssertGreaterThan(visiblePixels, 100, "the menu-bar logo must have a visible alpha mask")
    }

    func testInactiveLogoIsTintedWhenRenderedWithAColoredOverlay() throws {
        let application = NSApplication.shared
        let previousAppearance = application.appearance
        application.appearance = NSAppearance(named: .darkAqua)
        defer { application.appearance = previousAppearance }

        let image = MenuBarIcon.image(badge: .inactive, permissionOverlay: true)
        XCTAssertFalse(image.isTemplate, "red overlays require explicit colors")

        let bitmap = try XCTUnwrap(
            image.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:)),
            "the overlaid idle logo must retain its bitmap content",
        )
        var lightLogoPixels = 0
        for y in 0 ..< bitmap.pixelsHigh {
            for x in 0 ..< bitmap.pixelsWide {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { continue }
                let isVisible = color.alphaComponent > 0.05
                let isLightAndNeutral = color.redComponent > 0.75
                    && color.greenComponent > 0.75
                    && color.blueComponent > 0.75
                if isVisible, isLightAndNeutral { lightLogoPixels += 1 }
            }
        }
        XCTAssertGreaterThan(lightLogoPixels, 50, "the idle mark must stay visible on a dark menu bar with overlays")
    }
}
