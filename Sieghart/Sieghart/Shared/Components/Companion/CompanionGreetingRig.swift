@preconcurrency import AppKit
@preconcurrency import SceneKit
import Metal

// Live greeting scene. No movie playback or flattened character frames.
final class CompanionGreetingRig {
    let model: CompanionRigModel
    let halo=SCNNode(), handL=SCNNode(), handR=SCNNode()
    var warps:[SCNNode]=[], ring:[SCNNode]=[]
    let bounds:CGRect
    let scene=SCNScene()
    init(_ hero:CompanionAvatar) {
        model=CompanionRigModel(hero)
        bounds=rigNsPath(rigBodyPath(hero)).bounds
        scene.background.contents=NSColor.clear
        let ambient=SCNNode();ambient.light=SCNLight();ambient.light?.type = .ambient
        ambient.light?.intensity=260;ambient.light?.color=rigRgb(1,0.99,0.97);scene.rootNode.addChildNode(ambient)
        let key=SCNNode();key.light=SCNLight();key.light?.type = .directional
        key.light?.intensity=650;key.light?.color=rigRgb(1,0.985,0.95)
        key.position=SCNVector3(-500,700,650);key.look(at:SCNVector3(0,0,0));scene.rootNode.addChildNode(key)
        let fill=SCNNode();fill.light=SCNLight();fill.light?.type = .directional
        fill.light?.intensity=190;fill.light?.color=rigRgb(0.93,0.96,1)
        fill.position=SCNVector3(400,-80,700);fill.look(at:SCNVector3(0,0,0));scene.rootNode.addChildNode(fill)
        let camera=SCNNode();camera.camera=SCNCamera();camera.camera?.usesOrthographicProjection=true
        camera.camera?.orthographicScale=90;camera.camera?.zNear=0.1;camera.camera?.zFar=2000
        camera.camera?.wantsHDR=false;camera.camera?.wantsExposureAdaptation=false
        camera.position=SCNVector3(0,0,850);scene.rootNode.addChildNode(camera)
        let haloMat=SCNMaterial();haloMat.lightingModel = .constant;haloMat.diffuse.contents=Self.glowTexture()
        haloMat.isDoubleSided=true;haloMat.writesToDepthBuffer=false;haloMat.readsFromDepthBuffer=false
        halo.geometry=SCNPlane(width:1,height:1);halo.geometry?.materials=[haloMat];halo.position.z = -30
        // Draw the light before the opaque silhouettes. A transparent halo
        // drawn afterwards clips against unresolved MSAA depth at their edges.
        halo.renderingOrder = -100
        scene.rootNode.addChildNode(halo)
        scene.rootNode.addChildNode(model.root)
        let hb=bounds.height
        let pixel=hero == .ada
        let handColor=hero == .gantt || hero == .toni ? rigCream : hero.color
        let leftPath=NSBezierPath(roundedRect:CGRect(x:-hb*0.15,y:-hb*0.15,width:hb*0.30,height:hb*0.30),xRadius:pixel ? 0.7 : hb*0.15,yRadius:pixel ? 0.7 : hb*0.15)
        let rightPath=NSBezierPath(roundedRect:CGRect(x:-hb*0.20,y:-hb*0.11,width:hb*0.40,height:hb*0.22),xRadius:pixel ? 0.7 : hero == .toni ? hb*0.035 : hb*0.11,yRadius:pixel ? 0.7 : hero == .toni ? hb*0.035 : hb*0.11)
        for (node,path) in [(handL,leftPath),(handR,rightPath)] {
            let geometry=SCNShape(path:path,extrusionDepth:hero == .ada ? 5 : 8)
            geometry.chamferRadius=pixel ? 0.4 : 2
            geometry.materials=[rigMaterial(handColor)];node.geometry=geometry
            node.opacity=0;model.head.addChildNode(node)
        }
        for _ in rigGreetParticles.warps {
            let node=Self.particle();warps.append(node);scene.rootNode.addChildNode(node)
        }
        for _ in rigGreetParticles.ring {
            let node=Self.particle();ring.append(node);scene.rootNode.addChildNode(node)
        }
    }
    static func particle()->SCNNode {
        let n=SCNNode(geometry:SCNPlane(width:1,height:1))
        let m=SCNMaterial();m.lightingModel = .constant;m.diffuse.contents=NSColor.white
        m.isDoubleSided=true;m.writesToDepthBuffer=false;n.geometry?.materials=[m];n.opacity=0;n.position.z = -15
        return n
    }
    private static let glow = makeGlowTexture()
    static func glowTexture()->NSImage { glow }
    private static func makeGlowTexture()->NSImage {
        let img=NSImage(size:CGSize(width:512,height:512));img.lockFocus()
        let ctx=NSGraphicsContext.current!.cgContext
        let cs=CGColorSpaceCreateDeviceRGB()
        for (radius,alpha) in [(256.0,0.07),(256.0*2.6/4.2,0.18)] {
            let gradient=CGGradient(colorsSpace:cs,colors:[CGColor(red:1,green:1,blue:1,alpha:alpha),CGColor(red:1,green:1,blue:1,alpha:0)] as CFArray,locations:[0,1])!
            ctx.drawRadialGradient(gradient,startCenter:CGPoint(x:256,y:256),startRadius:0,endCenter:CGPoint(x:256,y:256),endRadius:radius,options:[])
        }
        img.unlockFocus();return img
    }
    func update(_ t:Double) {
        let p=rigGreetPose(t,compact:CompanionGreetingLayout())
        let hb=bounds.height,hh=hb/2,hw=bounds.width/2
        let naturalScale=p.hb/hb
        // Square silhouettes retain their proportions; all source timing is unchanged.
        var sx=p.sx,sy=p.sy
        if model.hero == .ada || model.hero == .gantt {let s=sqrt(sx*sy);sx=s;sy=s}
        model.head.scale=SCNVector3(naturalScale*sx,naturalScale*sy,naturalScale)
        model.head.position=SCNVector3(p.x-320-bounds.midX*naturalScale*sx,90-p.y-bounds.midY*naturalScale*sy,0)
        model.head.eulerAngles=SCNVector3(0,-0.07,0)
        model.head.opacity=p.hb > 0 ? 1 : 0
        model.updateEyes(open:p.open,joy:p.eye == .happy ? 0.85 : p.eye == .content ? 0.6 : 0,
                         gaze:CGSize(width:p.lookX*hw*0.15,height:p.lookY*hh*0.17),wink:0,anger:0)
        let haloWidth=p.hb*rigGASP*4.2
        halo.scale=SCNVector3(haloWidth,haloWidth,1);halo.position.x=CGFloat(p.x-320);halo.position.y=CGFloat(90-p.y)
        halo.opacity=p.halo
        halo.geometry?.firstMaterial?.multiply.contents=rigRgb(rigGLerp(232/255,59/255,p.haloBlue),rigGLerp(195/255,158/255,p.haloBlue),rigGLerp(154/255,255/255,p.haloBlue))
        let kl=max(0,p.handL),kr=max(0,p.handR)
        let ramp=p.wave>=0 ? rigGClamp(p.wave/0.08,0,1) : 0
        let bob=p.wave>=0 ? sin(p.wave*2*Double.pi*5)*hb*0.14*ramp : 0
        handL.position=SCNVector3(bounds.midX+rigGLerp(-hw*0.35,-hw-hb*0.22,kl),bounds.midY-rigGLerp(hh*0.85,hh*0.62,kl)-bob,model.front+1)
        handL.scale=SCNVector3(kl,kl,kl);handL.opacity=kl>0.01 ? 1 : 0
        handR.position=SCNVector3(bounds.midX+rigGLerp(hw*0.35,hw+hb*0.20,kr),bounds.midY-rigGLerp(hh*0.85,hh*0.20,kr),model.front+1)
        handR.scale=SCNVector3(kr,kr,kr);handR.opacity=kr>0.01 ? 1 : 0
        handR.eulerAngles.z=CGFloat(0.61-(p.wave>=0 ? sin(p.wave*2*Double.pi*2.5)*0.04 : 0))
        if let paper=model.paper {
            if model.hero == .gantt {paper.opacity=0}
            if model.hero == .toni {
                // The actual lower-left paper fold waves OUTWARD; no inward yaw.
                let k=rigGClamp(p.handL,0,1),w=max(0,p.wave)
                paper.eulerAngles=SCNVector3(0.08+k*0.14,0,-0.10-k*(0.52+sin(w*2*Double.pi*3)*0.22))
                handL.opacity=0;handR.opacity=0
                model.paperRight?.eulerAngles.z=CGFloat(k*sin(w*2*Double.pi*2.5)*0.04)
            }
        }
        // The source's seeded fall streaks and landing ring.
        for (n,s) in zip(warps,rigGreetParticles.warps) {
            let yBot=(t-s.t0)*s.speed,yTop=yBot-s.len
            let bottom=min(140,yBot),top=max(36,yTop),x=320-p.iw/2+s.xNorm*p.iw
            let visible=t<0.55 && t>=s.t0 && bottom>top && x>10 && x<630
            n.opacity=visible ? s.alpha*(1-rigGSeg(t,0.4,0.55))*p.card : 0
            n.position.x=CGFloat(x-320);n.position.y=CGFloat(90-(top+bottom)/2)
            n.scale=SCNVector3(s.thick,max(0.001,bottom-top),1)
        }
        let k=rigGSeg(t,0.45,1.8),rx=rigGLerp(14,380,CompanionEase.out(k)),ry=rx*0.34
        let fade=(1-k)*(k<0.08 ? k/0.08 : 1)*p.card
        for (n,dot) in zip(ring,rigGreetParticles.ring) {
            let x=cos(dot.a)*rx*(1+dot.j),y = -sin(dot.a)*ry*(1+dot.j)
            n.position.x=CGFloat(x);n.position.y=CGFloat(y);n.scale=SCNVector3(dot.s,dot.s,1)
            let inside=abs(x)<306 && y > -48 && y < 52
            n.opacity=k>0 && k<1 && inside ? dot.al*fade : 0
        }
    }
}
