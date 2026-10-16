// Approved v6 2.5D family: native extruded paths, PBR lighting and curved paper.
@preconcurrency import AppKit
@preconcurrency import SceneKit
import SwiftUI

extension CompanionAvatar {
    var color:NSColor {
        switch self {
        case .sig: rigRgb(0.13,0.15,0.15)
        case .rita: rigRgb(0.63,0.77,0.57)
        case .ada: rigRgb(1,0.76,0.34)
        case .gantt: rigRgb(0.69,0.64,0.87)
        case .elinor: rigRgb(0.98,0.83,0.71)
        case .toni: rigRgb(1,0.94,0.83)
        }
    }
}
func rigRgb(_ r:Double,_ g:Double,_ b:Double)->NSColor {NSColor(srgbRed:r,green:g,blue:b,alpha:1)}
let rigCream=rigRgb(1,0.94,0.82), rigCoral=rigRgb(0.96,0.55,0.44), rigMint=rigRgb(0.60,0.82,0.62), rigLilac=rigRgb(0.69,0.59,0.88), rigInk=rigRgb(0.07,0.09,0.09), rigGold=rigRgb(0.81,0.56,0.22)

private nonisolated(unsafe) var rigPaperTextures:[String:NSImage]=[:]
private let rigTextureLock = NSLock()
func rigTactileTexture(_ color:NSColor)->NSImage {
    rigTextureLock.lock(); defer { rigTextureLock.unlock() }
    let c=color.usingColorSpace(.sRGB)!,key="\(c.redComponent)-\(c.greenComponent)-\(c.blueComponent)"
    if let saved=rigPaperTextures[key] {return saved}
    let size=256,rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
    var seed:UInt64=0xAB42
    for y in 0..<size {for x in 0..<size {
        seed=seed &* 6364136223846793005 &+ 1442695040888963407
        let grain=(Double((seed>>32)&255)/255-0.5)*0.028
        let offset=y*rep.bytesPerRow+x*4
        for (i,v) in [c.redComponent,c.greenComponent,c.blueComponent].enumerated() {rep.bitmapData![offset+i]=UInt8(max(0,min(255,(v+grain)*255)))}
        rep.bitmapData![offset+3]=255
    }}
    let image=NSImage(size:CGSize(width:size,height:size));image.addRepresentation(rep);rigPaperTextures[key]=image;return image
}

