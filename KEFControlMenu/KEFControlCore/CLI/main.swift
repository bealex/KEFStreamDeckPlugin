//
// main
// KEFControlCore
//
// Created by Alexander Babaev on 11 January 2024.
// Copyright © 2024 Alexander Babaev. All rights reserved.
//

import Foundation
import KEFControl

guard CommandLine.arguments.count > 1 else {
    print("Usage: kefcli <speaker-address>")
    exit(1)
}

let address = CommandLine.arguments[1]

Task {
    do {
        let api = KEFNetworkApi()
        let (stream, _) = try api.events(for: address)
        for await event in stream {
            print("Event happened: \(event)")
        }
    } catch {
        print("Error: \(error)")
        exit(1)
    }
}

RunLoop.main.run()
