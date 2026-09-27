import Foundation

enum Side: String { case left, right }

let sideLandmarks: [String: [String: Int]] = [
    "left": ["hip": 23, "knee": 25, "ankle": 27],
    "right": ["hip": 24, "knee": 26, "ankle": 28],
]

func jointAngle(_ a: [Double], _ b: [Double], _ c: [Double]) -> Double {
    let ba = [a[0]-b[0], a[1]-b[1]]
    let bc = [c[0]-b[0], c[1]-b[1]]
    let dot = ba[0]*bc[0] + ba[1]*bc[1]
    let normBA = (ba[0]*ba[0] + ba[1]*ba[1]).squareRoot()
    let normBC = (bc[0]*bc[0] + bc[1]*bc[1]).squareRoot()
    var cosAngle = dot / (normBA * normBC)
    cosAngle = max(-1.0, min(1.0, cosAngle))
    return acos(cosAngle) * 180.0 / .pi
}

func segmentAngleVsVertical(_ top: [Double], _ bottom: [Double]) -> Double {
    let dx = bottom[0] - top[0]
    let dy = bottom[1] - top[1]
    var cosAngle = dy / (dx*dx + dy*dy).squareRoot()
    cosAngle = max(-1.0, min(1.0, cosAngle))
    return acos(cosAngle) * 180.0 / .pi
}

func selectSide(_ landmarks: [Double]) -> Side {
    let leftIds = [23, 25, 27]
    let rightIds = [24, 26, 28]
    let leftVis = leftIds.map { landmarks[$0*3+2] }.reduce(0,+) / 3.0
    let rightVis = rightIds.map { landmarks[$0*3+2] }.reduce(0,+) / 3.0
    return leftVis >= rightVis ? .left : .right
}
