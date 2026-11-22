import Foundation

/// Core-owned, versioned musical relationship. No client research or playback authority.
public struct DJConnectMusicOrigin: Codable, Equatable, Sendable {
    public struct Subject: Codable, Equatable, Sendable { public let title: String; public let artist: String }
    public struct Target: Codable, Equatable, Sendable { public let kind: String; public let title: String; public let artist: String }
    public struct Relation: Codable, Equatable, Sendable {
        public let kind: String
        public let direction: String
        public let uncertainty: String
        public let target: Target
    }
    public let schemaVersion: Int
    public let subject: Subject
    public let relation: Relation
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", subject, relation }
    public var isValid: Bool {
        schemaVersion == 1 && Self.text(subject.title, 160) && Self.text(subject.artist, 160)
            && Self.text(relation.target.title, 240) && relation.target.artist.count <= 160
            && relation.target.artist.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
            && ["recording", "work", "media"].contains(relation.target.kind)
            && ["sample", "interpolation", "cover", "remake", "remix", "earlier_performance", "media_use", "shared_source", "influence"].contains(relation.kind)
            && ["current_to_related", "related_to_current"].contains(relation.direction)
            && ["stated", "likely", "possible"].contains(relation.uncertainty)
            && (relation.kind == "media_use") == (relation.target.kind == "media")
            && (relation.target.kind != "media" || relation.direction == "current_to_related")
    }
    public var hasOriginalTarget: Bool {
        isValid && relation.direction == "current_to_related" && relation.target.kind != "media"
            && ["sample", "interpolation", "cover", "remake", "remix", "earlier_performance"].contains(relation.kind)
    }
    private static func text(_ value: String, _ limit: Int) -> Bool {
        !value.isEmpty && value.count <= limit && value == value.trimmingCharacters(in: .whitespacesAndNewlines)
            && value.unicodeScalars.allSatisfy { !CharacterSet.controlCharacters.contains($0) }
    }
}

extension DJConnectMoment {
    public var isMusicOriginV1: Bool {
        type == "music_origin" && musicOrigin?.isValid == true
            && knowledgeIntent?["type"] == "music_origin_story"
            && !title.isEmpty && !summary.isEmpty && !content.isEmpty && content.utf8.count <= 8_000
    }
}
