import Foundation

/// Local read classification only; no new backend wire or Canvas authority.
public enum DJConnectCanvasReadFailure: Error, Equatable, Sendable {
    case notOffered
    case invalidSnapshot
}

public struct DJConnectCanvasPresentation: Codable, Equatable, Sendable {
    public var matte: String
    public var show_track_title: Bool
    public var composition: String?
    public var cadence: String?
    public var matte_size: String?
    public var match_frame: Bool?
    public var frame_finish: String?

    public static let frameMatte = "frame"
    public static let frameFinishes = ["white", "teak", "walnut", "sand_gold", "terracotta"]
    public static let defaultFrameFinish = "teak"
    public var matteChoice: String { match_frame == true ? Self.frameMatte : matte }

    public mutating func selectMatte(_ choice: String) {
        if choice == Self.frameMatte {
            matte = "matching"
            match_frame = true
        } else {
            matte = choice
            if match_frame == true { match_frame = false }
        }
    }

    public static let matteSizes = ["small", "medium", "large"]
    public static let mattes = ["off", "matching", "contrast"]
}

public struct DJConnectCanvasPreferences: Codable, Equatable, Sendable {
    public var enabled: Bool
    public var selected_targets: [String]
    public var composition: String
    public var matte: String
    public var cadence: String
    public var cadence_overrides: [String: String]
    public var show_track_title: Bool?
    public var presentation_overrides: [String: DJConnectCanvasPresentation]?

    public func presentation(for target: DJConnectCanvasTarget) -> DJConnectCanvasPresentation {
        if let style = presentation_overrides?[target.id] { return style }
        if target.adapter == "switchbot" {
            return DJConnectCanvasPresentation(matte: "off", show_track_title: false)
        }
        return DJConnectCanvasPresentation(matte: matte, show_track_title: show_track_title ?? false)
    }

    public mutating func updatePresentation(
        for target: DJConnectCanvasTarget, _ update: (inout DJConnectCanvasPresentation) -> Void
    ) {
        guard presentation_overrides != nil else { return }
        var style = presentation(for: target)
        update(&style)
        presentation_overrides?[target.id] = style
    }

    public var isValid: Bool {
        ["central", "free", "full"].contains(composition) &&
        DJConnectCanvasPresentation.mattes.contains(matte) &&
        Self.cadences.contains(cadence) && selected_targets.count <= 16 &&
        Set(selected_targets).count == selected_targets.count &&
        Set(cadence_overrides.keys).isSubset(of: Set(selected_targets)) &&
        cadence_overrides.values.allSatisfy(Self.cadences.contains) &&
        (presentation_overrides?.values.allSatisfy { style in
            DJConnectCanvasPresentation.mattes.contains(style.matte)
                && (style.composition.map(Self.compositions.contains) ?? true)
                && (style.cadence.map(Self.cadences.contains) ?? true)
                && (style.matte_size.map(DJConnectCanvasPresentation.matteSizes.contains) ?? true)
                && (style.match_frame != true || style.matte == "matching")
                && (style.frame_finish.map(DJConnectCanvasPresentation.frameFinishes.contains) ?? true)
        } ?? true)
    }
    public static let compositions = ["central", "free", "full"]
    public static let cadences = ["track", "900", "1800", "3600"]
}

public struct DJConnectCanvasScreen: Codable, Equatable, Sendable {
    public var width: Int?
    public var height: Int?
    public var orientation: String?
    public var diagonal_inches: Double?
    public var provenance: String?
    public init(width: Int? = nil, height: Int? = nil, orientation: String? = nil) {
        self.width = width; self.height = height; self.orientation = orientation
    }
}

public struct DJConnectCanvasTarget: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let adapter: String
    public let state: String
    public let screen: DJConnectCanvasScreen
    public let remote_cleanup: Bool
    public let preview_available: Bool
    public let can_request_artwork: Bool?
    public let artwork_request_pending: Bool?
    public let artwork_preview_revision: String?
    public let preview_revision: String?
    public let shared_profiles: Int
    public let forgetting: Bool?
}

public struct DJConnectCanvasSnapshot: Decodable, Equatable, Sendable {
    public let success: Bool
    public let contract_version: Int
    public let binding: String
    public let revision: Int
    public let preferences: DJConnectCanvasPreferences
    public let targets: [DJConnectCanvasTarget]
    public let image_generation_available: Bool
    public let manual_artwork_refresh: Bool?
    public let can_manage_devices: Bool
    public let per_screen_composition_and_cadence: Bool?
    public let per_screen_matte_size: Bool?
    public let frame_matching_matte: Bool?
    public var isValid: Bool {
        success && contract_version == 1 && binding.count == 64 &&
        binding.allSatisfy({ $0.isHexDigit && $0.isASCII }) && revision >= 0 &&
        preferences.isValid && targets.count <= 64 && Set(targets.map(\.id)).count == targets.count &&
        Set(preferences.selected_targets).isSubset(of: Set(targets.map(\.id))) &&
        (preferences.presentation_overrides.map { Set($0.keys).isSubset(of: Set(targets.map(\.id))) } ?? true) &&
        targets.allSatisfy { target in
            ["samsung", "switchbot"].contains(target.adapter) &&
            !target.id.isEmpty && target.id.utf8.count <= 128 &&
            !target.name.isEmpty && target.name.count <= 128 &&
            target.shared_profiles >= 0 &&
            (target.preview_revision.map { revision in
                target.preview_available && revision.utf8.count == 64 &&
                revision.allSatisfy { $0.isASCII && $0.isHexDigit }
            } ?? true) &&
            (target.artwork_preview_revision.map { revision in
                revision.utf8.count == 64 && revision.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
            } ?? true) &&
            (target.adapter != "switchbot" || !target.remote_cleanup) &&
            (target.screen.width.map { (256...8192).contains($0) } ?? true) &&
            (target.screen.height.map { (256...8192).contains($0) } ?? true) &&
            (target.screen.orientation.map { ["portrait", "landscape"].contains($0) } ?? true)
        }
    }
}

public struct DJConnectCanvasReceipt: Decodable, Sendable {
    public let success: Bool
    public let contract_version: Int
    public let binding: String
    public let operation_id: String
    public let state: String?
    public let revision: Int?
    public let remaining_art: Bool?
    public let error: String?
}

/// A closed additive contract; synthesized optionals omit unrelated route fields.
struct DJConnectCanvasRequest: Encodable {
    let contract_version = 1
    let device_id: String
    let client_type: String
    var binding: String?
    var operation_id: String?
    var expected_revision: Int?
    var patch: DJConnectCanvasPreferences?
    var target_id: String?
    var preview_revision: String?
    var screen: DJConnectCanvasScreen?
    var cleanup_remote: Bool?
    var allow_remaining_art: Bool?
}
