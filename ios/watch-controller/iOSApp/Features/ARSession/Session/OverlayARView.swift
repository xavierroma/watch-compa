import SwiftUI
import ARKit
import RealityKit
import UIKit
import Vision
import AVFoundation
import Combine

final class OverlayARView: RealityKit.ARView, ARSessionDelegate {

    // Keep a reference to the content entity so we can update its texture
    private var contentEntity: ModelEntity?
    private var contentAnchor: AnchorEntity?
    private var dotEntity: ModelEntity?

    private weak var statusSink: ARStatusSink?

    // Combine
    private var cancellables = Set<AnyCancellable>()
    private var sceneUpdateSubscription: Cancellable?

    // Proxy for SwiftUI overlay rendering
    private let padProxy = PadCoordinatesProxy()

    // Throttle texture refreshes to avoid heavy updates
    private var lastTextureUpdate: CFAbsoluteTime = 0
    private let minTextureInterval: CFAbsoluteTime = 1.0 / 30.0 // ~30 FPS

    // Debug: visualize joints with small spheres
    private var debugVisualizeHandJoints: Bool = false
    private var jointDebugAnchor: AnchorEntity?
    private var jointSpheres: [String: ModelEntity] = [:]

    // Raw projection mode: place along camera ray at fixed distance (no depth/raycast)
    private var useFixedDistanceProjection: Bool = true
    private let fixedDistanceMeters: Float = 0.45

    // Depth-aware sizing tuning
    private let referenceDepthMeters: Float = 0.45   // where size looks "natural"
    private let minSphereScale: Float = 0.15         // clamp minimum visual size
    private let maxSphereScale: Float = 0.75         // clamp maximum visual size

    // Vision throttling and state
    private let handPoseRequest = VNDetectHumanHandPoseRequest()
    private let handQueue: DispatchQueue = DispatchQueue(label: "ar.handpose.queue", qos: .userInitiated)
    private var sequenceRequestHandler = VNSequenceRequestHandler()
    private var lastHandInferenceTime: CFAbsoluteTime = 0
    private let minHandInterval: CFAbsoluteTime = 1.0 / 30.0
    
    // HUD plane tuning
    private let hudBaseWidthMeters: Float = 0.025   // visible width at reference depth before scaling
    private let hudBaseHeightMeters: Float = 0.025 // visible height at reference depth before scaling
    private let hudMinScale: Float = 0.35
    private let hudMaxScale: Float = 1.75
    private let hudVerticalOffsetMeters: Float = 0.075 // 7,5 cm above the joint along world Y
    private var enableHUDPlane: Bool = true
    
    // HUD dot (moves on plane with pad touch)
    private var hudDotEntities: [String: ModelEntity] = [:]
    private let hudDotRadiusMeters: Float = 0.001
    private var hudAnchor: AnchorEntity?

    // Cache for HUD planes by joint name
    private var hudPlaneEntities: [String: ModelEntity] = [:]

    init(frame: CGRect, statusSink: ARStatusSink?) {
        self.statusSink = statusSink
        super.init(frame: frame)
        self.session.delegate = self

        // Bind proxy to the phone socket bridge publishers with smoothing
        let bridge = PhoneSocketBridge.shared
        padProxy.bindTo(event: bridge.$latestCoordinateEvent, on: .main)

        padProxy.$touchEvent
            .receive(on: RunLoop.main)
            .sink { [weak self] evt in
                guard let event = evt else { return }
                self?.updateHudDotPosition(from: event)
            }
            .store(in: &cancellables)
        
        handPoseRequest.maximumHandCount = 2

        // Create a debug anchor for hand joints
        let dbg = AnchorEntity(world: .zero)
        self.scene.addAnchor(dbg)
        self.jointDebugAnchor = dbg
        self.initHudAnchor(planeName: "watchHUD")
    }
    
