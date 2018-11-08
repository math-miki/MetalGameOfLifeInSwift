//
//  GOLRenderer.swift
//  MetalGameOfLife
//
//  Created by MikiTakahashi on 2018/11/08.
//  Copyright © 2018 MikiTakahashi. All rights reserved.
//

import Foundation
import Metal
import MetalKit

class GOLRenderer:NSObject, MTKViewDelegate {
    
    let kTextureCount = 3
    let kInitialAliveProbability: Int = 10
    let kCellValueAlive = 0
    let kCellValueDead = 255
    let kMaxInflightBuffers = 3
    
    var gridSize: MTLSize!
    
    
    var view: MTKView! = nil
    var device: MTLDevice! = nil
    var commandQueue: MTLCommandQueue! = nil
    var library: MTLLibrary! = nil
    var renderPipelineState: MTLRenderPipelineState! = nil
    var simulationPipeline: MTLComputePipelineState! = nil
    var activationPipeline: MTLComputePipelineState! = nil
    var samplerState: MTLSamplerState! = nil
    var textureQueue: Array<MTLTexture>! = nil
    
    var currentGameStateTexture: MTLTexture! = nil
    var vertexBuffer: MTLBuffer! = nil
    
    var colorMap: MTLTexture! = nil
    
    var activationPoints: Array<CGPoint>! = nil
    var inflightSemaphore: DispatchSemaphore! = nil
    var nextResizeTimestamp: Date!
    
    init(withView view: MTKView) {
        super.init()
        if(view.device == nil) {
            print("Cannot create renderer without the view already having an associated Metal Device")
            return
        }
        
        self.view = view
        self.view.delegate = self
        
        self.device = view.device
        self.library = device.makeDefaultLibrary()
        self.commandQueue = device.makeCommandQueue()
        
        activationPoints = Array<CGPoint>()
        textureQueue = Array<MTLTexture>()
        
        self.buildRenderResources()
        self.buildRenderPipeline()
        self.buildComputePipelines()
        
        self.reshapeWithDrawableSize(drawableSize: self.view.drawableSize)
        
        self.inflightSemaphore = DispatchSemaphore(value: kMaxInflightBuffers)
        
    }

    // MARK: - Resource and Pipeline Creation
    
    // #if TARGET_OS_IOS || TARGET_OS_TV
    func CGImageForName(name: String) -> CGImage {
        let image = UIImage(named: name)
        return image!.cgImage!
    }

    func buildRenderResources() {
        let textureLoader: MTKTextureLoader = MTKTextureLoader(device: self.device)
        let colorMapCGImage = self.CGImageForName(name: "colormap")
        do {
            try colorMap = textureLoader.newTexture(cgImage: colorMapCGImage, options: [:])
        } catch let error {
            print("Error at creation texture: ", error)
        }
        colorMap.label =  "Color Map"
        
        let vertexData = [
            -1,1,0,0,
            -1,-1,0,1,
            1,-1,1,1,
            1,-1,1,1,
            1,1,1,0,
            -1,1,0,0
        ]
        vertexBuffer = self.device.makeBuffer(bytes: vertexData, length: MemoryLayout<Int>.stride*vertexData.count, options: [.storageModeShared])
        vertexBuffer.label = "Fullscreen Quad Vertices"
    }
    
    func buildRenderPipeline() {
        let vertexProgram: MTLFunction = library.makeFunction(name: "lighting_vertex")!
        let fragmentProgtam: MTLFunction = library.makeFunction(name: "lighting_fragment")!
        
        // createa vertex descriptor that descrives a vertex with two float2 members: position and texture coordinates
        let vertexDescriptor = MTLVertexDescriptor()
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        vertexDescriptor.attributes[0].format = MTLVertexFormat.float2
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.stride * 2
        vertexDescriptor.attributes[1].bufferIndex = 0
        vertexDescriptor.attributes[1].format = MTLVertexFormat.float2;
        vertexDescriptor.layouts[0].stride = MemoryLayout<Float>.stride * 4
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunction.perVertex
        
        // descrive and create a render pipeline state
        let pipelineStateDescriptor: MTLRenderPipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.label = "Fullscreen Quad Pipeline"
        pipelineStateDescriptor.vertexFunction = vertexProgram
        pipelineStateDescriptor.fragmentFunction = fragmentProgtam
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = self.view.colorPixelFormat
        
        do {
            try self.renderPipelineState = device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        } catch let error {
            print("error at creation renderPipelineState: ", error)
        }
    }
    
    func reshapeWithDrawableSize(drawableSize: CGSize) {
        let scale = self.view.layer.contentsScale
        let proposedGridSize = MTLSizeMake(Int(drawableSize.width/scale), Int(drawableSize.height/scale), 1)
        
        if(self.gridSize.width != proposedGridSize.width || self.gridSize.height != proposedGridSize.height) {
            gridSize = proposedGridSize
            self.buildComputeResources()
        }
    }
    func buildComputeResources() {
        self.textureQueue.removeAll()
        self.currentGameStateTexture = nil
        
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: MTLPixelFormat.r8Uint, width: self.gridSize.width, height: self.gridSize.height, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        
        for i in 0..<kTextureCount {
            let texture = device.makeTexture(descriptor: descriptor)
            texture!.label = "Game State \(i)"
            self.textureQueue.append(texture!)
        }
        
        var randomGrid = Array.init(repeating: 0, count: self.gridSize.width * self.gridSize.height)
        for i in 0..<self.gridSize.width {
            for j in 0..<self.gridSize.height {
                let alive = arc4random_uniform(100)<kInitialAliveProbability ? self.kCellValueAlive : self.kCellValueDead
                randomGrid[j*self.gridSize.width + i] = alive
            }
        }
        let currentReadTexture = textureQueue.last
        currentReadTexture?.replace(region: MTLRegionMake2D(0, 0, self.gridSize.width, self.gridSize.height), mipmapLevel: 0, withBytes: randomGrid, bytesPerRow: self.gridSize.width)
    }
    
