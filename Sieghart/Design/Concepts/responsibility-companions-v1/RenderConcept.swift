import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Offscreen-only design artifact. Never initializes NSApplication or any live service.
@main struct RenderConcept {
    static let ink = Color(red: 0.16, green: 0.19, blue: 0.18)
    @MainActor static func board(time: Double) -> some View {
        let phase = ConceptPhase.current(time).phase
        return VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 7) {
                    Text("SIEGHART / SEIS COMPANIONS").font(.system(size: 21, weight: .semibold, design: .rounded)).tracking(0.6)
                    Text("Nomes e responsabilidades propostos · estudo de movimento")
                        .font(.system(size: 12)).foregroundStyle(ink.opacity(0.6))
                }
                Spacer()
                Text("PRÉVIA 01").font(.system(size: 11, weight: .bold)).foregroundStyle(ink.opacity(0.45))
            }
            HStack(spacing: 6) {
                ForEach(ConceptPhase.allCases, id: \.rawValue) { item in
                    Text(item.title).font(.system(size: 9, weight: .semibold)).tracking(0.3)
                        .padding(.horizontal, 10).padding(.vertical, 9)
                        .foregroundStyle(item == phase ? Color.white : ink.opacity(0.5))
                        .background(item == phase ? ink : ink.opacity(0.045), in: Capsule())
                }
            }
            VStack(spacing: 14) {
                ForEach(0..<2) { row in
                    HStack(spacing: 14) {
                        ForEach(Array(StudyAvatar.allCases[(row * 3)..<(row * 3 + 3)])) { avatar in
                            VStack(spacing: 5) {
                                ConceptCharacter(avatar: avatar, time: time)
                                Text(avatar.name).font(.system(size: 22, weight: .semibold, design: .rounded))
                                Text(avatar.role).font(.system(size: 12)).foregroundStyle(ink.opacity(0.6))
                            }.frame(width: 250, height: 248)
                                .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 24))
                        }
                    }
                }
            }
            HStack {
                Text(phase.detail).font(.system(size: 12)).foregroundStyle(ink.opacity(0.7))
                Spacer()
                Text("12 s / ciclo de demonstração").font(.system(size: 10)).foregroundStyle(ink.opacity(0.45))
            }.frame(height: 18)
        }.padding(28).foregroundStyle(ink)
            .background(Color(red: 0.970, green: 0.963, blue: 0.940))
            .environment(\.colorScheme, .light)
    }

    @MainActor static func snapshot(_ time: Double, to url: URL) throws {
        let renderer = ImageRenderer(content: board(time: time)); renderer.scale = 2
        guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw NSError(domain: "Concept", code: 1) }
        try png.write(to: url)
    }
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "Sieghart/Design/Concepts/responsibility-companions-v1", isDirectory: true)
        try snapshot(2.4, to: folder.appendingPathComponent("motion-still.png"))
        try snapshot(4.7, to: folder.appendingPathComponent("listening-left.png"))
        try snapshot(3.7, to: folder.appendingPathComponent("listening-right.png"))
        try snapshot(6.2, to: folder.appendingPathComponent("thinking.png"))
        try snapshot(10.3, to: folder.appendingPathComponent("sleeping.png"))
        if CommandLine.arguments.contains("--stills-only") { return }
        let frames = FileManager.default.temporaryDirectory.appendingPathComponent("sieghart-concept-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: frames) }
        for frame in 0..<720 {
            let renderer = ImageRenderer(content: board(time: Double(frame) / 60)); renderer.scale = 1
            guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw NSError(domain: "Concept", code: 2) }
            try png.write(to: frames.appendingPathComponent(String(format: "%04d.png", frame)))
        }
        func encode(_ arguments: [String]) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/opt/homebrew/bin/ffmpeg")
            process.arguments = ["-hide_banner", "-loglevel", "error", "-y"] + arguments
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else { throw NSError(domain: "Concept", code: 3) }
        }
        let input = ["-framerate", "60", "-i", frames.appendingPathComponent("%04d.png").path]
        try encode(input + ["-c:v", "libx264", "-crf", "18", "-preset", "fast", "-pix_fmt", "yuv420p", "-movflags", "+faststart", folder.appendingPathComponent("companions-motion.mp4").path])
        try encode(input + ["-filter_complex", "fps=25,scale=640:-2:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=192[p];[s1][p]paletteuse=dither=sierra2_4a", "-loop", "0", folder.appendingPathComponent("companions-motion.gif").path])
        print("Created 12-second concept animation: MP4 60 fps + GIF 25 fps. No app changes.")
    }
}
