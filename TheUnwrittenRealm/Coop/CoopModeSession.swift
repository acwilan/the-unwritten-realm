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
    @Published public private(set) var foundationModelAvailability: FoundationModelAvailability = FoundationModelStatus.current
    @Published public var errorMessage: String?

    public private(set) var localPlayerID: CoopPlayerID
    private var runtime: HostGameRuntime?
    private var transport: (any CoopGameTransport)?
    private var eventTask: Task<Void, Never>?
    private var pendingPeerIDs: [CoopPlayerID: CoopPeerID] = [:]
    private var hostPeerID: CoopPeerID?

    public init(localPlayerID: CoopPlayerID = UUID()) { self.localPlayerID = localPlayerID }

    public func host() {
        let campaign = CoopStarterCampaign.make()
        localPlayerID = CoopStarterCampaign.hostPlayerID
        state = campaign; isHost = true; isBrowsing = false
        let interpreter = FallbackCoopInterpreter(primary: AIProviderCoopInterpreter(provider: GameSession.defaultAI()), fallback: DeterministicCoopInterpreter())
        let narrator = FallbackCoopNarrator(primary: AIProviderCoopNarrator(provider: GameSession.defaultAI()), fallback: TemplateCoopNarrator())
        runtime = HostGameRuntime(state: campaign, interpreter: interpreter, narrator: narrator)
        projection = CoopStateProjection(state: campaign, playerID: localPlayerID)
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
                if let transport {
                    let projection = await runtime.projection(for: playerID)
                    let envelope = CoopWireEnvelope(sessionID: UUID(), senderPeerID: "host", payload: CoopTransportMessage.stateProjection(projection))
                    try await transport.send(try JSONEncoder.coop.encode(envelope), to: .peers([peerID]), reliability: .reliable)
                }
                pendingPlayers.removeValue(forKey: playerID)
                await refresh()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    public func submit(_ text: String) {
        guard let projection, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let submission = CoopPlayerIntentSubmission(campaignID: projection.campaignID, playerID: localPlayerID, baseRevision: projection.revision, text: text)
        Task { @MainActor in
            if let runtime {
                let response = await runtime.receive(submission)
                if response.accepted { self.projection = response.projection; self.state = await runtime.snapshot() }
                else { self.errorMessage = response.reason ?? "The host rejected that action." }
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
        #if canImport(MultipeerConnectivity)
        return MultipeerGameTransport(displayName: "Unwritten Realm")
        #else
        return LoopbackCoopTransport()
        #endif
    }

    private func refresh() async {
        guard let runtime else { return }
        state = await runtime.snapshot(); projection = await runtime.projection(for: localPlayerID)
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
        case .disconnected(let peerID): if hostPeerID == peerID { hostPeerID = nil }
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
                pendingPlayers[player.id] = player.displayName; pendingPeerIDs[player.id] = peerID
            } catch { errorMessage = error.localizedDescription }
        case .stateProjection(let projection): self.projection = projection
        case .intent(let submission):
            guard isHost, let runtime, let transport else { return }
            let response = await runtime.receive(submission)
            let envelope = CoopWireEnvelope(sessionID: UUID(), senderPeerID: "host", payload: CoopTransportMessage.stateProjection(response.projection))
            try? await transport.send(try JSONEncoder.coop.encode(envelope), to: .peers([peerID]), reliability: .reliable)
        case .characterClaim(let playerID, let characterID, let commandID):
            guard isHost, let runtime, let transport else { return }
            do {
                _ = try await runtime.claimCharacter(playerID: playerID, characterID: characterID, commandID: commandID)
                let projection = await runtime.projection(for: playerID)
                let envelope = CoopWireEnvelope(sessionID: UUID(), senderPeerID: "host", payload: CoopTransportMessage.stateProjection(projection))
                try await transport.send(try JSONEncoder.coop.encode(envelope), to: .peers([peerID]), reliability: .reliable)
            } catch { errorMessage = error.localizedDescription }
        case .eventBatch, .acknowledgement, .heartbeat, .resyncRequest: break
        }
    }
}

private extension JSONEncoder {
    static let coop: JSONEncoder = { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }()
}

private extension JSONDecoder {
    static let coop: JSONDecoder = { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }()
}
