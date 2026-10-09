import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Offscreen renderer only. No windows, microphone, shortcuts or live services.
@main struct RenderStudy {
    static let ink = Color(red: 0.14, green: 0.17, blue: 0.16)
    @MainActor static func board(time: Double) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SIEGHART / EXPRESSÕES").font(.system(size: 24, weight: .semibold, design: .rounded))
                Text("PRÉVIA 02   ·   Silhuetas preservadas, gestos menores, Coast Buddy redesenhado")
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.62))
            }
            ForEach(StudyPhase.allCases, id: \.rawValue) { phase in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(phase.title).font(.system(size: 11, weight: .bold)).tracking(1)
                        Text(phase.detail).font(.system(size: 11)).foregroundStyle(ink.opacity(0.6))
                    }
                    HStack(spacing: 12) {
                        ForEach(StudyAvatar.allCases) { avatar in
                            VStack(spacing: 2) {
                                StudyCharacter(avatar: avatar, phase: phase, time: time)
                                Text(avatar.name).font(.system(size: 11, weight: .semibold))
                            }.frame(width: 132, height: 142)
                                .background(Color.white, in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                }
            }
            Text("Estudo de animação · os gestos se repetem aqui para comparação · o app permanece sem alterações")
                .font(.system(size: 10)).foregroundStyle(ink.opacity(0.55))
        }.padding(26).foregroundStyle(ink).background(Color(red: 0.953, green: 0.960, blue: 0.949))
            .environment(\.colorScheme, .light)
    }

    @MainActor static func coast() -> some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("COAST BUDDY / NOVA DIREÇÃO").font(.system(size: 22, weight: .semibold, design: .rounded))
            Text("Calmo · curioso · de boa com a vida").font(.system(size: 13)).foregroundStyle(ink.opacity(0.65))
            HStack(alignment: .center, spacing: 22) {
                VStack(spacing: 10) {
                    StudyFace(avatar: .coastBuddy, openness: 0.92, joy: 0, tilt: 0, gaze: .zero).frame(width: 245, height: 245)
                    Text("CALMO").font(.system(size: 11, weight: .bold)).tracking(1.4)
                }.frame(width: 260)
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 20) {
                        VStack(spacing: 6) {
                            StudyCharacter(avatar: .coastBuddy, phase: .thinking, time: 0.6, size: 130)
                            Text("Curioso").font(.system(size: 12, weight: .medium))
                        }
                        VStack(spacing: 6) {
                            StudyCharacter(avatar: .coastBuddy, phase: .success, time: 0.52, size: 130)
                            Text("Entendido, de boa").font(.system(size: 12, weight: .medium))
                        }
                    }
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Mesma simplicidade dos outros companions")
                        Text("Olhos descansados e expressão tranquila")
                        Text("Uma curva pequena e a paleta verde suave")
                        Text("Movimento lento e piscadinha de confirmação")
                    }.font(.system(size: 12)).foregroundStyle(ink.opacity(0.70))
                }
            }.padding(16).background(.white, in: RoundedRectangle(cornerRadius: 24))
            Text("Proposta visual para aprovação · não aplicado ao app").font(.system(size: 10)).foregroundStyle(ink.opacity(0.55))
        }.padding(26).foregroundStyle(ink).background(Color(red: 0.953, green: 0.960, blue: 0.949)).environment(\.colorScheme, .light)
    }

    @MainActor static func writePNG<V: View>(_ content: V, to url: URL) throws {
        let renderer = ImageRenderer(content: content); renderer.scale = 2
        guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw NSError(domain: "Study", code: 1) }
        try png.write(to: url)
    }

    @MainActor static func writeVideo(to url: URL) throws {
        let frames = FileManager.default.temporaryDirectory.appendingPathComponent("sieghart-study-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: frames) }
        for frame in 0..<240 {
            let renderer = ImageRenderer(content: board(time: Double(frame) / 60)); renderer.scale = 1
            guard let cg = renderer.cgImage, let data = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw NSError(domain: "StudyVideo", code: 1) }
            try data.write(to: frames.appendingPathComponent(String(format: "%04d.png", frame)))
        }
        let encoder = Process()
        encoder.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
        encoder.arguments = ["-hide_banner", "-loglevel", "error", "-y", "-framerate", "60", "-i", frames.appendingPathComponent("%04d.png").path, "-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", url.path]
        try encoder.run(); encoder.waitUntilExit()
        guard encoder.terminationStatus == 0 else { throw NSError(domain: "StudyVideo", code: 2) }
    }

    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: "Sieghart/Design/Concepts/expressive-study-v2", isDirectory: true)
        try writePNG(board(time: 0.52), to: folder.appendingPathComponent("expressive-study-v2.png"))
        try writePNG(coast(), to: folder.appendingPathComponent("coast-buddy-v2.png"))
        let count = 100
        guard let gif = CGImageDestinationCreateWithURL(folder.appendingPathComponent("expressive-study-v2.gif") as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw NSError(domain: "Study", code: 2) }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<count {
            let renderer = ImageRenderer(content: board(time: Double(frame) * 0.04)); renderer.scale = 1
            guard let image = renderer.cgImage else { throw NSError(domain: "Study", code: 3) }
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.04]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw NSError(domain: "Study", code: 4) }
        if CommandLine.arguments.contains("--video") { try writeVideo(to: folder.appendingPathComponent("expressive-study-v2.mp4")) }
        print("Rendered preview-only expressions and Coast redesign. App sources unchanged.")
    }
}