func rigMaterial(_ color:NSColor,metal:Double=0)->SCNMaterial {
    let m=SCNMaterial();m.lightingModel = .physicallyBased
    m.diffuse.contents=metal>0 ? color : rigTactileTexture(color);m.roughness.contents=metal>0 ? 0.36 : 0.66;m.metalness.contents=metal
    m.specular.contents=NSColor(white:0.34,alpha:1);m.isDoubleSided=true
    return m
}
func rigNsPath(_ path:Path)->NSBezierPath {
    let bezier=NSBezierPath();bezier.windingRule = .evenOdd;bezier.flatness=0.12
    func point(_ p:CGPoint)->CGPoint {CGPoint(x:p.x-48,y:48-p.y)}
    var current=CGPoint.zero
    path.cgPath.applyWithBlock { ptr in
        let element=ptr.pointee
        switch element.type {
        case .moveToPoint: current=point(element.points[0]);bezier.move(to:current)
        case .addLineToPoint:current=point(element.points[0]);bezier.line(to:current)
        case .addQuadCurveToPoint:
            let control=point(element.points[0]),end=point(element.points[1])
            let a=CGPoint(x:current.x+(control.x-current.x)*2/3,y:current.y+(control.y-current.y)*2/3)
            let b=CGPoint(x:end.x+(control.x-end.x)*2/3,y:end.y+(control.y-end.y)*2/3)
            bezier.curve(to:end,controlPoint1:a,controlPoint2:b);current=end
        case .addCurveToPoint:
            let end=point(element.points[2]);bezier.curve(to:end,controlPoint1:point(element.points[0]),controlPoint2:point(element.points[1]));current=end
        case .closeSubpath:bezier.close()
        @unknown default:break
        }
    }
    return bezier
}
func rigPolygon(_ points:[(Double,Double)],radius:Double=0)->Path {
    let points=points.map{CGPoint(x:$0.0,y:$0.1)}
    var p=Path()
    for i in points.indices {
        let current=points[i],prev=points[(i+points.count-1)%points.count],next=points[(i+1)%points.count]
        func toward(_ n:CGPoint)->CGPoint {
            let x=n.x-current.x,y=n.y-current.y,dist=hypot(x,y),f=min(radius/max(0.01,dist),0.45)
            return CGPoint(x:current.x+x*f,y:current.y+y*f)
        }
        let a=toward(prev),b=toward(next)
        if i==0 {p.move(to:a)} else {p.addLine(to:a)}
        p.addQuadCurve(to:b,control:current)
    }
    p.closeSubpath();return p
}
func rigBodyPath(_ h:CompanionAvatar)->Path {
    switch h {
    case .sig:return Path(roundedRect:CGRect(x:7,y:25,width:82,height:48),cornerRadius:23)
    case .ada:return rigPolygon([(29,13),(67,13),(67,22),(78,22),(78,33),(85,33),(85,66),(78,66),(78,79),(18,79),(18,66),(11,66),(11,33),(18,33),(18,22),(29,22)],radius:1)
    case .rita:
        var p=Path();p.move(to:CGPoint(x:35,y:8))
        p.addCurve(to:CGPoint(x:77,y:35),control1:CGPoint(x:49,y:5),control2:CGPoint(x:73,y:16))
        p.addCurve(to:CGPoint(x:79,y:61),control1:CGPoint(x:84,y:44),control2:CGPoint(x:84,y:55))
        p.addCurve(to:CGPoint(x:47,y:82),control1:CGPoint(x:79,y:80),control2:CGPoint(x:62,y:82))
        p.addCurve(to:CGPoint(x:15,y:62),control1:CGPoint(x:26,y:82),control2:CGPoint(x:13,y:77))
        p.addCurve(to:CGPoint(x:30,y:34),control1:CGPoint(x:15,y:49),control2:CGPoint(x:25,y:40))
        p.addCurve(to:CGPoint(x:35,y:8),control1:CGPoint(x:40,y:20),control2:CGPoint(x:37,y:15));p.closeSubpath();return p
    case .gantt:return Path(roundedRect:CGRect(x:13,y:15,width:73,height:73),cornerRadius:15)
    case .elinor:return rigPolygon([(20,23),(73,23),(90,50),(72,76),(20,76),(7,50)],radius:4)
    case .toni:
        return Path(roundedRect:CGRect(x:17,y:20,width:64,height:63),cornerRadius:15)
    }
}
func rigShape(_ path:Path,color:NSColor,depth:Double=12,bevel:Double=3,side:NSColor?=nil)->SCNNode {
    let s=SCNShape(path:rigNsPath(path),extrusionDepth:depth);s.chamferRadius=bevel
    let front=rigMaterial(color),edge=rigMaterial(side ?? color)
    s.materials=[front,edge,edge,front,edge]
    let n=SCNNode(geometry:s);return n
}
func rigStroke(_ path:Path,color:NSColor,width:Double=2,depth:Double=1.4,metal:Double=0)->SCNNode {
    let root=SCNNode(),mat=rigMaterial(color,metal:metal)
    var current=CGPoint.zero,start=CGPoint.zero
    func add(_ end:CGPoint) {
        let dx=end.x-current.x,dy=end.y-current.y,d=hypot(dx,dy)
        if d>0.01 {
            let tube=SCNCapsule(capRadius:width/2,height:d+width);tube.radialSegmentCount=10;tube.capSegmentCount=3;tube.heightSegmentCount=1;tube.materials=[mat]
            let node=SCNNode(geometry:tube);node.position=SCNVector3((current.x+end.x)/2-48,48-(current.y+end.y)/2,0)
            node.eulerAngles.z=CGFloat(atan2(-dy,dx)-Double.pi/2);node.scale.z=CGFloat(depth/width);root.addChildNode(node)
        }
        current=end
    }
    path.cgPath.applyWithBlock {ptr in
        let e=ptr.pointee
        switch e.type {
        case .moveToPoint:current=e.points[0];start=current
        case .addLineToPoint:add(e.points[0])
        case .addQuadCurveToPoint:
            let a=current,b=e.points[0],c=e.points[1]
            for i in 1...12 {let t=Double(i)/12,u=1-t;add(CGPoint(x:u*u*a.x+2*u*t*b.x+t*t*c.x,y:u*u*a.y+2*u*t*b.y+t*t*c.y))}
        case .addCurveToPoint:
            let a=current,b=e.points[0],c=e.points[1],d=e.points[2]
            for i in 1...16 {let t=Double(i)/16,u=1-t;add(CGPoint(x:u*u*u*a.x+3*u*u*t*b.x+3*u*t*t*c.x+t*t*t*d.x,y:u*u*u*a.y+3*u*u*t*b.y+3*u*t*t*c.y+t*t*t*d.y))}
        case .closeSubpath:add(start)
        @unknown default:break
        }
    }
    // Segments never move relative to one another. Bake them into one mesh
    // so a ring does not issue dozens of separate draw commands every frame.
    return root.flattenedClone()
}

