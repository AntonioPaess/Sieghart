import AppKit
import SceneKit
import SwiftUI

enum State:Int,CaseIterable {
    case hello,idle,look,stroll,preparing,listening,thinking,working,speaking,understood,happy,celebrating,annoyed,startled,failure,sleeping,waking
    var title:String {["ALÔ / PRIMEIRA ABERTURA","REPOUSO","OLHAR","PASSEAR","PREPARANDO","ESCUTANDO","LOADING / PENSANDO","ATIVIDADE PRÓPRIA","FALANDO","ENTENDI","CONTENTE","COMEMORANDO","IRRITADO","SUSTO","ALGO DEU ERRADO","DORMINDO","DESPERTANDO"][rawValue]}
    var duration:Double {[4,2,2,2,2,2,3,4,2,2,2,3,2,1.5,2,3,2.5][rawValue]}
    // Waking is handled explicitly: all 17 existing/general states are visible.
    var seconds:Double {self == .waking ? 2.5 : duration}
    static var length:Double {allCases.reduce(0){$0+$1.seconds}}
    static func at(_ time:Double)->(State,Double) {
        var t=max(0,time).truncatingRemainder(dividingBy:length)
        for state in allCases {if t<state.seconds {return(state,t)};t-=state.seconds}
        return(.hello,0)
    }
    var start:Double {Self.allCases.prefix(rawValue).reduce(0){$0+$1.seconds}}
}
func smooth(_ value:Double)->Double {let x=min(1,max(0,value));return x*x*(3-2*x)}
struct Pose {
    var sx=1.0,sy=1.0,x=0.0,y=0.0,yaw=0.0,roll=0.0,pitch=0.0,open=1.0,joy=0.0,wink=0.0,anger=0.0,loading=0.0,fold=0.0,opacity=1.0
    var gaze=CGSize.zero
    func mix(_ other:Self,_ p:Double)->Self {
        func m(_ a:Double,_ b:Double)->Double {a+(b-a)*p}
        var result=Self()
        result.sx=m(sx,other.sx);result.sy=m(sy,other.sy);result.x=m(x,other.x);result.y=m(y,other.y)
        result.yaw=m(yaw,other.yaw);result.roll=m(roll,other.roll);result.pitch=m(pitch,other.pitch)
        result.open=m(open,other.open);result.joy=m(joy,other.joy);result.wink=m(wink,other.wink);result.anger=m(anger,other.anger)
        result.loading=m(loading,other.loading);result.fold=m(fold,other.fold);result.opacity=m(opacity,other.opacity)
        result.gaze=CGSize(width:m(gaze.width,other.gaze.width),height:m(gaze.height,other.gaze.height));return result
    }
}
func pose(_ hero:Hero,_ state:State,_ t:Double,_ global:Double)->Pose {
    let index=Double(Hero.allCases.firstIndex(of:hero)!)
    var p=Pose();let breath=sin(global*1.5+index*0.4)
    p.sx+=breath*0.004;p.sy+=breath*0.012;p.y+=breath*0.55
    p.yaw = -0.09+sin(global*0.8+index)*0.017
    let blink=(global+index*0.17).truncatingRemainder(dividingBy:4.2)
    if blink>3.55 && blink<3.85 {p.open=1-sin((blink-3.55)/0.3*Double.pi)*0.94}
    switch state {
    case .hello:
        let v=max(0,t-index*0.08),spring=1-exp(-5*v)*cos(9*v)
        p.sx=0.40+spring*0.60;p.sy=0.23+spring*0.77;p.y = -34*(1-spring)
        p.opacity=smooth(v/0.3);p.open=smooth(v/0.5)
        let wave=sin(max(0,v-0.7)*6)*exp(-max(0,v-0.7)*1.3)
        p.roll=wave*0.06;p.yaw = -0.09+wave*0.2;p.joy=smooth((v-0.6)/0.6)*0.65*(1-smooth((v-2.5)/1.1))
        p.fold=max(0,sin(min(1,max(0,(v-0.6)/2.5))*Double.pi))
    case .idle:p.gaze.width=sin(t*1.8+index*0.3)*0.7
    case .look:
        p.gaze.width=sin(t*Double.pi)*3.8;p.yaw = -0.09+sin(t*Double.pi)*0.20
    case .stroll:
        p.x=sin(t*Double.pi)*7;p.y+=abs(sin(t*Double.pi*2))*2
        p.roll=sin(t*Double.pi*2)*0.045;p.yaw = -0.09+cos(t*Double.pi)*0.12;p.gaze.width=cos(t*Double.pi)*2
    case .preparing:p.open*=0.85;p.loading=smooth(t/0.25);p.gaze.height = -0.7
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
        case .toni:p.gaze.width=smooth((t-1.6)/1.5)*2.7;p.gaze.height = -smooth((t-1.6)/1.5)*0.7
        }
    case .speaking:p.sy+=sin(t*10)*0.012;p.roll=sin(t*4.5)*0.025;p.open*=1+sin(t*9.5)*0.04;p.fold=0.3+sin(t*5)*0.18
    case .understood:
        let nod=sin(min(1,t/1.1)*Double.pi);p.pitch=nod*0.1;p.y-=nod*1.5;p.joy=nod*0.50;p.wink=hero == .sig || hero == .toni ? nod*0.85 : 0
    case .happy:p.joy=0.70;p.y+=sin(t*3)*1;p.roll=sin(t*2)*0.025
    case .celebrating:
        let u=min(1,t/1.35),jump=pow(sin(u*Double.pi),2)
        p.y+=jump*(hero == .ada ? 7 : 4);p.sx+=jump*0.025;p.sy-=jump*0.028
        p.roll=hero == .ada ? 0 : sin(u*Double.pi*2)*(1-u)*0.055;p.joy=smooth(t/0.3)*0.8*(1-smooth((t-1.5)/0.5));p.fold=jump
    case .annoyed:
        p.open*=0.66;p.anger=18*smooth(t/0.2);p.x=sin(t*15)*0.8*(1-smooth((t-1.4)/0.6));p.yaw = -0.09+sin(t*9)*0.045;p.fold=0.04
    case .startled:
        let s=sin(min(1,t/1.5)*Double.pi);p.open=1+s*0.22;p.sy+=s*0.045;p.y+=s*2;p.pitch = -s*0.03
    case .failure:p.open*=0.65;p.gaze.height=1.3;p.roll = -0.045*smooth(t/0.3);p.fold=0.1
    case .sleeping:
        let b=(1-cos(t*1.8))/2;p.open=0.045;p.sx=1+b*0.02;p.sy=0.94+b*0.06;p.roll=0.04+sin(t*0.8)*0.015;p.y = -1+b*0.7;p.fold=0.05
    case .waking:
        let stretch=sin(min(1,t/1.4)*Double.pi);p.open=0.06+smooth(t/0.9)*0.94;p.sy=0.96+stretch*0.08;p.y+=stretch*1.5;p.joy=stretch*0.22;p.fold=stretch*0.5
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

extension CharacterModel {
    func prepareMotion() {
        let small=shape(bodyPath(hero),color:hero.color,depth:3,bevel:0.5)
        small.scale=SCNVector3(0.19,0.19,0.19);small.position=SCNVector3(-36,29,front+8);small.opacity=0
        head.addChildNode(small);marker=small
        switch hero {
        case .ada:
            for n in 0..<3 {
                let line=shape(Path(roundedRect:CGRect(x:30,y:86+Double(n)*4,width:30-Double(n)*4,height:2),cornerRadius:0.5),color:[lilac,mint,coral][n],depth:1,bevel:0.2)
                line.position.z=CGFloat(front+2);activity.addChildNode(line)
            }
        case .elinor:
            for n in 0..<3 {
                let bar=shape(Path(roundedRect:CGRect(x:29+Double(n)*11,y:93-Double(n)*4,width:6,height:6+Double(n)*4),cornerRadius:1),color:gold,depth:2,bevel:0.5)
                bar.position.z=CGFloat(front+3);activity.addChildNode(bar)
            }
        case .gantt:
            for n in 0..<3 {
                let card=shape(Path(roundedRect:CGRect(x:24+Double(n)*19,y:88,width:12,height:10),cornerRadius:2),color:[lilac,coral,mint][n],depth:2,bevel:0.5)
                card.position.z=CGFloat(front+3);activity.addChildNode(card)
            }
        case .toni:
            let plane=shape(polygon([(29,85),(52,80),(44,99),(40,90)],radius:0.3),color:cream,depth:0.8,bevel:0.1,side:coral)
            plane.position.z=CGFloat(front+5);activity.addChildNode(plane)
        case .sig:
            for _ in 0..<2 {
                let route=shape(polygon([(46,82),(49,85),(46,88),(43,85)]),color:mint,depth:2,bevel:0.4)
                route.position.z=CGFloat(front+3);activity.addChildNode(route)
            }
        case .rita:
            let ring=stroke(bodyPath(hero),color:mint,width:0.8,depth:0.6);ring.position.z=CGFloat(front-1);ring.scale=SCNVector3(1.07,1.07,1);activity.addChildNode(ring)
        }
        activity.opacity=0
    }
    func animate(_ global:Double) {
        let (state,t)=State.at(global)
        let current=pose(hero,state,t,global)
        let next=State.allCases[(state.rawValue+1)%State.allCases.count]
        let blend=state == .hello || state == .waking ? 0 : smooth((t-state.seconds+0.24)/0.24)
        let p=current.mix(pose(hero,next,0,global),blend)
        head.scale=SCNVector3(p.sx,p.sy,1)
        head.position=SCNVector3(p.x,p.y,0);head.opacity=p.opacity
        head.eulerAngles=SCNVector3(p.pitch,p.yaw,p.roll)
        updateEyes(open:p.open,joy:p.joy,gaze:p.gaze,wink:p.wink,anger:p.anger)
        marker?.opacity=p.loading
        marker?.eulerAngles.y=CGFloat(sin(global*3)*0.25)
        marker?.scale=SCNVector3(0.19*(1+sin(global*4)*0.045),0.19*(1+sin(global*4)*0.045),0.19)
        for child in accessory.childNodes {child.geometry?.materials.forEach { $0.emission.contents = NSColor(white:p.loading*(0.035+max(0,sin(global*4))*0.025),alpha:1)}}
        if hero == .rita,accessory.childNodes.count>1 {
            let heart=accessory.childNodes[1],beat=state == .working || state == .listening ? max(0,sin(t*5))*0.08 : state == .hello ? p.fold*0.04 : 0
            heart.scale=SCNVector3(1+beat,1+beat,1);heart.eulerAngles.z=CGFloat(state == .annoyed ? -0.08 : sin(global*1.3)*0.016)
        }
        if hero == .elinor,let lens=accessory.childNodes.first {
            lens.position.y=CGFloat(-0.5+(state == .thinking || state == .working ? sin(t*2)*1.1 : 0))
            lens.eulerAngles.z=CGFloat(state == .listening ? sin(t*2)*0.035 : 0)
        }
        if let paper {
            if hero == .gantt {paper.opacity=p.fold;paper.eulerAngles=SCNVector3(0.06,p.fold*0.7,-p.fold*0.15)}
            if hero == .toni {paper.eulerAngles=SCNVector3(0.08+p.fold*0.12,0,-0.10-p.fold*0.38+sin(global*3)*p.fold*0.10)}
        }
        let active=state == .working
        activity.opacity=active ? smooth(t/0.3)*(1-smooth((t-3.6)/0.4)) : 0
        for (n,node) in activity.childNodes.enumerated() {
            switch hero {
            case .sig:let v=(t+Double(n)*0.7).truncatingRemainder(dividingBy:1.8)/1.8;node.position.x=CGFloat((n==0 ? -1 : 1)*v*30);node.position.y=CGFloat(sin(v*Double.pi)*6)
            case .rita:let breathe=(1-cos(t*Double.pi/2))/2;node.scale=SCNVector3(1.04+breathe*0.09,1.04+breathe*0.09,1);node.opacity=0.17+breathe*0.20
            case .ada:node.scale.x=CGFloat(smooth((t-Double(n)*0.5)/0.7))
            case .gantt:node.position.x=CGFloat(sin(max(0,t-Double(n)*0.4)*2)*3*(1-smooth((t-2)/1)))
            case .elinor:node.scale.y=CGFloat(0.15+smooth((t-Double(n)*0.3)/0.7)*0.85)
            case .toni:let v=smooth((t-1)/2.6);node.position.x=CGFloat(v*31);node.position.y=CGFloat(sin(v*Double.pi)*12);node.eulerAngles.z=CGFloat(v*0.3);node.opacity=smooth(t/0.3)
            }
        }
    }
}
