import Metal
import UIKit

#if targetEnvironment(simulator)
public typealias MetalOperatorDrawable = Void
#else
public typealias MetalOperatorDrawable = CAMetalDrawable
#endif

open class MetalOperator {
    enum Error: Swift.Error {
        case failedToConfigure
    }
    public var kernelEncoder         : AnyKernelEncoder?
    public var graphicsEncoder       : GraphicsEncoder
    public var pixelBufferProcessor  : PixelBufferProcessor
    
    public let device                : MTLDevice
    public let commandQueue          : MTLCommandQueue
    public let mainBundleLibrary     : MTLLibrary
    public let frameworkBundleLibrary: MTLLibrary
    private var destinationTexture   : MTLTexture!
    private var sourceTextures       : [MTLTexture] = []
    
    @available(iOS 10.0, *)
    public init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let commandQueue = device.makeCommandQueue() else { throw Error.failedToConfigure }
        let frameworkBundleLibrary = try device.makeDefaultLibrary(bundle: .init(for: MetalOperator.self))
        self.device = device
        self.frameworkBundleLibrary = frameworkBundleLibrary
        self.mainBundleLibrary = try device.makeDefaultLibrary(bundle: .main)
        kernelEncoder = try PassThroughEncoder(device: device, library: frameworkBundleLibrary)
        graphicsEncoder = try .init(device: device, library: frameworkBundleLibrary)
        pixelBufferProcessor = .init(device: device, pixelFormat: graphicsEncoder.pixelFormat)
        self.commandQueue = commandQueue
    }
    
    @available(iOS 10.0, *)
    open func install<K: Kernel>(kernel: K, bundle: Bundle? = nil) throws {
        switch bundle {
        case let specifiedBundle?:
            let specifiedBundleLibrary = try device.makeDefaultLibrary(bundle: specifiedBundle)
            kernelEncoder = try KernelEncoder(device: device, library: specifiedBundleLibrary, kernel: kernel)
        case .none where mainBundleLibrary.functionNames.contains(K.functionName):
            kernelEncoder = try KernelEncoder(device: device, library: mainBundleLibrary, kernel: kernel)
        default:
            kernelEncoder = try KernelEncoder(device: device, library: frameworkBundleLibrary, kernel: kernel)
        }
    }
    
    open func reset() {
        kernelEncoder = try? PassThroughEncoder(device: device, library: frameworkBundleLibrary)
    }
    
    open func commit(sourceImages: [CIImage], completion: ((UIImage) -> ())? = nil) {
        #if !targetEnvironment(simulator)
        guard let firstSourceImage = sourceImages.first,
            let destinationTexture = makeEmptyTexture(width: .init(firstSourceImage.extent.width), height: .init(firstSourceImage.extent.height)) else { return }
        let commandBuffer = commandQueue.makeCommandBuffer()
        let context = CIContext(mtlDevice: device)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let sourceTextures = sourceImages.compactMap { sourceImage -> MTLTexture? in
            guard let texture = makeEmptyTexture(width: .init(sourceImage.extent.width), height: .init(sourceImage.extent.height)) else { return nil }
            context.render(sourceImage, to: texture, commandBuffer: commandBuffer, bounds: sourceImage.extent, colorSpace: colorSpace)
            return texture
        }
        kernelEncoder?.encode(buffer: commandBuffer, destinationTexture: destinationTexture, sourceTextures: sourceTextures)
        commandBuffer?.addCompletedHandler { hand in
            guard let finalCiImage = CIImage(mtlTexture: destinationTexture, options: nil) else { return }
            let finalImage = UIImage(ciImage: finalCiImage, scale: UIScreen.main.nativeScale, orientation: .up)
            DispatchQueue.main.async {
                completion?(finalImage)
            }
        }
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        #endif
    }
    
    open func commit(drawable: MetalOperatorDrawable) {
        #if !targetEnvironment(simulator)
        let commandBuffer = commandQueue.makeCommandBuffer()
        if destinationTexture == nil {
            destinationTexture = makeEmptyTexture(width: drawable.texture.width, height: drawable.texture.height)
        }
        kernelEncoder?.encode(buffer: commandBuffer, destinationTexture: destinationTexture, sourceTextures: sourceTextures)
        graphicsEncoder.encode(commandBuffer: commandBuffer, targetDrawable: drawable, presentingTexture: destinationTexture)
        commandBuffer?.present(drawable)
        commandBuffer?.commit()
        commandBuffer?.waitUntilCompleted()
        #endif
    }
    
    @discardableResult
    open func compute(pixelBuffer: CVPixelBuffer) -> MTLTexture? {
        guard let bufferTexture = pixelBufferProcessor.makeTexture(imageBuffer: pixelBuffer) else { return nil }
        destinationTexture = makeEmptyTexture(width: bufferTexture.width, height: bufferTexture.height)
        sourceTextures = [bufferTexture]
        return bufferTexture
    }
    
    open func makeEmptyTexture(width: Int, height: Int) -> MTLTexture? {
        let textureDescriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: graphicsEncoder.pixelFormat,
            width: width,
            height: height,
            mipmapped: false
        )
        textureDescriptor.usage = [.shaderRead, .shaderWrite]
        return device.makeTexture(descriptor: textureDescriptor)
    }
}

private final class PassThroughKernel: Kernel {
    static let functionName: String = "pass_through"
}

private final class PassThroughEncoder: KernelEncoder<PassThroughKernel> {
    override func encode(buffer: MTLCommandBuffer?, destinationTexture: MTLTexture, sourceTextures: [MTLTexture] = []) {
        guard !sourceTextures.isEmpty else { return }
        super.encode(buffer: buffer, destinationTexture: destinationTexture, sourceTextures: sourceTextures)
    }
    
    convenience init(device: MTLDevice, library: MTLLibrary) throws {
        try self.init(device: device, library: library, kernel: .init())
    }
}


