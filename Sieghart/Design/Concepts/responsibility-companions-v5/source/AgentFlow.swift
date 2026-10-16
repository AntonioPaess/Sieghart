import AppKit
import SceneKit
import Metal

// Preview-only choreography. Labels are examples, never live agent state.
final class AgentFlow {
    let renderer:SCNRenderer
    var models:[CharacterModel]=[],halos:[SCNNode]=[]
    let starts:[Double]=[0,2,4.5,6.5,9.5,11.5,14]
    let names=["Escutando","Pensando / loading","Buscando","Executando a tarefa","Aguardando sua aprovação","Concluído","Repouso"]
    let sourceStates:[State]=[.listening,.thinking,.look,.working,.startled,.happy,.idle]
    let colors=[rgb(0.35,0.73,0.79),rgb(0.62,0.43,0.95),rgb(0.42,0.46,0.90),rgb(0.24,0.62,1),rgb(0.96,0.65,0.14),rgb(0.25,0.79,0.59),rgb(0.48,0.51,0.53)]
    init() {
        let scene=SCNScene();scene.background.contents=rgb(0.035,0.039,0.047)
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient;ambient.light?.intensity=260;ambient.light?.color=rgb(1,0.99,0.97);scene.rootNode.addChildNode(ambient)
        let key=SCNNode();key.light=SCNLight();key.light?.type = .directional;key.light?.intensity=650;key.light?.color=rgb(1,0.985,0.95)
        key.position=SCNVector3(-500,700,650);key.look(at:SCNVector3(0,0,0));scene.rootNode.addChildNode(key)
        let fill=SCNNode();fill.light=SCNLight();fill.light?.type = .directional;fill.light?.intensity=190;fill.light?.color=rgb(0.93,0.96,1);fill.position=SCNVector3(400,-80,700);fill.look(at:SCNVector3(0,0,0));scene.rootNode.addChildNode(fill)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true;camera.camera?.orthographicScale=175
        camera.camera?.zNear=0.1;camera.camera?.zFar=2000;camera.camera?.wantsHDR=false;camera.camera?.wantsExposureAdaptation=false
        camera.position=SCNVector3(0,0,850);scene.rootNode.addChildNode(camera)
        for (i,hero) in Hero.allCases.enumerated() {
            let model=CharacterModel(hero);model.prepareMotion();model.root.position=SCNVector3(Double(i%3-1)*154,i<3 ? 85 : -85,0)
            let bounds=nsPath(bodyPath(hero)).bounds,scale=52/bounds.height
            model.root.scale=SCNVector3(scale,scale,scale);scene.rootNode.addChildNode(model.root);models.append(model)
            let node=SCNNode(geometry:SCNPlane(width:bounds.height*4,height:bounds.height*4))
            let mat=SCNMaterial();mat.lightingModel = .constant;mat.diffuse.contents=GreetingStudy.glowTexture();mat.isDoubleSided=true;mat.writesToDepthBuffer=false
            node.geometry?.materials=[mat];node.position.z = -30;model.root.addChildNode(node);halos.append(node)
        }
        renderer=SCNRenderer(device:MTLCreateSystemDefaultDevice(),options:nil);renderer.scene=scene;renderer.pointOfView=camera;renderer.autoenablesDefaultLighting=false
    }
    func frame(_ t:Double)->Data {
        var phase=starts.count-1
        while phase>0 && starts[phase]>t {phase-=1}
        let local=t-starts[phase]
        SCNTransaction.begin();SCNTransaction.disableActions=true
        for (i,m) in models.enumerated() {
            let state=sourceStates[phase]
            m.animate(state.start+min(local,state.seconds-0.28))
            if phase == 0 {
                let level=(0.5+0.5*sin(local*9+Double(i)*0.3))*0.45
                m.head.eulerAngles.z=CGFloat(-0.10*GE.out(gSeg(local,0,0.2)))
                m.updateEyes(open:1.06+level*0.15,joy:0,gaze:CGSize(width:sin(local*1.1)*0.8,height:-1),wink:0,anger:0)
            }
            if phase == 2 {
                m.head.eulerAngles.y=CGFloat(sin(local*2.6)*0.35)
                m.updateEyes(open:1,joy:0,gaze:CGSize(width:sin(local*2.6)*4,height:-0.5),wink:0,anger:0)
                m.marker?.opacity=1
            }
            if phase == 4 {
                let entry=local<0.15 ? 0.2*GE.out(local/0.15) : 0.2*(1-GE.back(gSeg(local,0.15,0.45)))
                m.head.position.y=CGFloat((entry+abs(sin(local*5.2))*0.07)*24)
                m.head.eulerAngles.z=0;m.marker?.opacity=0.85;m.activity.opacity=0
                m.updateEyes(open:1.16,joy:0,gaze:.zero,wink:0,anger:0)
            }
            if phase == 5 {
                let v=max(0,local-Double(i)*0.06),rotation=GE.inOut(gSeg(v,0,0.95))*Double.pi*2
                m.head.eulerAngles.z=CGFloat(rotation)
                m.marker?.opacity=0;m.activity.opacity=0
                m.updateEyes(open:1,joy:0.85,gaze:.zero,wink:0,anger:0)
            }
            if phase == 6 {m.marker?.opacity=0}
            halos[i].geometry?.firstMaterial?.multiply.contents=colors[phase]
            halos[i].opacity=phase==6 ? 0.08 : 0.72
        }
        SCNTransaction.commit()
        let shot=renderer.snapshot(atTime:t,with:CGSize(width:1668,height:1200),antialiasingMode:.multisampling4X)
        let output=NSImage(size:CGSize(width:834,height:760));output.lockFocus()
        rgb(0.035,0.039,0.047).setFill();NSRect(x:0,y:0,width:834,height:760).fill()
        shot.draw(in:NSRect(x:0,y:86,width:834,height:600))
        GreetingStudy.text("SIEGHART / ESTADOS DOS AGENTES",x:28,y:720,size:22,weight:.semibold,color:rgb(0.93,0.90,0.85))
        GreetingStudy.text("Demonstração visual · gestos adaptados às seis identidades",x:28,y:697,size:12,weight:.regular,color:rgb(0.64,0.66,0.63))
        GreetingStudy.text(names[phase],x:28,y:667,size:12,weight:.bold,color:colors[phase])
        for (i,hero) in Hero.allCases.enumerated() {
            let x=Double(417+(i%3-1)*264),y=i<3 ? 407.0 : 115.0
            let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:19,weight:.semibold),.foregroundColor:rgb(0.91,0.89,0.85)]
            let name=hero.name as NSString;name.draw(at:NSPoint(x:x-name.size(withAttributes:attrs).width/2,y:y),withAttributes:attrs)
            let role=["Principal","Saúde e pausas","Código e GitHub","Agenda e rotina","Finanças e recursos","Comunicação"][i] as NSString
            let small:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:11),.foregroundColor:rgb(0.62,0.63,0.61)]
            role.draw(at:NSPoint(x:x-role.size(withAttributes:small).width/2,y:y-20),withAttributes:small)
        }
        GreetingStudy.text("Nenhuma tarefa real é executada nesta prévia",x:28,y:35,size:11,weight:.regular,color:rgb(0.60,0.62,0.58))
        output.unlockFocus()
        return NSBitmapImageRep(data:output.tiffRepresentation!)!.representation(using:.png,properties:[:])!
    }
}
