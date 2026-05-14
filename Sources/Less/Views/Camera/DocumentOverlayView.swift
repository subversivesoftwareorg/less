import SwiftUI

/// Draws the detected document boundary as a green rectangle overlay on the camera preview.
struct DocumentOverlayView: View {
    let detection: DocumentDetectionResult?

    var body: some View {
        GeometryReader { geometry in
            if let detection {
                let size = geometry.size
                Path { path in
                    // Vision coordinates are normalized (0-1) with origin at bottom-left.
                    // SwiftUI has origin at top-left, so flip Y.
                    let tl = CGPoint(x: detection.topLeft.x * size.width,
                                     y: (1 - detection.topLeft.y) * size.height)
                    let tr = CGPoint(x: detection.topRight.x * size.width,
                                     y: (1 - detection.topRight.y) * size.height)
                    let br = CGPoint(x: detection.bottomRight.x * size.width,
                                     y: (1 - detection.bottomRight.y) * size.height)
                    let bl = CGPoint(x: detection.bottomLeft.x * size.width,
                                     y: (1 - detection.bottomLeft.y) * size.height)

                    path.move(to: tl)
                    path.addLine(to: tr)
                    path.addLine(to: br)
                    path.addLine(to: bl)
                    path.closeSubpath()
                }
                .stroke(Color.green, lineWidth: 3)
                .animation(.easeInOut(duration: 0.15), value: detection.topLeft.x)
            }
        }
    }
}