    func buildComputePipelines() {
        self.commandQueue = device.makeCommandQueue()
        
        let descriptor = MTLComputePipelineDescriptor()
        descriptor.computeFunction = library.makeFunction(name: "game_of_life")
        descriptor.label = "Game of Life"
        do {
            try simulationPipeline = device.makeComputePipelineState(descriptor: descriptor, options: [], reflection: nil)
        } catch let error {
            print("Eror at creation computePipelineState: ", error)
        }
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.sAddressMode = MTLSamplerAddressMode.repeat
        samplerDescriptor.tAddressMode = MTLSamplerAddressMode.repeat
        samplerDescriptor.minFilter = MTLSamplerMinMagFilter.nearest
        samplerDescriptor.magFilter = MTLSamplerMinMagFilter.nearest
        samplerDescriptor.normalizedCoordinates = true
        self.samplerState = device.makeSamplerState(descriptor: samplerDescriptor)
    }

    // MARK: - Interactivity
    
    public func activateRandomCellsInNeighborhoodOfCell(cell: CGPoint) {
        self.activationPoints.append(cell)
    }
    
    // MARK: - Render and Compute Encoding
    
    func encodeComputerWorkInBuffer(commandBuffer: MTLCommandBuffer) {
        // to update simulation that was last displayed on the screen, read it
        let readTexture = self.textureQueue.last
        // write the new state at the head of the queue
        let writeTexture = self.textureQueue.first
        
        let commandEncoder = commandBuffer.makeComputeCommandEncoder()
        
        let threadsPerThreadgroup = MTLSizeMake(16, 16, 1)
        let threadgroupCount = MTLSizeMake(
            Int(ceil(Float(self.gridSize.width)/Float(threadsPerThreadgroup.width))),
            Int(ceil(Float(self.gridSize.height)/Float(threadsPerThreadgroup.height))),
            1)
        
        commandEncoder?.setComputePipelineState(self.simulationPipeline)
        commandEncoder?.setTexture(readTexture, index: 0)
        commandEncoder?.setTexture(writeTexture, index: 1)
        
        commandEncoder?.setSamplerState(samplerState, index: 0)
        commandEncoder?.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)
        
        if (self.activationPoints.count > 0) {
            var cellPositions = Array<UInt32>.init(repeating: 0, count: activationPoints.count * 2)
            for i in 0..<self.activationPoints.count {
                let p = self.activationPoints[i]
                cellPositions[i*2] = UInt32(p.x)
                cellPositions[i*2 + 1] = UInt32(p.y)
            }
            
            let threadsPerThreadgroup = MTLSizeMake(self.activationPoints.count, 1, 1)
            let threadgroupCount = MTLSizeMake(1, 1, 1)
            
            commandEncoder?.setComputePipelineState(self.activationPipeline)
            commandEncoder?.setTexture(writeTexture, index: 0)
            commandEncoder?.setBytes(cellPositions, length: MemoryLayout<UInt32>.stride * cellPositions.count, index: 0)
            commandEncoder?.dispatchThreadgroups(threadgroupCount, threadsPerThreadgroup: threadsPerThreadgroup)
            
        }
        
        commandEncoder?.endEncoding()
        
        self.currentGameStateTexture = self.textureQueue.first
        self.textureQueue.remove(at: 0)
        self.textureQueue.append(self.currentGameStateTexture)
    }
    
    func encodeRenderWorkInBuffer(commandBuffer: MTLCommandBuffer) {
        let renderPassDescriptor = self.view.currentRenderPassDescriptor
        
        if(renderPassDescriptor != nil) {
            let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor!)
            
            renderEncoder?.setRenderPipelineState(self.renderPipelineState)
            renderEncoder?.setVertexBuffer(self.vertexBuffer, offset: 0, index: 0)
            renderEncoder?.setFragmentTexture(self.currentGameStateTexture, index: 0)
            renderEncoder?.setFragmentTexture(self.colorMap, index: 1)
            renderEncoder?.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
            
            renderEncoder?.endEncoding()
            
            commandBuffer.present(self.view.currentDrawable!)
        }
    }
    
    // MARK: - MTKView Delegate Methods
    
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let resizeHysteresis: TimeInterval = 0.200;
        self.nextResizeTimestamp = Date(timeIntervalSinceNow: resizeHysteresis)
        DispatchQueue.main.asyncAfter(deadline: .now()+resizeHysteresis) {
            self.reshapeWithDrawableSize(drawableSize: self.view.drawableSize)
        }
    }
    
    func draw(in view: MTKView) {
        inflightSemaphore.wait(timeout: .distantFuture)
        let commandBuffer = self.commandQueue.makeCommandBuffer()
        
        self.encodeComputerWorkInBuffer(commandBuffer: commandBuffer!)
        self.encodeRenderWorkInBuffer(commandBuffer: commandBuffer!)
        
        commandBuffer!.commit()
    }
}
