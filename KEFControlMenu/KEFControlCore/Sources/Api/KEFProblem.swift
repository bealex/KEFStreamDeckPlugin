//
// KEFProblem
// Package
//
// Created by Alex Babaev on 26 July 2023.
// Copyright © 2023 Alex Babaev. All rights reserved.
//

import Foundation

enum KEFProblem: Error {
    case cantProcessUrl
    case httpError(Data, URLResponse, statusCode: Int)
    case jsonError(Data, URLResponse)
    case cantSerializeRequest
    case noValueInResponse
    case alreadyStarted
    case notSupported(String)
    case isNotSetup(String)
}
