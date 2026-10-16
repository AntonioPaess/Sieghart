import AppKit
import SceneKit
import SwiftUI

enum Hero: String, CaseIterable {
    case sig,rita,ada,gantt,elinor,toni
    var name:String {rawValue.prefix(1).uppercased()+rawValue.dropFirst()}
    var color:NSColor {
        switch self {
        case .sig: rgb(0.13,0.15,0.15)
        case .rita: rgb(0.63,0.77,0.57)
        case .ada: rgb(1,0.76,0.34)
        case .gantt: rgb(0.69,0.64,0.87)
        case .elinor: rgb(0.98,0.83,0.71)
        case .toni: rgb(1,0.94,0.83)
        }
    }
}
func rgb(_ r:Double,_ g:Double,_ b:Double)->NSColor {NSColor(srgbRed:r,green:g,blue:b,alpha:1)}
let cream=rgb(1,0.94,0.82), coral=rgb(0.96,0.55,0.44), mint=rgb(0.60,0.82,0.62), lilac=rgb(0.69,0.59,0.88), ink=rgb(0.07,0.09,0.09), gold=rgb(0.81,0.56,0.22)

var paperTextures:[String:NSImage]=[:]
var pillowNormals:NSImage?=nil
func softNormals()->NSImage {
    if let saved=pillowNormals {return saved}
    let size=256,rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
    for y in 0..<size {for x in 0..<size {
        let nx=(Double(x)/255-0.5)*0.58,ny=(0.5-Double(y)/255)*0.64,nz=sqrt(max(0.01,1-nx*nx-ny*ny)),offset=y*rep.bytesPerRow+x*4
        for (i,v) in [nx,ny,nz].enumerated() {rep.bitmapData![offset+i]=UInt8((v*0.5+0.5)*255)}
        rep.bitmapData![offset+3]=255
    }}
    let image=NSImage(size:CGSize(width:size,height:size));image.addRepresentation(rep);pillowNormals=image;return image
}
func tactileTexture(_ color:NSColor)->NSImage {
    let c=color.usingColorSpace(.sRGB)!,key="\(c.redComponent)-\(c.greenComponent)-\(c.blueComponent)"
    if let saved=paperTextures[key] {return saved}
    let size=256,rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:size*4,bitsPerPixel:32)!
    var seed:UInt64=0xAB42
    for y in 0..<size {for x in 0..<size {
        seed=seed &* 6364136223846793005 &+ 1442695040888963407
        let grain=(Double((seed>>32)&255)/255-0.5)*0.028
        let offset=y*rep.bytesPerRow+x*4
        for (i,v) in [c.redComponent,c.greenComponent,c.blueComponent].enumerated() {rep.bitmapData![offset+i]=UInt8(max(0,min(255,(v+grain)*255)))}
        rep.bitmapData![offset+3]=255
    }}
    let image=NSImage(size:CGSize(width:size,height:size));image.addRepresentation(rep);paperTextures[key]=image;return image
}

