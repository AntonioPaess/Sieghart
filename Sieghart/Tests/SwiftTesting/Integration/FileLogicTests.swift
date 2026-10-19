import Foundation
import Testing

extension LogicTests {
    @Suite(.tags(.filesCapture)) struct FileNameTests {
        @Test("G16.01 — nomes inválidos não escapam do diretório", arguments: ["../escape", "a/b", "", ".", "..", "bad\nname"])
        func invalidName(_ value: String) { #expect(!LocalFileOperations.validName(value)) }
        @Test("G16.01 — nomes literais com acentos e metacaracteres são válidos")
        func literalName() { #expect(LocalFileOperations.validName("literal $() ação.txt")) }
    }
    @Suite(.tags(.filesCapture)) struct URLCleanupTests {
        @Test("G16.05 — tracking removido preserva encoding, parâmetros funcionais repetidos e fragmento")
        func encoding() throws {
            let review = try URLTrackingCleanup.review("https://example.com/a%2Fb?utm_source=mail&q=a%2Bb&ref=keep&q=two&fbclid=abc#section")
            #expect(review.cleaned == "https://example.com/a%2Fb?q=a%2Bb&ref=keep&q=two#section")
        }
        @Test("G16.05 — URL assinada identificada; scheme não web rejeitado")
        func signedAndInvalid() throws {
            #expect(try URLTrackingCleanup.review("https://example.com/?X-Amz-Signature=abc&utm_source=keep").isSigned)
            #expect(throws: (any Error).self) { try URLTrackingCleanup.review("javascript:alert(1)") }
        }
    }
    @Suite(.tags(.filesCapture)) struct FileReceiverGeometryTests {
        @Test("G16.11 — coordenadas de tela, origem negativa e Retina são normalizadas em pontos", arguments: [CGFloat(0.85), 1, 1.2], [CGPoint(x: -1900, y: -400), .zero, CGPoint(x: 1440, y: 200)])
        func normalize(_ scale: CGFloat, _ origin: CGPoint) {
            let rect = CGRect(origin: origin, size: CGSize(width: 532 * scale, height: FileReceiverGeometry.stageHeight * scale))
            for point in [CGPoint.zero, CGPoint(x: 1, y: 1), CGPoint(x: 0.31, y: 0.72), CGPoint(x: 0.5, y: 0.5)] {
                let global = CGPoint(x: rect.minX + point.x * rect.width, y: rect.maxY - point.y * rect.height)
                let normalized = FileReceiverGeometry.normalizedPoint(global, in: rect)
                #expect(abs(normalized.x - point.x) < 0.000001 && abs(normalized.y - point.y) < 0.000001)
            }
            let center = FileReceiverGeometry.normalizedPoint(CGPoint(x: rect.midX, y: rect.midY), in: rect)
            #expect(abs(center.x - 0.5) < 1e-6 && abs(center.y - 0.5) < 1e-6)
        }
        @Test("G16.12 — corpo dentro da área, movimento vertical e Reduce Motion", arguments: [CGSize(width: 280, height: FileReceiverGeometry.stageHeight), CGSize(width: 532, height: 240), CGSize(width: 704, height: 320)])
        func characterBounds(_ size: CGSize) {
            let half = FileReceiverGeometry.characterSize / 2
            for point in [CGPoint(x: -1, y: -1), .zero, CGPoint(x: 1, y: 1), CGPoint(x: 2, y: 2)] {
                let center = FileReceiverGeometry.characterCenter(for: point, in: size, following: true)
                #expect(center.x - half >= 4 && center.x + half <= size.width - 4 && center.y - half >= 10 && center.y + half <= size.height - 10)
            }
            let upper = FileReceiverGeometry.characterCenter(for: CGPoint(x: 0.5, y: 0.08), in: size, following: true)
            let lower = FileReceiverGeometry.characterCenter(for: CGPoint(x: 0.5, y: 0.92), in: size, following: true)
            #expect(upper.x == lower.x && upper.y < lower.y)
            let still = FileReceiverGeometry.characterCenter(for: .zero, in: size, following: false)
            #expect(still == FileReceiverGeometry.characterCenter(for: CGPoint(x: 1, y: 1), in: size, following: false))
            #expect(still.x == size.width / 2 && still.y == 78)
        }
    }
}
