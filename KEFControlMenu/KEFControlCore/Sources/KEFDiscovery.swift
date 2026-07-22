//
// KEFDiscovery
// KEFControl
//
// Created by Alexander Babaev on 22 July 2026.
// Copyright © 2026 Alexander Babaev. All rights reserved.
//

import Foundation
import Memoirs
import Network

public struct DiscoveredSpeaker: Equatable, Sendable, Identifiable {
    public var id: String { instanceName }

    /// Bonjour instance, like `841715033A9C@LSXII`.
    public let instanceName: String
    /// Name the speakers are set to, like `Nano LSX`.
    public let name: String
    public let model: AudioSystem.Model
    /// Address to talk to, resolved to an IP where possible.
    public let address: String

    public init(instanceName: String, name: String, model: AudioSystem.Model, address: String) {
        self.instanceName = instanceName
        self.name = name
        self.model = model
        self.address = address
    }
}

private struct Advertisement: Sendable {
    let instanceName: String
    let endpoint: NWEndpoint
    let name: String?
    let model: String?
    let modelName: String?
}

/// Collects what the browser reports and resumes exactly once, however many times the Network framework calls back.
private actor BrowseSession {
    private var continuation: CheckedContinuation<[Advertisement], Never>?
    private var found: [Advertisement] = []
    private var isFinished: Bool = false

    func run(_ start: @Sendable @escaping () -> Void) async -> [Advertisement] {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            start()
        }
    }

    func keep(_ advertisements: [Advertisement]) {
        found = advertisements
    }

    func finish() {
        guard !isFinished else { return }

        isFinished = true
        continuation?.resume(returning: found)
        continuation = nil
    }
}

/// Same idea for a single resolved address.
private actor AddressSession {
    private var continuation: CheckedContinuation<String?, Never>?
    private var isFinished: Bool = false

    func run(_ start: @Sendable @escaping () -> Void) async -> String? {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            start()
        }
    }

    func finish(with address: String?) {
        guard !isFinished else { return }

        isFinished = true
        continuation?.resume(returning: address)
        continuation = nil
    }
}

/// Finds KEF speakers on the local network. They advertise `_kef-info._tcp`, with their name and model in the
/// TXT record, so a found speaker can fill in the settings on its own.
public actor KEFDiscovery {
    public static let serviceType: String = "_kef-info._tcp"

    public init() {
    }

    public func speakers(searchingFor seconds: TimeInterval = 3) async -> [DiscoveredSpeaker] {
        let advertisements = await browse(for: seconds)
        memoir.debug("Found \(advertisements.count) advertised speaker(s)")

        var result: [DiscoveredSpeaker] = []
        for advertisement in advertisements {
            guard let address = await address(of: advertisement.endpoint) else {
                memoir.warning("Can't resolve an address for \(advertisement.instanceName)")
                continue
            }

            let identifiers = [ advertisement.model, advertisement.modelName ].compactMap { $0 }
            result.append(
                DiscoveredSpeaker(
                    instanceName: advertisement.instanceName,
                    name: advertisement.name ?? advertisement.instanceName,
                    model: AudioSystem.Model(kefIdentifiers: identifiers),
                    address: address
                )
            )
        }
        return result.sorted { $0.name < $1.name }
    }

    private lazy var memoir: TracedMemoir = TracedMemoir(object: self, memoir: basicMemoir)
    private let queue: DispatchQueue = .init(label: "com.lonelybytes.kef.discovery")

    private func browse(for seconds: TimeInterval) async -> [Advertisement] {
        let session: BrowseSession = .init()
        let browser = NWBrowser(for: .bonjourWithTXTRecord(type: Self.serviceType, domain: nil), using: .tcp)

        return await session.run { [queue] in
            browser.browseResultsChangedHandler = { results, _ in
                // The browser keeps reporting; the timeout below decides when we have seen enough.
                let found = results.compactMap(Self.advertisement(from:))
                Task { await session.keep(found) }
            }
            browser.stateUpdateHandler = { state in
                guard case .failed = state else { return }

                Task {
                    await session.finish()
                    browser.cancel()
                }
            }
            browser.start(queue: queue)
            queue.asyncAfter(deadline: .now() + seconds) {
                Task {
                    await session.finish()
                    browser.cancel()
                }
            }
        }
    }

    private static func advertisement(from result: NWBrowser.Result) -> Advertisement? {
        guard case .service(let name, _, _, _) = result.endpoint else { return nil }

        var record: NWTXTRecord?
        if case .bonjour(let found) = result.metadata {
            record = found
        }
        return Advertisement(
            instanceName: name,
            endpoint: result.endpoint,
            name: record?["name"],
            model: record?["model"],
            modelName: record?["modelName"]
        )
    }

    /// Bonjour hands back a service, not an address; connecting to it is the supported way to learn where it lives.
    private func address(of endpoint: NWEndpoint) async -> String? {
        let session: AddressSession = .init()
        // Without this the speakers resolve to an IPv6 link-local address, which needs a zone id no URL can carry.
        let parameters: NWParameters = .tcp
        (parameters.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options)?.version = .v4
        let connection = NWConnection(to: endpoint, using: parameters)

        return await session.run { [queue] in
            connection.stateUpdateHandler = { state in
                switch state {
                    case .ready:
                        let host = connection.currentPath?.remoteEndpoint.flatMap(Self.host(of:))
                        Task {
                            await session.finish(with: host)
                            connection.cancel()
                        }
                    case .failed, .cancelled:
                        Task {
                            await session.finish(with: nil)
                            connection.cancel()
                        }
                    default:
                        break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + 3) {
                Task {
                    await session.finish(with: nil)
                    connection.cancel()
                }
            }
        }
    }

    private static func host(of endpoint: NWEndpoint) -> String? {
        guard case .hostPort(let host, _) = endpoint else { return nil }

        switch host {
            // Descriptions carry an interface suffix, like `192.168.23.106%en0`, which a URL must not have.
            case .ipv4(let address): return "\(address)".components(separatedBy: "%").first
            case .ipv6(let address): return ("\(address)".components(separatedBy: "%").first).map { "[\($0)]" }
            case .name(let name, _): return name
            @unknown default: return nil
        }
    }
}
