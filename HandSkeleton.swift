import Vision

enum HandSkeleton {
    typealias Joint = VNHumanHandPoseObservation.JointName
    
    // Each chain is a set of joints connected in order
    static let chains: [[Joint]] = [
        // Thumb
        [.thumbCMC, .thumbMP, .thumbIP, .thumbTip],
        
        // Index
        [.indexMCP, .indexPIP, .indexDIP, .indexTip],
        
        // Middle
        [.middleMCP, .middlePIP, .middleDIP, .middleTip],
        
        // Ring
        [.ringMCP, .ringPIP, .ringDIP, .ringTip],
        
        // Little
        [.littleMCP, .littlePIP, .littleDIP, .littleTip],
        
        // Palm-ish connections (optional, helps visually)
        [.wrist, .indexMCP],
        [.wrist, .middleMCP],
        [.wrist, .ringMCP],
        [.wrist, .littleMCP]
    ]
}
