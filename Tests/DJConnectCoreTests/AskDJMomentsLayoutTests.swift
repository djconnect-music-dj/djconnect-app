import Foundation
import SwiftUI
import Testing
@testable import DJConnectCore
@testable import DJConnectUI
#if os(macOS)
import AppKit

/// Actual shared catalogue/card geometry; original Core content remains Dutch.
/// Five client chrome locales are not five real-model narration acceptance claims.
@Test(.isolatedAppKitResources) @MainActor func momentsNativeCatalogueRendersPhoneWideAndAccessibleTypeInFiveClientLocales() async throws {
    _ = NSApplication.shared
    let url = try #require(askDJMomentsFixtureURL("producer-final"))
    let packet = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    let raw = try JSONSerialization.data(withJSONObject: try #require(packet["inventory"]))
    let inventory = try JSONDecoder().decode(DJConnectAskDJMoments.Inventory.self, from: raw)
    let wire = try MomentsControllerWire(lateFailure: false)
    let identity = DJConnectIdentity(deviceID: "declared-layout-fixture", deviceName: "Fixture", clientType: .ios,
                                    firmware: "4.1.0", appVersion: "4.1.0", platform: .ios)
    let store = DJConnectInMemoryTokenStore(token: "declared-layout-token")
    let origin = try #require(URL(string: "https://paired.example"))
    let hybrid = DJConnectHybridTransport(localURL: nil, remoteURL: origin, expectedInstallID: "controller-fixture-install",
                                         identity: identity, tokenStore: store, wire: wire)
    let client = DJConnectClient(baseURL: origin, identity: identity, tokenStore: store, hybridTransport: hybrid)
    let scope = AskDJMomentsController.Scope(profileID: "declared-layout-profile", sessionID: inventory.sessionID,
        binding: "fixture-binding", settingsGeneration: "fixture-generation", voiceRevision: "fixture-voice",
        historyEpoch: UUID(), connection: UUID(), revision: 1)
    let controller = AskDJMomentsController(testClient: client, scope: { scope })
    defer { controller.close() }
    controller.open()
    for _ in 0..<500 { if controller.inventory != nil { break }; try await Task.sleep(for: .milliseconds(2)) }
    try #require(controller.inventory != nil)
    let visible = inventory.visibleTypes
    #expect(!visible.isEmpty && visible.count < inventory.types.count)
    for language in ["en", "nl", "de", "fr", "es"] {
        for width: CGFloat in [390, 960] {
            let content = SessionCurrentDJCard(sessionID: inventory.sessionID, state: .expanded, mood: nil) {
                DJPersonaAvatarView(confirmedMood: nil, language: language).frame(width: 80, height: 80)
            } detail: {
                AskDJMomentsCardContent(controller: controller, language: language, result: { AnyView(EmptyView()) })
            }
            .environment(\.dynamicTypeSize, .accessibility2)
            .environment(\.djConnectGlassEffectsEnabled, false)
            .frame(width: width).padding(12).foregroundStyle(.white).background(Color.indigo)
            // Native hosting is required: ImageRenderer omits AppKit scroll content.
            let host = NSHostingView(rootView: content.environment(\.colorScheme, .dark))
            let height = ceil(host.fittingSize.height)
            #expect(height > 100 && height < 1200)
            let window = NSWindow(contentRect: .init(x: -20000, y: -20000, width: width + 24, height: height),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .darkAqua); window.contentView = host
            window.orderBack(nil)
            try await Task.sleep(for: .milliseconds(50))
            host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
            #expect(host.bounds.width == width + 24)
            let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            window.close()

            func isTextInk(_ x: Int, _ y: Int) -> Bool {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return false }
                return min(color.redComponent, color.greenComponent, color.blueComponent) > 0.85
            }

            // Count the rendered title groups in the catalogue below the header.
            // Convert layout points to bitmap pixels using this capture's scale.
            let scale = CGFloat(bitmap.pixelsWide) / host.bounds.width
            func pixels(_ points: CGFloat) -> Int { Int((points * scale).rounded()) }
            let narrow = width == 390
            let columns = pixels(170)..<(bitmap.pixelsWide - pixels(24))
            let rows = pixels(80)..<(bitmap.pixelsHigh - pixels(20))
            let detected = narrow
                ? rows.filter { y in columns.contains { x in isTextInk(x, y) } }
                : columns.filter { x in rows.contains { y in isTextInk(x, y) } }
            let groups = zip(detected, detected.dropFirst()).filter { $1 - $0 > pixels(13) }.count
                + (detected.isEmpty ? 0 : 1)
            #expect(groups == visible.count, "\(language)/\(width): visible catalogue titles")

            // The close button's white xmark is the only bright ink in this
            // small top-trailing area. Look for each diagonal on both sides.
            let centerX = bitmap.pixelsWide - pixels(50)
            let centerY = pixels(50)
            for direction in [-1, 1] {
                for side in [-1, 1] {
                    let foundStroke = (pixels(3)...pixels(7)).contains { step in
                        (-pixels(2)...pixels(2)).contains { offset in
                            let x = centerX + step * side
                            let y = centerY + step * side * direction + offset
                            return isTextInk(x, y)
                        }
                    }
                    #expect(foundStroke, "\(language)/\(width): close mark diagonal must be visible")
                }
            }
            if let folder = ProcessInfo.processInfo.environment["DJCONNECT_ASK_MOMENTS_ARTIFACT_DIR"] {
                let directory = URL(fileURLWithPath: folder)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let png = try #require(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("moments-catalogue-\(language)-\(Int(width)).png"))
            }
        }
    }
    #expect(await wire.requestCount == 0, "Rendering/filtering never prepares a Moment")
    #expect(await wire.cancelCount == 0)
}
#endif
