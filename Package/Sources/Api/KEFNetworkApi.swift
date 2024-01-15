//
// KEFNetworkApi
// Package
//
// Created by Alex Babaev on 26 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation
import Memoirs

public class KEFNetworkApi: KEFApi {
    private lazy var memoir: TracedMemoir = TracedMemoir(object: self, memoir: basicMemoir)

    private static let urlSession: URLSession = URLSession(configuration: URLSessionConfiguration.default)
    private static let pollingUrlSessionConfiguration: URLSessionConfiguration = {
        var result = URLSessionConfiguration.default
        result.httpMaximumConnectionsPerHost = 10
        return result
    }()
    private static let urlSessionForPolling: URLSession = URLSession(configuration: pollingUrlSessionConfiguration)

    public init() {
        memoir.debug("")
    }

    private let pathIsMuted: String = "settings:/mediaPlayer/mute"
    private let pathPhysicalSource: String = "settings:/kef/play/physicalSource"
    private let pathDeviceName: String = "settings:/deviceName"
    private let pathModelName: String = "settings:/kef/host/modelName"
    private let pathVolume: String = "player:volume"

    private let roleValue: String = "value"

    public func set<Type: RawValueType>(value: Type, for path: KeyPath<KEFValueOptions, Type>, ip: String) async throws {
        switch path {
            case \.volume:
                try await setValue(RawValue(value), path: pathVolume, role: roleValue, ip: ip)
            case \.isMuted:
                try await setValue(RawValue(value), path: pathIsMuted, role: roleValue, ip: ip)
            case \.physicalSource:
                try await setValue(RawValue(value), path: pathPhysicalSource, role: roleValue, ip: ip)
            default:
                throw KEFProblem.notSupported("Setting value \(path)")
        }

        memoir.debug("Set value: \(value) for \(ip)")
    }

    public func get<Type>(_ path: KeyPath<KEFValueOptions, Type>, ip: String) async throws -> Type {
        var result: Any?
        switch path {
            case \.volume:
                let value: RawValue<Int32> = try await getValue(path: pathVolume, roles: roleValue, ip: ip)
                result = value.value ?? 0
            case \.isMuted:
                let value: RawValue<Bool> = try await getValue(path: pathIsMuted, roles: roleValue, ip: ip)
                result = value.value ?? false
            case \.physicalSource:
                let value: RawValue<PlaybackInfo.Source> = try await getValue(path: pathPhysicalSource, roles: roleValue, ip: ip)
                result = value.value ?? .unsupported
            case \.name:
                let value: RawValue<String> = try await getValue(path: pathDeviceName, roles: roleValue, ip: ip)
                result = value.value ?? "KEF"
            case \.model:
                let value: RawValue<String> = try await getValue(path: pathModelName, roles: roleValue, ip: ip)
                var model: AudioSystem.Model = .unknown
                switch value.value {
                    case "SP4041": model = .lsxII
                    default: break
                }
                result = model
            default:
                throw KEFProblem.notSupported("\(path)")
        }
        guard let typedResult = result as? Type else { fatalError("Can't return \(path) as \(Type.self)") }

        memoir.debug("Got value for \(path) --> \(typedResult)")
        return typedResult
    }

    private let decoder: JSONDecoder = .init()
    private let encoder: JSONEncoder = .init()