// Restore the earlier fixed badge with a travelling inner stroke. Only one
// shader uniform changes per frame; the badge and its silhouette never rotate.
func rigLoadingBadge(_ hero: CompanionAvatar) -> (node: SCNNode, progress: SCNMaterial) {
    let node = SCNNode()
    let outer = CompanionLoadingShape(avatar: hero).path(in: CGRect(x: 36, y: 36, width: 24, height: 24))
    node.addChildNode(rigShape(outer, color: NSColor(hero.processingTint), depth: 1.5, bevel: 0.4))
    let edge = rigStroke(outer, color: rigRgb(0.14, 0.17, 0.16), width: 1.2, depth: 0.5)
    edge.position.z = 1.5; node.addChildNode(edge)
    let inner = CompanionLoadingShape(avatar: hero).path(in: CGRect(x: 40, y: 40, width: 16, height: 16))
    var points: [CGPoint] = [], current = CGPoint.zero
    func append(_ p: CGPoint) {
        if let last = points.last, hypot(p.x - last.x, p.y - last.y) < 0.001 { return }
        points.append(p); current = p
    }
    inner.cgPath.applyWithBlock { pointer in
        let e = pointer.pointee
        switch e.type {
        case .moveToPoint, .addLineToPoint: append(e.points[0])
        case .addQuadCurveToPoint:
            let a = current, b = e.points[0], c = e.points[1]
            for i in 1...12 { let t = Double(i) / 12, u = 1 - t; append(CGPoint(x: u*u*a.x + 2*u*t*b.x + t*t*c.x, y: u*u*a.y + 2*u*t*b.y + t*t*c.y)) }
        case .addCurveToPoint:
            let a = current, b = e.points[0], c = e.points[1], d = e.points[2]
            for i in 1...16 { let t = Double(i) / 16, u = 1 - t; append(CGPoint(x: u*u*u*a.x + 3*u*u*t*b.x + 3*u*t*t*c.x + t*t*t*d.x, y: u*u*u*a.y + 3*u*u*t*b.y + 3*u*t*t*c.y + t*t*t*d.y)) }
        case .closeSubpath: break
        @unknown default: break
        }
    }
    if let first = points.first, let last = points.last, hypot(first.x-last.x, first.y-last.y) < 0.001 { points.removeLast() }
    let n = points.count
    var distances = [0.0]
    for i in 0..<n { let a = points[i], b = points[(i+1)%n]; distances.append(distances.last! + hypot(b.x-a.x, b.y-a.y)) }
    var vertices: [SCNVector3] = [], uv: [CGPoint] = [], indices: [Int32] = []
    func normal(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
        let length = max(0.001, hypot(b.x-a.x, b.y-a.y))
        return CGPoint(x: -(b.y-a.y)/length, y: (b.x-a.x)/length)
    }
    for i in 0...n {
        let p = points[i%n], before = normal(points[(i+n-1)%n], p), after = normal(p, points[(i+1)%n])
        let length = max(0.001, hypot(before.x+after.x, before.y+after.y))
        let m = CGPoint(x: (before.x+after.x)/length, y: (before.y+after.y)/length)
        let width = min(1.8, 0.95 / max(0.25, m.x*after.x + m.y*after.y))
        for sign in [-1.0, 1] {
            vertices.append(SCNVector3(p.x - 48 + m.x*width*sign, 48 - p.y - m.y*width*sign, 2))
            uv.append(CGPoint(x: distances[i] / distances.last!, y: (sign+1)/2))
        }
        if i < n { let a = Int32(i*2); indices += [a,a+1,a+2,a+1,a+3,a+2] }
    }
    let progress = SCNMaterial(); progress.lightingModel = .constant
    progress.isDoubleSided = true; progress.writesToDepthBuffer = false; progress.blendMode = .alpha
    progress.setValue(Float(0), forKey: "phase")
    progress.shaderModifiers = [.fragment: """
    #pragma arguments
    float phase;
    #pragma transparent
    #pragma body
    float d = fract(_surface.diffuseTexcoord.x - phase + 1.0);
    float arc = 1.0 - step(0.29, d);
    float alpha = mix(0.14, 0.90, arc);
    // SceneKit's transparent fragment output is linear and premultiplied.
    _output.color = float4(float3(0.0174, 0.0245, 0.0220) * alpha, alpha);
    """]
    let mesh = SCNGeometry(sources: [SCNGeometrySource(vertices: vertices), SCNGeometrySource(textureCoordinates: uv)],
                           elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)])
    mesh.materials = [progress]; node.addChildNode(SCNNode(geometry: mesh))
    return (node, progress)
}

