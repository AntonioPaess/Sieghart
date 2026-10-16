import AppKit
import SceneKit
import SwiftUI

enum CompanionRigState:Int,CaseIterable {
    case hello,idle,look,stroll,preparing,listening,thinking,working,speaking,understood,happy,celebrating,annoyed,startled,failure,sleeping,waking
    var title:String {["ALÔ / PRIMEIRA ABERTURA","REPOUSO","OLHAR","PASSEAR","PREPARANDO","ESCUTANDO","LOADING / PENSANDO","ATIVIDADE PRÓPRIA","FALANDO","ENTENDI","CONTENTE","COMEMORANDO","IRRITADO","SUSTO","ALGO DEU ERRADO","DORMINDO","DESPERTANDO"][rawValue]}
    var duration:Double {[4,2,2,2,2,2,3,4,2,2,2,3,2,1.5,2,3,2.5][rawValue]}
    // Waking is handled explicitly: all 17 existing/general states are visible.
    var seconds:Double {self == .waking ? 2.5 : duration}
    static var length:Double {allCases.reduce(0){$0+$1.seconds}}
    static func at(_ time:Double)->(CompanionRigState,Double) {
        var t=max(0,time).truncatingRemainder(dividingBy:length)
        for state in allCases {if t<state.seconds {return(state,t)};t-=state.seconds}
        return(.hello,0)
    }
    var start:Double {Self.allCases.prefix(rawValue).reduce(0){$0+$1.seconds}}
}
func rigSmooth(_ value:Double)->Double {let x=min(1,max(0,value));return x*x*(3-2*x)}

// A top intake, then two soft acknowledgement pulses. The receipt has no
// progress bar or spinning body; rigid characters preserve their silhouette.
struct CompanionFileIntake: Sendable {
    var scaleX = 1.0, scaleY = 1.0, pitch = 0.0, eyeOpen = 1.0, joy = 0.0
    var aperture = 0.0, suction = 0.0, fileOpacity = 0.0, fileScaleX = 1.0, fileScaleY = 1.0
}
func rigFileIntake(time t: Double) -> CompanionFileIntake {
    var p = CompanionFileIntake()
    p.suction = rigSmooth((t - 0.08) / 0.30)
    p.aperture = 1 - rigSmooth((t - 0.38) / 0.12)
    p.fileOpacity = 1 - rigSmooth((t - 0.30) / 0.09)
    p.fileScaleX = 1 - p.suction * 0.75; p.fileScaleY = 1 - p.suction * 0.2
    if t < 0.08 { let k=rigSmooth(t/0.08);p.scaleX=1+k*0.045;p.scaleY=1-k*0.06 }
    else if t < 0.38 { p.scaleX=rigGLerp(1.045,0.975,p.suction);p.scaleY=rigGLerp(0.94,1.045,p.suction) }
    else if t < 0.49 { let k=rigSmooth((t-0.38)/0.11);p.scaleX=rigGLerp(0.975,1.075,k);p.scaleY=rigGLerp(1.045,0.90,k) }
    else if t < 0.65 { let k=rigSmooth((t-0.49)/0.16);p.scaleX=rigGLerp(1.075,1,k);p.scaleY=rigGLerp(0.90,1,k) }
    else if t < 0.95 { let pulse=pow(sin((t-0.65)/0.15 * .pi),2)*(1-rigSmooth((t-0.85)/0.10));p.scaleX=1+pulse*0.015;p.scaleY=1-pulse*0.025 }
    p.pitch = -0.035 * (1-rigSmooth((t-0.4)/0.3))
    p.eyeOpen = 1 - sin(rigGSeg(t,0.39,0.66)*Double.pi)*0.45
    p.joy = sin(rigGSeg(t,0.48,1.25)*Double.pi)*0.6
    return p
}
struct CompanionRigPose: Sendable {
    var sx=1.0,sy=1.0,sz=1.0,x=0.0,y=0.0,yaw=0.0,roll=0.0,pitch=0.0,open=1.0,joy=0.0,wink=0.0,anger=0.0,loading=0.0,fold=0.0,opacity=1.0
    var gaze=CGSize.zero
    func mix(_ other:Self,_ p:Double)->Self {
        func m(_ a:Double,_ b:Double)->Double {a+(b-a)*p}
        var result=Self()
        result.sx=m(sx,other.sx);result.sy=m(sy,other.sy);result.sz=m(sz,other.sz);result.x=m(x,other.x);result.y=m(y,other.y)
        result.yaw=m(yaw,other.yaw);result.roll=m(roll,other.roll);result.pitch=m(pitch,other.pitch)
        result.open=m(open,other.open);result.joy=m(joy,other.joy);result.wink=m(wink,other.wink);result.anger=m(anger,other.anger)
        result.loading=m(loading,other.loading);result.fold=m(fold,other.fold);result.opacity=m(opacity,other.opacity)
        result.gaze=CGSize(width:m(gaze.width,other.gaze.width),height:m(gaze.height,other.gaze.height));return result
    }
}