    private func setValue<Type>(_ value: RawValue<Type>, path: String, role: String, ip: String) async throws {
        var urlRequest = URLRequest(url: try setValueUrl(address: ip))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let value = String(data: try encoder.encode(value), encoding: .utf8) else { throw KEFProblem.cantSerializeRequest }
        let bodyString = "{\"path\": \"\(path)\",\"role\": \"\(role)\",\"value\": \(value)}"
        urlRequest.httpBody = bodyString.data(using: .utf8)

        let (response, data) = try await request(urlRequest, in: Self.urlSession)
        guard ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2 else {
            memoir.error("Error: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw KEFProblem.httpError(data, response)
        }
    }

    private func getValue<Type>(path: String, roles: String, ip: String) async throws -> RawValue<Type> {
        let urlRequest = URLRequest(url: try getValueUrl(address: ip, path: path, roles: roles))
        let (response, data) = try await request(urlRequest, in: Self.urlSession)
        guard ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2 else {
            memoir.error("Error: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw KEFProblem.httpError(data, response)
        }

        let valueArray = try decoder.decode([RawValue<Type>].self, from: data)
        guard !valueArray.isEmpty else { throw KEFProblem.noValueInResponse }

        return valueArray[0]
    }

    private var isEventPollingStarted: Bool = false
    private let subscriptionList: String =
        """
        [
            { "path": "player:volume", "type": "itemWithValue" },
            { "path": "settings:/mediaPlayer/mute", "type": "itemWithValue" },
            { "path": "settings:/deviceName", "type": "itemWithValue" },
            { "path": "settings:/kef/play/physicalSource", "type": "itemWithValue" }
        ]
        """

    private var eventsContinuations: [String: AsyncStream<KEFValue>.Continuation] = [:]

    public func events(for ip: String) throws -> (AsyncStream<KEFValue>, id: String) {
        guard !isEventPollingStarted else {
            memoir.warning("Already started polling, please do it only once")
            throw KEFProblem.alreadyStarted
        }

        isEventPollingStarted = true
        memoir.debug("Event polling started")
        let id = UUID().uuidString
        let stream = AsyncStream<KEFValue> { [self] continuation in
            eventsContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }

                eventsContinuations[id] = nil
                isEventPollingStarted = false
                memoir.debug("Event polling terminated")
            }

            Task {
                guard let subscriptionId = try await subscribe(toJSONPaths: subscriptionList, ip: ip) else {
                    memoir.error("Can't get subscriptionId")
                    return continuation.finish()
                }

                memoir.debug("Event polling initialized (id: \(subscriptionId))")
                while isEventPollingStarted {
                    let events = try await pollEvents(subscriptionId: subscriptionId, ip: ip)
                    events.forEach {
                        continuation.yield($0)
                    }
                }
                continuation.finish()
            }
        }
        return (stream, id)
    }

    public func terminateEventsStream(id: String) {
        guard let continuation = eventsContinuations[id] else { return memoir.warning("Can't find continuation for id \(id)") }

        continuation.finish()
    }

    // Returns subscription queue id for long polling.
    private func subscribe(toJSONPaths: String, ip: String) async throws -> String? {
        var urlRequest = URLRequest(url: try subscribeUrl(subscribeJson: toJSONPaths, address: ip))
        urlRequest.setValue("keep-alive", forHTTPHeaderField: "Connection")
        let (response, data) = try await request(urlRequest, in: Self.urlSessionForPolling)
        guard ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2 else {
            memoir.error("Error: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw KEFProblem.httpError(data, response)
        }

        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\"", with: "")
    }

    private func pollEvents(subscriptionId: String, ip: String) async throws -> [KEFValue] {
        var urlRequest = URLRequest(url: try longPollUrl(subscriptionId: subscriptionId, address: ip))
        urlRequest.setValue("keep-alive", forHTTPHeaderField: "Connection")
        let (response, data) = try await request(urlRequest, in: Self.urlSessionForPolling)
        guard ((response as? HTTPURLResponse)?.statusCode ?? 0) / 100 == 2 else {
            memoir.error("Error: \(String(data: data, encoding: .utf8) ?? "nil")")
            throw KEFProblem.httpError(data, response)
        }
        guard let json = try JSONSerialization.jsonObject(with: data, options: [ .fragmentsAllowed ]) as? [Any] else {
            memoir.error("Can't parse \(String(data: data, encoding: .utf8) ?? "nil")")
            throw KEFProblem.jsonError(data, response)
        }

        return try json.compactMap { item in
            guard let item = item as? [String: Any], item["itemType"] as? String == "update" else { return nil }
            guard let value = item["itemValue"] as? [String: Any] else { return nil }
            guard let path = item["path"] as? String else { return nil }

            let valueData = try JSONSerialization.data(withJSONObject: value)
            switch path {
                case pathVolume:
                    return try decoder.decode(RawValue<Int32>.self, from: valueData).value.map { .volume($0) }
                case pathIsMuted:
                    return try decoder.decode(RawValue<Bool>.self, from: valueData).value.map { .isMuted($0) }
                case pathPhysicalSource:
                    return try decoder.decode(RawValue<PlaybackInfo.Source>.self, from: valueData).value.map { .source($0) }
                default:
                    return nil
            }
        }
    }

