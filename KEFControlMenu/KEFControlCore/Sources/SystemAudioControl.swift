//
// SystemAudioControl
// KEFControl
//
// Created by Alexander Babaev on 03 November 2025.
// Copyright © 2025 Alexander Babaev. All rights reserved.
//

import Combine
import CoreAudio
import Foundation
import Memoirs

public struct AudioOutputDevice: Equatable, Sendable {
    /// What the device physically is, as far as CoreAudio is willing to say.
    public enum Kind: Equatable, Sendable {
        case builtInSpeakers
        case headphones
        case bluetooth
        case airPlay
        case display
        case external
        case virtual
        case unknown
    }

    public let id: AudioDeviceID
    public let name: String
    public let uid: String
    public let kind: Kind

    public init(id: AudioDeviceID, name: String, uid: String, kind: Kind) {
        self.id = id
        self.name = name
        self.uid = uid
        self.kind = kind
    }
}

/// Volume control for the system default output device, used when the KEF speakers are not the selected output.
@MainActor
public final class SystemAudioControl {
    public enum Event {
        case device(AudioOutputDevice?)
        case playback(volume: Double, isMuted: Bool)
    }

    struct Listener {
        let objectID: AudioObjectID
        let address: AudioObjectPropertyAddress
        let block: AudioObjectPropertyListenerBlock
    }

    public var eventPublisher: AnyPublisher<Event, Never> { eventSubject.eraseToAnyPublisher() }

    private(set) public var device: AudioOutputDevice?
    /// Volume of the default output device, in `0 ... 1`.
    private(set) public var volume: Double = 0
    private(set) public var isMuted: Bool = false
    /// `false` for devices that have no software volume (HDMI/display audio, most aggregate devices).
    private(set) public var isVolumeControlAvailable: Bool = false

    public init() {
    }

    public func startMonitoring() {
        guard systemListener == nil else { return memoir.warning("Already monitoring the default output device") }

        let address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        systemListener = addListener(for: address, on: AudioObjectID(kAudioObjectSystemObject)) { [weak self] in
            self?.updateDevice()
        }
        updateDevice()
    }

    public func stopMonitoring() {
        remove(listeners: deviceListeners)
        deviceListeners = []
        remove(listeners: [ systemListener ].compactMap { $0 })
        systemListener = nil
    }

    /// Changes the volume by `delta` (in `0 ... 1` units) and returns the new volume.
    @discardableResult
    public func changeVolume(by delta: Double) -> Double {
        setVolume(volume + delta)
        return volume
    }

    public func setVolume(_ newVolume: Double) {
        guard let device, isVolumeControlAvailable else { return }

        let clamped = min(1, max(0, newVolume))
        let addresses = volumeAddresses(of: device.id)
        let didSet = addresses.reduce(false) { result, address in
            Self.set(Float32(clamped), at: address, on: device.id) || result
        }
        guard didSet else { return memoir.error("Can't set volume \(clamped) for \(device.name)") }

        // The property listener echoes the change back, but updating right away keeps repeated key presses smooth.
        volume = clamped
        // macOS unmutes the device when the volume is raised from zero; mirror that so the icon does not lie.
        if isMuted, clamped > 0 {
            setMuted(false)
        } else {
            eventSubject.send(.playback(volume: volume, isMuted: isMuted))
        }
    }

    public func toggleMute() {
        setMuted(!isMuted)
    }

    public func setMuted(_ newValue: Bool) {
        guard let device else { return }

        let address = Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        guard Self.set(UInt32(newValue ? 1 : 0), at: address, on: device.id) else {
            return memoir.error("Can't set mute \(newValue) for \(device.name)")
        }

        isMuted = newValue
        eventSubject.send(.playback(volume: volume, isMuted: isMuted))
    }

    private lazy var memoir: TracedMemoir = TracedMemoir(object: self, memoir: basicMemoir)
    private let eventSubject: PassthroughSubject<Event, Never> = .init()

    private var systemListener: Listener?
    private var deviceListeners: [Listener] = []

    private func updateDevice() {
        remove(listeners: deviceListeners)
        deviceListeners = []

        device = Self.defaultOutputDevice()
        memoir.debug("Default output device: \(device?.name ?? "—")")

        guard let device else {
            isVolumeControlAvailable = false
            volume = 0
            isMuted = false
            eventSubject.send(.device(nil))
            return eventSubject.send(.playback(volume: volume, isMuted: isMuted))
        }

        let addresses = volumeAddresses(of: device.id)
        isVolumeControlAvailable = addresses.contains { Self.isSettable($0, on: device.id) }
        for address in addresses {
            deviceListeners.append(addListener(for: address, on: device.id) { [weak self] in self?.updatePlayback() })
        }
        let muteAddress = Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        if Self.hasProperty(muteAddress, on: device.id) {
            deviceListeners.append(addListener(for: muteAddress, on: device.id) { [weak self] in self?.updatePlayback() })
        }

        // Everything about the device has to be known before it is announced, or subscribers read stale values.
        readPlayback()
        eventSubject.send(.device(device))
        eventSubject.send(.playback(volume: volume, isMuted: isMuted))
    }

    private func updatePlayback() {
        readPlayback()
        eventSubject.send(.playback(volume: volume, isMuted: isMuted))
    }

    private func readPlayback() {
        guard let device else { return }

        let addresses = volumeAddresses(of: device.id)
        let values = addresses.compactMap { Self.value(Float32.self, at: $0, from: device.id) }
        volume = values.isEmpty ? 0 : Double(values.reduce(0, +) / Float32(values.count))

        let muteAddress = Self.address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        isMuted = (Self.value(UInt32.self, at: muteAddress, from: device.id) ?? 0) != 0
    }

