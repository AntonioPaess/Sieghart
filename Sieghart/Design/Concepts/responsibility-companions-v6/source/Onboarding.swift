import AppKit
import SceneKit

// Sig is permanently the principal. Specialists are introduced, never offered as a principal picker.
final class TeamOnboarding {
    let study=GreetingStudy(.sig),canvas=ConceptCanvas(1280,960)
    let agents:[CharacterModel],angles:[Double]=[150,30,90,222,318]
    let notch=SCNNode(),notchSig=CharacterModel(.sig)
    var cardKey = -1
    let headlines=["Respira comigo.","Código com menos ruído.","Um compromisso por vez.","Clareza para decidir.","Da ideia à mensagem."]
    let descriptions=["Pausas, bem-estar e um ritmo mais leve.","GitHub, revisões e próximos passos.","Agenda, lembretes e tempo para focar.","Organiza finanças e recursos.","Arquivos, emails e comunicação."]
    init() {
        study.renderer.pointOfView?.camera?.orthographicScale=180
        agents=Hero.allCases.dropFirst().map{hero in let m=CharacterModel(hero);m.prepareMotion();return m}
        for model in agents {study.scene.rootNode.addChildNode(model.root)}
        let mat=SCNMaterial();mat.lightingModel = .constant;mat.diffuse.contents=NSColor.black
        notch.geometry=SCNShape(path:NSBezierPath(roundedRect:CGRect(x:-95,y:-14,width:190,height:28),xRadius:12,yRadius:12),extrusionDepth:0)
        notch.geometry?.materials=[mat];notch.position=SCNVector3(0,165,20);notch.opacity=0;study.scene.rootNode.addChildNode(notch)
        let b=nsPath(bodyPath(.sig)).bounds,s=13/b.height
        notchSig.head.scale=SCNVector3(s,s,s);notchSig.head.position=SCNVector3(-b.midX*s,-b.midY*s,0)
        notchSig.root.position=SCNVector3(0,165,30);notchSig.root.opacity=0;study.scene.rootNode.addChildNode(notchSig.root)
    }
    func draw(_ t:Double) {
        SCNTransaction.begin();SCNTransaction.disableActions=true
        study.update(min(t,4.6))
        let expand=GE.inOut(gSeg(t,7.0,9.4)),height=gLerp(104,330,expand)
        let key=Int(height*2)
        if key != cardKey {
            cardKey=key
            let y=gLerp(-50,-155,expand)
            study.card.geometry=SCNShape(path:NSBezierPath(roundedRect:CGRect(x:-310,y:y,width:620,height:height),xRadius:22,yRadius:22),extrusionDepth:0)
            let mat=SCNMaterial();mat.lightingModel = .constant;mat.diffuse.contents=rgb(0.055,0.062,0.066);study.card.geometry?.materials=[mat]
        }
        let dock=GE.inOut(gSeg(t,7.4,10.0))
        let sig=study.model,b=study.bounds,s=gLerp(58,65,dock)/b.height
        if t>=4.6 {
            sig.head.scale=SCNVector3(s,s,s)
            sig.head.position=SCNVector3(-145*dock-b.midX*s,35*dock-b.midY*s,0)
            sig.head.eulerAngles=SCNVector3(0,-0.07+sin(t*0.8)*0.015,0)
            sig.updateEyes(open:1,joy:0.20,gaze:CGSize(width:dock*1.5,height:0),wink:0,anger:0)
            study.halo.position=SCNVector3(-145*dock,35*dock,-30)
            study.halo.scale=SCNVector3(gLerp(285,200,dock),gLerp(285,200,dock),1);study.halo.opacity=gLerp(0.8,0.24,dock)
        }
        let active=t>=10.2 && t<25.2 ? min(4,Int((t-10.2)/3)) : -1
        notch.opacity=smooth((t-9.4)/0.6);notchSig.root.opacity=notch.opacity
        for (i,m) in agents.enumerated() {
            let start=4.6+Double(i)*0.09,u=gSeg(t,start,start+1.0)
            let radius=112*GE.back(u),angle=(angles[i]-(1-GE.inOut(gSeg(t,5.6,7.4)))*240)*Double.pi/180
            let cx=cos(angle)*radius,cy=sin(angle)*radius
            let d=GE.inOut(gSeg(t,7.4+Double(i)*0.08,9.5+Double(i)*0.08)),tx=Double(i-2)*108,ty = -95.0
            // Arc gently down into the five real positions in the widget dock.
            let x=gLerp(cx,tx,d),y=gLerp(cy,ty,d)+sin(d*Double.pi)*22
            m.root.position=SCNVector3(x,y,-28*(1-GE.out(u)));m.root.opacity=GE.out(gSeg(t,start,start+0.25))
            let bounds=nsPath(bodyPath(m.hero)).bounds,scale=gLerp(gLerp(0.08,40/bounds.height,GE.back(u)),32/bounds.height,d)
            let at=active==i ? t-(10.2+Double(i)*3) : 0
            let hop=active==i ? pow(sin(gSeg(at,0.05,0.7)*Double.pi),2)*5 : 0
            m.head.scale=SCNVector3(scale,scale,scale);m.head.position=SCNVector3(-bounds.midX*scale,-bounds.midY*scale+hop,0)
            m.head.eulerAngles=SCNVector3(0,-0.10+sin(t+Double(i))*0.025,sin(t*1.4+Double(i))*0.012)
            let blink=(t+Double(i)*0.37).truncatingRemainder(dividingBy:4.2)
            let open=blink>3.55 && blink<3.85 ? 1-sin((blink-3.55)/0.3*Double.pi)*0.95 : 1
            m.updateEyes(open:open,joy:active==i ? 0.65*smooth(at/0.3) : 0,gaze:CGSize(width:-cos(angle)*0.8*(1-d),height:0),wink:0,anger:0)
            m.marker?.opacity=0;m.activity.opacity=0
            if m.hero == .toni {m.paper?.eulerAngles=SCNVector3(0.08,0,-0.1-(active==i ? sin(at*5)*0.25+0.3 : 0))}
        }
        SCNTransaction.commit()
        let shot=study.renderer.snapshot(atTime:t,with:CGSize(width:1280,height:720),antialiasingMode:.multisampling4X)
        canvas.draw {
            shot.draw(in:NSRect(x:0,y:72,width:640,height:360))
            GreetingStudy.text("SIEGHART / CONHEÇA SUA EQUIPE",x:20,y:459,size:15,weight:.semibold,color:cream)
            let show=smooth((t-9.4)/0.6)
            if show>0 {
                let c=NSColor(srgbRed:0.88,green:0.88,blue:0.85,alpha:show)
                ConceptCanvas.centered("Sig",x:175,y:230,size:17,weight:.semibold,color:c)
                ConceptCanvas.centered("Seu companion principal",x:175,y:210,size:10,color:c)
                // Labels leave the physically shaded specialist icons unobscured.
                for (i,h) in Hero.allCases.dropFirst().enumerated() {
                    let x=320+Double(i-2)*108
                    let labelColor=active==i ? mint : c
                    ConceptCanvas.centered(h.name,x:x,y:120,size:12,weight:.semibold,color:labelColor)
                    ConceptCanvas.centered(["Saúde","Código","Agenda","Finanças","Comunicação"][i],x:x,y:105,size:8.5,color:c)
                    if active==i {
                        mint.withAlphaComponent(0.9).setFill();NSBezierPath(roundedRect:NSRect(x:x-13,y:95,width:26,height:2),xRadius:1,yRadius:1).fill()
                    }
                }
                let title=active>=0 ? agents[active].hero.name : "Sig reúne a equipe."
                let headline=active>=0 ? headlines[active] : "Eu junto tudo para você."
                let desc=active>=0 ? descriptions[active] : "Cada especialista cuida de uma área."
                GreetingStudy.text(title,x:290,y:337,size:12,weight:.medium,color:mint.withAlphaComponent(show))
                GreetingStudy.text(headline,x:290,y:307,size:18,weight:.semibold,color:c)
                GreetingStudy.text(desc,x:290,y:279,size:10,weight:.regular,color:c)
                GreetingStudy.text("Sig é sempre o principal.",x:290,y:250,size:10,weight:.regular,color:c)
                GreetingStudy.text("Diga o que precisa. Eu chamo quem pode ajudar.",x:290,y:232,size:8.5,weight:.regular,color:NSColor(white:0.6,alpha:show))
            }
            let phase=t<4.6 ? "O primeiro alô do Sig" : t<7.4 ? "Os cinco especialistas saem de trás dele" : t<10.2 ? "Cada um ocupa seu lugar no widget" : active>=0 ? "Conheça \(agents[active].hero.name)" : "Sua equipe está pronta. Começar com Sig."
            GreetingStudy.text(phase,x:20,y:26,size:12,weight:.medium,color:rgb(0.75,0.77,0.73))
            GreetingStudy.text("Conceito visual · 60 fps",x:20,y:10,size:8,weight:.regular,color:rgb(0.50,0.54,0.52))
        }
    }
}
