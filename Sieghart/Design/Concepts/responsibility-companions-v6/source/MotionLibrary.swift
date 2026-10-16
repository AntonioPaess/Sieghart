import AppKit
import SceneKit
import Metal
import SwiftUI

// Isolated visual concepts. No microphone, calendar, account or real agent is used.
struct MotionStage: Decodable {
    let id:Int, title:String, motion:String, start:Double, duration:Double
}
struct MotionClip: Decodable {
    let id:String, file:String, poster:String, duration:Double, stages:[MotionStage]
}
struct MotionManifest: Decodable { let clips:[MotionClip] }
let roles=["Companion principal","Saúde e pausas","Código e GitHub","Agenda e rotina","Finanças e recursos","Comunicação e arquivos"]

final class ConceptCanvas {
    let rep:NSBitmapImageRep
    let width:Int, height:Int
    init(_ width:Int,_ height:Int) {
        self.width=width;self.height=height
        rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32)!
    }
    func draw(_ block:()->Void) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
        NSGraphicsContext.current!.cgContext.scaleBy(x:2,y:2)
        rgb(0.035,0.039,0.047).setFill();NSRect(x:0,y:0,width:width/2,height:height/2).fill()
        block();NSGraphicsContext.restoreGraphicsState()
    }
    var bytes:Data {Data(bytes:rep.bitmapData!,count:rep.bytesPerRow*rep.pixelsHigh)}
    var png:Data {rep.representation(using:.png,properties:[:])!}
    static func centered(_ text:String,x:Double,y:Double,size:Double,weight:NSFont.Weight = .regular,color:NSColor = cream) {
        let s=text as NSString,attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color]
        s.draw(at:NSPoint(x:x-s.size(withAttributes:attrs).width/2,y:y),withAttributes:attrs)
    }
}

func centeredShape(_ path:Path,_ color:NSColor,_ depth:Double=1)->SCNNode {
    // shape() maps the design's 96×96 coordinates to a centered SceneKit node.
    shape(path,color:color,depth:depth,bevel:0.3)
}
func smallText(_ value:String,color:NSColor,size:Double)->SCNNode {
    let geometry=SCNText(string:value,extrusionDepth:0.35)
    geometry.font=NSFont.systemFont(ofSize:size,weight:.semibold);geometry.flatness=0.1
    let mat=SCNMaterial();mat.lightingModel = .constant;mat.diffuse.contents=color;geometry.materials=[mat]
    let node=SCNNode(geometry:geometry),bounds=node.boundingBox
    node.pivot=SCNMatrix4MakeTranslation((bounds.min.x+bounds.max.x)/2,(bounds.min.y+bounds.max.y)/2,0)
    return node
}
func heartPath()->Path {
    var p=Path();p.move(to:CGPoint(x:48,y:54))
    p.addCurve(to:CGPoint(x:41,y:44),control1:CGPoint(x:37,y:46),control2:CGPoint(x:38,y:39))
    p.addQuadCurve(to:CGPoint(x:48,y:43),control:CGPoint(x:45,y:40))
    p.addQuadCurve(to:CGPoint(x:55,y:44),control:CGPoint(x:52,y:40))
    p.addCurve(to:CGPoint(x:48,y:54),control1:CGPoint(x:59,y:39),control2:CGPoint(x:59,y:46));p.closeSubpath();return p
}
func starPath()->Path {
    polygon((0..<10).map {i in let a=Double(i)*Double.pi/5-Double.pi/2,r=i%2==0 ? 6.5 : 2.8;return(48+cos(a)*r,48+sin(a)*r)},radius:0.3)
}
enum ParticleKind {case heart,star,spark,sweat,z}

