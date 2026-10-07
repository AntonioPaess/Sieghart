import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// Render native artwork offscreen. Never instantiate the app, live adapters,
// shortcut registrations, sensor or microphone for a design preview.
@main struct CompanionPreview {
    @MainActor static func board(time: Double? = nil, dark: Bool = true, sleeping: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Text("SIEGHART — SIMPLE COMPANIONS").font(.system(size: 24, weight: .semibold))
            Text(sleeping ? "Sleeping · Soft breathing and floating z" : time == nil ? "Native artwork · Small shapes, expressive eyes" : "Native movement · Breathing, gaze and soft blinking")
                .font(.callout).foregroundStyle(CompanionStyle.muted)
            Grid(horizontalSpacing: 18, verticalSpacing: 18) {
                ForEach(0..<2) { row in
                    GridRow {
                        ForEach(Array(CompanionAvatar.allCases[row * 3 ..< row * 3 + 3])) { avatar in
                            VStack(spacing: 14) {
                                CompanionCharacter(size: time == nil ? (dark ? 108 : 160) : 94, avatar: avatar, animates: time != nil,
                                    gaze: CGSize(width: sin((time ?? 0) * 1.3) * 3, height: cos((time ?? 0) * 1.1) * 1.5), mood: sleeping ? .asleep : .idle, previewTime: time)
                                Text(avatar.name).font(.headline)
                                HStack(spacing: 28) {
                                    CompanionCharacter(size: 28, avatar: avatar, animates: false, mood: .happy)
                                    CompanionCharacter(size: 28, avatar: avatar, animates: false, mood: .annoyed)
                                    CompanionCharacter(size: 28, avatar: avatar, animates: false, mood: .asleep)
                                }
                                Text("HAPPY       GRUMPY       SLEEP").font(.system(size: 8, weight: .medium)).foregroundStyle(CompanionStyle.muted)
                            }.frame(width: 242).padding(22)
                                .background(dark ? CompanionStyle.surface : .white, in: RoundedRectangle(cornerRadius: 20))
                        }
                    }
                }
            }
        }.padding(30).foregroundStyle(dark ? .white : Color(red: 0.10, green: 0.12, blue: 0.12)).background(dark ? CompanionStyle.background : .white).environment(\.colorScheme, dark ? .dark : .light)
    }

    @MainActor static func main() throws {
        let directory = URL(fileURLWithPath: "Sieghart/Design/Concepts", isDirectory: true)
        let still = ImageRenderer(content: board()); still.scale = 2
        guard let cg = still.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 1) }
        try png.write(to: directory.appendingPathComponent("avatar-reactions-preview.png"))
        let light = ImageRenderer(content: board(dark: false)); light.scale = 2
        guard let lightImage = light.cgImage, let lightPNG = NSBitmapImageRep(cgImage: lightImage).representation(using: .png, properties: [:]) else { throw NSError(domain: "Preview", code: 5) }
        try lightPNG.write(to: directory.appendingPathComponent("simple-companions-depth-preview.png"))
        let count = 94
        guard let gif = CGImageDestinationCreateWithURL(directory.appendingPathComponent("simple-companions-motion.gif") as CFURL, UTType.gif.identifier as CFString, count, nil) else { throw NSError(domain: "Preview", code: 2) }
        CGImageDestinationSetProperties(gif, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<count {
            let renderer = ImageRenderer(content: board(time: Double(index) / 20, dark: false)); renderer.scale = 1
            guard let frame = renderer.cgImage else { throw NSError(domain: "Preview", code: 3) }
            CGImageDestinationAddImage(gif, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(gif) else { throw NSError(domain: "Preview", code: 4) }
        guard let sleep = CGImageDestinationCreateWithURL(directory.appendingPathComponent("simple-companions-sleep.gif") as CFURL, UTType.gif.identifier as CFString, 90, nil) else { throw NSError(domain: "Preview", code: 6) }
        CGImageDestinationSetProperties(sleep, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for index in 0..<90 {
            let renderer = ImageRenderer(content: board(time: Double(index) / 20, sleeping: true)); renderer.scale = 1
            guard let frame = renderer.cgImage else { throw NSError(domain: "Preview", code: 7) }
            CGImageDestinationAddImage(sleep, frame, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.05]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(sleep) else { throw NSError(domain: "Preview", code: 8) }
        print("Rendered six native companions and a 20 fps preview. Runtime motion updates at 60 Hz.")
    }
}
