import Foundation

#if canImport(MultipeerConnectivity)
import MultipeerConnectivity
#endif

public enum CoopReliability: Sendable { case reliable, bestEffort }
public enum CoopRecipientSet: Sendable { case all, peers(Set<CoopPeerID>) }

public struct CoopWireEnvelope<Payload: Codable & Sendable>: Codable, Sendable {
    public let protocolVersion: UInt16
    public let messageID: UUID
    public let sessionID: UUID
    public let senderPeerID: CoopPeerID
    public let sentAt: Date
    public let payload: Payload
    public init(protocolVersion: UInt16 = 1, messageID: UUID = UUID(), sessionID: UUID, senderPeerID: CoopPeerID, sentAt: Date = Date(), payload: Payload) {
        self.protocolVersion = protocolVersion; self.messageID = messageID; self.sessionID = sessionID; self.senderPeerID = senderPeerID; self.sentAt = sentAt; self.payload = payload
    }
}

public enum CoopTransportMessage: Codable, Sendable {
    case joinRequest(displayName: String, playerID: CoopPlayerID, protocolVersion: UInt16)
    case characterClaim(playerID: CoopPlayerID, characterID: CoopCharacterID, commandID: UUID)
    case intent(CoopPlayerIntentSubmission)
    case eventBatch([CommittedCoopEvent])
    case stateProjection(CoopStateProjection)
    case hostResponse(CoopHostResponse)
    case acknowledgement(sequence: UInt64)
    case heartbeat
    case resyncRequest(afterSequence: UInt64)
}

public enum CoopTransportEvent: Sendable {
    case discovered(peerID: CoopPeerID, displayName: String)
    case connected(peerID: CoopPeerID)
    case disconnected(peerID: CoopPeerID)
    case received(peerID: CoopPeerID, data: Data)
    case failed(String)
}

public protocol CoopGameTransport: AnyObject, Sendable {
    var events: AsyncStream<CoopTransportEvent> { get }
    func startHosting() async throws
    func startBrowsing() async throws
    func invite(peerID: CoopPeerID) async throws
    func send(_ data: Data, to recipients: CoopRecipientSet, reliability: CoopReliability) async throws
    func disconnect() async
}

/// In-process transport used by solo mode and protocol tests. It deliberately
/// uses the same bytes and envelope as the nearby transport.
public final class LoopbackCoopTransport: CoopGameTransport, @unchecked Sendable {
    public let peerID: CoopPeerID
    public let events: AsyncStream<CoopTransportEvent>
    private let continuation: AsyncStream<CoopTransportEvent>.Continuation
    private var connected = false

    public init(peerID: CoopPeerID = UUID().uuidString) {
        self.peerID = peerID
        var continuation: AsyncStream<CoopTransportEvent>.Continuation!
        events = AsyncStream { continuation = $0 }
        self.continuation = continuation
    }

    public func startHosting() async throws { connected = true }
    public func startBrowsing() async throws { connected = true }
    public func invite(peerID: CoopPeerID) async throws { continuation.yield(.connected(peerID: peerID)) }
    public func send(_ data: Data, to recipients: CoopRecipientSet, reliability: CoopReliability) async throws {
        guard connected else { throw CoopRuntimeError("Transport is not connected.") }
        continuation.yield(.received(peerID: peerID, data: data))
    }
    public func disconnect() async { connected = false; continuation.finish() }
}

#if canImport(MultipeerConnectivity)
/// Nearby transport adapter. Discovery metadata contains only a display name
/// and protocol version; campaign state is exchanged only after approval.
public final class MultipeerGameTransport: NSObject, CoopGameTransport, @unchecked Sendable {
    public static let serviceType = "unwritten-realm"
    public let peerID: CoopPeerID
    public let events: AsyncStream<CoopTransportEvent>
    private let continuation: AsyncStream<CoopTransportEvent>.Continuation
    private let peer: MCPeerID
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser
    private let advertiser: MCNearbyServiceAdvertiser
    private var discovered: [CoopPeerID: MCPeerID] = [:]

    public init(displayName: String, peerID: CoopPeerID = UUID().uuidString) {
        self.peerID = peerID; self.peer = MCPeerID(displayName: displayName)
        self.session = MCSession(peer: self.peer, securityIdentity: nil, encryptionPreference: .required)
        self.browser = MCNearbyServiceBrowser(peer: self.peer, serviceType: Self.serviceType)
        self.advertiser = MCNearbyServiceAdvertiser(peer: self.peer, discoveryInfo: ["v": "1"], serviceType: Self.serviceType)
        var continuation: AsyncStream<CoopTransportEvent>.Continuation!
        events = AsyncStream { continuation = $0 }; self.continuation = continuation
        super.init()
        session.delegate = self; browser.delegate = self; advertiser.delegate = self
    }

    public func startHosting() async throws { advertiser.startAdvertisingPeer() }
    public func startBrowsing() async throws { browser.startBrowsingForPeers() }
    public func invite(peerID: CoopPeerID) async throws {
        guard let target = discovered[peerID] ?? session.connectedPeers.first(where: { $0.displayName == peerID }) else { throw CoopRuntimeError("Peer is not available.") }
        browser.invitePeer(target, to: session, withContext: nil, timeout: 15)
    }
    public func send(_ data: Data, to recipients: CoopRecipientSet, reliability: CoopReliability) async throws {
        let peers: [MCPeerID]
        switch recipients { case .all: peers = session.connectedPeers; case .peers(let ids): peers = session.connectedPeers.filter { ids.contains($0.displayName) } }
        guard !peers.isEmpty else { return }
        try session.send(data, toPeers: peers, with: reliability == .reliable ? .reliable : .unreliable)
    }
    public func disconnect() async { session.disconnect(); browser.stopBrowsingForPeers(); advertiser.stopAdvertisingPeer(); continuation.finish() }
}

extension MultipeerGameTransport: MCSessionDelegate, MCNearbyServiceBrowserDelegate, MCNearbyServiceAdvertiserDelegate {
    public func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state { case .connected: continuation.yield(.connected(peerID: peerID.displayName)); case .notConnected: continuation.yield(.disconnected(peerID: peerID.displayName)); default: break }
    }
    public func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) { continuation.yield(.received(peerID: peerID.displayName, data: data)) }
    public func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    public func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    public func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
    public func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) { discovered[peerID.displayName] = peerID; continuation.yield(.discovered(peerID: peerID.displayName, displayName: peerID.displayName)) }
    public func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) { discovered.removeValue(forKey: peerID.displayName); continuation.yield(.disconnected(peerID: peerID.displayName)) }
    public func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) { continuation.yield(.failed(error.localizedDescription)) }
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) { invitationHandler(true, session) }
    public func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) { continuation.yield(.failed(error.localizedDescription)) }
}
#endif