    private func request(
        _ request: URLRequest,
        in session: URLSession,
        file: String = #fileID,
        function: String = #function,
        line: UInt = #line
    ) async throws -> (URLResponse, Data) {
        let requestId = UUID().uuidString
        let body = request.httpBody.map { "--> Body: \(String(data: $0, encoding: .utf8) ?? "???")" } ?? ""
        let method = request.httpMethod ?? "???"
        memoir.debug("--> [\(requestId)] Request: \(method) \(request.url!.absoluteString)\(body)", file: file, function: function, line: line)
        let (data, response) = try await session.data(for: request)
        memoir.debug("<-- [\(requestId)] Response: \(String(data: data, encoding: .utf8) ?? "nil")", file: file, function: function, line: line)
        return (response, data)
    }

    private func setValueUrl(address: String) throws -> URL {
        let urlString = "http://\(address)/api/setData"
        guard let baseUrl = URL(string: urlString) else { fatalError("Can't create URL for \(urlString)") }

        return baseUrl
    }

    private func setValueUrl<Type>(path: String, role: String, value: RawValue<Type>, address: String) throws -> URL {
        let urlString = "http://\(address)/api/setData"
        guard let baseUrl = URL(string: urlString) else { fatalError("Can't create URL for \(urlString)") }
        guard var urlComponents = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false) else { throw KEFProblem.cantProcessUrl }

        urlComponents.queryItems = [
            URLQueryItem(name: "role", value: role),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "value", value: String(data: try encoder.encode(value), encoding: .utf8)),
        ]
        guard let url = urlComponents.url else { throw KEFProblem.cantProcessUrl }

        return url
    }

    private func getValueUrl(address: String, path: String, roles: String) throws -> URL {
        let urlString = "http://\(address)/api/getData"
        guard let baseUrl = URL(string: urlString) else { fatalError("Can't create URL for \(urlString)") }
        guard var urlComponents = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false) else { throw KEFProblem.cantProcessUrl }

        urlComponents.queryItems = [
            URLQueryItem(name: "roles", value: roles),
            URLQueryItem(name: "path", value: path),
        ]
        guard let url = urlComponents.url else { throw KEFProblem.cantProcessUrl }

        return url
    }

    private func subscribeUrl(subscribeJson: String, address: String) throws -> URL {
        let urlString = "http://\(address)/api/event/modifyQueue"
        guard let baseUrl = URL(string: urlString) else { fatalError("Can't create URL for \(urlString)") }
        guard var urlComponents = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false) else { throw KEFProblem.cantProcessUrl }

        urlComponents.queryItems = [
            URLQueryItem(name: "queueId", value: ""),
            URLQueryItem(name: "subscribe", value: subscribeJson),
        ]
        guard let url = urlComponents.url else { throw KEFProblem.cantProcessUrl }

        return url
    }

    private func longPollUrl(subscriptionId: String, address: String) throws -> URL {
        let urlString = "http://\(address)/api/event/pollQueue"
        guard let baseUrl = URL(string: urlString) else { fatalError("Can't create URL for \(urlString)") }
        guard var urlComponents = URLComponents(url: baseUrl, resolvingAgainstBaseURL: false) else { throw KEFProblem.cantProcessUrl }

        urlComponents.queryItems = [
            URLQueryItem(name: "timeout", value: "10"),
            URLQueryItem(name: "queueId", value: subscriptionId),
        ]
        guard let url = urlComponents.url else { throw KEFProblem.cantProcessUrl }

        return url
    }
}
