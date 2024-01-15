//
// main
// KEFControlCore
//
// Created by Alexander Babaev on 11 January 2024.
// Copyright © 2024 Alexander Babaev. All rights reserved.
//

import Foundation
import KEFControl

Task {
    let api = KEFNetworkApi()
    let (stream, id) = try api.events(for: "192.168.23.106")
    for await event in stream {
        print("Event happened: \(event)")
    }
}

RunLoop.main.run()
