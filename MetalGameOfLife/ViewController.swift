//
//  ViewController.swift
//  MetalGameOfLife
//
//  Created by MikiTakahashi on 2018/11/08.
//  Copyright © 2018 MikiTakahashi. All rights reserved.
//

import UIKit
import MetalKit

class ViewController: UIViewController {
    var renderer: GOLRenderer!
    var metalView: MTKView!
    var metalDevice: MTLDevice!
    override func viewDidLoad() {
        super.viewDidLoad()
        self.metalView = MTKView()
        
        self.view = metalView
        
        self.setupView()
    }
    
    // MARK: - Setup Methods
    func setupView() {
        self.metalView.device = MTLCreateSystemDefaultDevice()
        self.metalView.colorPixelFormat = MTLPixelFormat.rgba8Unorm
        self.metalView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        self.metalView.drawableSize = self.metalView.bounds.size
        
        self.renderer = GOLRenderer(withView: metalView)
    }

    // MARK: - Interaction (Touch) Handling
    func locationInGridForLocationInView(point: CGPoint) -> CGPoint {
        let viewSize = self.view.frame.size
        let normalizedWidth = point.x/viewSize.width
        let normalizedHeight = point.y/viewSize.height
        let gridSize = self.renderer.gridSize as! MTLSize
        let gridX = Int(round(normalizedWidth * CGFloat(gridSize.width)))
        let gridY = Int(round(normalizedHeight * CGFloat(gridSize.height)))
        return CGPoint(x: gridX, y: gridY)
    }
    
    func activateRandomCellsForPoint(point: CGPoint) {
        let gridLocation = self.locationInGridForLocationInView(point: point)
        self.renderer.activateRandomCellsInNeighborhoodOfCell(cell: gridLocation)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self.view)
            self.activateRandomCellsForPoint(point: location)
        }
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        for touch in touches {
            let location = touch.location(in: self.view)
            self.activateRandomCellsForPoint(point: location)
        }
    }
    
}

