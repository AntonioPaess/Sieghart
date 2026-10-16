import AppKit
import Metal
import SceneKit
import SwiftUI

@main struct CompanionRuntimePreview {
    @MainActor static func main() throws {
        let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        if CommandLine.arguments.contains("--check-bundle") {
            let bundle = Bundle(url: folder)!
            for member in CompanionAvatar.allCases {
                let image = bundle.image(forResource: NSImage.Name("Companion-\(member.rawValue)"))!
                let pixels = CompanionArtwork.fullResolutionPixels(in: image)!
                precondition(pixels.width == 1024 && pixels.height == 1024, "Compiled assets must retain their Retina pixels")
                print("PASS: compiled \(member.name) artwork: \(pixels.width)×\(pixels.height)")
            }
            return
        }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        func write(_ image: NSImage, _ name: String) throws {
            let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
            try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name + ".png"))
        }
        if CommandLine.arguments.contains("--file-receive") {
            for member in CompanionAvatar.allCases {
                for t in [0.08,0.20,0.34,0.49,0.80,1.30] {
                    try write(CompanionScene.snapshot(avatar: member, animation: .fileReceive, time: t, size: CGSize(width: 384,height: 384)), "\(member.rawValue)-receive-\(Int(t*100))")
                }
            }
            let frames=folder.appendingPathComponent("frames", isDirectory:true)
            try FileManager.default.createDirectory(at: frames, withIntermediateDirectories:true)
            let actor=CompanionScene.Coordinator(.toni), renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(), options:nil)
            renderer.scene=actor.scene;renderer.pointOfView=actor.camera;renderer.autoenablesDefaultLighting=false
            for index in 0..<156 {
                let wall=Double(index)/60, animation:CompanionAnimation=wall<0.65 ? .fileOpen : wall<1.95 ? .fileReceive : .idle
                let time=wall<0.65 ? wall : wall<1.95 ? wall-0.65 : wall-1.95
                actor.update(CompanionScene(avatar:.toni,animation:animation,time:time,animates:true,gaze:nil,replay:0,preview:true))
                let image=renderer.snapshot(atTime:wall,with:CGSize(width:512,height:512),antialiasingMode:.multisampling4X)
                try NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!.write(to:frames.appendingPathComponent(String(format:"%04d.png",index)))
            }
            print("Rendered file intake for six native rigs and 156 frames for Toni; app stayed closed.")
            return
        }
        if CommandLine.arguments.contains("--portraits") {
            // Export from native geometry at the target pixel resolution. Do not
            // upscale old PNGs or use a continuous renderer for idle portraits.
            for member in CompanionAvatar.allCases {
                let asset = folder.appendingPathComponent("Companion-\(member.rawValue).imageset", isDirectory: true)
                try FileManager.default.createDirectory(at: asset, withIntermediateDirectories: true)
                for (scale, pixels) in [(1, 512), (2, 1024)] {
                    let image = CompanionScene.snapshot(avatar: member, size: CGSize(width: pixels, height: pixels))
                    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                    precondition(rep.pixelsWide == pixels && rep.pixelsHigh == pixels)
                    try rep.representation(using: .png, properties: [:])!.write(to: asset.appendingPathComponent(scale == 1 ? "portrait.png" : "portrait@2x.png"))
                }
                let contents = """
                {"images":[{"filename":"portrait.png","idiom":"universal","scale":"1x"},{"filename":"portrait@2x.png","idiom":"universal","scale":"2x"}],"info":{"author":"xcode","version":1}}
                """
                try contents.write(to: asset.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
            }
            print("PASS: six native 512px/1024px portrait pairs exported; app not launched.")
            return
        }
        if CommandLine.arguments.contains("--display-quality") {
            let sheet = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 920,
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 32)!
            let graphics = NSGraphicsContext(bitmapImageRep: sheet)!
            NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = graphics
            graphics.cgContext.scaleBy(x: 2, y: 2)
            NSColor(srgbRed: 0.025, green: 0.028, blue: 0.031, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: 720, height: 460).fill()
            for (index, member) in CompanionAvatar.allCases.enumerated() {
                let source = CompanionArtwork.fullResolutionPixels(in: CompanionArtwork.portrait(for: member))!
                let x = CGFloat(index % 3) * 240, y: CGFloat = index < 3 ? 230 : 10
                for (points, offset) in [(96, 34), (38, 165)] {
                    let cg = CompanionArtwork.displayPixels(from: source, width: points * 2, height: points * 2)
                    let image = NSImage(cgImage: cg, size: CGSize(width: points, height: points))
                    image.draw(in: CGRect(x: x + CGFloat(offset), y: y + 84, width: CGFloat(points), height: CGFloat(points)))
                    ("\(points) pt" as NSString).draw(at: CGPoint(x: x + CGFloat(offset), y: y + 63), withAttributes: [.font: NSFont.systemFont(ofSize: 10), .foregroundColor: NSColor.gray])
                }
                (member.name as NSString).draw(at: CGPoint(x: x + 34, y: y + 29), withAttributes: [.font: NSFont.systemFont(ofSize: 16, weight: .semibold), .foregroundColor: NSColor.white])
            }
            NSGraphicsContext.restoreGraphicsState()
            try sheet.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("display-quality.png"))
            print("PASS: display-size portrait preview uses the production Retina raster cache; app not launched.")
            return
        }
        let montage = NSImage(size: NSSize(width: 1020, height: 680))
        montage.lockFocus(); NSColor(srgbRed: 0.055, green: 0.06, blue: 0.07, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 1020, height: 680).fill()
        for (index, member) in CompanionAvatar.allCases.enumerated() {
            let image = CompanionScene.snapshot(avatar: member, animation: .idle, time: 1.3, size: CGSize(width: 420, height: 420))
            try write(CompanionScene.snapshot(avatar: member, size: CGSize(width: 256, height: 256)), "Companion-\(member.rawValue)")
            let x = 40 + (index % 3) * 330, y = index < 3 ? 390 : 65
            image.draw(in: NSRect(x: x + 45, y: y + 30, width: 210, height: 210))
            (member.name as NSString).draw(at: NSPoint(x: x + 125, y: y + 9), withAttributes: [.font: NSFont.systemFont(ofSize: 22, weight: .semibold), .foregroundColor: NSColor.white])
            (member.subtitle as NSString).draw(at: NSPoint(x: x + 72, y: y - 15), withAttributes: [.font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.lightGray])
        }
        montage.unlockFocus(); try write(montage, "native-family")
        let team = CompanionTeamScene.Coordinator()
        let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        renderer.scene = team.greeting.scene; renderer.pointOfView = team.camera; renderer.autoenablesDefaultLighting = false
        let viewport = CompanionOpeningLayout.viewport(for: CompanionHomeLayout().size)
        let pixels = CGSize(width: viewport.width * 2, height: viewport.height * 2)
        if CommandLine.arguments.contains("--border-check") {
            team.update(time: 3.5, animates: true)
            let light = team.greeting.halo
            light.geometry?.firstMaterial?.multiply.contents = NSColor.white
            for (name, order, readsDepth) in [("border-before", 0, true), ("border-after", -100, false)] {
                light.renderingOrder = order
                light.geometry?.firstMaterial?.readsFromDepthBuffer = readsDepth
                try write(renderer.snapshot(atTime: 3.5, with: pixels, antialiasingMode: .multisampling2X), name)
            }
            print("PASS: identical geometry and pose rendered with old/new halo composition at native 2× MSAA; app not launched.")
            return
        }
        for (name, t) in [("hello", 1.8), ("hello-rest", 3.5), ("orbit", 6.6), ("dock", 8.7), ("sig", 11.5), ("rita", 14.1), ("ada", 17.1), ("gantt", 20.1), ("elinor", 23.1), ("toni", 26.1), ("ready", 30.5)] {
            team.update(time: t, animates: true)
            try write(renderer.snapshot(atTime: t, with: pixels, antialiasingMode: .multisampling4X), name)
        }
        for member in CompanionAvatar.allCases {
            for (animation, t) in [(CompanionAnimation.listening, 1.1), (.working, 1.3), (.sleeping, 1.7)] {
                try write(CompanionScene.snapshot(avatar: member, animation: animation, time: t, size: CGSize(width: 448, height: 448)), "\(member.rawValue)-\(animation.rawValue)")
            }
        }
        if CommandLine.arguments.contains("--movie") {
            let frames = URL(fileURLWithPath: "/private/tmp/sieghart-hello-frames", isDirectory: true)
            try FileManager.default.createDirectory(at: frames, withIntermediateDirectories: true)
            let layout = CompanionHomeLayout()
            let dockLabelOffset = viewport.height - CompanionHomeLayout.height
            // Rasterize the production SwiftUI caption once per stage. Reusing
            // it keeps export cost bounded and matches the app's actual layout.
            let captions = [10.0, 13, 16, 19, 22, 25, 28].map { t in
                let member = CompanionTeamFormation.activeMember(at: t) ?? .sig
                let view = CompanionIntroductionCaption(member: member, copy: .forIntroduction(at: t))
                    .frame(width: layout.size.width - 142, alignment: .leading)
                    .foregroundStyle(Color.white).environment(\.colorScheme, .dark)
                let caption = ImageRenderer(content: view); caption.scale = 2
                let cg = caption.cgImage!
                return NSImage(cgImage: cg, size: CGSize(width: cg.width, height: cg.height))
            }
            for frame in 0..<Int(CompanionTeamFormation.duration * 60) {
                try autoreleasepool {
                    let t = Double(frame) / 60
                    team.update(time: t, animates: true)
                    let scene = renderer.snapshot(atTime: t, with: pixels, antialiasingMode: .multisampling2X)
                    let image = NSImage(size: pixels)
                    image.lockFocus()
                    NSColor(srgbRed: 0.018, green: 0.02, blue: 0.023, alpha: 1).setFill()
                    NSRect(origin: .zero, size: pixels).fill()
                    scene.draw(in: NSRect(origin: .zero, size: pixels))
                    if t >= CompanionTeamFormation.dockTime {
                        let caption = captions[CompanionTeamFormation.turn(at: t)]
                        let centerY = pixels.height / 2 + (CompanionHomeLayout.height / 2 - layout.hero.y + CompanionHomeLayout.introductionTextLift) * 2
                        caption.draw(in: NSRect(x: 284, y: centerY - caption.size.height / 2, width: caption.size.width, height: caption.size.height))
                    }
                    if t >= CompanionTeamFormation.dockTime {
                        for member in CompanionAvatar.allCases {
                            guard let slot = CompanionTeamFormation.dockSlot(member: member, turn: CompanionTeamFormation.turn(at: t)) else { continue }
                            let text = member.name as NSString, font = NSFont.systemFont(ofSize: 18, weight: .medium)
                            let width = text.size(withAttributes: [.font: font]).width
                            text.draw(at: NSPoint(x: layout.dock(slot).x * 2 - width / 2, y: 9 + dockLabelOffset), withAttributes: [.font: font, .foregroundColor: NSColor.lightGray])
                        }
                    }
                    image.unlockFocus()
                    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
                    try rep.representation(using: .png, properties: [:])!.write(to: frames.appendingPathComponent(String(format: "%04d.png", frame)))
                }
            }
            print("\(Int(CompanionTeamFormation.duration * 60)) frames exported from the production SceneKit choreography at 60 fps. Text overlay reproduces its layout; this is not an app screen recording.")
        }
        // Exercise frame updates independently of display refresh, after mesh-cache warmup.
        let c = CompanionScene.Coordinator(.sig)
        for i in 0..<90 { c.update(CompanionScene(avatar: .sig, animation: .listening, time: Double(i)/60, animates: true, gaze: nil, replay: 0)) }
        let start = Date()
        for i in 90..<390 { c.update(CompanionScene(avatar: .sig, animation: .listening, time: Double(i)/60, animates: true, gaze: nil, replay: 0)) }
        print("Native frame update average: \(Date().timeIntervalSince(start) * 1000 / 300) ms. GPU snapshots and 23 PNGs exported; app not launched.")
    }
}
