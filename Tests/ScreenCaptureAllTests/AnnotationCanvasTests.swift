import CoreGraphics
import Testing
@testable import ScreenCaptureAll

struct AnnotationCanvasTests {
    @Test(arguments: [
        CGRect(x: 0, y: 0, width: 1920, height: 1080),
        CGRect(x: -1920, y: -300, width: 3840, height: 1380),
        CGRect(x: -2500.5, y: -1600.25, width: 1500.75, height: 1000.5)
    ])
    func screenAndCanvasRoundTrip(frame: CGRect) {
        let canvas = AnnotationCanvas(frameInAppKitScreenSpace: frame)
        #expect(canvas.point(fromScreen: CGPoint(x: frame.minX, y: frame.maxY)) == .zero)
        #expect(canvas.point(fromScreen: CGPoint(x: frame.maxX, y: frame.minY)) == CGPoint(
            x: frame.width,
            y: frame.height
        ))

        // Conversion is not clamped: hidden annotations keep their full geometry.
        for point in [CGPoint.zero, CGPoint(x: 123.25, y: 456.5), CGPoint(x: -40.5, y: -20.25)] {
            let screenPoint = canvas.screenPoint(fromCanvas: point)
            #expect(canvas.point(fromScreen: screenPoint) == point)
            #expect(canvas.screenPoint(fromCanvas: canvas.point(fromScreen: point)) == point)
        }
    }

    @Test
    func screenRectUsesItsTopLeftCornerInCanvas() {
        let canvas = AnnotationCanvas(frameInAppKitScreenSpace: CGRect(x: -800, y: -300, width: 2000, height: 1200))
        let screenRect = CGRect(x: -700, y: 500, width: 240, height: 180)
        #expect(canvas.rect(fromScreen: screenRect) == CGRect(x: 100, y: 220, width: 240, height: 180))
    }

    @Test(arguments: [CGFloat(1), 2, 5.0 / 3.0])
    func selectionOffsetAndFractionalDensity(density: CGFloat) throws {
        let canvas = AnnotationCanvas(frameInAppKitScreenSpace: CGRect(x: -1000, y: -400, width: 2400, height: 1600))
        let selection = CGRect(x: -600, y: 200, width: 300, height: 180)
        let destination = CGRect(x: 17.5, y: -23.25, width: 300 * density, height: 180 * density)
        let transform = try #require(canvas.transform(selectionRect: selection, destinationRect: destination))
        let topLeft = canvas.point(fromScreen: CGPoint(x: selection.minX, y: selection.maxY))
        let bottomRight = canvas.point(fromScreen: CGPoint(x: selection.maxX, y: selection.minY))
        expectClose(topLeft.applying(transform), CGPoint(x: destination.minX, y: destination.maxY))
        expectClose(bottomRight.applying(transform), CGPoint(x: destination.maxX, y: destination.minY))

        let canvasPoint = canvas.point(fromScreen: CGPoint(x: selection.minX + 37.25, y: selection.maxY - 61.5))
        let mappedPoint = canvasPoint.applying(transform)
        expectClose(mappedPoint, CGPoint(x: destination.minX + 37.25 * density, y: destination.maxY - 61.5 * density))
        expectClose(mappedPoint.applying(transform.inverted()), canvasPoint)
    }

    @Test
    func destinationUsesIndependentXAndYDensity() throws {
        let canvas = AnnotationCanvas(frameInAppKitScreenSpace: CGRect(x: -1200, y: -900, width: 3000, height: 2100))
        let selection = CGRect(x: -300, y: -100, width: 120, height: 80)
        let destination = CGRect(x: -50, y: 30, width: 200, height: 160)
        let transform = try #require(canvas.transform(selectionRect: selection, destinationRect: destination))
        let screenPoint = CGPoint(x: -264, y: -40)
        let canvasPoint = canvas.point(fromScreen: screenPoint)
        expectClose(canvasPoint.applying(transform), CGPoint(x: 10, y: 150))
        #expect(abs(transform.a - CGFloat(5.0 / 3.0)) < 0.000_001)
        #expect(transform.d == -2)
        expectClose(canvasPoint.applying(transform).applying(transform.inverted()), canvasPoint)
    }

    @Test
    func movingAndResizingSelectionDoNotChangeCanvasGeometry() throws {
        let canvas = AnnotationCanvas(frameInAppKitScreenSpace: CGRect(x: -500, y: -300, width: 1600, height: 1000))
        let screenPoint = CGPoint(x: -200, y: 400)
        let point = canvas.point(fromScreen: screenPoint)
        for selection in [
            CGRect(x: -300, y: 300, width: 200, height: 200),
            CGRect(x: -250, y: 350, width: 100, height: 100),
            CGRect(x: 0, y: 0, width: 100, height: 100)
        ] {
            let destination = CGRect(origin: .zero, size: selection.size)
            let transform = try #require(canvas.transform(selectionRect: selection, destinationRect: destination))
            expectClose(point.applying(transform), CGPoint(x: screenPoint.x - selection.minX, y: screenPoint.y - selection.minY))
            #expect(canvas.point(fromScreen: screenPoint) == point)
        }
    }

    @Test
    func perDisplayDestinationKeepsFullSelectionMapping() throws {
        let canvas = AnnotationCanvas(frameInAppKitScreenSpace: CGRect(x: -120, y: -50, width: 240, height: 150))
        let selection = CGRect(x: -60, y: 0, width: 120, height: 100)
        // The overlay only sees x >= 0, but receives the complete destination.
        let destination = CGRect(x: -60, y: 0, width: 120, height: 100)
        let transform = try #require(canvas.transform(selectionRect: selection, destinationRect: destination))
        let visiblePoint = canvas.point(fromScreen: CGPoint(x: 20, y: 30))
        #expect(visiblePoint.applying(transform) == CGPoint(x: 20, y: 30))
        let hiddenPoint = canvas.point(fromScreen: CGPoint(x: -40, y: 70))
        #expect(hiddenPoint.applying(transform) == CGPoint(x: -40, y: 70))
    }

    @Test
    func emptySelectionOrDestinationHasNoTransform() {
        let canvas = AnnotationCanvas(frameInAppKitScreenSpace: CGRect(x: 0, y: 0, width: 100, height: 100))
        let frame = CGRect(x: 0, y: 0, width: 40, height: 30)
        #expect(canvas.transform(selectionRect: .zero, destinationRect: frame) == nil)
        #expect(canvas.transform(selectionRect: frame, destinationRect: .zero) == nil)
    }

    private func expectClose(_ actual: CGPoint, _ expected: CGPoint) {
        #expect(abs(actual.x - expected.x) < 0.000_001)
        #expect(abs(actual.y - expected.y) < 0.000_001)
    }
}
