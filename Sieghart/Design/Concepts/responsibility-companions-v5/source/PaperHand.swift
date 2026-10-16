import AppKit
import SceneKit

// A closed, thin, curved sheet with front/back normals, not a flat rotating sticker.
func curledPaperHand()->SCNNode {
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
    let mat=material(cream);mat.roughness.contents=0.55;geometry.materials=[mat]
    return SCNNode(geometry:geometry)
}
