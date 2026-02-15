import SwiftUI
import Vision

struct HandOverlay: View {
    typealias Joint = VNHumanHandPoseObservation.JointName
    
    let points: [Joint: CGPoint]      // normalized [0,1]
    let mirrored: Bool                // front camera typically true
    
    var body: some View {
        GeometryReader { _ in
            Canvas { context, size in
                // 1) Draw bones (lines)
                var path = Path()
                
                for chain in HandSkeleton.chains {
                    var last: CGPoint? = nil
                    
                    for joint in chain {
                        guard let pNorm = points[joint] else {
                            last = nil
                            continue
                        }
                        let p = toScreen(pNorm, size: size, mirrored: mirrored)
                        
                        if let prev = last {
                            path.move(to: prev)
                            path.addLine(to: p)
                        }
                        last = p
                    }
                }
                
                context.stroke(path, with: .color(.white), lineWidth: 4)
                
                // 2) Draw joints (dots)
                for (_, pNorm) in points {
                    let p = toScreen(pNorm, size: size, mirrored: mirrored)
                    let r: CGFloat = 5
                    let rect = CGRect(x: p.x - r, y: p.y - r, width: 2*r, height: 2*r)
                    context.fill(Path(ellipseIn: rect), with: .color(.white))
                }
                
                // 3) Draw bend angle labels
                drawAngleLabels(context: &context, size: size)
            }
            .allowsHitTesting(false)
        }
    }
    
    // MARK: - Angle labels
    
    private func drawAngleLabels(context: inout GraphicsContext, size: CGSize) {
        // Angle at B using A-B-C
        let triples: [(a: Joint, b: Joint, c: Joint)] = [
            // Index
            (.wrist,    .indexMCP,  .indexPIP),
            (.indexMCP, .indexPIP,  .indexDIP),
            (.indexPIP, .indexDIP,  .indexTip),
            
            // Middle
            (.wrist,     .middleMCP, .middlePIP),
            (.middleMCP, .middlePIP, .middleDIP),
            (.middlePIP, .middleDIP, .middleTip),
            
            // Ring
            (.wrist,   .ringMCP,  .ringPIP),
            (.ringMCP, .ringPIP,  .ringDIP),
            (.ringPIP, .ringDIP,  .ringTip),
            
            // Little
            (.wrist,     .littleMCP, .littlePIP),
            (.littleMCP, .littlePIP, .littleDIP),
            (.littlePIP, .littleDIP, .littleTip),
            
            // Thumb (CMC -> MP -> IP -> Tip)
            (.thumbCMC, .thumbMP, .thumbIP),
            (.thumbMP,  .thumbIP, .thumbTip),
        ]
        
        let font = Font.system(size: 12, weight: .semibold, design: .rounded)
        
        for t in triples {
            guard
                let A = points[t.a],
                let B = points[t.b],
                let C = points[t.c]
            else { continue }
            
            let aS = toScreen(A, size: size, mirrored: mirrored)
            let bS = toScreen(B, size: size, mirrored: mirrored)
            let cS = toScreen(C, size: size, mirrored: mirrored)
            
            guard let deg = angleDegrees(a: aS, b: bS, c: cS) else { continue }
            
            // Slight offset so text doesn't sit directly on the dot
            let labelPoint = CGPoint(x: bS.x + 10, y: bS.y - 10)
            
            let s = "\(Int(round(deg)))°"
            let text = Text(s).font(font).foregroundColor(.white)
            context.draw(text, at: labelPoint, anchor: .topLeading)
        }
    }
    
    /// Angle ABC at point B in degrees (2D).
    private func angleDegrees(a: CGPoint, b: CGPoint, c: CGPoint) -> Double? {
        let v1 = CGVector(dx: a.x - b.x, dy: a.y - b.y)
        let v2 = CGVector(dx: c.x - b.x, dy: c.y - b.y)
        
        let dot = v1.dx * v2.dx + v1.dy * v2.dy
        let m1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let m2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        
        guard m1 > 1e-6, m2 > 1e-6 else { return nil }
        
        var cosv = dot / (m1 * m2)
        cosv = min(1, max(-1, cosv))
        
        return Double(acos(cosv) * 180.0 / .pi)
    }
    
    // Vision normalized coords: origin bottom-left
    // SwiftUI coords: origin top-left
    private func toScreen(_ p: CGPoint, size: CGSize, mirrored: Bool) -> CGPoint {
        var x = p.x * size.width
        let y = (1.0 - p.y) * size.height   // flip Y
        
        if mirrored {
            x = size.width - x              // flip X
        }
        return CGPoint(x: x, y: y)
    }
}