func material(_ color:NSColor,metal:Double=0)->SCNMaterial {
    let m=SCNMaterial();m.lightingModel = .physicallyBased
    m.diffuse.contents=metal>0 ? color : tactileTexture(color);m.roughness.contents=metal>0 ? 0.36 : 0.66;m.metalness.contents=metal
    m.specular.contents=NSColor(white:0.34,alpha:1);m.isDoubleSided=true
    return m
}
func nsPath(_ path:Path)->NSBezierPath {
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
func polygon(_ points:[(Double,Double)],radius:Double=0)->Path {
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
func bodyPath(_ h:Hero)->Path {
    switch h {
    case .sig:return Path(roundedRect:CGRect(x:7,y:25,width:82,height:48),cornerRadius:23)
    case .ada:return polygon([(29,13),(67,13),(67,22),(78,22),(78,33),(85,33),(85,66),(78,66),(78,79),(18,79),(18,66),(11,66),(11,33),(18,33),(18,22),(29,22)],radius:1)
    case .rita:
        var p=Path();p.move(to:CGPoint(x:35,y:8))
        p.addCurve(to:CGPoint(x:77,y:35),control1:CGPoint(x:49,y:5),control2:CGPoint(x:73,y:16))
        p.addCurve(to:CGPoint(x:79,y:61),control1:CGPoint(x:84,y:44),control2:CGPoint(x:84,y:55))
        p.addCurve(to:CGPoint(x:47,y:82),control1:CGPoint(x:79,y:80),control2:CGPoint(x:62,y:82))
        p.addCurve(to:CGPoint(x:15,y:62),control1:CGPoint(x:26,y:82),control2:CGPoint(x:13,y:77))
        p.addCurve(to:CGPoint(x:30,y:34),control1:CGPoint(x:15,y:49),control2:CGPoint(x:25,y:40))
        p.addCurve(to:CGPoint(x:35,y:8),control1:CGPoint(x:40,y:20),control2:CGPoint(x:37,y:15));p.closeSubpath();return p
    case .gantt:return Path(roundedRect:CGRect(x:13,y:15,width:73,height:73),cornerRadius:15)
    case .elinor:return polygon([(20,23),(73,23),(90,50),(72,76),(20,76),(7,50)],radius:4)
    case .toni:
        var p=Path(roundedRect:CGRect(x:17,y:20,width:64,height:63),cornerRadius:15)
        p.addPath(polygon([(27,73),(11,72),(24,90),(37,78)],radius:3));return p
    }
}
func shape(_ path:Path,color:NSColor,depth:Double=12,bevel:Double=3,side:NSColor?=nil)->SCNNode {
    let s=SCNShape(path:nsPath(path),extrusionDepth:depth);s.chamferRadius=bevel
    let front=material(color),edge=material(side ?? color)
    s.materials=[front,edge,edge,front,edge]
    let n=SCNNode(geometry:s);return n
}
func curvedSurface(_ path:Path,color:NSColor,z:Double,inset:Double,height:Double)->SCNNode {
    var lines:[(CGPoint,CGPoint)]=[],current=CGPoint.zero,start=CGPoint.zero
    func line(_ end:CGPoint) {lines.append((current,end));current=end}
    path.cgPath.applyWithBlock {ptr in
        let e=ptr.pointee
        switch e.type {
        case .moveToPoint:current=e.points[0];start=current
        case .addLineToPoint:line(e.points[0])
        case .addQuadCurveToPoint:
            let a=current,b=e.points[0],c=e.points[1]
            for i in 1...16 {let t=Double(i)/16,u=1-t;line(CGPoint(x:u*u*a.x+2*u*t*b.x+t*t*c.x,y:u*u*a.y+2*u*t*b.y+t*t*c.y))}
        case .addCurveToPoint:
            let a=current,b=e.points[0],c=e.points[1],d=e.points[2]
            for i in 1...24 {let t=Double(i)/24,u=1-t;line(CGPoint(x:u*u*u*a.x+3*u*u*t*b.x+3*u*t*t*c.x+t*t*t*d.x,y:u*u*u*a.y+3*u*u*t*b.y+3*u*t*t*c.y+t*t*t*d.y))}
        case .closeSubpath:line(start)
        @unknown default:break
        }
    }
    func distance(_ p:CGPoint)->Double {
        var smallest=Double.greatestFiniteMagnitude
        for (a,b) in lines {
            let dx=b.x-a.x,dy=b.y-a.y,len=dx*dx+dy*dy,t=max(0,min(1,((p.x-a.x)*dx+(p.y-a.y)*dy)/max(0.0001,len)))
            smallest=min(smallest,hypot(p.x-a.x-dx*t,p.y-a.y-dy*t))
        };return smallest
    }
    let steps=96
    var vertices:[SIMD3<Float>]=[],normals:[SIMD3<Float>]=[],uv:[CGPoint]=[],grid=[Int32](repeating:-1,count:(steps+1)*(steps+1)),indices:[Int32]=[]
    for row in 0...steps {for col in 0...steps {
        let p=CGPoint(x:col,y:row),d=distance(p)
        guard path.contains(p),d>=inset else {continue}
        let h=height*(1-exp(-(d-inset)/9))
        grid[row*(steps+1)+col]=Int32(vertices.count)
        vertices.append(SIMD3(Float(col)-48,48-Float(row),Float(z+h)));normals.append(.zero);uv.append(CGPoint(x:Double(col)/96,y:Double(row)/96))
    }}
    func triangle(_ a:Int32,_ b:Int32,_ c:Int32) {
        guard min(a,min(b,c))>=0 else {return}
        indices.append(contentsOf:[a,b,c]);let i=Int(a),j=Int(b),k=Int(c),n=simd_cross(vertices[j]-vertices[i],vertices[k]-vertices[i])
        normals[i]+=n;normals[j]+=n;normals[k]+=n
    }
    for row in 0..<steps {for col in 0..<steps {
        let a=grid[row*(steps+1)+col],b=grid[row*(steps+1)+col+1],c=grid[(row+1)*(steps+1)+col],d=grid[(row+1)*(steps+1)+col+1]
        triangle(a,c,b);triangle(b,c,d)
    }}
    func scn(_ p:SIMD3<Float>)->SCNVector3 {SCNVector3(CGFloat(p.x),CGFloat(p.y),CGFloat(p.z))}
    let v=SCNGeometrySource(vertices:vertices.map(scn)),n=SCNGeometrySource(normals:normals.map{scn(simd_length($0)>0 ? simd_normalize($0) : SIMD3(0,0,1))}),t=SCNGeometrySource(textureCoordinates:uv)
    let data=indices.withUnsafeBytes{Data($0)},e=SCNGeometryElement(data:data,primitiveType:.triangles,primitiveCount:indices.count/3,bytesPerIndex:4)
    let geometry=SCNGeometry(sources:[v,n,t],elements:[e]);geometry.materials=[material(color)]
    return SCNNode(geometry:geometry)
}
func stroke(_ path:Path,color:NSColor,width:Double=2,depth:Double=1.4,metal:Double=0)->SCNNode {
    let root=SCNNode(),mat=material(color,metal:metal)
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
    return root
}
func eyePath(rect:CGRect,joy:Double,pixel:Bool)->Path {
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

final class CharacterModel {
    let hero:Hero
    let root=SCNNode(),head=SCNNode(),accessory=SCNNode(),activity=SCNNode()
    var eyes:[SCNNode]=[]
    var front:Double=10
    var paper:SCNNode?
    var marker:SCNNode?
    init(_ hero:Hero) {
        self.hero=hero;root.addChildNode(head)
        let depth=hero == .sig ? 24.0 : hero == .rita ? 22 : 16
        let body=shape(bodyPath(hero),color:hero.color,depth:depth,bevel:hero == .ada ? 0.8 : hero == .rita ? 2.5 : hero == .gantt ? 3.5 : 6,side:hero == .elinor ? rgb(0.88,0.53,0.47) : nil)
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
                let page=shape(Path(roundedRect:CGRect(x:16+offset,y:18+offset,width:64,height:64),cornerRadius:12),color:index==0 ? cream : rgb(0.92,0.84,0.70),depth:1.5,bevel:0.5)
                page.position.z=CGFloat(front+Double(3-index)*2.2);head.addChildNode(page)
                if index==0 {
                    page.geometry?.shaderModifiers=[.geometry:roundedLighting]
                }
            }
            front+=7.5
        }
        if hero == .toni {
            let fold=shape(polygon([(69,20),(82,21),(91,63),(80,77),(68,62)],radius:3),color:coral,depth:3,bevel:1)
            fold.position.z=CGFloat(front-0.7);head.addChildNode(fold)
            var tail=Path();tail.move(to:CGPoint(x:26,y:65));tail.addCurve(to:CGPoint(x:9,y:67),control1:CGPoint(x:19,y:61),control2:CGPoint(x:12,y:63));tail.addCurve(to:CGPoint(x:22,y:88),control1:CGPoint(x:10,y:77),control2:CGPoint(x:16,y:78));tail.addCurve(to:CGPoint(x:31,y:78),control1:CGPoint(x:28,y:90),control2:CGPoint(x:33,y:83));tail.addCurve(to:CGPoint(x:26,y:65),control1:CGPoint(x:31,y:74),control2:CGPoint(x:30,y:68));tail.closeSubpath()
            let flap=shape(tail,color:cream,depth:2.5,bevel:1.2)
            flap.pivot=SCNMatrix4MakeTranslation(-20,-18,0);flap.position=SCNVector3(-20,-18,front+1);head.addChildNode(flap);paper=flap
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
            attach(shape(polygon([(77,20),(85,29),(77,38),(69,29)],radius:1),color:mint,depth:3,bevel:0.7))
            attach(shape(polygon([(77,20),(77,29),(85,29)]),color:rgb(0.77,0.94,0.73),depth:0.4,bevel:0.1),z:front+4)
        case .rita:
            var cuff=Path();cuff.move(to:CGPoint(x:52,y:12));cuff.addCurve(to:CGPoint(x:74,y:76),control1:CGPoint(x:81,y:28),control2:CGPoint(x:89,y:54));attach(stroke(cuff,color:cream,width:2.2,depth:1.6),z:front+0.2)
            var heart=Path();heart.move(to:CGPoint(x:77,y:39));heart.addCurve(to:CGPoint(x:68,y:29),control1:CGPoint(x:72,y:35),control2:CGPoint(x:67,y:33));heart.addCurve(to:CGPoint(x:77,y:28),control1:CGPoint(x:65,y:23),control2:CGPoint(x:73,y:22));heart.addCurve(to:CGPoint(x:85,y:30),control1:CGPoint(x:81,y:23),control2:CGPoint(x:88,y:25));heart.addCurve(to:CGPoint(x:77,y:39),control1:CGPoint(x:85,y:34),control2:CGPoint(x:81,y:36))
            heart=heart.applying(CGAffineTransform(translationX:77,y:31).scaledBy(x:0.82,y:0.82).translatedBy(x:-77,y:-31));attach(stroke(heart,color:coral,width:2.1,depth:1.5),z:front+2)
            accessory.childNodes.last?.pivot=SCNMatrix4MakeTranslation(29,17,0);accessory.childNodes.last?.position.x=29;accessory.childNodes.last?.position.y=17
        case .ada:
            var p=Path();p.move(to:CGPoint(x:72,y:22));p.addLine(to:CGPoint(x:67,y:27));p.addLine(to:CGPoint(x:72,y:32));p.move(to:CGPoint(x:80,y:22));p.addLine(to:CGPoint(x:85,y:27));p.addLine(to:CGPoint(x:80,y:32));attach(stroke(p,color:rgb(0.16,0.63,0.58),width:3,depth:1.8))
        case .gantt:
            for x in [Double(31),61] {
                attach(shape(Path(roundedRect:CGRect(x:x,y:10,width:5,height:17),cornerRadius:2.5),color:lilac,depth:4,bevel:1),z:front+1)
            }
            attach(shape(polygon([(78,70),(85,70),(85,84),(81.5,81),(78,84)],radius:0.5),color:coral,depth:2,bevel:0.6),z:front+0.5)
            let page=shape(polygon([(80,20),(77,31),(90,39)],radius:2),color:cream,depth:1.2,bevel:0.4);attach(page,z:front+2);paper=page;page.opacity=0
        case .elinor:
            attach(stroke(Path(ellipseIn:CGRect(x:50,y:33,width:25,height:31)),color:gold,width:1.8,depth:2,metal:0.65),z:front+2.4)
            accessory.childNodes.last?.pivot=SCNMatrix4MakeTranslation(14.5,-0.5,0);accessory.childNodes.last?.position.x=14.5;accessory.childNodes.last?.position.y = -0.5
            var arm=Path();arm.move(to:CGPoint(x:75,y:51));arm.addQuadCurve(to:CGPoint(x:86,y:48),control:CGPoint(x:82,y:56));attach(stroke(arm,color:gold,width:1.4,metal:0.55))
            attach(shape(Path(ellipseIn:CGRect(x:84,y:45,width:5,height:5)),color:gold,depth:2.2,bevel:1),z:front+1.5)
        case .toni:
            var wax=Path()
            for n in 0...80 {let a=Double(n)*Double.pi*2/80,r=8+sin(a*8)*0.4,point=CGPoint(x:81+cos(a)*r,y:33+sin(a)*r);if n==0 {wax.move(to:point)} else {wax.addLine(to:point)}};wax.closeSubpath()
            let seal=shape(wax,color:lilac,depth:3,bevel:1.2);attach(seal,z:front+2)
            attach(stroke(Path(ellipseIn:CGRect(x:75,y:27,width:12,height:12)),color:rgb(0.78,0.69,0.94),width:0.7,depth:0.8),z:front+4)
            let pen=polygon([(81,28),(85,34),(83,38),(79,38),(77,34)],radius:0.6);attach(shape(pen,color:rgb(0.51,0.40,0.74),depth:0.6,bevel:0.2),z:front+5)
        }
    }
    func updateEyes(open:Double,joy:Double,gaze:CGSize,wink:Double,anger:Double) {
        for (index,eye) in eyes.enumerated() {
            let width=(hero == .ada ? 11.0 : 9.5)+joy*3.5
            let height=max(1.8,(hero == .ada ? 11.0 : 20.0)*open*(index==1 ? 1-wink : 1))
            let centers:[Double]=hero == .gantt ? [34,59] : hero == .rita ? [36,62] : [34,62]
            let rect=CGRect(x:centers[index]-width/2,y:48-height/2,width:width,height:height)
            var path=eyePath(rect:rect,joy:joy,pixel:hero == .ada)
            if anger>2 {
                let f=anger/18,drop=rect.height*0.30*f
                var cut=Path();cut.move(to:CGPoint(x:rect.minX,y:rect.minY+(index==0 ? 0 : drop)))
                cut.addLine(to:CGPoint(x:rect.maxX,y:rect.minY+(index==0 ? drop : 0)))
                cut.addLine(to:CGPoint(x:rect.maxX,y:rect.midY))
                cut.addCurve(to:CGPoint(x:rect.midX,y:rect.maxY),control1:CGPoint(x:rect.maxX,y:rect.maxY),control2:CGPoint(x:rect.midX+rect.width/3,y:rect.maxY))
                cut.addCurve(to:CGPoint(x:rect.minX,y:rect.midY),control1:CGPoint(x:rect.midX-rect.width/3,y:rect.maxY),control2:CGPoint(x:rect.minX,y:rect.maxY));cut.closeSubpath();path=cut
            }
            let geo=SCNShape(path:nsPath(path),extrusionDepth:0.9);geo.chamferRadius=hero == .ada ? 0.4 : 0.7
            let eyeMat=material(hero == .sig ? cream : ink);eyeMat.roughness.contents=0.42;eyeMat.specular.contents=NSColor(white:0.55,alpha:1);geo.materials=[eyeMat]
            eye.geometry=geo;eye.position.x=CGFloat(gaze.width);eye.position.y=CGFloat(-gaze.height)
            // Tilt each eye around its own center, preserving the face positions.
            eye.pivot=SCNMatrix4MakeTranslation(CGFloat(centers[index]-48),0,0)
            eye.position.x += CGFloat(centers[index]-48)
            eye.eulerAngles.z=0
        }
    }
}
