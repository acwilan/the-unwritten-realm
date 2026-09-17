import Foundation
import SwiftUI

@MainActor
public final class CoopModeSession: ObservableObject {
    @Published public private(set) var state: CoopCampaignState?
    @Published public private(set) var projection: CoopStateProjection?
    @Published public private(set) var isHost = false
    @Published public private(set) var isBrowsing = false
    @Published public private(set) var discoveredPeers: [String] = []
    @Published public private(set) var pendingPlayers: [CoopPlayerID: String] = [:]
    @Published public private(set) var isProcessing = false
    @Published public private(set) var foundationModelAvailability: FoundationModelAvailability = FoundationModelStatus.current
    @Published public var errorMessage: String?

    public private(set) var localPlayerID: CoopPlayerID
    private var runtime: HostGameRuntime?
    private var transport: (any CoopGameTransport)?
    private var eventTask: Task<Void, Never>?
    private var pendingPeerIDs: [CoopPlayerID: CoopPeerID] = [:]
    private var hostPeerID: CoopPeerID?

    public init(localPlayerID: CoopPlayerID? = nil) {
        self.localPlayerID = localPlayerID ?? (try? CoopInstallationIdentity().installationID) ?? UUID()
    }

    public func host(difficulty: CampaignDifficulty = .easy) {
        let campaign = CoopStarterCampaign.make(difficulty: difficulty)
        localPlayerID = CoopStarterCampaign.hostPlayerID
        state = campaign; isHost = true; isBrowsing = false
        let interpreter = FallbackCoopInterpreter(primary: AIProviderCoopInterpreter(provider: GameSession.defaultAI()), fallback: DeterministicCoopInterpreter())
        let narrator = FallbackCoopNarrator(primary: AIProviderCoopNarrator(provider: GameSession.defaultAI()), fallback: TemplateCoopNarrator())
        runtime = HostGameRuntime(state: campaign, interpreter: interpreter, narrator: narrator, initialEvents: [CoopStarterCampaign.openingEvent])
        projection = CoopStateProjection(state: campaign, playerID: localPlayerID, events: [CoopStarterCampaign.openingEvent])
        startListening(with: makeTransport(), hosting: true)
    }

    public func browse() {
        isBrowsing = true; isHost = false
        startListening(with: makeTransport(), hosting: false)
    }

    public func invite(_ peerID: CoopPeerID) {
        guard let transport else { return }
        Task { try? await transport.invite(peerID: peerID) }
    }