    /// Devices either expose one main volume, or one volume per stereo channel; the main element is preferred.
    private func volumeAddresses(of deviceID: AudioDeviceID) -> [AudioObjectPropertyAddress] {
        let main = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput)
        guard !Self.hasProperty(main, on: deviceID) else { return [ main ] }

        let stereoAddress = Self.address(kAudioDevicePropertyPreferredChannelsForStereo, scope: kAudioObjectPropertyScopeOutput)
        let channels = Self.value((UInt32, UInt32).self, at: stereoAddress, from: deviceID) ?? (1, 2)
        return [ channels.0, channels.1 ]
            .map { Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioObjectPropertyScopeOutput, element: $0) }
            .filter { Self.hasProperty($0, on: deviceID) }
    }

    private static func defaultOutputDevice() -> AudioOutputDevice? {
        let address = address(kAudioHardwarePropertyDefaultOutputDevice)
        guard let deviceID = value(AudioDeviceID.self, at: address, from: AudioObjectID(kAudioObjectSystemObject)) else {
            return nil
        }
        guard deviceID != kAudioObjectUnknown else { return nil }

        let name = string(at: Self.address(kAudioObjectPropertyName), from: deviceID)
        let uid = string(at: Self.address(kAudioDevicePropertyDeviceUID), from: deviceID)
        return AudioOutputDevice(id: deviceID, name: name ?? "Unknown", uid: uid ?? "", kind: kind(of: deviceID))
    }

    private static func kind(of deviceID: AudioDeviceID) -> AudioOutputDevice.Kind {
        let transportAddress = address(kAudioDevicePropertyTransportType)
        guard let transport = value(UInt32.self, at: transportAddress, from: deviceID) else { return .unknown }

        switch transport {
            case kAudioDeviceTransportTypeBuiltIn: return builtInKind(of: deviceID)
            case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE: return .bluetooth
            case kAudioDeviceTransportTypeAirPlay: return .airPlay
            case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort: return .display
            case kAudioDeviceTransportTypeVirtual, kAudioDeviceTransportTypeAggregate: return .virtual
            case kAudioDeviceTransportTypeUSB, kAudioDeviceTransportTypeThunderbolt: return .external
            case kAudioDeviceTransportTypeFireWire, kAudioDeviceTransportTypePCI: return .external
            default: return .unknown
        }
    }

    /// Built-in output is the speakers or the headphone jack, depending on what is plugged in.
    private static func builtInKind(of deviceID: AudioDeviceID) -> AudioOutputDevice.Kind {
        let sourceAddress = address(kAudioDevicePropertyDataSource, scope: kAudioObjectPropertyScopeOutput)
        guard let source = value(UInt32.self, at: sourceAddress, from: deviceID) else { return .builtInSpeakers }

        // 'hdpn' is the headphone jack; anything else on built-in output is the internal speakers.
        return source == 0x6864_706E ? .headphones : .builtInSpeakers
    }
}

// MARK: - Property listeners

extension SystemAudioControl {
    private func addListener(
        for address: AudioObjectPropertyAddress, on objectID: AudioObjectID, onChange: @escaping () -> Void
    ) -> Listener {
        var mutableAddress = address
        // The queue is main, so the callback is already on the main actor.
        let block: AudioObjectPropertyListenerBlock = { _, _ in
            MainActor.assumeIsolated { onChange() }
        }
        let status = AudioObjectAddPropertyListenerBlock(objectID, &mutableAddress, DispatchQueue.main, block)
        if status != noErr {
            memoir.error("Can't listen to \(address.mSelector) of \(objectID): \(status)")
        }
        return Listener(objectID: objectID, address: address, block: block)
    }

    private func remove(listeners: [Listener]) {
        for listener in listeners {
            var address = listener.address
            AudioObjectRemovePropertyListenerBlock(listener.objectID, &address, DispatchQueue.main, listener.block)
        }
    }
}

// MARK: - CoreAudio property access

extension SystemAudioControl {
    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    private static func hasProperty(_ address: AudioObjectPropertyAddress, on objectID: AudioObjectID) -> Bool {
        var address = address
        return AudioObjectHasProperty(objectID, &address)
    }

    private static func isSettable(_ address: AudioObjectPropertyAddress, on objectID: AudioObjectID) -> Bool {
        var address = address
        var isSettable: DarwinBoolean = false
        guard AudioObjectIsPropertySettable(objectID, &address, &isSettable) == noErr else { return false }

        return isSettable.boolValue
    }

    private static func value<Value>(
        _ type: Value.Type, at address: AudioObjectPropertyAddress, from objectID: AudioObjectID
    ) -> Value? {
        var address = address
        var size = UInt32(MemoryLayout<Value>.size)
        let result = UnsafeMutablePointer<Value>.allocate(capacity: 1)
        defer { result.deallocate() }

        guard AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, result) == noErr else { return nil }

        return result.pointee
    }

    private static func set<Value>(_ value: Value, at address: AudioObjectPropertyAddress, on objectID: AudioObjectID) -> Bool {
        var address = address
        var value = value
        let size = UInt32(MemoryLayout<Value>.size)
        return AudioObjectSetPropertyData(objectID, &address, 0, nil, size, &value) == noErr
    }

    private static func string(at address: AudioObjectPropertyAddress, from objectID: AudioObjectID) -> String? {
        var address = address
        var result: CFString?
        var size = UInt32(MemoryLayout<CFString?>.size)
        let status = withUnsafeMutablePointer(to: &result) {
            AudioObjectGetPropertyData(objectID, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return nil }

        return result as String?
    }
}
