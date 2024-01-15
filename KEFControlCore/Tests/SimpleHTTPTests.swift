//
// SimpleHTTPTests
// KEFControl
//
// Created by Alex Babaev on 09 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation
import KEFControl
import XCTest

class SimpleHTTPTests: XCTestCase {
    let kefAddress = "192.168.23.106"

    func testInitialization() async throws {
        var testSource: PlaybackInfo.Source = .unsupported
        var testModel: AudioSystem.Model = .unknown
        let expectationState = XCTestExpectation(description: "Wait for state")
        let expectationModel = XCTestExpectation(description: "Wait for model")

        let networkApi = KEFNetworkApi()
        let control = KEFControl(api: networkApi)
        await control.set(ip: kefAddress, andStartStreaming: false)
        let subscription = await control.eventPublisher.sink { event in
            switch event {
                case .playback(let info):
                    guard info.source != .unsupported else { return }

                    testSource = info.source
                    expectationState.fulfill()
                case .system(let system):
                    guard system.model != .unknown else { return }

                    testModel = system.model
                    expectationModel.fulfill()
            }
        }
        try await control.startEventListening()

        await fulfillment(of: [ expectationState, expectationModel ], timeout: 2)
        XCTAssertNotNil(subscription)
        XCTAssertNotEqual(testSource, .unsupported)
        XCTAssertNotEqual(testModel, .unknown)
    }

    func testVolumeSet() async throws {
        let control = KEFControl(api: KEFNetworkApi())
        await control.set(ip: kefAddress, andStartStreaming: false)
        try await control.startEventListening()
        try await Task.sleep(for: .seconds(1))
        _ = try await control.changeVolume(by: 2)
        try await Task.sleep(for: .seconds(1))
        _ = try await control.changeVolume(by: -2)
        try await Task.sleep(for: .seconds(1))
    }

    func testPolling() async throws {
        let control = KEFControl(api: KEFNetworkApi())
        await control.set(ip: kefAddress, andStartStreaming: false)
        try await control.startEventListening()
        try await Task.sleep(for: .seconds(3))
        try await control.stopEventListening()
        try await Task.sleep(for: .seconds(1))
    }
}