    public func approve(_ playerID: CoopPlayerID) {
        guard let runtime else { return }
        Task { @MainActor in
            do {
                let peerID = pendingPeerIDs[playerID] ?? "pending-\(playerID.uuidString)"
                _ = try await runtime.approve(playerID: playerID, peerID: peerID)
                pendingPlayers.removeValue(forKey: playerID)
                pendingPeerIDs.removeValue(forKey: playerID)
                await synchronizeHostAndPlayers()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    public func submit(_ text: String) {
        guard let projection, !isProcessing, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let submission = CoopPlayerIntentSubmission(campaignID: projection.campaignID, playerID: localPlayerID, baseRevision: projection.revision, text: text)
        isProcessing = true
        Task { @MainActor in
            defer { self.isProcessing = false }
            if let runtime {
                let response = await runtime.receive(submission)
                await synchronizeHostAndPlayers()
                if !response.accepted { self.errorMessage = response.reason ?? "The host rejected that action." }
            } else if let transport, let hostPeerID {
                do {
                    let envelope = CoopWireEnvelope(sessionID: UUID(), senderPeerID: "client-\(localPlayerID.uuidString)", payload: CoopTransportMessage.intent(submission))
                    try await transport.send(try JSONEncoder.coop.encode(envelope), to: .peers([hostPeerID]), reliability: .reliable)
                } catch { self.errorMessage = error.localizedDescription }
            }
        }
    }

    public func claim(_ characterID: CoopCharacterID) {
        guard let projection else { return }
        let commandID = UUID()
        Task { @MainActor in
            if let runtime {
                do { _ = try await runtime.claimCharacter(playerID: localPlayerID, characterID: characterID, commandID: commandID); await refresh() }
                catch { errorMessage = error.localizedDescription }
            } else if let transport, let hostPeerID {
                do {
                    let payload = CoopTransportMessage.characterClaim(playerID: localPlayerID, characterID: characterID, commandID: commandID)
                    let envelope = CoopWireEnvelope(sessionID: projection.campaignID, senderPeerID: "client-\(localPlayerID.uuidString)", payload: payload)
                    try await transport.send(try JSONEncoder.coop.encode(envelope), to: .peers([hostPeerID]), reliability: .reliable)
                } catch { errorMessage = error.localizedDescription }
            }
        }
    }

    public func stop() {
        eventTask?.cancel(); eventTask = nil
        if let transport { Task { await transport.disconnect() } }
        transport = nil; runtime = nil; state = nil; projection = nil; isHost = false; isBrowsing = false
        discoveredPeers = []; pendingPlayers = [:]; pendingPeerIDs = [:]; hostPeerID = nil; isProcessing = false
    }

    private func startListening(with transport: any CoopGameTransport, hosting: Bool) {
        self.transport = transport
        eventTask?.cancel()
        eventTask = Task { [weak self] in
            guard let self else { return }
            for await event in transport.events { await self.handle(event) }
        }
        Task {
            do { if hosting { try await transport.startHosting() } else { try await transport.startBrowsing() } }
            catch { self.errorMessage = error.localizedDescription }
        }
    }

    private func makeTransport() -> any CoopGameTransport {
        #if targetEnvironment(simulator)
        // Simulator does not provide the iOS local-network privacy path used by
        // Bonjour/Multipeer Connectivity. Keep the simulator path deterministic
        // and in-process so UI and protocol flows remain testable from Xcode.
        return LoopbackCoopTransport()
        #elseif canImport(MultipeerConnectivity)
        // MCPeerID display names must be unique within a nearby session. A
        // short per-session suffix avoids collisions when two devices run the
        // same app without exposing a user's device name.
        let suffix = String(UUID().uuidString.prefix(4))
        return MultipeerGameTransport(displayName: "Unwritten Realm \(suffix)")
        #else
        return LoopbackCoopTransport()
        #endif
    }

    private func refresh() async {
        guard let runtime else { return }
        state = await runtime.snapshot(); projection = await runtime.projection(for: localPlayerID)
    }

    /// Refresh the host UI and send each approved player a projection made for
    /// that player. Projections are individualized so private observations do
    /// not leak between players.
    private func synchronizeHostAndPlayers() async {
        guard isHost, let runtime else { return }
        let snapshot = await runtime.snapshot()
        state = snapshot
        projection = await runtime.projection(for: localPlayerID)

        guard let transport else { return }
        for player in snapshot.party.players.values where player.id != localPlayerID && player.approved {
            guard let peerID = player.peerID else { continue }
            let playerProjection = await runtime.projection(for: player.id)
            await send(.stateProjection(playerProjection), to: peerID, using: transport)
        }
    }

    private func send(_ message: CoopTransportMessage, to peerID: CoopPeerID, using transport: any CoopGameTransport) async {
        do {
            let envelope = CoopWireEnvelope(
                sessionID: UUID(),
                senderPeerID: isHost ? "host" : "client-\(localPlayerID.uuidString)",
                payload: message
            )
            try await transport.send(
                try JSONEncoder.coop.encode(envelope),
                to: .peers([peerID]),
                reliability: .reliable
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handle(_ event: CoopTransportEvent) async {
        switch event {
        case .discovered(let peerID, _): if !discoveredPeers.contains(peerID) { discoveredPeers.append(peerID) }
        case .failed(let message): errorMessage = message
        case .connected(let peerID):
            if !isHost {
                hostPeerID = peerID
                guard let transport else { return }
                let join = CoopWireEnvelope(sessionID: UUID(), senderPeerID: "client-\(localPlayerID.uuidString)", payload: CoopTransportMessage.joinRequest(displayName: "Player", playerID: localPlayerID, protocolVersion: 1))
                try? await transport.send(try JSONEncoder.coop.encode(join), to: .peers([peerID]), reliability: .reliable)
            }
        case .disconnected(let peerID):
            if hostPeerID == peerID {
                hostPeerID = nil
                projection = nil
                errorMessage = "The host ended the co-op session."
            }
        case .received(let peerID, let data): await receive(data, from: peerID)
        }
    }

    private func receive(_ data: Data, from peerID: CoopPeerID) async {
        guard let envelope = try? JSONDecoder.coop.decode(CoopWireEnvelope<CoopTransportMessage>.self, from: data) else { return }
        switch envelope.payload {
        case .joinRequest(let displayName, let playerID, _):
            guard isHost, let runtime else { return }
            do {
                let player = try await runtime.registerPlayer(displayName: displayName, playerID: playerID, peerID: peerID)
                if player.approved {
                    await synchronizeHostAndPlayers()
                } else {
                    pendingPlayers[player.id] = player.displayName; pendingPeerIDs[player.id] = peerID
                }
            } catch { errorMessage = error.localizedDescription }
        case .stateProjection(let projection):
            guard projection.campaignID == self.projection?.campaignID || self.projection == nil else { return }
            guard projection.revision >= (self.projection?.revision ?? 0) else { return }
            self.projection = projection
        case .hostResponse(let response):
            guard response.projection.campaignID == self.projection?.campaignID || self.projection == nil else { return }
            guard response.projection.revision >= (self.projection?.revision ?? 0) else { return }
            self.projection = response.projection
            if !response.accepted { errorMessage = response.reason ?? "The host rejected that action." }
        case .intent(let submission):
            guard isHost, let runtime, let transport else { return }
            let response = await runtime.receive(submission)
            await synchronizeHostAndPlayers()
            await send(.hostResponse(response), to: peerID, using: transport)
        case .characterClaim(let playerID, let characterID, let commandID):
            guard isHost, let runtime, let transport else { return }
            do {
                _ = try await runtime.claimCharacter(playerID: playerID, characterID: characterID, commandID: commandID)
                await synchronizeHostAndPlayers()
            } catch {
                let projection = await runtime.projection(for: playerID)
                await send(
                    .hostResponse(CoopHostResponse(accepted: false, reason: error.localizedDescription, projection: projection)),
                    to: peerID,
                    using: transport
                )
            }
        case .resyncRequest:
            guard isHost, let runtime, let transport else { return }
            let snapshot = await runtime.snapshot()
            guard let player = snapshot.party.players.values.first(where: { $0.peerID == peerID }) else { return }
            let playerProjection = await runtime.projection(for: player.id)
            await send(.stateProjection(playerProjection), to: peerID, using: transport)
        case .eventBatch, .acknowledgement, .heartbeat: break
        }
    }
}

private extension JSONEncoder {
    static let coop: JSONEncoder = { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }()
}

private extension JSONDecoder {
    static let coop: JSONDecoder = { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }()
}