// A shared clock drives six different greetings. Square bodies stay square;
// the expressive gesture belongs to the character's existing accessory.
func rigIdentityHelloPose(_ hero: CompanionAvatar, _ time: Double) -> CompanionRigPose {
    let t = max(0, time)
    let gesture = rigSmooth(t / 0.18) * (1 - rigSmooth((t - 1.55) / 0.5))
    var p = CompanionRigPose(); p.yaw = -0.09
    switch hero {
    case .sig:
        p.joy = gesture * 0.6; p.roll = sin(t * 4) * gesture * 0.025
    case .rita:
        let breathe = sin(min(1, t / 1.8) * .pi) * gesture
        p.sx += breathe * 0.025; p.sy += breathe * 0.045
        p.pitch = breathe * 0.10; p.roll = -breathe * 0.045
        p.y = breathe * 1.4; p.joy = gesture * 0.3
        p.wink = sin(rigGSeg(t, 0.85, 1.4) * .pi) * 0.9
    case .ada:
        let first = sin(rigGSeg(t, 0.12, 0.65) * .pi)
        let second = sin(rigGSeg(t, 0.78, 1.38) * .pi)
        p.y = first * 4 + second * 7
        p.joy = max(first, second) * 0.8
        p.gaze.width = sin(t * 5) * gesture * 0.8
    case .gantt:
        p.pitch = sin(t * 3) * gesture * 0.055
        p.y = sin(t * 3) * gesture * 0.6
        p.joy = gesture * 0.6
    case .elinor:
        p.pitch = gesture * 0.075; p.yaw += sin(t * 3) * gesture * 0.04
        p.wink = sin(rigGSeg(t, 0.3, 1) * .pi) * 0.9
        p.joy = gesture * 0.25
    case .toni:
        p.roll = sin(t * 5) * gesture * 0.055
        p.y = sin(t * 3) * gesture * 0.8
        p.joy = gesture * 0.7
    }
    return p
}

// A short, identity-specific reaction while waiting for a turn. The intro
// schedules one companion at a time; inactive miniatures remain cached.
func rigWaitingPose(_ hero: CompanionAvatar, _ time: Double) -> CompanionRigPose {
    let k = pow(sin(rigGSeg(time, 0, 0.85) * .pi), 2)
    var p = rigIdentityHelloPose(hero, 0)
    p.gaze = CGSize(width: -2.5 * k, height: -0.8 * k)
    switch hero {
    case .sig: p.pitch = k * 0.07; p.open = 1 - k * 0.2
    case .rita: p.roll = -k * 0.07; p.wink = k * 0.45
    case .ada: p.y = pow(sin(time * .pi * 2 / 0.85), 2) * k * 3
    case .gantt: p.pitch = -k * 0.08; p.open = 1 - k * 0.3
    case .elinor: p.yaw += k * 0.10; p.open = 1 - k * 0.4
    case .toni: p.roll = k * 0.055; p.open = 1 - k * 0.35
    }
    return p
}

