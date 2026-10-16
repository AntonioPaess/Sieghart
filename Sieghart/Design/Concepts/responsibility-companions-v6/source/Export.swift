import AppKit
import Darwin

func exportRaw(_ file:String,seconds:Double,width:Int,height:Int,draw:(Double)->Data)throws {
    let process=Process();process.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
    process.arguments=["-hide_banner","-loglevel","error","-y","-f","rawvideo","-pixel_format","rgba","-video_size","\(width)x\(height)","-framerate","60","-i","pipe:0","-c:v","libx264","-crf","16","-preset","fast","-pix_fmt","yuv420p","-movflags","+faststart",ExportGreeting.folder.appendingPathComponent(file).path]
    let pipe=Pipe();process.standardInput=pipe;try process.run()
    let count=Int((seconds*60).rounded())
    for i in 0..<count {
        autoreleasepool {pipe.fileHandleForWriting.write(draw(Double(i)/60))}
        if i%300==0 {print("\(file): \(i)/\(count)")}
    }
    try pipe.fileHandleForWriting.close();process.waitUntilExit()
    guard process.terminationStatus==0 else {throw NSError(domain:"ConceptMotion",code:Int(process.terminationStatus))}
    print("Saved \(file)")
}

@main struct ExportV6 {
    static func main()throws {
        setbuf(stdout,nil)
        let folder=ExportGreeting.folder
        let manifest=try JSONDecoder().decode(MotionManifest.self,from:Data(contentsOf:folder.appendingPathComponent("motion-manifest.json")))
        let target=CommandLine.arguments.dropFirst().first ?? "all"
        if target=="all" || target=="onboarding" || target=="stills" {
            let e=TeamOnboarding()
            for (file,time) in [("onboarding-orbit",6.7),("onboarding-docking",8.7),("onboarding-widget",26.6),("onboarding-rita",11.5)] {
                e.draw(time);try e.canvas.png.write(to:folder.appendingPathComponent(file+".png"))
            }
            if target != "stills" {try exportRaw("onboarding-widget-60fps.mp4",seconds:30,width:1280,height:960){t in e.draw(t);return e.canvas.bytes}}
        }
        let library=MotionLibrary()
        for clip in manifest.clips where target=="all" || target=="stills" || target==clip.id {
            for stage in clip.stages {
                let time=stage.start+min(1.1,stage.duration*0.45)
                library.draw(clip,time);try library.canvas.png.write(to:folder.appendingPathComponent("motion-\(stage.id).png"))
            }
            library.draw(clip,clip.stages[0].start+min(1.0,clip.stages[0].duration*0.4))
            try library.canvas.png.write(to:folder.appendingPathComponent(clip.poster))
            if target != "stills" {try exportRaw(clip.file,seconds:clip.duration,width:1280,height:1040){t in library.draw(clip,t);return library.canvas.bytes}}
        }
    }
}