func rigEyePath(rect:CGRect,joy:Double,pixel:Bool)->Path {
    let j=min(1,max(0,joy))
    if pixel {
        if j<0.4 {return Path(roundedRect:rect,cornerRadius:0.8)}
        var p=Path()
        for n in 0..<4 {p.addRect(CGRect(x:rect.minX+CGFloat(n)*rect.width/4,y:rect.minY+(n==0 || n==3 ? rect.height*0.32 : 0),width:rect.width/4,height:max(2,rect.height*0.28)))}
        return p
    }
    func mix(_ a:(Double,Double),_ b:(Double,Double))->CGPoint {CGPoint(x:rect.minX+(a.0+(b.0-a.0)*j)*rect.width,y:rect.minY+(a.1+(b.1-a.1)*j)*rect.height)}
    var p=Path();p.move(to:mix((0,0.5),(0,0.85)))
    p.addCurve(to:mix((0.5,0),(0.5,0.15)),control1:mix((0,0.22),(0,0.48)),control2:mix((0.22,0),(0.22,0.15)))
    p.addCurve(to:mix((1,0.5),(1,0.85)),control1:mix((0.78,0),(0.78,0.15)),control2:mix((1,0.22),(1,0.48)))
    p.addCurve(to:mix((0.5,1),(0.5,0.45)),control1:mix((1,0.78),(1,1)),control2:mix((0.78,1),(0.80,0.45)))
    p.addCurve(to:mix((0,0.5),(0,0.85)),control1:mix((0.22,1),(0.20,0.45)),control2:mix((0,0.78),(0,1)));p.closeSubpath();return p
}

