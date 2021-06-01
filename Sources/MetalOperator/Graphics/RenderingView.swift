//
//  File.swift
//  
//
//  Created by Navi on 01/06/21.
//

import UIKit
import Metal
import MetalKit

public final class RenderingView: UIView {
    public var gpuOperator: MetalOperator? {
        didSet {
            #if !targetEnvironment(simulator)
            guard let gpu = gpuOperator else { return }
            metalLayer.device = gpu.device
            metalLayer.pixelFormat = gpu.graphicsEncoder.pixelFormat
            metalLayer.framebufferOnly = false
            metalLayer.contentsScale = isRoughnessAcceptable ? 1 : UIScreen.main.nativeScale
            #endif
        }
    }
    
    public var isRoughnessAcceptable: Bool = false {
        didSet {
            metalLayer.contentsScale = isRoughnessAcceptable ? 1 : UIScreen.main.nativeScale
        }
    }
    
    public override init(frame: CGRect) {
        super.init(frame: frame)
        configure()
    }
    
    public required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        configure()
    }
    
    deinit {
        stop()
    }
    
    private func configure() {
        backgroundColor = .clear
    }
    
    private var link: CADisplayLink?
}

#if targetEnvironment(simulator)
extension RenderingView {
    var metalLayer: CALayer {
        return layer
    }
    
    public override class var layerClass: AnyClass {
        return CALayer.self
    }
    
    public func run() {}
    public func stop() {}
}
#else
extension RenderingView {
    var metalLayer: CAMetalLayer {
        return layer as! CAMetalLayer
    }
    
    public override class var layerClass: AnyClass {
        return CAMetalLayer.self
    }
    
    public func run() {
        link = CADisplayLink(target: self, selector: #selector(render))
        link?.add(to: .main, forMode: .common)
    }
    
    public func stop() {
        link?.invalidate()
        link = nil
    }
    
    @objc func render() {
        autoreleasepool {
            guard let drawable = metalLayer.nextDrawable() else { return }
            gpuOperator?.commit(drawable: drawable)
        }
    }
}
#endif