extension CompanionRigModel {
    func updateWaitingGesture(time: Double) {
        let k = pow(sin(rigGSeg(time, 0, 0.85) * .pi), 2)
        switch hero {
        case .gantt: paper?.opacity = k; paper?.eulerAngles.y = CGFloat(k * 0.45)
        case .elinor: accessory.childNodes.first?.eulerAngles.z = CGFloat(k * 0.10)
        case .toni: paper?.eulerAngles.z = CGFloat(-0.1 - k * (0.25 + sin(time * 12) * 0.08))
        default: break
        }
    }
    func updateIdentityHello(time: Double, strength: Double) {
        let t = max(0, time)
        let gesture = rigSmooth(t / 0.18) * (1 - rigSmooth((t - 1.55) / 0.5)) * strength
        accessory.scale = SCNVector3(1, 1, 1); accessory.opacity = 1
        switch hero {
        case .sig:
            let pulse = 1 + gesture * 0.06
            accessory.scale = SCNVector3(pulse, pulse, 1)
        case .rita:
            // Her integrated pulse brightens during a soft breath and nod.
            accessory.opacity = 1 - gesture * (0.22 + sin(t * 7) * 0.2)
        case .ada:
            // Code brackets answer the two stepped, rigid-body hops.
            accessory.opacity = 1 - gesture * (0.28 + sin(t * 9) * 0.22)
        case .gantt:
            paper?.opacity = gesture
            paper?.eulerAngles.y = CGFloat(gesture * (0.55 + sin(t * 5) * 0.18))
        case .elinor:
            accessory.childNodes.first?.eulerAngles.z = CGFloat(sin(t * 5) * gesture * 0.14)
        case .toni:
            paper?.eulerAngles = SCNVector3(0.08 + gesture * 0.18, 0,
                                           -0.1 - gesture * (0.52 + sin(t * .pi * 6) * 0.22))
            paperRight?.eulerAngles.z = CGFloat(gesture * sin(t * 3) * 0.045)
        }
    }
}

