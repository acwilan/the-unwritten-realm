import Foundation

public struct CoopJournalRecord: Codable, Equatable, Sendable {
    public let event: CommittedCoopEvent
    public init(event: CommittedCoopEvent) { self.event = event }
}

public struct CoopSnapshotEnvelope: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let savedAt: Date
    public let state: CoopCampaignState
    public init(state: CoopCampaignState, savedAt: Date = Date()) { schemaVersion = CoopCampaignState.currentSchemaVersion; self.savedAt = savedAt; self.state = state }
}

public protocol CoopCampaignJournalStore: Sendable {
    func load() throws -> (state: CoopCampaignState, events: [CommittedCoopEvent])?
    func saveSnapshot(_ state: CoopCampaignState) throws
    func append(_ events: [CommittedCoopEvent]) throws
}

/// Snapshot and journal files are separate so replay and migration remain
/// explicit. The append operation is atomic at the record level and snapshots
/// are replaced atomically.
public struct JSONCoopCampaignJournalStore: CoopCampaignJournalStore {
    public let snapshotURL: URL
    public let journalURL: URL

    public init(directory: URL) {
        snapshotURL = directory.appendingPathComponent("campaign-snapshot-v1.json")
        journalURL = directory.appendingPathComponent("campaign-events-v1.jsonl")
    }

    public func load() throws -> (state: CoopCampaignState, events: [CommittedCoopEvent])? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        let envelope = try JSONDecoder.coop.decode(CoopSnapshotEnvelope.self, from: Data(contentsOf: snapshotURL))
        guard envelope.schemaVersion <= CoopCampaignState.currentSchemaVersion else { throw CoopStoreError.unsupportedSchema }
        guard FileManager.default.fileExists(atPath: journalURL.path) else { return (envelope.state, []) }
        let records = try Data(contentsOf: journalURL).split(separator: 10).compactMap { try? JSONDecoder.coop.decode(CoopJournalRecord.self, from: Data($0)).event }
        return (envelope.state, records.filter { $0.sequence > envelope.state.revision })
    }

    public func saveSnapshot(_ state: CoopCampaignState) throws {
        let directory = snapshotURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder.coop.encode(CoopSnapshotEnvelope(state: state)).write(to: snapshotURL, options: .atomic)
    }

    public func append(_ events: [CommittedCoopEvent]) throws {
        guard !events.isEmpty else { return }
        let directory = journalURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let handle: FileHandle
        if FileManager.default.fileExists(atPath: journalURL.path) { handle = try FileHandle(forWritingTo: journalURL); try handle.seekToEnd() }
        else { FileManager.default.createFile(atPath: journalURL.path, contents: nil); handle = try FileHandle(forWritingTo: journalURL) }
        defer { try? handle.close() }
        for event in events {
            handle.write(try JSONEncoder.coop.encode(CoopJournalRecord(event: event)))
            handle.write(Data([10]))
        }
    }
}

public enum CoopStoreError: Error, Equatable, Sendable { case unsupportedSchema; case invalidReplay }

public enum CoopReplay {
    public static func apply(_ events: [CommittedCoopEvent], to initial: CoopCampaignState) throws -> CoopCampaignState {
        var state = initial
        for event in events where event.sequence > state.revision { state = try state.reduced(by: event.payload) }
        return state
    }
}

private extension JSONEncoder {
    static let coop: JSONEncoder = {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .iso8601; return encoder
    }()
}

private extension JSONDecoder {
    static let coop: JSONDecoder = { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }()
}
