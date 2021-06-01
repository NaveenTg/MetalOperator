//
//  File.swift
//  
//
//  Created by Navi on 01/06/21.
//

import Foundation

import Metal
public protocol Kernel {
    static var functionName: String { get }
    func encode(withEncoder encoder: MTLComputeCommandEncoder)
}

public extension Kernel {
    func encode(withEncoder encoder: MTLComputeCommandEncoder) {}
}

