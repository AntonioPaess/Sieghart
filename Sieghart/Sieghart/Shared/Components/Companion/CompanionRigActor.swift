@preconcurrency import AppKit
@preconcurrency import SceneKit
import Metal
import SwiftUI

func rigCenteredShape(_ path:Path,_ color:NSColor,_ depth:Double=1)->SCNNode {
    // rigShape() maps the design's 96×96 coordinates to a centered SceneKit node.
    rigShape(path,color:color,depth:depth,bevel:0.3)
}
func rigSmallText(_ value:String,color:NSColor,size:Double)->SCNNode {
    let geometry=SCNText(string:value,extrusionDepth:0.35)
    geometry.font=NSFont.systemFont(ofSize:size,weight:.semibold);geometry.flatness=0.1
    let mat=SCNMaterial();mat.lightingModel = .constant;mat.diffuse.contents=color;geometry.materials=[mat]
    let node=SCNNode(geometry:geometry),bounds=node.boundingBox
    node.pivot=SCNMatrix4MakeTranslation((bounds.min.x+bounds.max.x)/2,(bounds.min.y+bounds.max.y)/2,0)
    return node
}
func rigHeartPath()->Path {
    var p=Path();p.move(to:CGPoint(x:48,y:54))
    p.addCurve(to:CGPoint(x:41,y:44),control1:CGPoint(x:37,y:46),control2:CGPoint(x:38,y:39))
    p.addQuadCurve(to:CGPoint(x:48,y:43),control:CGPoint(x:45,y:40))
    p.addQuadCurve(to:CGPoint(x:55,y:44),control:CGPoint(x:52,y:40))
    p.addCurve(to:CGPoint(x:48,y:54),control1:CGPoint(x:59,y:39),control2:CGPoint(x:59,y:46));p.closeSubpath();return p
}
func rigStarPath()->Path {
    rigPolygon((0..<10).map {i in let a=Double(i)*Double.pi/5-Double.pi/2,r=i%2==0 ? 6.5 : 2.8;return(48+cos(a)*r,48+sin(a)*r)},radius:0.3)
}
enum CompanionParticle {case heart,star,spark,sweat,z}