    private func hudDot(forPlaneNamed name: String) -> ModelEntity {
        if let dot = hudDotEntities[name] { return dot }
        // Flat disc: cylinder with tiny height; plane normal is +Y so this reads 2D-on-plane
        let mesh = MeshResource.generateCylinder(height: 0.0008, radius: hudDotRadiusMeters)
        var mat = UnlitMaterial()
        mat.color = .init(tint: .white)
        mat.blending = .transparent(opacity: 1.0)
        let dot = ModelEntity(mesh: mesh, materials: [mat])
        dot.transform.rotation = .init(angle: .pi / 2, axis: .init(x: 1, y: 0, z: 0))
        hudDotEntities[name] = dot
        return dot
    }
    
    /// Moves a small dot on the HUD plane (local X–Z) based on normalized touch (u,v) in [0,1].
    private func updateHudDotPosition(from event: TouchEvent) {
        guard enableHUDPlane else { return }

        // Expect a normalized TouchEvent (x,y ∈ [0,1]); also accept a dict via FromDict for safety.
        let u: Float = max(0, min(1, Float(event.x)))
        let v: Float = max(0, min(1, Float(event.y)))
        
        let localX: Float = (u - 0.5) * hudBaseWidthMeters
        let localY: Float = (v - 0.5) * hudBaseHeightMeters
        let localZ: Float = 0.001 // tiny lift above plane to avoid z-fighting
        // Ensure plane exists and is attached
        let planeName = "watchHUD"
        let plane = hudPlane(named: planeName)
        if plane.parent == nil, let anchor = hudAnchor { anchor.addChild(plane) }

        // Ensure dot exists and is attached to the plane (inherits billboard + scaling)
        let dot = hudDot(forPlaneNamed: planeName)
        if dot.parent == nil { plane.addChild(dot) }

        dot.position = SIMD3<Float>(localX, localY, localZ)
    }

    @MainActor required dynamic init(frame frameRect: CGRect) {
        super.init(frame: frameRect)
    }

    @MainActor required dynamic init?(coder decoder: NSCoder) {
        super.init(coder: decoder)
    }

    deinit {
        sceneUpdateSubscription?.cancel()
        sceneUpdateSubscription = nil
        cancellables.removeAll()
    }

    private func setStatus(_ s: ARSessionStatus) {
        statusSink?.didUpdateStatus(s)
    }