func rigPose(_ hero:CompanionAvatar,_ state:CompanionRigState,_ t:Double,_ global:Double)->CompanionRigPose {
    let index=Double(CompanionAvatar.allCases.firstIndex(of:hero)!)
    var p=CompanionRigPose();let breath=sin(global*1.5+index*0.4)
    p.sx+=breath*0.004;p.sy+=breath*0.012;p.y+=breath*0.55
    p.yaw = -0.09+sin(global*0.8+index)*0.017
    let blink=(global+index*0.17).truncatingRemainder(dividingBy:4.2)
    if blink>3.55 && blink<3.85 {p.open=1-sin((blink-3.55)/0.3*Double.pi)*0.94}
    switch state {
    case .hello:
        let v=max(0,t-index*0.08),spring=1-exp(-5*v)*cos(9*v)
        p.sx=0.40+spring*0.60;p.sy=0.23+spring*0.77;p.y = -34*(1-spring)
        p.opacity=rigSmooth(v/0.3);p.open=rigSmooth(v/0.5)
        let wave=sin(max(0,v-0.7)*6)*exp(-max(0,v-0.7)*1.3)
        p.roll=wave*0.06;p.yaw = -0.09+wave*0.2;p.joy=rigSmooth((v-0.6)/0.6)*0.65*(1-rigSmooth((v-2.5)/1.1))
        p.fold=max(0,sin(min(1,max(0,(v-0.6)/2.5))*Double.pi))
    case .idle:p.gaze.width=sin(t*1.8+index*0.3)*0.7
    case .look:
        p.gaze.width=sin(t*Double.pi)*3.8;p.yaw = -0.09+sin(t*Double.pi)*0.20
    case .stroll:
        p.x=sin(t*Double.pi)*7;p.y+=abs(sin(t*Double.pi*2))*2
        p.roll=sin(t*Double.pi*2)*0.045;p.yaw = -0.09+cos(t*Double.pi)*0.12;p.gaze.width=cos(t*Double.pi)*2
    case .preparing:p.open*=0.85;p.loading=rigSmooth(t/0.25);p.gaze.height = -0.7
    case .listening:
        p.open*=1.06;p.gaze=CGSize(width:sin(t*3)*1.7,height:-0.7)
        p.pitch=sin(t*3.4)*0.03;p.yaw = -0.09+sin(t*2.2)*0.10;p.roll=sin(t*2.1)*0.025;p.fold=0.20+sin(t*2)*0.12
    case .thinking:
        p.loading=1;p.open*=0.8;p.gaze=CGSize(width:sin(t*2.3)*1.7,height:-1.8)
        p.yaw = -0.09+sin(t*2.3)*0.10;p.roll=sin(t*2)*0.018;p.fold=0.15+sin(t*2)*0.08
    case .working:
        p.loading=0.6;p.fold=0.4+sin(t*2)*0.3
        switch hero {
        case .sig:p.gaze.width=sin(t*2)*2.5;p.yaw = -0.09+sin(t*2)*0.15
        case .rita:let b=(1-cos(t*Double.pi/2))/2;p.sx=1+b*0.025;p.sy=0.98+b*0.06;p.y+=b*1.3;p.open=0.72;p.joy=0.12
        case .ada:p.gaze.height=1.2;let hop=pow(sin(min(1,max(0,(t-2.9)/0.8))*Double.pi),2);p.y+=hop*5;p.joy=hop*0.7
        case .gantt:p.gaze.width=sin(t*1.5)*1.3;p.pitch=sin(t*1.5)*0.035
        case .elinor:p.gaze.height=0.7;p.yaw = -0.09+sin(t*1.5)*0.08
        case .toni:p.gaze.width=rigSmooth((t-1.6)/1.5)*2.7;p.gaze.height = -rigSmooth((t-1.6)/1.5)*0.7
        }
    case .speaking:p.sy+=sin(t*10)*0.012;p.roll=sin(t*4.5)*0.025;p.open*=1+sin(t*9.5)*0.04;p.fold=0.3+sin(t*5)*0.18
    case .understood:
        let nod=sin(min(1,t/1.1)*Double.pi);p.pitch=nod*0.1;p.y-=nod*1.5;p.joy=nod*0.50;p.wink=hero == .sig || hero == .toni ? nod*0.85 : 0
    case .happy:p.joy=0.70;p.y+=sin(t*3)*1;p.roll=sin(t*2)*0.025
    case .celebrating:
        let u=min(1,t/1.35),jump=pow(sin(u*Double.pi),2)
        p.y+=jump*(hero == .ada ? 7 : 4);p.sx+=jump*0.025;p.sy-=jump*0.028
        p.roll=hero == .ada ? 0 : sin(u*Double.pi*2)*(1-u)*0.055;p.joy=rigSmooth(t/0.3)*0.8*(1-rigSmooth((t-1.5)/0.5));p.fold=jump
    case .annoyed:
        p.open*=0.66;p.anger=18*rigSmooth(t/0.2);p.x=sin(t*15)*0.8*(1-rigSmooth((t-1.4)/0.6));p.yaw = -0.09+sin(t*9)*0.045;p.fold=0.04
    case .startled:
        let s=sin(min(1,t/1.5)*Double.pi);p.open=1+s*0.22;p.sy+=s*0.045;p.y+=s*2;p.pitch = -s*0.03
    case .failure:p.open*=0.65;p.gaze.height=1.3;p.roll = -0.045*rigSmooth(t/0.3);p.fold=0.1
    case .sleeping:
        let b=(1-cos(t*1.8))/2;p.open=0.045;p.sx=1+b*0.02;p.sy=0.94+b*0.06;p.roll=0.04+sin(t*0.8)*0.015;p.y = -1+b*0.7;p.fold=0.05
    case .waking:
        let stretch=sin(min(1,t/1.4)*Double.pi);p.open=0.06+rigSmooth(t/0.9)*0.94;p.sy=0.96+stretch*0.08;p.y+=stretch*1.5;p.joy=stretch*0.22;p.fold=stretch*0.5
    }
    // Preserve each silhouette and give the common state its own character.
    switch hero {
    case .ada:
        if state == .hello {let v=max(0,t-index*0.08),s=0.23+(1-exp(-5*v)*cos(9*v))*0.77;p.sx=s;p.sy=s}
        else {p.sx=1;p.sy=1;p.roll=0}
    case .gantt:p.sx=p.sy;p.roll*=0.60
    case .rita:p.roll*=1.35;p.yaw*=0.80
    case .elinor:p.yaw*=0.65;p.roll*=0.55
    case .toni:p.roll*=1.15
    case .sig:break
    }
    return p
}