final class CompanionRigActor {
    let model:CompanionRigModel
    let halo=SCNNode(),hands=[SCNNode(),SCNNode()],slot=SCNNode(),file=SCNNode(),bar=SCNNode(),fill=SCNNode(),cursor=SCNNode()
    let question:SCNNode,exclamation:SCNNode,check:SCNNode
    var particles:[CompanionParticle:[SCNNode]]=[:],cheeks:[SCNNode]=[]
    let bounds:CGRect,index:Int
    init(_ hero:CompanionAvatar,_ index:Int) {
        self.index=index;model=CompanionRigModel(hero);model.prepareMotion();bounds=rigNsPath(rigBodyPath(hero)).bounds
        let hm=SCNMaterial();hm.lightingModel = .constant;hm.diffuse.contents=CompanionGreetingRig.glowTexture();hm.isDoubleSided=true;hm.writesToDepthBuffer=false;hm.readsFromDepthBuffer=false
        let haloDiameter=max(bounds.width,bounds.height)*1.22
        halo.geometry=SCNPlane(width:haloDiameter,height:haloDiameter);halo.geometry?.materials=[hm];halo.position=SCNVector3(bounds.midX,bounds.midY,-32);model.root.addChildNode(halo)
        halo.renderingOrder = -100
        for (i,h) in hands.enumerated() {
            let path:Path=hero == .ada ? Path(roundedRect:CGRect(x:43,y:43,width:10,height:10),cornerRadius:0.6) : hero == .gantt ? Path(roundedRect:CGRect(x:42,y:43,width:12,height:9),cornerRadius:2) : Path(ellipseIn:CGRect(x:42,y:44,width:12,height:8))
            h.geometry=rigCenteredShape(path,hero == .toni || hero == .gantt ? rigCream : hero.color,4).geometry
            h.position=SCNVector3((i==0 ? -1 : 1)*(bounds.width/2+7),-8,model.front+3);h.opacity=0;model.head.addChildNode(h)
        }
        let mouthWidth = min(30, bounds.width * 0.46)
        slot.geometry=rigCenteredShape(Path(roundedRect:CGRect(x:48-mouthWidth/2,y:43,width:mouthWidth,height:10),cornerRadius:5),rigInk,0.8).geometry
        slot.position=SCNVector3(0,bounds.maxY-6,model.front+1.5);slot.opacity=0;model.head.addChildNode(slot)
        file.geometry=rigCenteredShape(Path(roundedRect:CGRect(x:41,y:39,width:14,height:18),cornerRadius:2),rigCream,1.5).geometry
        let corner=rigCenteredShape(rigPolygon([(49,39),(55,39),(55,45)]),rigLilac,0.7);corner.position.z=2;file.addChildNode(corner)
        for y in [-1.0,-5.0] { let line = SCNBox(width:8,height:0.7,length:0.4,chamferRadius:0.3);line.materials=[rigMaterial(rigLilac)];let node=SCNNode(geometry:line);node.position=SCNVector3(0,y,2.2);file.addChildNode(node) }
        file.opacity=0;model.head.addChildNode(file)
        for (node,color) in [(bar,rigRgb(0.20,0.23,0.25)),(fill,rigMint)] {
            let box=SCNBox(width:76,height:2.5,length:0.5,chamferRadius:1.2);box.materials=[rigMaterial(color)];node.geometry=box;node.position=SCNVector3(0,-48,model.front);model.root.addChildNode(node);node.opacity=0
        }
        let pointer=rigPolygon([(48,42),(48,54),(51,50),(55,51)],radius:0.3)
        cursor.geometry=rigCenteredShape(pointer,rigCream,1).geometry;cursor.position.z=CGFloat(model.front+18);cursor.opacity=0;model.root.addChildNode(cursor)
        question=rigSmallText("?",color:rigGold,size:13);exclamation=rigSmallText("!",color:rigCoral,size:13);check=rigSmallText("✓",color:rigMint,size:12)
        for n in [question,exclamation,check] {n.position=SCNVector3(-bounds.width/2-3,bounds.height/2+3,model.front+8);n.opacity=0;model.head.addChildNode(n)}
        for kind in [CompanionParticle.heart,.star,.spark,.sweat,.z] {
            var nodes:[SCNNode]=[]
            for _ in 0..<5 {
                let n:SCNNode
                switch kind {
                case .heart:n=rigCenteredShape(rigHeartPath(),rigCoral,1.2)
                case .star:n=rigCenteredShape(rigStarPath(),rigGold,1)
                case .spark:n=rigCenteredShape(rigPolygon([(48,43),(51,48),(48,53),(45,48)]),rigMint,1)
                case .sweat:n=rigCenteredShape(rigPolygon([(48,42),(44,49),(45,53),(51,53),(52,49)],radius:2),rigRgb(0.5,0.7,0.9),1)
                case .z:n=rigSmallText("z",color:rigLilac,size:9)
                }
                n.opacity=0;model.root.addChildNode(n);nodes.append(n)
            };particles[kind]=nodes
        }
        for x in [-20.0,20.0] {
            let n=rigCenteredShape(Path(ellipseIn:CGRect(x:44,y:46,width:8,height:4)),rigCoral,0.4)
            n.position=SCNVector3(x,-8,model.front+1);n.opacity=0;model.head.addChildNode(n);cheeks.append(n)
        }
    }
    func particle(_ kind:CompanionParticle,_ t:Double,repeatEvery:Double=0,amount:Int=5,strength:Double=1) {
        let local=repeatEvery>0 ? t.truncatingRemainder(dividingBy:repeatEvery) : t
        for (i,n) in particles[kind]!.enumerated() {
            let age=local-Double(i)*0.14,life=1.55+Double(i%2)*0.2,k=rigGSeg(age,0,life)
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
        if model.hero == .elinor { model.accessory.childNodes.first?.eulerAngles.z = 0 }
        model.paperRight?.eulerAngles.z=0
        file.scale=SCNVector3(1,1,1);question.scale=SCNVector3(1,1,1)
        file.eulerAngles = SCNVector3Zero; slot.scale = SCNVector3(1,1,1)
        if model.hero == .sig {model.accessory.childNodes.first?.geometry?.firstMaterial?.diffuse.contents=rigMint}
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
    private(set) var lastPose = CompanionRigPose()
    private var previousID: Int?
    private var spiralEyes: [SCNNode] = []
    func update(id:Int,t:Double,duration:Double,global:Double, continuous: Bool = false,
                gaze: CGSize? = nil, source: CompanionRigPose? = nil, transition: Double = 1, animates: Bool = true) {
        // Reset only on a state transition; idle frames do not touch hidden props.
        if previousID != id { resetExtras(); previousID = id }
        let hero=model.hero,offset=Double(index)*0.11
        // Activities retain the previously approved task-specific geometry.
        if id == 9 && animates { model.updateActivity(time: t.truncatingRemainder(dividingBy: 3.4)) }
        model.activity.opacity=id==9 ? rigSmooth(t/0.25) : 0
        var p=rigPose(hero,.idle,t,global+Double(index)*0.17)
        var color=rigRgb(0.50,0.55,0.55),haloStrength=0.0,blush=0.0
        var customScale=1.0,rollEyes=false,showHand=0.0
        func burst(_ start:Double,_ length:Double=0.7)->Double {sin(rigGSeg(t,start,start+length)*Double.pi)}
        func squash(_ start:Double=0.55) {
            let u=t-start
            var sy=1.0,sx=1.0
            if u>=0 && u<0.07 {sy=rigGLerp(1,0.78,CompanionEase.out(u/0.07));sx=rigGLerp(1,1.16,CompanionEase.out(u/0.07))}
            else if u<0.2 && u>=0.07 {sy=rigGLerp(0.78,1.10,CompanionEase.out((u-0.07)/0.13));sx=rigGLerp(1.16,0.95,CompanionEase.out((u-0.07)/0.13))}
            else if u<0.37 && u>=0.2 {sy=rigGLerp(1.1,1,CompanionEase.inOut((u-0.2)/0.17));sx=rigGLerp(0.95,1,CompanionEase.inOut((u-0.2)/0.17))}
            if hero != .ada && hero != .gantt {p.sy*=sy;p.sx*=sx}
            p.y+=sin(rigGSeg(u,0,0.6)*Double.pi)*3
        }
        switch id {
        case 1:
            let g=rigGreetPose(t,compact:CompanionGreetingLayout())
            customScale=g.hb/58;p.x=(g.x-320)*0.7;p.y=(90-g.y)*0.7;p.opacity=g.hb>0 ? 1 : 0
            p.sx=g.sx;p.sy=g.sy;p.open=g.open;p.joy=g.eye == .happy ? 0.85 : g.eye == .content ? 0.6 : 0
            p.gaze=CGSize(width:g.lookX*4,height:g.lookY*3);showHand=max(g.handL,g.handR)
            handWave(max(0,g.wave),showHand);color=rigRgb(rigGLerp(0.91,0.23,g.haloBlue),rigGLerp(0.76,0.62,g.haloBlue),rigGLerp(0.60,1,g.haloBlue));haloStrength=g.halo*0.85
            particle(.spark,t-0.5,amount:5,strength:0.5)
        case 2:
            // Hover follows the user's real pointer. A simulated cursor belongs
            // only to explicit touch/dizzy demonstrations, never this gaze state.
            if gaze == nil {
                let x=sin(t*2.2)*4,y=sin(t*1.2)*2;p.gaze=CGSize(width:x,height:y);p.yaw=x*0.09;p.pitch = -y*0.025
            }
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
            squash();let e=rigSmooth((t-0.55)/0.12)*(1-rigSmooth((t-1.55)/0.25));p.open=1-e*0.85;p.anger=17*e;p.yaw=sin((t-0.55)*18)*0.22*e
        case 8:
            let u=t-0.8;rollEyes=u>0 && u<1.9;p.roll=u>0 && u<1.3 ? CompanionEase.inOut(u/1.3)*Double.pi*4 : 0;p.open=0.9
            if t<0.8 {p.y=abs(sin(t*Double.pi*4))*2;cursor.opacity=0.8;cursor.position=SCNVector3(-12,14,model.front+18)}
            if u>1.3 {squash(2.1)};color=rigLilac;haloStrength=0.5
        case 9:
            p=rigPose(hero,.working,t,global);color=rigRgb(0.24,0.62,1);haloStrength=0.60
        case 10,26:
            p=rigPose(hero,.thinking,t,global);p.gaze=CGSize(width:-2.5,height:-2);color=rigLilac;haloStrength=0.55
        case 11:
            p.gaze.width=sin(t*2.6)*4;p.yaw=sin(t*2.6)*0.35;p.loading=1;color=rigRgb(0.44,0.50,0.95);haloStrength=0.55
        case 12:
            let entry=t<0.15 ? 0.2*CompanionEase.out(t/0.15) : 0.2*(1-CompanionEase.back(rigGSeg(t,0.15,0.45)))
            p.y+=(entry+abs(sin(t*5.2))*0.07)*24;p.open=1.12;question.opacity=1;color=rigGold;haloStrength=0.52
        case 13:
            p.roll=0.17*rigSmooth(t/0.25);p.gaze=CGSize(width:2,height:-1);question.opacity=1;color=rigGold;haloStrength=0.36
        case 14:
            let u=t-0.5;p.x=u>=0 && u<0.28 ? sin(u*Double.pi*4/0.28)*4*(1-u/0.28) : 0;p.open=0.55;p.anger=3;exclamation.opacity=rigSmooth(t/0.15);color=rigCoral;haloStrength=0.45
        case 15:
            let u=t-0.30;p.roll=u>=0 && u<0.95 ? CompanionEase.inOut(u/0.95)*Double.pi*2 : 0;p.joy=0.8;particle(.spark,t-0.8);check.opacity=rigSmooth((t-1.2)/0.2);color=rigMint;haloStrength=0.55
        case 16:
            p.open=0.62;p.gaze.height=1.6;p.roll = -0.05;particle(.sweat,t-0.3,amount:1);exclamation.opacity=0.8;color=rigGold;haloStrength=0.36
        case 17:
            let sleepTime=t+Double(index)*0.43
            p=rigPose(hero,.sleeping,sleepTime,global)
            if hero == .ada || hero == .gantt {
                let inhale=(1-cos(sleepTime*1.8))/2
                p.sx=1+inhale*0.022;p.sy=p.sx;p.y = -1+inhale
            }
            p.open=0.04;p.loading=0;particle(.z,t-offset,repeatEvery:2.2,amount:2,strength:0.7);haloStrength=0.05
        case 18:
            p.joy=0.83;p.roll=sin(t*2.5)*0.055;p.y+=burst(0.2,0.6)*3;blush=0.28;particle(.heart,t-0.3,amount:4);color=rigCoral;haloStrength=0.22
        case 19:
            let s=burst(0.3,0.6);p.open=1+s*0.25;p.y+=s*7;p.pitch = -s*0.10;color=rigLilac;haloStrength=0.20
        case 20:
            squash(0.15);p.roll = -0.14*rigSmooth(t/0.22);p.joy=0.85;blush=0.22;particle(.star,t-0.4);color=rigGold;haloStrength=0.3
        case 21:
            let k=rigSmooth((t-0.4)/0.16)*(1-rigSmooth((t-1.2)/0.24));p.wink=k;p.roll=k*0.12;p.joy=k*0.25
        case 22:
            let stretch=sin(rigGSeg(t,0.3,1.3)*Double.pi);if hero != .ada && hero != .gantt {p.sy+=stretch*0.12;p.sx-=stretch*0.06};p.open=1-rigSmooth((t-0.7)/0.15)*(1-rigSmooth((t-1.9)/0.5));particle(.z,t-0.7,amount:2,strength:0.6)
        case 23:
            let u=(t+offset).truncatingRemainder(dividingBy:2.2);p.y+=pow(sin(rigGSeg(u,0.35,0.95)*Double.pi),2)*5;p.joy=0.80;blush=0.18
        case 24,25:
            let level=(0.5+0.5*sin(t*9+offset))*0.45;p.open=1.06+level*0.15;p.roll = -0.07*rigSmooth(t/0.18);p.pitch=sin(t*3.5)*0.025;p.gaze.height = -0.7
            if hero != .ada && hero != .gantt {p.sy+=level*0.025}
            if id==24 {showHand=rigSmooth((t-0.2)/0.2)*0.5;handWave(t*0.2,showHand)}
            color=rigRgb(0.40,0.75,0.80);haloStrength=id==24 ? 0.45 : 0.17
        case 27:
            p=rigPose(hero,.speaking,t,global);p.sy+=sin(t*Double.pi*7)*0.012;showHand=(0.3+sin(t*2)*0.10)*rigSmooth(t/0.25);handWave(t*0.15,showHand);color=rigRgb(0.4,0.75,0.8);haloStrength=0.30
        case 28:
            if t<0.55 {p.open=1.12;p.roll = -0.07;handWave(t*0.2,0.5*(1-rigSmooth((t-0.4)/0.15)))}
            else {let u=t-0.55;p=rigPose(hero,.understood,u,global);p.joy=burst(0.55,1.0)*0.65}
            color=rigMint;haloStrength=0.24
        case 29:
            let fade=rigSmooth(t/0.3)*(1-rigSmooth((t-duration+0.5)/0.5)),beat=t*Double.pi*2*112/60
            p.y+=abs(sin(beat))*4*fade;p.roll=sin(beat/2+offset)*0.11*fade;p.yaw=sin(beat/2+offset)*0.22*fade;p.joy=0.6*fade
            if hero != .ada && hero != .gantt {p.sx+=sin(beat)*0.03*fade;p.sy-=sin(beat)*0.04*fade}
            p.fold=0.3+sin(beat)*0.15;color=rigLilac;haloStrength=0.24
        case 30:
            let x=sin(t*2.1)*20;p.gaze=CGSize(width:x*0.13,height:-2);p.yaw=x*0.003
            slot.opacity=rigSmooth(t/0.2);slot.scale.y=0.35;p.loading=0;color=rigMint;haloStrength=0.2
        case 31:
            let k=rigSmooth(t/0.35);slot.opacity=k;slot.scale.y=CGFloat(max(0.01,k*0.65))
            p.open=1-k*0.12;p.gaze.height = -1.2*k;p.pitch = -0.03*k;p.yaw=0;p.loading=0;color=rigMint;haloStrength=0.18*k
        case 32:
            let intake = rigFileIntake(time: t)
            p.sx=intake.scaleX;p.sy=intake.scaleY;p.yaw=0;p.pitch=intake.pitch;p.open=intake.eyeOpen;p.joy=intake.joy;p.gaze.height = -intake.aperture
            slot.opacity=intake.aperture;slot.scale.y=CGFloat(max(0.01,intake.aperture*0.75))
            file.opacity=intake.fileOpacity;file.scale=SCNVector3(intake.fileScaleX,intake.fileScaleY,1)
            file.position=SCNVector3(12*(1-intake.suction),bounds.maxY+rigGLerp(30,-9,intake.suction),model.front+rigGLerp(14,-5,intake.suction))
            file.eulerAngles.z=CGFloat((1-intake.suction)*(-0.14+sin(t*15)*0.03))
            color=rigMint;haloStrength=0.22*(1-rigSmooth((t-0.8)/0.4));p.loading=0
        case 33:
            let chew=sin(t*Double.pi*2/0.28)*0.045*rigSmooth(t/0.15)*(1-rigSmooth((t-2.3)/0.5))
            if hero != .ada && hero != .gantt {p.sy+=chew;p.sx-=chew*0.6};p.joy=0.5;p.fold=0.1+abs(chew)*2;p.loading=0.65;color=rigLilac;haloStrength=0.28
        case 34:
            let u=CompanionEase.inOut(rigGSeg(t,0.6,3.3)),shrink=CompanionEase.inOut(rigGSeg(t,0.1,0.6));customScale=rigGLerp(1,0.25,shrink);p.x=rigGLerp(0,-38+u*76,shrink);p.y=rigGLerp(0,-43,shrink);p.gaze.width=3;p.loading=0
            bar.opacity=shrink;fill.opacity=shrink;fill.scale.x=CGFloat(max(0.001,u));fill.position.x=CGFloat(-38+38*u);color=rigMint;haloStrength=0.23
        case 35:
            p.y+=burst(0.2,0.4)*6;p.joy=0.85;check.opacity=CompanionEase.back(rigGSeg(t,0.2,0.45));particle(.spark,t-0.4,amount:3);color=rigMint;haloStrength=0.55
        case 36:
            let grow=CompanionEase.back(rigGSeg(t,0.2,0.7));customScale=rigGLerp(0.25,1,grow);p.x=38*(1-CompanionEase.inOut(rigGSeg(t,0.2,0.7)));p.y = -43*(1-CompanionEase.inOut(rigGSeg(t,0.2,0.7)));p.joy=0.5;check.opacity=rigSmooth((t-0.7)/0.2);color=rigMint;haloStrength=0.25
        case 37:
            let f=sin(t*3)*0.13;p.roll=f;p.yaw=sin(t*3)*0.20;model.accessory.eulerAngles.z=CGFloat(sin(t*3-0.75)*0.12-f);p.fold=0.4+sin(t*3-0.4)*0.2
        case 38:
            let down=1-CompanionEase.inOut(rigGSeg(t,0.5,0.68)),up=CompanionEase.back(rigGSeg(t,0.7,1.05)),k=t<0.7 ? down : up
            model.accessory.opacity=max(0,min(1,k));model.accessory.scale=SCNVector3(max(0.01,k),max(0.01,k),1);squash(1.05);p.joy=burst(1.05,1)*0.5
            // A personalization of the existing identifying accessory, not a role swap.
            let accent=t>=0.7 ? rigLilac : rigMint
            if hero == .sig {model.accessory.childNodes.first?.geometry?.firstMaterial?.diffuse.contents=accent}
        case 39:
            let out=CompanionEase.inOut(rigGSeg(t,0.4,0.85)),back=CompanionEase.inOut(rigGSeg(t,2.5,2.95)),k=out-back;p.x=k*28;p.y = -k*24;p.roll=sin(t*2)*k*0.07;p.gaze.width = -k*2
        case 40:
            let back=CompanionEase.inOut(rigGSeg(t,0.4,0.85)),returnHome=CompanionEase.inOut(rigGSeg(t,2.5,2.95)),k=1-back+returnHome;p.x=k*28;p.y = -k*24;exclamation.opacity=back-returnHome;color=rigGold;haloStrength=0.40
        case 41:
            if t<1 {showHand=CompanionEase.out(rigGSeg(t,0.25,0.5));handWave(t,showHand);p.joy=0.7}
            else if t<1.15 {showHand=1-CompanionEase.inOut((t-1)/0.15);handWave(t,showHand);p.joy=0.7*showHand}
            else if t<2.4 {p=rigPose(hero,.thinking,t-1.15,global);color=rigLilac;haloStrength=0.4}
        case 42:
            let hide=1-CompanionEase.inOut(rigGSeg(t,0.6,0.69)),pop=CompanionEase.back(rigGSeg(t,0.7,0.98));p.loading=t<0.7 ? hide : 0;question.opacity=t>=0.7 ? max(0,min(1,pop)) : 0;question.scale=SCNVector3(max(0.01,pop),max(0.01,pop),1);color=rigGold;haloStrength=0.3
        case 43:
            p = rigIdentityHelloPose(hero, t)
            model.updateIdentityHello(time: t, strength: animates ? 1 : 0)
            if hero == .sig { handWave(max(0, t - 0.45), rigSmooth(t / 0.2) * (1 - rigSmooth((t - 1.55) / 0.5))) }
        case 44:
            let k=rigSmooth((t-0.4)/0.1)*(1-rigSmooth((t-0.86)/0.12));slot.opacity=k;slot.scale.y=CGFloat(max(0.01,k*0.7));file.opacity=1-rigSmooth((t-0.76)/0.10);file.position=SCNVector3(0,bounds.maxY+rigGLerp(30,-9,rigGSeg(t,0.4,0.86)),model.front+rigGLerp(12,-5,rigGSeg(t,0.4,0.86)))
            squash(0.86);p.fold=k;p.joy=rigSmooth((t-0.86)/0.2)*0.65
        case 45:
            let k=1-CompanionEase.inOut(rigGSeg(t,0.5,0.76));p.open=1+k*0.12;p.roll = -0.06*k;p.gaze.height = -k*0.8;haloStrength=0.05+0.15*k
        case 47:p=rigPose(hero,.waking,t,global);p.loading=0
        case 48:p=rigPose(hero,.stroll,t,global);p.loading=0
        case 49:p=rigPose(hero,.understood,t,global);p.loading=0
        default:break
        }
        // Complete each clip with an actual neutral state and no stale activity marker.
        let leave=continuous || id==1 || id==31 ? 0 : rigSmooth((t-duration+0.26)/0.26)
        p=p.mix(rigPose(hero,.idle,t,global),leave)
        if hero == .ada || hero == .gantt {let equal=sqrt(max(0.01,p.sx*p.sy));p.sx=equal;p.sy=equal}
        if let gaze { p.gaze = gaze; p.yaw += Double(gaze.width) * 0.045; p.pitch -= Double(gaze.height) * 0.025 }
        if !animates {
            p = CompanionRigPose(); p.open = id == 17 ? 0.045 : 1
            p.loading = [9,10,11,26,33].contains(id) ? 1 : 0
            customScale = 1; haloStrength = 0.08; blush = 0; rollEyes = false
            hands.forEach { $0.opacity = 0 }; particles.values.flatMap { $0 }.forEach { $0.opacity = 0 }
            [slot,file,bar,fill,cursor,question,exclamation,check].forEach { $0.opacity = 0 }
            model.activity.opacity = 0
        }
        p.sx *= customScale; p.sy *= customScale; p.sz = customScale
        if let source { p = source.mix(p, transition) }
        lastPose = p
        model.head.scale=SCNVector3(p.sx,p.sy,p.sz)
        model.head.position=SCNVector3(p.x,p.y,0);model.head.opacity=p.opacity
        model.head.eulerAngles=SCNVector3(p.pitch,p.yaw,p.roll)
        model.updateEyes(open:p.open,joy:p.joy,gaze:p.gaze,wink:p.wink,anger:p.anger)
        if rollEyes && spiralEyes.isEmpty {
            let path=Path {v in
                for n in 0...40 {let a=Double(n)*Double.pi*4/40,r=Double(n)/40*4,point=CGPoint(x:48+cos(a)*r,y:48+sin(a)*r);if n==0 {v.move(to:point)}else{v.addLine(to:point)}}
            }
            for eye in model.eyes {
                let spiral=rigStroke(path,color:hero == .sig ? rigCream : rigInk,width:hero == .ada ? 1.8 : 1.2,depth:0.7)
                spiral.position.z=1; eye.addChildNode(spiral); spiralEyes.append(spiral)
            }
        }
        for (index, eye) in model.eyes.enumerated() {
            if rollEyes { eye.geometry = nil; eye.scale.y = 1 }
            if index < spiralEyes.count {
                spiralEyes[index].isHidden = !rollEyes
                spiralEyes[index].eulerAngles.z = CGFloat(t * 2)
            }
        }
        model.marker?.opacity=p.loading
        model.marker?.eulerAngles.z = 0
        if p.loading > 0 { model.loadingProgress?.setValue(Float((animates ? t : 0).truncatingRemainder(dividingBy: 2) / 2), forKey: "phase") }
        if id != 1 && id != 24 && id != 27 && id != 28 && id != 41 && id != 43 {
            if hero == .toni {model.paper?.eulerAngles=SCNVector3(0.08+p.fold*0.12,0,-0.1-p.fold*0.38+sin(t*3)*p.fold*0.10)}
        }
        if hero == .gantt && id != 43 {model.paper?.opacity=p.fold;model.paper?.eulerAngles.y=CGFloat(p.fold*0.7)}
        cheeks.forEach{$0.opacity=blush*(1-leave)}
        halo.geometry?.firstMaterial?.multiply.contents=color;halo.opacity=haloStrength*(1-leave)+0.05*leave
        if leave>0 {hands.forEach{$0.opacity*=1-leave};[question,exclamation,check,slot,file,bar,fill].forEach{$0.opacity*=1-leave}}
    }
}
