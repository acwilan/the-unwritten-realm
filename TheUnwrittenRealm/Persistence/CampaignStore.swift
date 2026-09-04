import Foundation

public protocol CampaignStore: Sendable {
    func load() throws -> CampaignState?
    func save(_ state: CampaignState) throws
    func delete() throws
}

public struct JSONCampaignStore: CampaignStore {
    public let url: URL

    public init(url: URL? = nil) {
        self.url = url ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TheUnwrittenRealm", isDirectory: true)
            .appendingPathComponent("campaign-v1.json")
    }

    public func load() throws -> CampaignState? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        let state = try JSONDecoder.campaign.decode(CampaignState.self, from: data)
        guard state.schemaVersion <= CampaignState.currentSchemaVersion else { throw StoreError.unsupportedSchema }
        return state
    }

    public func save(_ state: CampaignState) throws {
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.campaign.encode(state).write(to: url, options: .atomic)
    }

    public func delete() throws {
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }
}

public enum StoreError: Error { case unsupportedSchema }

private extension JSONEncoder {
    static var campaign: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var campaign: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