final class MotionActor {
    let model:CharacterModel
    let halo=SCNNode(),hands=[SCNNode(),SCNNode()],slot=SCNNode(),file=SCNNode(),bar=SCNNode(),fill=SCNNode(),cursor=SCNNode()
    let question:SCNNode,exclamation:SCNNode,check:SCNNode
    var particles:[ParticleKind:[SCNNode]]=[:],cheeks:[SCNNode]=[]
    let bounds:CGRect,index:Int
    init(_ hero:Hero,_ index:Int) {
        self.index=index;model=CharacterModel(hero);model.prepareMotion();bounds=nsPath(bodyPath(hero)).bounds
        let hm=SCNMaterial();hm.lightingModel = .constant;hm.diffuse.contents=GreetingStudy.glowTexture();hm.isDoubleSided=true;hm.writesToDepthBuffer=false
        halo.geometry=SCNPlane(width:bounds.height*3.2,height:bounds.height*3.2);halo.geometry?.materials=[hm];halo.position=SCNVector3(bounds.midX,bounds.midY,-32);model.root.addChildNode(halo)
        for (i,h) in hands.enumerated() {
            let path:Path=hero == .ada ? Path(roundedRect:CGRect(x:43,y:43,width:10,height:10),cornerRadius:0.6) : hero == .gantt ? Path(roundedRect:CGRect(x:42,y:43,width:12,height:9),cornerRadius:2) : Path(ellipseIn:CGRect(x:42,y:44,width:12,height:8))
            h.geometry=centeredShape(path,hero == .toni || hero == .gantt ? cream : hero.color,4).geometry
            h.position=SCNVector3((i==0 ? -1 : 1)*(bounds.width/2+7),-8,model.front+3);h.opacity=0;model.head.addChildNode(h)
        }
        let sg=SCNBox(width:28,height:1,length:0.8,chamferRadius:0.4);sg.materials=[material(ink)];slot.geometry=sg;slot.position=SCNVector3(0,-14,model.front+2);slot.opacity=0;model.head.addChildNode(slot)
        file.geometry=centeredShape(Path(roundedRect:CGRect(x:41,y:39,width:14,height:18),cornerRadius:2),cream,1.5).geometry
        let corner=centeredShape(polygon([(49,39),(55,39),(55,45)]),lilac,0.7);corner.position.z=2;file.addChildNode(corner);file.opacity=0;model.root.addChildNode(file)
        for (node,color) in [(bar,rgb(0.20,0.23,0.25)),(fill,mint)] {
            let box=SCNBox(width:76,height:2.5,length:0.5,chamferRadius:1.2);box.materials=[material(color)];node.geometry=box;node.position=SCNVector3(0,-48,model.front);model.root.addChildNode(node);node.opacity=0
        }
        let pointer=polygon([(48,42),(48,54),(51,50),(55,51)],radius:0.3)
        cursor.geometry=centeredShape(pointer,cream,1).geometry;cursor.position.z=CGFloat(model.front+18);cursor.opacity=0;model.root.addChildNode(cursor)
        question=smallText("?",color:gold,size:13);exclamation=smallText("!",color:coral,size:13);check=smallText("✓",color:mint,size:12)
        for n in [question,exclamation,check] {n.position=SCNVector3(-bounds.width/2-3,bounds.height/2+3,model.front+8);n.opacity=0;model.head.addChildNode(n)}
        for kind in [ParticleKind.heart,.star,.spark,.sweat,.z] {
            var nodes:[SCNNode]=[]
            for _ in 0..<5 {
                let n:SCNNode
                switch kind {
                case .heart:n=centeredShape(heartPath(),coral,1.2)
                case .star:n=centeredShape(starPath(),gold,1)
                case .spark:n=centeredShape(polygon([(48,43),(51,48),(48,53),(45,48)]),mint,1)
                case .sweat:n=centeredShape(polygon([(48,42),(44,49),(45,53),(51,53),(52,49)],radius:2),rgb(0.5,0.7,0.9),1)
                case .z:n=smallText("z",color:lilac,size:9)
                }
                n.opacity=0;model.root.addChildNode(n);nodes.append(n)
            };particles[kind]=nodes
        }
        for x in [-20.0,20.0] {
            let n=centeredShape(Path(ellipseIn:CGRect(x:44,y:46,width:8,height:4)),coral,0.4)
            n.position=SCNVector3(x,-8,model.front+1);n.opacity=0;model.head.addChildNode(n);cheeks.append(n)
        }
    }
    func particle(_ kind:ParticleKind,_ t:Double,repeatEvery:Double=0,amount:Int=5,strength:Double=1) {
        let local=repeatEvery>0 ? t.truncatingRemainder(dividingBy:repeatEvery) : t
        for (i,n) in particles[kind]!.enumerated() {
            let age=local-Double(i)*0.14,life=1.55+Double(i%2)*0.2,k=gSeg(age,0,life)
            n.opacity=i<amount && age>=0 && age<life ? sin(k*Double.pi)*strength : 0
            n.position=SCNVector3(kind == .z ? 25+k*12 : (Double(i)-2)*11+sin(k*3+Double(i))*4,bounds.maxY+4+k*23,model.front+3)
            n.scale=SCNVector3(0.45+k*0.20,0.45+k*0.20,0.65)
            n.eulerAngles.z=CGFloat(kind == .z ? 0 : sin(k*3+Double(i))*0.20)
        }
    }
    func resetExtras() {
        hands.forEach{$0.opacity=0};[slot,file,bar,fill,cursor,question,exclamation,check].forEach{$0.opacity=0}
        particles.values.flatMap{$0}.forEach{$0.opacity=0};cheeks.forEach{$0.opacity=0}
        model.accessory.opacity=1;model.accessory.scale=SCNVector3(1,1,1);model.accessory.eulerAngles.z=0
        model.paperRight?.eulerAngles.z=0
        file.scale=SCNVector3(1,1,1);question.scale=SCNVector3(1,1,1)
        if model.hero == .sig {model.accessory.childNodes.first?.geometry?.firstMaterial?.diffuse.contents=mint}
    }
    func handWave(_ t:Double,_ presence:Double) {
        let k=max(0,presence)
        if model.hero == .toni {
            model.paper?.eulerAngles=SCNVector3(0.08+k*0.18,0,-0.1-k*(0.5+sin(t*Double.pi*6)*0.22))
            model.paperRight?.eulerAngles.z=CGFloat(k*sin(t*3)*0.045)
        } else {
            for (i,h) in hands.enumerated() {
                h.opacity=k;h.scale=SCNVector3(k,k,k)
                h.position.y=CGFloat(-8+(i==0 ? sin(t*Double.pi*10)*6*k : 12*k))
                h.eulerAngles.z=CGFloat((i==0 ? -1 : 1)*(0.45+sin(t*Double.pi*5)*0.12)*k)
            }
        }
    }
    func update(id:Int,t:Double,duration:Double,global:Double) {
        resetExtras()
        let hero=model.hero,offset=Double(index)*0.11
        // Activities retain the previously approved task-specific geometry.
        model.animate(State.working.start+min(max(0,t),3.4))
        model.activity.opacity=id==9 ? smooth(t/0.25) : 0
        var p=pose(hero,.idle,t,global+Double(index)*0.17)
        var color=rgb(0.50,0.55,0.55),haloStrength=0.10,blush=0.0
        var customScale=1.0,rollEyes=false,showHand=0.0
        func burst(_ start:Double,_ length:Double=0.7)->Double {sin(gSeg(t,start,start+length)*Double.pi)}
        func squash(_ start:Double=0.55) {
            let u=t-start
            var sy=1.0,sx=1.0
            if u>=0 && u<0.07 {sy=gLerp(1,0.78,GE.out(u/0.07));sx=gLerp(1,1.16,GE.out(u/0.07))}
            else if u<0.2 && u>=0.07 {sy=gLerp(0.78,1.10,GE.out((u-0.07)/0.13));sx=gLerp(1.16,0.95,GE.out((u-0.07)/0.13))}
            else if u<0.37 && u>=0.2 {sy=gLerp(1.1,1,GE.inOut((u-0.2)/0.17));sx=gLerp(0.95,1,GE.inOut((u-0.2)/0.17))}
            if hero != .ada && hero != .gantt {p.sy*=sy;p.sx*=sx}
            p.y+=sin(gSeg(u,0,0.6)*Double.pi)*3
        }
        switch id {
        case 1:
            let g=greetPose(t,compact:IslandRestingLayout())
            customScale=g.hb/58;p.x=(g.x-320)*0.7;p.y=(90-g.y)*0.7;p.opacity=g.hb>0 ? 1 : 0
            p.sx=g.sx;p.sy=g.sy;p.open=g.open;p.joy=g.eye == .happy ? 0.85 : g.eye == .content ? 0.6 : 0
            p.gaze=CGSize(width:g.lookX*4,height:g.lookY*3);showHand=max(g.handL,g.handR)
            handWave(max(0,g.wave),showHand);color=rgb(gLerp(0.91,0.23,g.haloBlue),gLerp(0.76,0.62,g.haloBlue),gLerp(0.60,1,g.haloBlue));haloStrength=g.halo*0.85
            particle(.spark,t-0.5,amount:5,strength:0.5)
        case 2:
            let x=sin(t*2.2)*4,y=sin(t*1.2)*2;p.gaze=CGSize(width:x,height:y);p.yaw=x*0.09;p.pitch = -y*0.025
            cursor.opacity=0.85;cursor.position=SCNVector3(x*8,18-y*6,model.front+18)
        case 3:
            let local=t*1.9+Double(index)*1.07;p.gaze=CGSize(width:sin(local)*3,height:cos(local*0.7)*1.3);p.yaw=sin(local)*0.22
        case 4,46:
            let b=sin(t*1.8+Double(index)*0.53);if hero != .ada && hero != .gantt {p.sy=1+b*0.023;p.sx=1-b*0.006};p.y=b*0.65
        case 5:
            let u=(t-offset).truncatingRemainder(dividingBy:1.7)
            let b=u>0.45 && u<0.65 ? sin((u-0.45)/0.20*Double.pi) : u>0.85 && u<1.05 ? sin((u-0.85)/0.20*Double.pi) : 0
            p.open=1-b*0.95
        case 6:
            squash();cursor.opacity=0.8;cursor.position=SCNVector3(-12,16,model.front+18);p.joy=burst(0.65,0.8)*0.45
        case 7:
            squash();let e=smooth((t-0.55)/0.12)*(1-smooth((t-1.55)/0.25));p.open=1-e*0.85;p.anger=17*e;p.yaw=sin((t-0.55)*18)*0.22*e
        case 8:
            let u=t-0.8;rollEyes=u>0 && u<1.9;p.roll=u>0 && u<1.3 ? GE.inOut(u/1.3)*Double.pi*4 : 0;p.open=0.9
            if t<0.8 {p.y=abs(sin(t*Double.pi*4))*2;cursor.opacity=0.8;cursor.position=SCNVector3(-12,14,model.front+18)}
            if u>1.3 {squash(2.1)};color=lilac;haloStrength=0.5
        case 9:
            p=pose(hero,.working,t,global);color=rgb(0.24,0.62,1);haloStrength=0.60
        case 10,26:
            p=pose(hero,.thinking,t,global);p.gaze=CGSize(width:-2.5,height:-2);color=lilac;haloStrength=0.55
        case 11:
            p.gaze.width=sin(t*2.6)*4;p.yaw=sin(t*2.6)*0.35;p.loading=1;color=rgb(0.44,0.50,0.95);haloStrength=0.55
        case 12:
            let entry=t<0.15 ? 0.2*GE.out(t/0.15) : 0.2*(1-GE.back(gSeg(t,0.15,0.45)))
            p.y+=(entry+abs(sin(t*5.2))*0.07)*24;p.open=1.12;question.opacity=1;color=gold;haloStrength=0.52
        case 13:
            p.roll=0.17*smooth(t/0.25);p.gaze=CGSize(width:2,height:-1);question.opacity=1;color=gold;haloStrength=0.36
        case 14:
            let u=t-0.5;p.x=u>=0 && u<0.28 ? sin(u*Double.pi*4/0.28)*4*(1-u/0.28) : 0;p.open=0.55;p.anger=3;exclamation.opacity=smooth(t/0.15);color=coral;haloStrength=0.45
        case 15:
            let u=t-0.30;p.roll=u>=0 && u<0.95 ? GE.inOut(u/0.95)*Double.pi*2 : 0;p.joy=0.8;particle(.spark,t-0.8);check.opacity=smooth((t-1.2)/0.2);color=mint;haloStrength=0.55
        case 16:
            p.open=0.62;p.gaze.height=1.6;p.roll = -0.05;particle(.sweat,t-0.3,amount:1);exclamation.opacity=0.8;color=gold;haloStrength=0.36
        case 17:
            let sleepTime=t+Double(index)*0.43
            p=pose(hero,.sleeping,sleepTime,global)
            if hero == .ada || hero == .gantt {
                let inhale=(1-cos(sleepTime*1.8))/2
                p.sx=1+inhale*0.022;p.sy=p.sx;p.y = -1+inhale
            }
            p.open=0.04;p.loading=0;particle(.z,t-offset,repeatEvery:2.2,amount:2,strength:0.7);haloStrength=0.05
        case 18:
            p.joy=0.83;p.roll=sin(t*2.5)*0.055;p.y+=burst(0.2,0.6)*3;blush=0.28;particle(.heart,t-0.3,amount:4);color=coral;haloStrength=0.22
        case 19:
            let s=burst(0.3,0.6);p.open=1+s*0.25;p.y+=s*7;p.pitch = -s*0.10;color=lilac;haloStrength=0.20
        case 20:
            squash(0.15);p.roll = -0.14*smooth(t/0.22);p.joy=0.85;blush=0.22;particle(.star,t-0.4);color=gold;haloStrength=0.3
        case 21:
            let k=smooth((t-0.4)/0.16)*(1-smooth((t-1.2)/0.24));p.wink=k;p.roll=k*0.12;p.joy=k*0.25
        case 22:
            let stretch=sin(gSeg(t,0.3,1.3)*Double.pi);if hero != .ada && hero != .gantt {p.sy+=stretch*0.12;p.sx-=stretch*0.06};p.open=1-smooth((t-0.7)/0.15)*(1-smooth((t-1.9)/0.5));particle(.z,t-0.7,amount:2,strength:0.6)
        case 23:
            let u=(t+offset).truncatingRemainder(dividingBy:2.2);p.y+=pow(sin(gSeg(u,0.35,0.95)*Double.pi),2)*5;p.joy=0.80;blush=0.18
        case 24,25:
            let level=(0.5+0.5*sin(t*9+offset))*0.45;p.open=1.06+level*0.15;p.roll = -0.07*smooth(t/0.18);p.pitch=sin(t*3.5)*0.025;p.gaze.height = -0.7
            if hero != .ada && hero != .gantt {p.sy+=level*0.025}
            if id==24 {showHand=smooth((t-0.2)/0.2)*0.5;handWave(t*0.2,showHand)}
            color=rgb(0.40,0.75,0.80);haloStrength=id==24 ? 0.45 : 0.17
        case 27:
            p=pose(hero,.speaking,t,global);p.sy+=sin(t*Double.pi*7)*0.012;showHand=(0.3+sin(t*2)*0.10)*smooth(t/0.25);handWave(t*0.15,showHand);color=rgb(0.4,0.75,0.8);haloStrength=0.30
        case 28:
            if t<0.55 {p.open=1.12;p.roll = -0.07;handWave(t*0.2,0.5*(1-smooth((t-0.4)/0.15)))}
            else {let u=t-0.55;p=pose(hero,.understood,u,global);p.joy=burst(0.55,1.0)*0.65}
            color=mint;haloStrength=0.24
        case 29:
            let fade=smooth(t/0.3)*(1-smooth((t-duration+0.5)/0.5)),beat=t*Double.pi*2*112/60
            p.y+=abs(sin(beat))*4*fade;p.roll=sin(beat/2+offset)*0.11*fade;p.yaw=sin(beat/2+offset)*0.22*fade;p.joy=0.6*fade
            if hero != .ada && hero != .gantt {p.sx+=sin(beat)*0.03*fade;p.sy-=sin(beat)*0.04*fade}
            p.fold=0.3+sin(beat)*0.15;color=lilac;haloStrength=0.24
        case 30:
            let x=sin(t*2.1)*30,y=22+sin(t*1.4)*10;file.opacity=1;file.position=SCNVector3(x,y,model.front+14);p.x=x*0.20;p.gaze=CGSize(width:x*0.13,height:-y*0.05);p.yaw=x*0.006
        case 31:
            let k=GE.back(gSeg(t,0.3,0.7));slot.opacity=1;slot.scale.y=CGFloat(1+max(0,k)*10);p.fold=max(0,k)*0.9;p.open=0.9;file.opacity=smooth((t-1.4)/0.3);file.position=SCNVector3(0,32,model.front+10);color=mint;haloStrength=0.23
        case 32:
            let u=gSeg(t,0.9,1.2),k=GE.inOut(u);slot.opacity=1-smooth((t-1.2)/0.12);slot.scale.y=10
            file.opacity=1-smooth((t-1.11)/0.12);file.scale=SCNVector3(1-k*0.8,1-k*0.8,1);file.position=SCNVector3(18*(1-k),gLerp(33,-14,k),model.front+11)
            p.fold=1-smooth((t-1.2)/0.2);p.joy=smooth((t-1.2)/0.2)*0.5;squash(1.2);color=mint;haloStrength=0.3
        case 33:
            let chew=sin(t*Double.pi*2/0.28)*0.045*smooth(t/0.15)*(1-smooth((t-2.3)/0.5))
            if hero != .ada && hero != .gantt {p.sy+=chew;p.sx-=chew*0.6};p.joy=0.5;p.fold=0.1+abs(chew)*2;p.loading=0.65;color=lilac;haloStrength=0.28
        case 34:
            let u=GE.inOut(gSeg(t,0.6,3.3)),shrink=GE.inOut(gSeg(t,0.1,0.6));customScale=gLerp(1,0.25,shrink);p.x=gLerp(0,-38+u*76,shrink);p.y=gLerp(0,-43,shrink);p.gaze.width=3;p.loading=0
            bar.opacity=shrink;fill.opacity=shrink;fill.scale.x=CGFloat(max(0.001,u));fill.position.x=CGFloat(-38+38*u);color=mint;haloStrength=0.23
        case 35:
            p.y+=burst(0.2,0.4)*6;p.joy=0.85;check.opacity=GE.back(gSeg(t,0.2,0.45));particle(.spark,t-0.4,amount:3);color=mint;haloStrength=0.55
        case 36:
            let grow=GE.back(gSeg(t,0.2,0.7));customScale=gLerp(0.25,1,grow);p.x=38*(1-GE.inOut(gSeg(t,0.2,0.7)));p.y = -43*(1-GE.inOut(gSeg(t,0.2,0.7)));p.joy=0.5;check.opacity=smooth((t-0.7)/0.2);color=mint;haloStrength=0.25
        case 37:
            let f=sin(t*3)*0.13;p.roll=f;p.yaw=sin(t*3)*0.20;model.accessory.eulerAngles.z=CGFloat(sin(t*3-0.75)*0.12-f);p.fold=0.4+sin(t*3-0.4)*0.2
        case 38:
            let down=1-GE.inOut(gSeg(t,0.5,0.68)),up=GE.back(gSeg(t,0.7,1.05)),k=t<0.7 ? down : up
            model.accessory.opacity=max(0,min(1,k));model.accessory.scale=SCNVector3(max(0.01,k),max(0.01,k),1);squash(1.05);p.joy=burst(1.05,1)*0.5
            // A personalization of the existing identifying accessory, not a role swap.
            let accent=t>=0.7 ? lilac : mint
            if hero == .sig {model.accessory.childNodes.first?.geometry?.firstMaterial?.diffuse.contents=accent}
        case 39:
            let out=GE.inOut(gSeg(t,0.4,0.85)),back=GE.inOut(gSeg(t,2.5,2.95)),k=out-back;p.x=k*28;p.y = -k*24;p.roll=sin(t*2)*k*0.07;p.gaze.width = -k*2
        case 40:
            let back=GE.inOut(gSeg(t,0.4,0.85)),returnHome=GE.inOut(gSeg(t,2.5,2.95)),k=1-back+returnHome;p.x=k*28;p.y = -k*24;exclamation.opacity=back-returnHome;color=gold;haloStrength=0.40
        case 41:
            if t<1 {showHand=GE.out(gSeg(t,0.25,0.5));handWave(t,showHand);p.joy=0.7}
            else if t<1.15 {showHand=1-GE.inOut((t-1)/0.15);handWave(t,showHand);p.joy=0.7*showHand}
            else if t<2.4 {p=pose(hero,.thinking,t-1.15,global);color=lilac;haloStrength=0.4}
        case 42:
            let hide=1-GE.inOut(gSeg(t,0.6,0.69)),pop=GE.back(gSeg(t,0.7,0.98));p.loading=t<0.7 ? hide : 0;question.opacity=t>=0.7 ? max(0,min(1,pop)) : 0;question.scale=SCNVector3(max(0.01,pop),max(0.01,pop),1);color=gold;haloStrength=0.3
        case 43:
            let k=smooth((t-0.25)/0.2)*(1-smooth((t-1.55)/0.15));p.joy=0.8*k;p.y+=burst(0,0.44)*2;handWave(max(0,t-0.45),k)
        case 44:
            let k=smooth((t-0.4)/0.1)*(1-smooth((t-0.86)/0.12));slot.opacity=k;slot.scale.y=10;file.opacity=1-smooth((t-0.76)/0.10);file.position=SCNVector3(0,gLerp(30,-14,gSeg(t,0.4,0.86)),model.front+10)
            squash(0.86);p.fold=k;p.joy=smooth((t-0.86)/0.2)*0.65
        case 45:
            let k=1-GE.inOut(gSeg(t,0.5,0.76));p.open=1+k*0.12;p.roll = -0.06*k;p.gaze.height = -k*0.8;haloStrength=0.05+0.15*k
        case 47:p=pose(hero,.waking,t,global);p.loading=0
        case 48:p=pose(hero,.stroll,t,global);p.loading=0
        case 49:p=pose(hero,.understood,t,global);p.loading=0
        default:break
        }
        // Complete each clip with an actual neutral state and no stale activity marker.
        let leave=id==1 ? 0 : smooth((t-duration+0.26)/0.26)
        p=p.mix(pose(hero,.idle,t,global),leave)
        if hero == .ada || hero == .gantt {let equal=sqrt(max(0.01,p.sx*p.sy));p.sx=equal;p.sy=equal}
        model.head.scale=SCNVector3(p.sx*customScale,p.sy*customScale,customScale)
        model.head.position=SCNVector3(p.x,p.y,0);model.head.opacity=p.opacity
        model.head.eulerAngles=SCNVector3(p.pitch,p.yaw,p.roll)
        model.updateEyes(open:p.open,joy:p.joy,gaze:p.gaze,wink:p.wink,anger:p.anger)
        if rollEyes {
            for (i,eye) in model.eyes.enumerated() {
                let path=Path {v in
                    for n in 0...40 {let a=Double(n)*Double.pi*4/40,r=Double(n)/40*4,point=CGPoint(x:48+cos(a)*r,y:48+sin(a)*r);if n==0 {v.move(to:point)}else{v.addLine(to:point)}}
                }
                let s=stroke(path,color:hero == .sig ? cream : ink,width:hero == .ada ? 1.8 : 1.2,depth:0.7)
                eye.geometry=nil;eye.childNodes.forEach{$0.removeFromParentNode()};eye.addChildNode(s);eye.position.x=CGFloat(i==0 ? -14 : 14);eye.pivot=SCNMatrix4Identity
            }
        } else {model.eyes.forEach{$0.childNodes.forEach{$0.removeFromParentNode()}}}
        model.marker?.opacity=p.loading
        model.marker?.eulerAngles.z=CGFloat(t*2.8)
        model.marker?.scale=SCNVector3(0.19,0.19,0.19)
        if id != 1 && id != 24 && id != 27 && id != 28 && id != 41 && id != 43 {
            if hero == .toni {model.paper?.eulerAngles=SCNVector3(0.08+p.fold*0.12,0,-0.1-p.fold*0.38+sin(t*3)*p.fold*0.10)}
        }
        if hero == .gantt {model.paper?.opacity=p.fold;model.paper?.eulerAngles.y=CGFloat(p.fold*0.7)}
        cheeks.forEach{$0.opacity=blush*(1-leave)}
        halo.geometry?.firstMaterial?.multiply.contents=color;halo.opacity=haloStrength*(1-leave)+0.05*leave
        if leave>0 {hands.forEach{$0.opacity*=1-leave};[question,exclamation,check,slot,file,bar,fill].forEach{$0.opacity*=1-leave}}
    }
}

