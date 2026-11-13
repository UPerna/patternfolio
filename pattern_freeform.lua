-- Lin and Kaplan (freeform finite Euclidean profile), Sections 3 and 4.
local P=require("pattern")
local Packing=require("pattern_circle_packing")
local PIC=require("pattern_islamic")
local N=require("pattern_predicates")
local M={}
local function sub(a,b) return {a[1]-b[1],a[2]-b[2]} end
local function add(a,b,k) return {a[1]+k*b[1],a[2]+k*b[2]} end
local function dot(a,b) return a[1]*b[1]+a[2]*b[2] end
local function det(a,b) return a[1]*b[2]-a[2]*b[1] end
local function norm(a) return math.sqrt(dot(a,a)) end
local function unit(a)
  local length=norm(a)
  assert(length>0,"freeform-zero-vector")
  return {a[1]/length,a[2]/length}
end
local function mid(a,b) return add(a,sub(b,a),.5) end
local function keys(t)
  local result={}
  for k in pairs(t) do result[#result+1]=k end
  table.sort(result,P.byte_less)
  return result
end
local function key(a,b)
  if P.byte_less(b,a) then return b.."+"..a end
  return a.."+"..b
end
local function cycle_points(vertices,ids)
  local p={}
  for i,id in ipairs(ids) do p[i]=assert(vertices[id],"freeform-patch-vertex") end
  return p
end
local function check_face(polygon)
  for i,p in ipairs(polygon) do
    for j,q in ipairs(polygon) do
      if j~=i and j~=i%#polygon+1 then
        assert(N.orient2d(p,polygon[i%#polygon+1],q)>0,"freeform-nonconvex-polygon")
      end
    end
  end
end
local function tri_incenter(a,b,c)
  local wa,wb,wc=norm(sub(b,c)),norm(sub(a,c)),norm(sub(a,b))
  local sum=wa+wb+wc
  return {(wa*a[1]+wb*b[1]+wc*c[1])/sum,(wa*a[2]+wb*b[2]+wc*c[2])/sum}
end

function M.patch(packing,tau)
  assert(type(tau)=="number" and tau>=.5 and tau<1,"freeform-tau")
  local disk=Packing.disk(packing.complex)
  local C=packing.circles
  local vertices,faces,triangle_arcs={},{},{}
  for i,f in ipairs(disk.faces) do
    for j,u in ipairs(f) do
      local v,w=f[j%3+1],f[(j+1)%3+1]
      triangle_arcs[u.."/"..v.."/"..w]=i
    end
  end
  for _,u in ipairs(disk.ids) do
    local circle=C[u]
    local neighbors=keys(disk.adjacent[u])
    local angles={}
    for _,v in ipairs(neighbors) do
      local d=sub(C[v].center,circle.center)
      angles[v]=math.atan(d[2],d[1])
    end
    table.sort(neighbors,function(a,b)return angles[a]<angles[b] end)
    local cycle={}
    for i,v in ipairs(neighbors) do
      local w=neighbors[i%#neighbors+1]
      local theta=angles[v]
      local spread=(angles[w]-theta)%(2*math.pi)
      local face=triangle_arcs[u.."/"..v.."/"..w]
      assert(face or circle.boundary,"freeform-arc-link")
      assert(not face or spread<math.pi,"freeform-triangle-arc")
      local tangent="t/"..u.."/"..v
      local arc="arc/"..u.."/"..(face or "exterior")
      assert(not vertices[arc],"freeform-multiple-exterior-arcs")
      vertices[tangent]=add(circle.center,{math.cos(theta),math.sin(theta)},tau*circle.radius)
      local phi=theta+spread/2
      vertices[arc]=add(circle.center,{math.cos(phi),math.sin(phi)},tau*circle.radius)
      cycle[#cycle+1]=tangent;cycle[#cycle+1]=arc
    end
    if not circle.boundary then faces[#faces+1]={id="wheel/"..u,kind="cyclic",circle=u,vertices=cycle} end
  end
  for i,f in ipairs(disk.faces) do
    local center="incenter/"..i
    vertices[center]=tri_incenter(C[f[1]].center,C[f[2]].center,C[f[3]].center)
    for j,u in ipairs(f) do
      local v=f[j%3+1]
      local cycle={"arc/"..u.."/"..i,"t/"..u.."/"..v,"t/"..v.."/"..u,"arc/"..v.."/"..i,center}
      faces[#faces+1]={id="pentagon/"..i.."/"..j,kind="filler",triangle=i,vertices=cycle}
    end
  end
  local edges={}
  for _,f in ipairs(faces) do
    check_face(cycle_points(vertices,f.vertices))
    for i,a in ipairs(f.vertices) do
      local b=f.vertices[i%#f.vertices+1]
      local id=key(a,b)
      local e=edges[id]
      if not e then edges[id]={from=a,to=b,faces={f.id}}
      else
        assert(#e.faces==1 and a==e.to and b==e.from,"freeform-patch-incidence")
        e.faces[2]=f.id
      end
    end
  end
  return {vertices=vertices,faces=faces,edges=edges}
end

local function wheel_alpha(n,theta)
  local a=math.pi/n
  return 1-2*math.sin(a)*math.sin(math.pi/2-a)*math.sin(theta-a)/math.sin(math.pi/2+2*a-theta)
end
local function wheel(face,polygon,circle,tau,angle)
  local n=#polygon
  local alpha=wheel_alpha(n,math.rad(angle))
  local radius=alpha*tau*circle.radius*math.cos(math.pi/n)
  assert(alpha>0 and alpha<1 and radius>0,"freeform-wheel-angle")
  local center=circle.center
  local mids,paths={},{}
  for i,p in ipairs(polygon) do mids[i]=mid(p,polygon[i%n+1]) end
  for i,a in ipairs(mids) do
    local j=(i+1)%n+1
    local b=mids[j]
    local chord=unit(sub(a,b))
    local normal={-chord[2],chord[1]}
    local m=mid(a,b)
    local foot=add(center,chord,dot(sub(center,m),chord)*-1)
    local h=radius^2-dot(sub(foot,center),sub(foot,center))
    assert(h>0,"freeform-wheel-no-bisector-intersection:"..face.id)
    local sign=dot(sub(m,center),normal)>=0 and 1 or -1
    local meet=add(foot,normal,sign*math.sqrt(h))
    for k,p in ipairs(polygon) do
      assert(det(sub(p,polygon[k%n+1]),sub(p,meet))>=-1e-10,"freeform-wheel-outside-polygon")
    end
    paths[#paths+1]={from=i,to=j,bend=meet}
  end
  return mids,paths,alpha
end

function M.ornament(packing,patch,tau,angle)
  local nodes,links,ports,degree={},{},{},{}
  local wheel_directions,wheel_evidence={},{}
  local function contact(face,index,side,point,direction)
    local ids=face.vertices
    local seam=key(ids[index],ids[index%#ids+1])
    local id="contact/"..seam.."/"..(side==1 and "plus" or "minus")
    local old=ports[id]
    if old then
      assert(#old.faces==1 and norm(sub(nodes[id],point))<1e-10,"freeform-seam-position")
      assert(norm(add(old.direction,direction,1))<1e-9,"freeform-seam-direction")
      old.faces[2]=face.id
    else
      nodes[id]=point
      ports[id]={faces={face.id},direction=direction,scaffold_edge=seam}
    end
    return id,seam
  end
  local function add_bend(face,i,point,a,b)
    local name=face.id.."/"..i
    local bend="bend/"..name
    nodes[bend]=point
    for _,v in ipairs{a,b} do degree[v]=(degree[v]or 0)+1 end
    links[#links+1]={id="path/"..name.."/a",from=a,to=bend,face=face.id}
    links[#links+1]={id="path/"..name.."/b",from=bend,to=b,face=face.id}
  end
  for _,face in ipairs(patch.faces) do
    if face.kind=="cyclic" then
      local polygon=cycle_points(patch.vertices,face.vertices)
      local circle=packing.circles[face.circle]
      local mids,paths,alpha=wheel(face,polygon,circle,tau,angle)
      wheel_evidence[face.id]={order=#polygon,alpha=alpha,circle=face.circle}
      for i,p in ipairs(paths) do
        local a,b=mids[p.from],mids[p.to]
        local direction1,direction2=unit(sub(p.bend,a)),unit(sub(p.bend,b))
        local port1,e1=contact(face,p.from,1,a,direction1)
        local port2,e2=contact(face,p.to,-1,b,direction2)
        wheel_directions[e1]=wheel_directions[e1] or {}
        wheel_directions[e2]=wheel_directions[e2] or {}
        wheel_directions[e1][1]={-direction1[1],-direction1[2]}
        wheel_directions[e2][-1]={-direction2[1],-direction2[2]}
        add_bend(face,i,p.bend,port1,port2)
      end
    end
  end
  for _,face in ipairs(patch.faces) do
    if face.kind=="filler" then
      local polygon=cycle_points(patch.vertices,face.vertices)
      local function copy(i,side)
        local k=key(face.vertices[i],face.vertices[i%#face.vertices+1])
        local seam=wheel_directions[k]
        return seam and seam[side]
      end
      local motif=PIC.motif(polygon,angle,0,nil,copy)
      for _,r in ipairs(motif.rays) do r.port=contact(face,r.edge,r.side,r.origin,r.direction) end
      for i,p in ipairs(motif.paths) do
        add_bend(face,i,p.point,motif.rays[p.first].port,motif.rays[p.second].port)
      end
    end
  end
  for id,p in pairs(ports) do
    assert(degree[id]==#p.faces and #p.faces==#patch.edges[p.scaffold_edge].faces,"freeform-seam-incidence")
  end
  return {nodes=nodes,links=links,ports=ports,wheels=wheel_evidence}
end

local function records(graph)
  local vertices,contacts=P.array(),P.array()
  for _,id in ipairs(keys(graph.nodes)) do vertices[#vertices+1]={id=id,point=graph.nodes[id]} end
  for _,id in ipairs(keys(graph.ports)) do
    local p=graph.ports[id]
    contacts[#contacts+1]={id=id,faces=p.faces,direction=p.direction,scaffold_edge=p.scaffold_edge}
  end
  return {vertices=vertices,edges=graph.links},contacts
end
function M.definition()
  return P.definition({id="ornament/islamic-freeform",version="1",family="finite-circle-packing",
    units="cm",capabilities={"graph"},parameters={
      tau={type="number",minimum=.5,maximum=.99},
      contact_angle={type="number",minimum=45,maximum=80},
      tolerance={type="number",minimum=1e-13,maximum=1e-7},
      max_iterations={type="integer",minimum=1,maximum=3000}},
    transforms={metric_constrained=true,uniform_scale=true,reflection=false},
    assumptions={"Oriented triangular disk with positive source boundary radii",
      "Numerically validated circle packing and convex patch faces",
      "Complete wheel and greedy PIC pairing with shared contacts",
      "Outer faces expose patch boundary ports and no over/under is assigned"}})
end

local function solver_receipt(k)
  local p=k.packing
  return {algorithm=p.solver,status="converged",tolerance=p.tolerance,iterations=p.iterations,route=k.route,
    boundary_rule="csc(pi/(2*degree-2))-1",normalization=P.plain(p.normalization),
    maximum_angular_residual=p.maximum_angular_residual,maximum_tangency_residual=p.maximum_tangency_residual,
    minimum_nonedge_clearance=p.minimum_nonedge_clearance}
end
local function validate(instance)
  local k=P.plain(instance.extensions.freeform)
  assert(k.route=="computed" or k.route=="replayed","freeform-solver-route")
  Packing.validate(k.packing)
  local patch=M.patch(k.packing,k.tau)
  local ornament=M.ornament(k.packing,patch,k.tau,k.contact_angle)
  local graph,ports=records(ornament)
  assert(P.serialize(patch)==P.serialize(k.patch),"freeform-patch-certificate")
  assert(P.serialize(graph)==P.serialize(instance.structures.graph),"freeform-ornament-certificate")
  assert(P.serialize(ports)==P.serialize(k.contacts),"freeform-contacts-certificate")
  assert(P.serialize(ornament.wheels)==P.serialize(k.wheels),"freeform-wheels-certificate")
  return {ok=true,checks={"disk, tangency, nonedge clearance and normalization","cyclic polygon and filler incidence",
    "wheel equations and PIC seam continuity"},solver=solver_receipt(k)}
end
function M.validate(instance)
  return validate(P.instance(P.plain(instance),M.definition()))
end

function M.register(registry)
  local d=M.definition()
  local function validate_inputs(s)
    local inputs=P.plain(s.inputs)
    for k in pairs(inputs) do if k~="complex" and k~="panel" and k~="packing" then return false end end
    if next(P.plain(s.constraints)) then return false end
    if inputs.packing then
      return type(inputs.packing)=="table" and not inputs.complex and not inputs.panel
        and s.parameters.tolerance==nil and s.parameters.max_iterations==nil
    end
    return type(inputs.complex)=="table"
  end
  local function generate(s,context)
    local p,inputs=s.parameters,P.plain(s.inputs)
    local packing,route=inputs.packing,"replayed"
    if not packing then
      local faces=inputs.complex and inputs.complex.faces
      assert(type(faces)=="table","freeform-complex-required")
      local cap=p.max_iterations or 600
      packing=Packing.solve(inputs.complex,{panel=inputs.panel,tolerance=p.tolerance,iterations=cap,poll=function(n)context:consume("operations",n)end})
      route="computed"
    end
    Packing.validate(packing)
    local tau,angle=p.tau or .8,p.contact_angle or 72
    local patch=M.patch(packing,tau)
    for _,f in ipairs(patch.faces) do
      context:consume("objects",#f.vertices*8)
      context:consume("operations",4*(#f.vertices)^2)
    end
    local ornament=M.ornament(packing,patch,tau,angle)
    local graph,ports=records(ornament)
    return {id=s.id.."/freeform",definition_ref={id=d.id,version=d.version},frame=P.plain(context.frame),
      structures={graph=graph},provenance={generator=d.id,generator_version=d.version,seed=s.seed,
        construction="lin-kaplan-freeform-v1"},
      extensions={freeform={tau=tau,contact_angle=angle,packing=packing,route=route,patch=patch,
        contacts=ports,wheels=ornament.wheels}}}
  end
  registry:register(d,{validate_inputs=validate_inputs,generate=generate,validate=validate,lower=PIC.lower_graph})
  return d
end
return M
