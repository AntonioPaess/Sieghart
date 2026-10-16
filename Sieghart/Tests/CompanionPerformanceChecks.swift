import AppKit
import Darwin
@preconcurrency import Metal
@preconcurrency import SceneKit
import SwiftUI

// Metal render-pass benchmark: real geometry, materials, shaders and command
// buffers at 60 Hz. No app, windows, microphone, permissions or resident services.
private final class RenderProbe: @unchecked Sendable {
    let renderer: SCNRenderer
    let queue: any MTLCommandQueue
    let texture: any MTLTexture
    let size: CGSize
    let actor: CompanionScene.Coordinator?
    let team: CompanionTeamScene.Coordinator?
    @MainActor init(size: CGSize, animation: CompanionAnimation? = nil, arrival: Bool = false, member: CompanionAvatar = .sig) {
        self.size = size
        let device = MTLCreateSystemDefaultDevice()!
        queue = device.makeCommandQueue()!
        renderer = SCNRenderer(device: device, options: nil)
        renderer.autoenablesDefaultLighting = false
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm,
            width: Int(size.width), height: Int(size.height), mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .private
        texture = device.makeTexture(descriptor: descriptor)!
        if arrival {
            let c = CompanionTeamScene.Coordinator(); team = c; actor = nil
            c.configure(CompanionTeamScene.Input(start: Date.timeIntervalSinceReferenceDate,
                                                animates: true, size: CompanionOpeningLayout.viewport(for: CompanionHomeLayout().size)))
            renderer.scene = c.greeting.scene; renderer.pointOfView = c.camera; renderer.delegate = c
        } else {
            let c = CompanionScene.Coordinator(member); actor = c; team = nil
            c.configure(CompanionScene(avatar: member, animation: animation ?? .idle,
                time: Date.timeIntervalSinceReferenceDate, animates: true, gaze: nil, replay: 0))
            renderer.scene = c.scene; renderer.pointOfView = c.camera; renderer.delegate = c
        }
    }
    private func render() -> Double {
        let begin = CACurrentMediaTime()
        autoreleasepool {
            let pass = MTLRenderPassDescriptor()
            pass.colorAttachments[0].texture = texture
            pass.colorAttachments[0].loadAction = .clear; pass.colorAttachments[0].storeAction = .store
            pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
            let command = queue.makeCommandBuffer()!
            renderer.render(atTime: CACurrentMediaTime(), viewport: CGRect(origin: .zero, size: size), commandBuffer: command, passDescriptor: pass)
            command.commit(); command.waitUntilCompleted(); precondition(command.status == .completed)
        }
        return (CACurrentMediaTime() - begin) * 1000
    }
    func run(name: String, frames: Int = 300) -> String { Self.run([self], name: name, frames: frames) }
    static func run(_ probes: [RenderProbe], name: String, frames: Int = 300) -> String {
        precondition(!Thread.isMainThread)
        func cpu() -> Double {
            var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
                + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        for _ in 0..<45 { for probe in probes { _ = probe.render() } }
        let start = CACurrentMediaTime(), initialCPU = cpu()
        var samples = [Double](), deadline = start
        for _ in 0..<frames {
            let begin = CACurrentMediaTime()
            for probe in probes { _ = probe.render() }
            samples.append((CACurrentMediaTime() - begin) * 1000); deadline += 1.0 / 60
            let wait = deadline - CACurrentMediaTime()
            if wait > 0 { usleep(useconds_t(wait * 1_000_000)) }
        }
        let duration = CACurrentMediaTime() - start, cpuPercent = (cpu() - initialCPU) / duration * 100
        samples.sort()
        for probe in probes {
            precondition((probe.actor?.renderedFrameCount ?? probe.team!.renderedFrameCount) >= frames)
            precondition(probe.actor?.renderedOffMain ?? probe.team!.renderedOffMain, "All pose updates must run off the main thread")
        }
        let p95 = samples[Int(Double(samples.count - 1) * 0.95)]
        precondition(cpuPercent < 40, "Renderer CPU regression: \(cpuPercent)%")
        precondition(p95 < 16.7, "60Hz frame budget missed: \(p95) ms")
        return String(format: "%@: %.1f%% CPU; %.2fms p95 including GPU completion; %.1f FPS", name, cpuPercent, p95, Double(frames)/duration)
    }

}

@main struct CompanionPerformanceChecks {
    @MainActor static func main() async {
        print("Metal validation: \(ProcessInfo.processInfo.environment["MTL_DEBUG_LAYER"] ?? "default")")
        for (name, member, animation) in [("Sig listening 192px", CompanionAvatar.sig, CompanionAnimation.listening),
                                         ("Sig thinking 192px", .sig, .voiceThinking),
                                         ("Elinor dizzy 448px", .elinor, .dizzy),
                                         ("Toni hello 448px", .toni, .hello)] {
            let probe = RenderProbe(size: CGSize(width: name.contains("448") ? 448 : 192, height: name.contains("448") ? 448 : 192), animation: animation, member: member)
            print(await Task.detached { probe.run(name: name) }.value)
        }
        let simultaneous = [RenderProbe(size: CGSize(width: 192, height: 192), animation: .listening),
                            RenderProbe(size: CGSize(width: 448, height: 448), animation: .working, member: .elinor),
                            RenderProbe(size: CGSize(width: 448, height: 448), animation: .thinking, member: .toni)]
        print(await Task.detached { RenderProbe.run(simultaneous, name: "Three simultaneous scenes") }.value)
        let team = RenderProbe(size: CGSize(width: 1064, height: 600), arrival: true)
        let arrivalFrames = Int(CompanionTeamFormation.duration * 60)
        print(await Task.detached { team.run(name: "Six-member arrival 1064×600", frames: arrivalFrames) }.value)
        print("PASS: native Metal rendering, bounded CPU, 60Hz frame budget and no per-frame main-thread work")
    }
}
