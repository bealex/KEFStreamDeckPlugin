//
//  File.swift
//
//
//  Created by Alex Babaev on 19/7/23.
//

import Memoirs

public let basicMemoir: Memoir = MultiplexingMemoir(memoirs: [
    PrintMemoir(shortTracers: true),
    OSLogMemoir(subsystem: "KEFPlugin", isSensitive: false)
])