    func prepareAndStartSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            setStatus(.notSupported)
            return
        }
        setStatus(.checkingPrerequisites)
        checkCameraAuthorizationAndStart()
    }

    private func checkCameraAuthorizationAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            setStatus(.cameraNotDetermined)
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    if granted {
                        self.setupSession()
                    } else {
                        self.setStatus(.cameraDenied)
                    }
                }
            }
        case .denied, .restricted:
            setStatus(.cameraDenied)
        @unknown default:
            setStatus(.cameraDenied)
        }
    }

    func setupSession() {
        guard ARWorldTrackingConfiguration.isSupported else {
            setStatus(.notSupported)
            return
        }
        let config = ARWorldTrackingConfiguration()
        config.environmentTexturing = .automatic
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
        }
        if let images = ARReferenceImage.referenceImages(inGroupNamed: "AR Resources", bundle: .main),
           !images.isEmpty {
            config.detectionImages = images
            config.maximumNumberOfTrackedImages = 1
        } else {
            setStatus(.missingReferenceImages)
            return
        }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        setStatus(.ready)
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let now = CFAbsoluteTimeGetCurrent()
        guard (now - lastHandInferenceTime) >= minHandInterval else { return }
        lastHandInferenceTime = now

        let pixelBuffer = frame.capturedImage
        let uiOrientation: UIInterfaceOrientation = self.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let orientation: CGImagePropertyOrientation = cgImagePropertyOrientation(for: uiOrientation)
        let viewportSize = bounds.size;

        handQueue.async { [weak self] in
            guard let self else {return}
            do {
                try self.sequenceRequestHandler.perform([self.handPoseRequest], on: pixelBuffer, orientation: orientation)
                let observations = self.handPoseRequest.results ?? []
                if observations.isEmpty {
                    return
                }
                var highestScore: (obs: VNHumanHandPoseObservation, score: Float)?
                for obs in observations {
                    guard let idx = try? obs.recognizedPoints(.thumb)[.thumbIP],
                          idx.confidence > 0.2 else { continue }
                    let score = idx.confidence
                    if highestScore == nil || score > highestScore!.score { highestScore = (obs, score) }
                }
                let chosen = highestScore?.obs
                
                if let thumbJoint = try? chosen?.recognizedPoints(.thumb)[.thumbIP] {
                    let visionPoint = CGPoint(x: CGFloat(thumbJoint.location.x), y: CGFloat(thumbJoint.location.y))
                    let imageInCameraSpace = visionPointToCameraImage(visionPoint, orientation: orientation)
                    let viewNorm = imageInCameraSpace.applying(frame.displayTransform(for: uiOrientation, viewportSize: viewportSize))
                    let screenPt = CGPoint(x: viewNorm.x * viewportSize.width,
                                           y: viewNorm.y * viewportSize.height)
                    DispatchQueue.main.async {
                        if let world = self.worldPositionRaw(screenPt: screenPt, frame: frame) {
                            self.hudAnchor?.position = world
                            print(self.hudAnchor?.position as Any)
                        }
                    }
                }
                
                if self.debugVisualizeHandJoints {
                    var pts: [(name: String, pt: CGPoint, confidence: Float)] = []
                    if let chosen {
                        if let dict = try? chosen.recognizedPoints(.thumb)  {
                            for (k, v) in dict where v.confidence > 0.2 {
                                let visionPoint = CGPoint(x: CGFloat(v.location.x), y: CGFloat(v.location.y))
                                let imageInCameraSpace = visionPointToCameraImage(visionPoint, orientation: orientation)
                                let viewNorm = imageInCameraSpace.applying(frame.displayTransform(for: uiOrientation, viewportSize: viewportSize))
                                let screenPt = CGPoint(x: viewNorm.x * viewportSize.width,
                                                       y: viewNorm.y * viewportSize.height)
                                pts.append((name: k.rawValue.rawValue, pt: screenPt, confidence: v.confidence))

                            }
                        }
                    }
                    DispatchQueue.main.async {
                        self.updateDebugHandJoints(points: pts, frame: frame, viewportSize: viewportSize)
                    }
                }
            } catch {
                print("frame processing error")
                // ignore this frame on failure
            }
        }
    }

    func sessionWasInterrupted(_ session: ARSession) {
        setStatus(.interrupted)
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // Try to resume tracking by rerunning the configuration
        prepareAndStartSession()
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        setStatus(.sessionFailed(error.localizedDescription))
    }


    private func cgImagePropertyOrientation(for orientation: UIInterfaceOrientation) -> CGImagePropertyOrientation {
      switch orientation {
      case .portrait:            return .right
      case .portraitUpsideDown:  return .left
      case .landscapeLeft:       return .down      // ⟵ was .up
      case .landscapeRight:      return .up        // ⟵ was .down
      default:                   return .right
      }
    }

    private func screenPoint(fromVisionNormalized norm: CGPoint,
                             frame: ARFrame,
                             viewportSize: CGSize) -> CGPoint
    {
        let uiOrientation: UIInterfaceOrientation =
            self.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait

        // Vision -> ARKit image space (flip Y)
        let imageForAR = CGPoint(x: norm.x, y: 1.0 - norm.y)

        // Map image-norm (top-left origin) -> view-norm
        let displayTransform = frame.displayTransform(for: uiOrientation, viewportSize: viewportSize)
        let viewNorm = imageForAR.applying(displayTransform)

        return CGPoint(x: viewNorm.x * viewportSize.width,
                       y: viewNorm.y * viewportSize.height)
    }

    private func updateDebugHandJoints(
      points: [(name: String, pt: CGPoint, confidence: Float)],
      frame: ARFrame,
      viewportSize: CGSize
    ) {
        
        for item in points {
            let screenPt = item.pt
            
            if debugVisualizeHandJoints {
                if let world = self.worldPositionRaw(screenPt: screenPt, frame: frame) {
                    guard let anchor = jointDebugAnchor else { return }
                    let node = debugSphere(named: item.name)
                    node.position = world
                    
                    // Depth-aware visual scale (smaller when farther)
                    let depth = self.sampleDepthMeters(at: screenPt, frame: frame, viewportSize: viewportSize) ?? referenceDepthMeters
                    var scale = referenceDepthMeters / max(0.05, depth) // inverse with floor
                    scale = max(minSphereScale, min(maxSphereScale, scale))
                    node.setScale(SIMD3<Float>(repeating: scale), relativeTo: nil)
                    
                    if node.parent == nil { anchor.addChild(node) }
                }
            }
        }
    }
        
    private func initHudAnchor(planeName: String) {
        if self.hudAnchor != nil { return }
        
        let anchor = AnchorEntity(world: .zero)
        self.scene.addAnchor(anchor)
        self.hudAnchor = anchor
        
        let plane = hudPlane(named: planeName)
        plane.position = anchor.position + SIMD3<Float>(0, hudVerticalOffsetMeters, 0)
        anchor.addChild(plane)
    }
    
    /// Returns a reusable billboarded HUD plane for a given joint name.
    private func hudPlane(named name: String) -> ModelEntity {
        if let e = hudPlaneEntities[name] { return e }

        let mesh = MeshResource.generatePlane(width: hudBaseWidthMeters,
                                              height: hudBaseHeightMeters)

        var material = UnlitMaterial()
        material.blending = .transparent(opacity: 1.0) // allow transparency in texture
        if let outline = makePlaneOutlineImage(size: 512).cgImage,
           let tex = try? TextureResource(image: outline, options: .init(semantic: .color)) {
            material.color = .init(texture: .init(tex))
        } else {
            // Fallback: opaque white perimeter via tint if texture creation fails
            material.color = .init(tint: .white)
        }

        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Keep the plane facing the camera so it reads like a HUD.
        entity.components.set(BillboardComponent())

        // Start unit; we scale per-frame based on depth.
        entity.scale = .one

        hudPlaneEntities[name] = entity
        return entity
    }

    private func debugSphere(named name: String) -> ModelEntity {
        if let existing = jointSpheres[name] { return existing }
        let ent = makeTransparentGridSphereEntity(radius: 0.008, gridSize: 512, latLines: 1, lonLines: 4, lineWidth: 1.0)
        jointSpheres[name] = ent
        return ent
    }

    private func worldPositionRaw(screenPt: CGPoint, frame: ARFrame) -> SIMD3<Float>? {
        guard let ray = self.ray(through: screenPt) else { return nil }
        let origin = ray.origin
        let dir = simd_normalize(ray.direction)

        let viewportSize = bounds.size
        if let depthMeters = sampleDepthMeters(at: screenPt, frame: frame, viewportSize: viewportSize) {
            // depth is line-of-sight distance from the camera → walk along the ray
            return origin + dir * depthMeters
        }
        return origin + dir * fixedDistanceMeters
    }

    
    /// Sample the LiDAR scene depth (meters) at a screen point.
    /// Returns nil if depth not available or the point is off the depth map.
    private func sampleDepthMeters(
        at screenPt: CGPoint,
        frame: ARFrame,
        viewportSize: CGSize
    ) -> Float? {
        // Prefer smoothed depth
        guard let sceneDepth = frame.smoothedSceneDepth ?? frame.sceneDepth else { return nil }
        let depthPB = sceneDepth.depthMap
        let confPB  = sceneDepth.confidenceMap  // optional but usually present

        // Map view point -> normalized image coords using inverse displayTransform
        let uiOrientation: UIInterfaceOrientation =
        self.window?.windowScene?.effectiveGeometry.interfaceOrientation ?? .portrait
        let displayTransform = frame.displayTransform(for: uiOrientation, viewportSize: viewportSize)
        let inv = displayTransform.inverted()

        let viewNorm = CGPoint(x: screenPt.x / viewportSize.width,
                               y: screenPt.y / viewportSize.height)
        var imgNorm = viewNorm.applying(inv) // [0,1]x[0,1], top-left origin

        // Guard and clamp
        if !imgNorm.x.isFinite || !imgNorm.y.isFinite { return nil }
        imgNorm.x = max(0, min(1, imgNorm.x))
        imgNorm.y = max(0, min(1, imgNorm.y))

        // Convert to depth-map pixel space
        let w = CVPixelBufferGetWidth(depthPB)
        let h = CVPixelBufferGetHeight(depthPB)
        let fx = CGFloat(w - 1) * imgNorm.x
        let fy = CGFloat(h - 1) * imgNorm.y

        CVPixelBufferLockBaseAddress(depthPB, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthPB, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(depthPB) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthPB)
        let stride = bytesPerRow / MemoryLayout<Float32>.size

        // Bilinear sample Float32 depth in meters
        let x0 = max(0, min(w - 1, Int(floor(fx))))
        let y0 = max(0, min(h - 1, Int(floor(fy))))
        let x1 = max(0, min(w - 1, x0 + 1))
        let y1 = max(0, min(h - 1, y0 + 1))
        let tx = Float(fx - CGFloat(x0))
        let ty = Float(fy - CGFloat(y0))

        func depthAt(_ x: Int, _ y: Int) -> Float {
            let rowPtr = base.advanced(by: y * bytesPerRow)
            let fPtr = rowPtr.assumingMemoryBound(to: Float.self)
            return fPtr[x]
        }

        var d00 = depthAt(x0, y0)
        var d10 = depthAt(x1, y0)
        var d01 = depthAt(x0, y1)
        var d11 = depthAt(x1, y1)

        // Optional: confidence-weighted blend (if confidenceMap exists)
        if let confPB = confPB {
            CVPixelBufferLockBaseAddress(confPB, .readOnly)
            defer { CVPixelBufferUnlockBaseAddress(confPB, .readOnly) }
            if let cbase = CVPixelBufferGetBaseAddress(confPB) {
                let cBPR = CVPixelBufferGetBytesPerRow(confPB)
                func confAt(_ x: Int, _ y: Int) -> Float {
                    let row = cbase.advanced(by: y * cBPR)
                    let p = row.assumingMemoryBound(to: UInt8.self)[x]
                    // map 0..255 to 0..1, add small epsilon to avoid dropping to zero
                    return max(0.05, Float(p) / 255.0)
                }
                let w00 = confAt(x0, y0), w10 = confAt(x1, y0)
                let w01 = confAt(x0, y1), w11 = confAt(x1, y1)

                if w00 + w10 > 0 {
                    d00 = d00 * (w00 / (w00 + w10)) + d10 * (w10 / (w00 + w10))
                }
                if w01 + w11 > 0 {
                    d01 = d01 * (w01 / (w01 + w11)) + d11 * (w11 / (w01 + w11))
                }
            }
        }

        let d0 = d00 + (d10 - d00) * tx
        let d1 = d01 + (d11 - d01) * tx
        let d = d0 + (d1 - d0) * ty

        return (d.isFinite && d > 0) ? d : nil
    }
}

    // MARK: - Debug sphere styling (transparent fill + lat/long grid texture)
    private func makeTransparentGridSphereEntity(radius: Float = 0.008,
                                                 gridSize: Int = 512,
                                                 latLines: Int = 8,
                                                 lonLines: Int = 12,
                                                 lineWidth: CGFloat = 1.0) -> ModelEntity {
        // Parent container so we can layer two spheres (fill + grid) without z-fighting issues
        let parent = ModelEntity()

        // Inner: translucent white fill using UnlitMaterial for consistent translucency
        let innerMesh = MeshResource.generateSphere(radius: radius)
        var innerMat = UnlitMaterial()
        innerMat.color = .init(tint: UIColor(white: 1.0, alpha: 1.0))
        innerMat.blending = .transparent(opacity: 0.7)
        let inner = ModelEntity(mesh: innerMesh, materials: [innerMat])
        parent.addChild(inner)

        // Outer: very slightly larger sphere with unlit grid texture (lat/long lines)
        let outerMesh = MeshResource.generateSphere(radius: radius * 1.005)
        let gridImage = makeLatLongGridImage(size: gridSize, latLines: latLines, lonLines: lonLines, lineWidth: lineWidth)
        var outerMat = UnlitMaterial()
        outerMat.blending = .transparent(opacity: 1.0)
        if let cg = gridImage.cgImage, let tex = try? TextureResource(image: cg, options: .init(semantic: .color)) {
            outerMat.color = .init(texture: .init(tex))
        } else {
            outerMat.color = .init(tint: .white)
        }
        let outer = ModelEntity(mesh: outerMesh, materials: [outerMat])
        parent.addChild(outer)

        return parent
    }

    private func makeLatLongGridImage(size: Int,
                                      latLines: Int,
                                      lonLines: Int,
                                      lineWidth: CGFloat) -> UIImage {
        let dim = CGFloat(size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim), format: format)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            // Transparent background
            cg.setFillColor(UIColor.clear.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: dim, height: dim))

            // Line style
            cg.setStrokeColor(UIColor(white: 1.0, alpha: 0.9).cgColor)
            cg.setLineWidth(lineWidth)
            cg.setLineCap(.round)

            // Equirectangular UV grid: U in [0,1] horizontally (longitude), V in [0,1] vertically (latitude)
            // Draw longitude lines (vertical lines in texture)
            if lonLines > 0 {
                // Draw exactly `lonLines` longitudes evenly spaced around [0,1), no duplicate seam
                for i in 0..<lonLines {
                    let u = CGFloat(i) / CGFloat(lonLines)
                    let x = u * dim
                    cg.move(to: CGPoint(x: x, y: 0))
                    cg.addLine(to: CGPoint(x: x, y: dim))
                }
            }

            // Draw latitude lines (horizontal lines in texture)
            if latLines > 0 {
                // Draw exactly `latLines` latitudes between the poles (exclude poles themselves)
                for j in 1...latLines {
                    let v = CGFloat(j) / CGFloat(latLines + 1) // distribute between (0,1)
                    let y = v * dim
                    cg.move(to: CGPoint(x: 0, y: y))
                    cg.addLine(to: CGPoint(x: dim, y: y))
                }
            }

            cg.strokePath()
        }
        return img
    }

    // Helper to make a transparent image with an opaque rounded white perimeter
    private func makePlaneOutlineImage(size: Int,
                                       lineWidth: CGFloat = 12.0,
                                       cornerRadius: CGFloat = 24.0,
                                       inset: CGFloat = 2.0) -> UIImage {
        let dim = CGFloat(size)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: dim, height: dim), format: format)
        let img = renderer.image { ctx in
            let cg = ctx.cgContext
            // Fully transparent background
            cg.setFillColor(UIColor.clear.cgColor)
            cg.fill(CGRect(x: 0, y: 0, width: dim, height: dim))

            // Opaque white perimeter stroke
            cg.setStrokeColor(UIColor(white: 1.0, alpha: 1.0).cgColor)
            cg.setLineWidth(lineWidth)
            cg.setLineJoin(.round)
            cg.setLineCap(.round)

            // Inset rect so the stroke doesn't clip at the edges
            let rect = CGRect(x: inset + lineWidth/2,
                              y: inset + lineWidth/2,
                              width: dim - 2*(inset + lineWidth/2),
                              height: dim - 2*(inset + lineWidth/2))
            let path = UIBezierPath(roundedRect: rect, cornerRadius: cornerRadius)
            cg.addPath(path.cgPath)
            cg.strokePath()
        }
        return img
    }


fileprivate extension simd_float4x4 {
    var translation: SIMD3<Float> { SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z) }
}

fileprivate extension SIMD3 where Scalar == Float {
    var allFinite: Bool { x.isFinite && y.isFinite && z.isFinite }
}

func visionPointToCameraImage(_ pBL: CGPoint,
                              orientation: CGImagePropertyOrientation) -> CGPoint {
    switch orientation {
    case .up:
        return CGPoint(x: pBL.x, y: 1-pBL.y)
    case .down:
        return CGPoint(x: 1-pBL.x, y: pBL.y)
    case .right:
        return CGPoint(x: 1-pBL.y, y: 1-pBL.x)
    case .left:
        return CGPoint(x: pBL.y, y: pBL.x)
    //Untested:
    case .upMirrored:
        return pBL
    case .downMirrored:
        return pBL
    case .leftMirrored:
        return pBL
    case .rightMirrored:
        return pBL
    @unknown default:
        return pBL
    }
}