extension CompanionRigModel {
    func prepareMotion() {
        let badge = rigLoadingBadge(hero)
        marker = badge.node; loadingProgress = badge.progress
        badge.node.position = SCNVector3(-36, 29, front + 8); badge.node.opacity = 0
        head.addChildNode(badge.node)
        switch hero {
        case .ada:
            for n in 0..<3 {
                let line=rigShape(Path(roundedRect:CGRect(x:30,y:86+Double(n)*4,width:30-Double(n)*4,height:2),cornerRadius:0.5),color:[rigLilac,rigMint,rigCoral][n],depth:1,bevel:0.2)
                line.position.z=CGFloat(front+2);activity.addChildNode(line)
            }
        case .elinor:
            for n in 0..<3 {
                let bar=rigShape(Path(roundedRect:CGRect(x:29+Double(n)*11,y:93-Double(n)*4,width:6,height:6+Double(n)*4),cornerRadius:1),color:rigGold,depth:2,bevel:0.5)
                bar.position.z=CGFloat(front+3);activity.addChildNode(bar)
            }
        case .gantt:
            for n in 0..<3 {
                let card=rigShape(Path(roundedRect:CGRect(x:24+Double(n)*19,y:88,width:12,height:10),cornerRadius:2),color:[rigLilac,rigCoral,rigMint][n],depth:2,bevel:0.5)
                card.position.z=CGFloat(front+3);activity.addChildNode(card)
            }
        case .toni:
            let plane=rigShape(rigPolygon([(29,85),(52,80),(44,99),(40,90)],radius:0.3),color:rigCream,depth:0.8,bevel:0.1,side:rigCoral)
            plane.position.z=CGFloat(front+5);activity.addChildNode(plane)
        case .sig:
            for _ in 0..<2 {
                let route=rigShape(rigPolygon([(46,82),(49,85),(46,88),(43,85)]),color:rigMint,depth:2,bevel:0.4)
                route.position.z=CGFloat(front+3);activity.addChildNode(route)
            }
        case .rita:
            let ring=rigStroke(rigBodyPath(hero),color:rigMint,width:0.8,depth:0.6);ring.position.z=CGFloat(front-1);ring.scale=SCNVector3(1.07,1.07,1);activity.addChildNode(ring)
        }
        activity.opacity=0
    }
    func updateActivity(time t: Double) {
        for (n,node) in activity.childNodes.enumerated() {
            switch hero {
            case .sig:let v=(t+Double(n)*0.7).truncatingRemainder(dividingBy:1.8)/1.8;node.position.x=CGFloat((n==0 ? -1 : 1)*v*30);node.position.y=CGFloat(sin(v*Double.pi)*6)
            case .rita:let breathe=(1-cos(t*Double.pi/2))/2;node.scale=SCNVector3(1.04+breathe*0.09,1.04+breathe*0.09,1);node.opacity=0.17+breathe*0.20
            case .ada:node.scale.x=CGFloat(rigSmooth((t-Double(n)*0.5)/0.7))
            case .gantt:node.position.x=CGFloat(sin(max(0,t-Double(n)*0.4)*2)*3*(1-rigSmooth((t-2)/1)))
            case .elinor:node.scale.y=CGFloat(0.15+rigSmooth((t-Double(n)*0.3)/0.7)*0.85)
            case .toni:let v=rigSmooth((t-1)/2.6);node.position.x=CGFloat(v*31);node.position.y=CGFloat(sin(v*Double.pi)*12);node.eulerAngles.z=CGFloat(v*0.3);node.opacity=rigSmooth(t/0.3)
            }
        }
    }
}