// Created before attachment; afterwards only the SceneKit render callback mutates this rig.
final class CompanionRigModel {
    let hero:CompanionAvatar
    let root=SCNNode(),head=SCNNode(),accessory=SCNNode(),activity=SCNNode()
    var eyes:[SCNNode]=[]
    var front:Double=10
    var paper:SCNNode?
    var paperRight:SCNNode?
    var marker:SCNNode?
    var loadingProgress: SCNMaterial?
    // Quantized meshes are cached per live actor, with a bounded cache.
    private(set) var eyeCache:[String:SCNGeometry]=[:]
    private var eyeKeys = ["", ""]
    private lazy var eyeMaterial: SCNMaterial = {
        let material = rigMaterial(hero == .sig ? rigCream : rigInk)
        material.roughness.contents = 0.42
        material.specular.contents = NSColor(white: 0.55, alpha: 1)
        return material
    }()
    init(_ hero:CompanionAvatar) {
        self.hero=hero;root.addChildNode(head)
        let depth=hero == .sig ? 24.0 : hero == .rita ? 22 : 16
        let body=rigShape(rigBodyPath(hero),color:hero.color,depth:depth,bevel:hero == .ada ? 0.8 : hero == .rita ? 2.5 : hero == .gantt ? 3.5 : 6,side:hero == .elinor ? rigRgb(0.88,0.53,0.47) : nil)
        let roundedLighting="""
        #pragma body
        if (_geometry.normal.z > 0.99) {
            _geometry.normal = normalize(float3(_geometry.position.x * 0.010, _geometry.position.y * 0.014, 1.0));
        }
        """
        body.geometry?.shaderModifiers=[.geometry:roundedLighting]
        head.addChildNode(body);front=Double(body.boundingBox.max.z)+0.8
        if hero == .gantt {
            for index in (0..<3).reversed() {
                let offset=Double(index)*1.4
                let page=rigShape(Path(roundedRect:CGRect(x:16+offset,y:18+offset,width:64,height:64),cornerRadius:12),color:index==0 ? rigCream : rigRgb(0.92,0.84,0.70),depth:1.5,bevel:0.5)
                page.position.z=CGFloat(front+Double(3-index)*2.2);head.addChildNode(page)
                if index==0 {
                    page.geometry?.shaderModifiers=[.geometry:roundedLighting]
                }
            }
            front+=7.5
        }
        if hero == .toni {
            let fold=rigShape(rigPolygon([(69,20),(82,21),(91,63),(80,77),(68,62)],radius:3),color:rigCoral,depth:3,bevel:1)
            fold.position.z = -6;head.addChildNode(fold)
            fold.pivot=SCNMatrix4MakeTranslation(26,18,0)
            fold.position=SCNVector3(26,18,-6);paperRight=fold
            let flap=rigCurledPaperHand()
            flap.position=SCNVector3(-28,-20,front+0.5)
            head.addChildNode(flap);paper=flap
        }
        head.addChildNode(accessory);head.addChildNode(activity)
        addAccessory()
        for _ in 0..<2 {
            let eye=SCNNode();eye.position.z=CGFloat(front+1.4);head.addChildNode(eye);eyes.append(eye)
        }
        updateEyes(open:1,joy:0,gaze:.zero,wink:0,anger:0)
    }
    func attach(_ node:SCNNode,z:Double?=nil) {node.position.z=CGFloat(z ?? front+2);accessory.addChildNode(node)}
    func addAccessory() {
        switch hero {
        case .sig:
            attach(rigShape(rigPolygon([(77,20),(85,29),(77,38),(69,29)],radius:1),color:rigMint,depth:3,bevel:0.7))
            attach(rigShape(rigPolygon([(77,20),(77,29),(85,29)]),color:rigRgb(0.77,0.94,0.73),depth:0.4,bevel:0.1),z:front+4)
        case .rita:
            // A small integrated pulse replaces the white strap and floating heart.
            var pulse=Path();pulse.move(to:CGPoint(x:61,y:36))
            for point in [(64.0,36.0),(66,32),(68,40),(70,36),(73,36)] {pulse.addLine(to:CGPoint(x:point.0,y:point.1))}
            attach(rigStroke(pulse,color:rigCoral,width:1.5,depth:0.8),z:front+0.25)
        case .ada:
            var p=Path();p.move(to:CGPoint(x:72,y:22));p.addLine(to:CGPoint(x:67,y:27));p.addLine(to:CGPoint(x:72,y:32));p.move(to:CGPoint(x:80,y:22));p.addLine(to:CGPoint(x:85,y:27));p.addLine(to:CGPoint(x:80,y:32));attach(rigStroke(p,color:rigRgb(0.16,0.63,0.58),width:3,depth:1.8))
        case .gantt:
            for x in [Double(31),61] {
                attach(rigShape(Path(roundedRect:CGRect(x:x,y:10,width:5,height:17),cornerRadius:2.5),color:rigLilac,depth:4,bevel:1),z:front+1)
            }
            attach(rigShape(rigPolygon([(78,70),(85,70),(85,84),(81.5,81),(78,84)],radius:0.5),color:rigCoral,depth:2,bevel:0.6),z:front+0.5)
            let page=rigShape(rigPolygon([(80,20),(77,31),(90,39)],radius:2),color:rigCream,depth:1.2,bevel:0.4);attach(page,z:front+2);paper=page;page.opacity=0
        case .elinor:
            attach(rigStroke(Path(ellipseIn:CGRect(x:50,y:33,width:25,height:31)),color:rigGold,width:1.8,depth:2,metal:0.65),z:front+2.4)
            accessory.childNodes.last?.pivot=SCNMatrix4MakeTranslation(14.5,-0.5,0);accessory.childNodes.last?.position.x=14.5;accessory.childNodes.last?.position.y = -0.5
            var arm=Path();arm.move(to:CGPoint(x:75,y:51));arm.addQuadCurve(to:CGPoint(x:86,y:48),control:CGPoint(x:82,y:56));attach(rigStroke(arm,color:rigGold,width:1.4,metal:0.55))
            attach(rigShape(Path(ellipseIn:CGRect(x:84,y:45,width:5,height:5)),color:rigGold,depth:2.2,bevel:1),z:front+1.5)
        case .toni:
            var wax=Path()
            for n in 0...80 {let a=Double(n)*Double.pi*2/80,r=8+sin(a*8)*0.4,point=CGPoint(x:81+cos(a)*r,y:33+sin(a)*r);if n==0 {wax.move(to:point)} else {wax.addLine(to:point)}};wax.closeSubpath()
            let seal=rigShape(wax,color:rigLilac,depth:3,bevel:1.2);attach(seal,z:front+2)
            attach(rigStroke(Path(ellipseIn:CGRect(x:75,y:27,width:12,height:12)),color:rigRgb(0.78,0.69,0.94),width:0.7,depth:0.8),z:front+4)
            let pen=rigPolygon([(81,28),(85,34),(83,38),(79,38),(77,34)],radius:0.6);attach(rigShape(pen,color:rigRgb(0.51,0.40,0.74),depth:0.6,bevel:0.2),z:front+5)
        }
    }
    func updateEyes(open:Double,joy:Double,gaze:CGSize,wink:Double,anger:Double) {
        // Blinks and winks scale a persistent mesh. They never tessellate SCNShape
        // or dispose Metal buffers at display frequency. Expressions have 13 × 7
        // bounded variants per eye, independent of blink/open/gaze values.
        let joyStep = min(12, max(0, Int((joy * 12).rounded())))
        let angerStep = min(6, max(0, Int((anger / 3).rounded())))
        let j = Double(joyStep) / 12, a = Double(angerStep) * 3
        let baseHeight = hero == .ada ? 11.0 : 20.0
        let centers = hero == .gantt ? [34.0,59.0] : hero == .rita ? [36.0,62.0] : [34.0,62.0]
        for (index, eye) in eyes.enumerated() {
            let key = "\(index):\(joyStep):\(angerStep)"
            if eyeKeys[index] != key || eye.geometry == nil {
                if eyeCache[key] == nil {
                    let width = (hero == .ada ? 11.0 : 9.5) + j * 3.5
                    let rect = CGRect(x:48-width/2,y:48-baseHeight/2,width:width,height:baseHeight)
                    var path = rigEyePath(rect:rect,joy:j,pixel:hero == .ada)
                    if a > 2 {
                        let drop = rect.height * 0.30 * a / 18
                        var cut = Path(); cut.move(to:CGPoint(x:rect.minX,y:rect.minY+(index == 0 ? 0 : drop)))
                        cut.addLine(to:CGPoint(x:rect.maxX,y:rect.minY+(index == 0 ? drop : 0)))
                        cut.addLine(to:CGPoint(x:rect.maxX,y:rect.midY))
                        cut.addCurve(to:CGPoint(x:rect.midX,y:rect.maxY),control1:CGPoint(x:rect.maxX,y:rect.maxY),control2:CGPoint(x:rect.midX+rect.width/3,y:rect.maxY))
                        cut.addCurve(to:CGPoint(x:rect.minX,y:rect.midY),control1:CGPoint(x:rect.midX-rect.width/3,y:rect.maxY),control2:CGPoint(x:rect.minX,y:rect.maxY)); cut.closeSubpath(); path = cut
                    }
                    let geometry = SCNShape(path:rigNsPath(path),extrusionDepth:0.9)
                    geometry.chamferRadius = hero == .ada ? 0.4 : 0.7
                    geometry.materials = [eyeMaterial]; eyeCache[key] = geometry
                }
                eye.geometry = eyeCache[key]; eyeKeys[index] = key
            }
            eye.scale.y = CGFloat(max(1.8/baseHeight, open * (index == 1 ? 1-wink : 1)))
            eye.position.x = CGFloat(centers[index]-48+gaze.width)
            eye.position.y = CGFloat(-gaze.height); eye.eulerAngles.z = 0
        }
    }
}

