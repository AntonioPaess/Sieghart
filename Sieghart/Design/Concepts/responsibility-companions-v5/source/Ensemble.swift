import AppKit
import SceneKit
import Darwin

final class Ensemble {
    let study=GreetingStudy(.sig)
    var agents:[CharacterModel]=[]
    let angles:[Double]=[162,18,90,234,306]
    let sceneHeight=360.0
    init() {
        study.renderer.pointOfView?.camera?.orthographicScale=180
        for hero in Hero.allCases.dropFirst() {
            let m=CharacterModel(hero);study.scene.rootNode.addChildNode(m.root);agents.append(m)
        }
    }
    func frame(_ t:Double)->Data {
        SCNTransaction.begin();SCNTransaction.disableActions=true
        study.update(t)
        let expand=GE.inOut(gSeg(t,4.25,5.10)),height=gLerp(104,330,expand)
        study.card.geometry=SCNShape(path:NSBezierPath(roundedRect:CGRect(x:-310,y:-height/2,width:620,height:height),xRadius:20,yRadius:20),extrusionDepth:0)
        let cm=SCNMaterial();cm.lightingModel = .constant;cm.diffuse.contents=rgb(20/255,21/255,24/255);study.card.geometry?.materials=[cm]
        for (i,m) in agents.enumerated() {
            let start=4.50+Double(i)*0.09,u=gSeg(t,start,start+1.15)
            let radius=120*GE.back(u),orbit=GE.inOut(gSeg(t,5.35,7.25))
            let angle=angles[i]*Double.pi/180-(1-orbit)*Double.pi*0.60
            m.root.position=SCNVector3(cos(angle)*radius,sin(angle)*radius,-26*(1-GE.out(u)))
            m.root.opacity=GE.out(gSeg(t,start,start+0.28))
            let bounds=nsPath(bodyPath(m.hero)).bounds
            let scale=gLerp(0.08,42/bounds.height,GE.back(u))
            m.head.scale=SCNVector3(scale,scale,scale)
            m.head.position=SCNVector3(-bounds.midX*scale,-bounds.midY*scale,0)
            m.head.eulerAngles=SCNVector3(0,-0.10+sin(t+Double(i))*0.03,sin(t*1.4+Double(i))*0.015)
            let blink=(t+Double(i)*0.27).truncatingRemainder(dividingBy:3.9)
            let open=blink>3.4 && blink<3.65 ? 1-sin((blink-3.4)/0.25*Double.pi)*0.95 : 1
            m.updateEyes(open:open,joy:0.55*sin(Double.pi*gSeg(t,start+0.5,start+2)),gaze:CGSize(width:-cos(angle)*1.4,height:sin(angle)*0.8),wink:0,anger:0)
            if m.hero == .toni {m.paper?.eulerAngles=SCNVector3(0.08,0,-0.1-0.12*sin(t*2))}
        }
        SCNTransaction.commit()
        let shot=study.renderer.snapshot(atTime:t,with:CGSize(width:1280,height:720),antialiasingMode:.multisampling4X)
        let output=NSImage(size:CGSize(width:640,height:430));output.lockFocus()
        rgb(0.035,0.039,0.047).setFill();NSRect(x:0,y:0,width:640,height:430).fill()
        shot.draw(in:NSRect(x:0,y:34,width:640,height:360))
        GreetingStudy.text("SIEGHART / UM COMPANION, UMA EQUIPE",x:20,y:402,size:14,weight:.semibold,color:rgb(0.92,0.90,0.86))
        let labels=GE.inOut(gSeg(t,7.25,8.0))
        if labels>0 {
            let c=NSColor(srgbRed:0.85,green:0.84,blue:0.81,alpha:labels)
            for (i,m) in agents.enumerated() {
                let p=m.root.position,x=320+Double(p.x),y=214+Double(p.y)-37
                let name=m.hero.name as NSString,attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:12,weight:.medium),.foregroundColor:c]
                name.draw(at:NSPoint(x:x-name.size(withAttributes:attrs).width/2,y:y),withAttributes:attrs)
                let role=["Saúde e pausas","Código e GitHub","Agenda e rotina","Finanças e recursos","Comunicação"][i] as NSString
                let small:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:9),.foregroundColor:c]
                role.draw(at:NSPoint(x:x-role.size(withAttributes:small).width/2,y:y-14),withAttributes:small)
            }
            let name="Sig · principal" as NSString,attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11,weight:.medium),.foregroundColor:c]
            name.draw(at:NSPoint(x:320-name.size(withAttributes:attrs).width/2,y:173),withAttributes:attrs)
        }
        let phase=t<4.5 ? "O alô do Sig" : t<5.8 ? "A equipe sai de trás dele" : t<7.25 ? "Os cinco rodeiam o Sig" : "Cada um encontra seu lugar"
        GreetingStudy.text(phase,x:20,y:12,size:11,weight:.regular,color:rgb(0.68,0.68,0.70))
        GreetingStudy.text("Conceito · 60 fps",x:531,y:12,size:10,weight:.regular,color:rgb(0.51,0.52,0.55))
        output.unlockFocus()
        return NSBitmapImageRep(data:output.tiffRepresentation!)!.representation(using:.png,properties:[:])!
    }
}

func export(_ file:String,seconds:Double,frame:(Double)->Data)throws {
    let p=Process();p.executableURL=URL(fileURLWithPath:"/opt/homebrew/bin/ffmpeg")
    p.arguments=["-hide_banner","-loglevel","error","-y","-f","image2pipe","-framerate","60","-i","pipe:0","-c:v","libx264","-crf","16","-preset","fast","-pix_fmt","yuv420p","-movflags","+faststart",ExportGreeting.folder.appendingPathComponent(file).path]
    let pipe=Pipe();p.standardInput=pipe;try p.run()
    for i in 0..<Int(seconds*60) {
        autoreleasepool {pipe.fileHandleForWriting.write(frame(Double(i)/60))}
        if i%180==0 {print("\(file): \(i)/\(Int(seconds*60))")}
    }
    try pipe.fileHandleForWriting.close();p.waitUntilExit()
    guard p.terminationStatus==0 else {throw NSError(domain:"MotionV5",code:3)}
}

@main struct ExportV5 {
    static func main()throws {
        setbuf(stdout,nil)
        let e=Ensemble()
        for (name,t) in [("ensemble-emerging",5.5),("ensemble-orbit",6.5),("ensemble-settled",8.2)] {
            try e.frame(t).write(to:ExportGreeting.folder.appendingPathComponent(name+".png"))
        }
        let r=GreetingStudy(.rita),toni=GreetingStudy(.toni)
        for (name,t) in [("rest",4.6),("wave-out",1.6),("wave-return",1.77)] {
            try r.frame(t).write(to:ExportGreeting.folder.appendingPathComponent("rita-"+name+".png"))
            try toni.frame(t).write(to:ExportGreeting.folder.appendingPathComponent("toni-"+name+".png"))
        }
        if CommandLine.arguments.contains("--stills-only") {print("V5 stills saved");return}
        try export("ensemble-hello-60fps.mp4",seconds:10,frame:e.frame)
        try export("rita-hello-60fps.mp4",seconds:6,frame:r.frame)
        try export("toni-hello-60fps.mp4",seconds:6,frame:toni.frame)
        if CommandLine.arguments.contains("--greetings-only") {return}
        let flow=AgentFlow()
        try flow.frame(7.8).write(to:ExportGreeting.folder.appendingPathComponent("agent-flow.png"))
        try export("agent-flow-60fps.mp4",seconds:16,frame:flow.frame)
    }
}
