import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Production native character paths and voice poses, rendered without windows.
@main struct VoiceMotionPreview {
    @MainActor static func board(time: Double) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("SIEGHART · VOICE GESTURES").font(.system(size: 23, weight: .semibold))
            Text("Native animation · Listening, processing and verified completion").font(.callout).foregroundStyle(.secondary)
            ForEach(0..<3) { row in
                let phase: CompanionVoicePhase = row == 0 ? .listening : row == 1 ? .thinking : .success
                let title = row == 0 ? "LISTENING · Ear and attentive lean" : row == 1 ? "PROCESSING · Thought dots and curious gaze" : "COMPLETED · Hop, turn and landing"
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    HStack(spacing: 16) {
                        ForEach(CompanionAvatar.allCases) { avatar in
                            VStack(spacing: 2) {
                                CompanionCharacter(size: 92, avatar: avatar, animates: true, voicePhase: phase, previewTime: row == 2 ? time.truncatingRemainder(dividingBy: 1.8) : time)
                                Text(avatar.name).font(.system(size: 10, weight: .medium))
                            }.frame(width: 104, height: 118)
                        }
                    }
                }
            }
        }.padding(24).foregroundStyle(Color(red: 0.1, green: 0.12, blue: 0.12)).background(.white).environment(\.colorScheme, .light)
    }
    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: "Sieghart/Design/Concepts", isDirectory: true)
        let renderer = ImageRenderer(content: board(time: 0.55)); renderer.scale = 2
        guard let cg = renderer.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw NSError(domain: "VoicePreview", code: 1) }
        try png.write(to: directory.appendingPathComponent("simple-companions-voice.png"))
        let count = 60
        guard let gif = CGImageDestinationCreateWithURL(directory.appendingPathComponent("simple-companions-voice.gif") as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw NSError(domain: "VoicePreview", code: 2) }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for frame in 0..<count {
            let renderer = ImageRenderer(content: board(time: Double(frame) * 0.06)); renderer.scale = 1
            guard let image = renderer.cgImage else { throw NSError(domain: "VoicePreview", code: 3) }
            CGImageDestinationAddImage(gif, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.06]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw NSError(domain: "VoicePreview", code: 4) }
        print("Rendered production voice gestures for all six companions. No app or microphone opened.")
    }
}