final class MotionLibrary {
    let renderer:SCNRenderer,canvas=ConceptCanvas(1280,1040)
    let actors:[MotionActor]
    let scene=SCNScene()
    init() {
        scene.background.contents=rgb(0.035,0.039,0.047)
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=260;ambient.light?.color=rgb(1,0.99,0.97);scene.rootNode.addChildNode(ambient)
        for (x,y,z,intensity,color) in [(-500.0,700.0,650.0,650.0,rgb(1,0.985,0.95)),(400,-80,700,190,rgb(0.93,0.96,1))] {
            let n=SCNNode();n.light=SCNLight();n.light?.type = .directional;n.light?.intensity=CGFloat(intensity);n.light?.color=color;n.position=SCNVector3(x,y,z);n.look(at:SCNVector3(0,0,0));scene.rootNode.addChildNode(n)
        }
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.orthographicScale=175;camera.camera?.zNear=0.1;camera.camera?.zFar=2000;camera.camera?.wantsHDR=false;camera.camera?.wantsExposureAdaptation=false;camera.position=SCNVector3(0,0,850);scene.rootNode.addChildNode(camera)
        actors=Hero.allCases.enumerated().map{MotionActor($0.element,$0.offset)}
        for (i,a) in actors.enumerated() {
            a.model.root.position=SCNVector3(Double(i%3-1)*154,i<3 ? 85 : -85,0)
            let s=52/a.bounds.height;a.model.root.scale=SCNVector3(s,s,s);scene.rootNode.addChildNode(a.model.root)
        }
        renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera;renderer.autoenablesDefaultLighting=false
    }
    func draw(_ clip:MotionClip,_ time:Double) {
        let stage=clip.stages.last(where:{$0.start<=time}) ?? clip.stages[0],t=time-stage.start
        SCNTransaction.begin();SCNTransaction.disableActions=true
        for a in actors {a.update(id:stage.id,t:t,duration:stage.duration,global:time)}
        SCNTransaction.commit()
        let shot=renderer.snapshot(atTime:time,with:CGSize(width:1280,height:860),antialiasingMode:.multisampling4X)
        canvas.draw {
            shot.draw(in:NSRect(x:0,y:44,width:640,height:430))
            GreetingStudy.text("SIEGHART / MOVIMENTOS",x:24,y:489,size:18,weight:.semibold,color:cream)
            GreetingStudy.text(stage.title,x:24,y:464,size:14,weight:.medium,color:mint)
            GreetingStudy.text("\(clip.stages.firstIndex(where:{$0.id==stage.id})!+1) / \(clip.stages.count)",x:575,y:467,size:11,weight:.regular,color:rgb(0.6,0.62,0.62))
            for (i,h) in Hero.allCases.enumerated() {
                let x=Double(320+(i%3-1)*189),y=i<3 ? 270.0 : 62.0
                ConceptCanvas.centered(h.name,x:x,y:y,size:15,weight:.semibold)
                ConceptCanvas.centered(roles[i],x:x,y:y-17,size:9,color:rgb(0.62,0.65,0.64))
            }
            GreetingStudy.text("Sig é o principal fixo · os cinco especialistas mantêm suas identidades",x:24,y:13,size:9,weight:.regular,color:rgb(0.60,0.63,0.61))
        }
    }
}