@preconcurrency import AppKit
@preconcurrency import SceneKit

// A closed, thin, curved sheet with front/back normals, not a flat rotating sticker.
func rigCurledPaperHand()->SCNNode {
    let nu=32,nv=8
    var vertices:[SCNVector3]=[],normals:[SCNVector3]=[],uv:[CGPoint]=[]
    for side in [1.0,-1.0] {
        for i in 0...nu {for j in 0...nv {
            let u=Double(i)/Double(nu),v=Double(j)/Double(nv)*2-1
            let half=8*(1-u*0.82)
            let x = -28*u,y = -4*u+sin(u*Double.pi)*6+v*half
            let z=0.8+sin(u*Double.pi)*9+u*2+v*v*1.2+side*0.55
            vertices.append(SCNVector3(x,y,z))
            uv.append(CGPoint(x:u,y:(v+1)/2))
            let nx=(9*Double.pi*cos(u*Double.pi)+2)/28,ny = -2.4*v/max(1,half)
            let length=sqrt(nx*nx+ny*ny+1)
            normals.append(SCNVector3(side*nx/length,side*ny/length,side/length))
        }}
    }
    let count=(nu+1)*(nv+1)
    var indices:[Int32]=[]
    func tri(_ a:Int,_ b:Int,_ c:Int){indices += [Int32(a),Int32(b),Int32(c)]}
    for i in 0..<nu {for j in 0..<nv {
        let a=i*(nv+1)+j,b=(i+1)*(nv+1)+j,c=a+1,d=b+1
        tri(a,c,b);tri(b,c,d)
        tri(a+count,b+count,c+count);tri(b+count,d+count,c+count)
    }}
    var edge:[Int]=[]
    for j in 0...nv {edge.append(j)}
    for i in 1...nu {edge.append(i*(nv+1)+nv)}
    for j in (0..<nv).reversed() {edge.append(nu*(nv+1)+j)}
    for i in (1..<nu).reversed() {edge.append(i*(nv+1))}
    for i in edge.indices {
        let a=edge[i],b=edge[(i+1)%edge.count]
        tri(a,b,a+count);tri(b,b+count,a+count)
    }
    let element=SCNGeometryElement(indices:indices,primitiveType:.triangles)
    let geometry=SCNGeometry(sources:[SCNGeometrySource(vertices:vertices),SCNGeometrySource(normals:normals),SCNGeometrySource(textureCoordinates:uv)],elements:[element])
    let mat=rigMaterial(rigCream);mat.roughness.contents=0.55;geometry.materials=[mat]
    return SCNNode(geometry:geometry)
}
