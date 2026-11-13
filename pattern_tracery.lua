-- Havemann and Fellner, VAST 2004, §§2.2–2.5. Construction stays
-- analytic until lowering to the shared cubic drawing vocabulary.
local P,H,G=require("pattern"),require("pattern_hash"),require("pattern_geometry")
local M={VERSION="gothic-tracery-2d-v1"}
local pi,tau=math.pi,2*math.pi
local EPS=2e-11
local function point(x,y) return {x,y} end
local function polar(c,r,a) return {c[1]+r*math.cos(a),c[2]+r*math.sin(a)} end
local function distance(a,b) return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2) end
local function angle(c,p) return math.atan(p[2]-c[2],p[1]-c[1]) end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end

local function network()
  local vertices,edges,by_id,arcs,details=P.array(),P.array(),{},P.array(),{}
  local b={vertices=vertices,edges=edges,details=details}
  function b.vertex(id,p)
    local prior=by_id[id]
    if prior then assert(distance(prior,p)<EPS,"tracery-inconsistent-junction");return id end
    by_id[id]=p
    vertices[#vertices+1]={id=id,point=p}
    return id
  end
  function b.line(id,a,z)
    assert(distance(by_id[a],by_id[z])>EPS,"tracery-collapsed-jamb")
    edges[#edges+1]={id=id,from=a,to=z}
    details[id]={kind="line"}
  end
  function b.arc(id,a,z,c,r,start,sweep,role)
    assert(r>EPS and math.abs(sweep)>EPS and math.abs(sweep)<tau,"tracery-arc-domain")
    assert(distance(by_id[a],polar(c,r,start))<EPS and distance(by_id[z],polar(c,r,start+sweep))<EPS,
      "tracery-arc-endpoint")
    local arc={id=id,from=a,to=z,center=c,radius=r,start=start,sweep=sweep,role=role,breaks={}}
    arcs[#arcs+1]=arc
    return arc
  end
  function b.split(arc,id)
    local p=assert(by_id[id])
    local direction=arc.sweep>0 and 1 or -1
    local travel=(direction*(angle(arc.center,p)-arc.start))%tau
    assert(travel>EPS and travel<math.abs(arc.sweep)-EPS,"tracery-contact-outside-active-arc")
    assert(math.abs(distance(p,arc.center)-arc.radius)<EPS,"tracery-contact-off-circle")
    arc.breaks[#arc.breaks+1]={t=travel,id=id}
  end
  function b.finish()
    for _,arc in ipairs(arcs) do
      local direction=arc.sweep>0 and 1 or -1
      table.sort(arc.breaks,function(a,z)return a.t<z.t end)
      local start,from=0,arc.from
      arc.breaks[#arc.breaks+1]={t=math.abs(arc.sweep),id=arc.to}
      for i,s in ipairs(arc.breaks) do
        assert(s.t-start>EPS,"tracery-coincident-arc-splits")
        local id=arc.id.."/"..i
        edges[#edges+1]={id=id,from=from,to=s.id}
        details[id]={kind="arc",center=arc.center,radius=arc.radius,
          start=arc.start+direction*start,sweep=direction*(s.t-start),role=arc.role,source=arc.id}
        start,from=s.t,s.id
      end
    end
    return {vertices=vertices,edges=edges},details
  end
  function b.point(id) return assert(by_id[id]) end
  return b
end

local function arch(b,id,left,right,base,spring,excess,ends)
  local width=right-left
  local radius=width*excess
  local center=(right+left)/2
  local c=(excess-.5)*width
  local rise=math.sqrt(radius^2-c^2)
  local lc,rc={center+c,spring},{center-c,spring}
  local alpha=math.atan(rise,c)
  local apex=b.vertex(id.."/apex",{center,spring+rise})
  local first=b.arc(id.."/left",ends[1],apex,lc,radius,pi,-alpha,"arch")
  local second=b.arc(id.."/right",apex,ends[2],rc,radius,alpha,-alpha,"arch")
  return {id=id,left=left,right=right,base=base,spring=spring,excess=excess,
    radius=radius,axis=center,center_offset=c,apex=b.point(apex),centers={lc,rc},
    semantic=first.id.."/1"},first,second
end
local function ring(b,id,c,r,ports,meta)
  local ordered={}
  for i,p in ipairs(ports) do ordered[i]={id=p,a=angle(c,b.point(p))%tau} end
  table.sort(ordered,function(a,z)return a.a<z.a end)
  assert(#ordered>=3,"tracery-circle-ports")
  for i,p in ipairs(ordered) do
    local q=ordered[i%#ordered+1]
    local sweep=(q.a-p.a)%tau
    b.arc(id.."/arc/"..i,p.id,q.id,c,r,p.a,sweep,"circle")
  end
  meta.rings[#meta.rings+1]={id=id,center=c,radius=r,semantic=id.."/arc/1/1",ports=ports}
end
local function foils(b,id,c,r,n,theta,depth,meta,shared_tip,parent)
  local a=pi/n
  local s=math.sin(a)
  local radius=r*s/(1+s)
  local d=r-radius
  assert(radius>=.055,"tracery-foil-radius-limit")
  local feet,tips=P.array(),P.array()
  local record={id=id,parent=parent,center=c,container_radius=r,foil_radius=radius,
    count=n,angle=theta,depth=depth,petals=P.array()}
  meta.foils[#meta.foils+1]=record
  for i=1,n do
    local t=theta+(i-1)*2*a
    feet[i]=b.vertex(id.."/foot/"..i,polar(c,d*math.cos(a),t+a))
    tips[i]=b.vertex(i==1 and shared_tip or id.."/tip/"..i,polar(c,r,t))
  end
  for i=1,n do
    local t=theta+(i-1)*2*a
    local center=polar(c,d,t)
    local name=id.."/petal/"..i
    local arc=b.arc(name,feet[(i-2)%n+1],feet[i],center,radius,t-pi/2-a,pi+2*a,"foil")
    b.split(arc,tips[i])
    local child=depth>0 and name.."/child" or nil
    record.petals[i]={id=name,center=center,tip=tips[i],from=feet[(i-2)%n+1],to=feet[i],child=child}
    if child then foils(b,child,center,radius,3,t,depth-1,meta,tips[i],name) end
  end
  return tips
end

local function rosette_center(outer,inner)
  local r,s=outer.radius,inner.radius
  local a,b=outer.centers[2],inner.centers[2]
  local axis=outer.axis
  local lo,hi=math.max(outer.spring,inner.apex[2]),outer.apex[2]
  local function value(y)
    local p={axis,y}
    return distance(p,a)+distance(p,b)-r-s
  end
  assert(lo<hi and value(lo)<-EPS and value(hi)>EPS,"tracery-rosette-unbracketed")
  for _=1,60 do
    local y=(lo+hi)/2
    if value(y)<0 then lo=y else hi=y end
  end
  local c={axis,(lo+hi)/2}
  local radius=r-distance(c,a)
  assert(radius>.09 and math.abs(value(c[2]))<EPS,"tracery-rosette-residual")
  return c,radius
end
local function tangency(c,m,r)
  local d=distance(c,m)
  assert(d>EPS,"tracery-tangency-center")
  return {m[1]+r*(c[1]-m[1])/d,m[2]+r*(c[2]-m[2])/d}
end
local function construct(request,context)
  local frame,p=request.frame,request.parameters
  assert(frame.unit=="cm" and frame.dimension==2 and frame.handedness=="right","tracery-frame")
  local x,y=table.unpack(frame.origin)
  local b=network()
  local meta={profile=p.profile,arches=P.array(),rings=P.array(),foils=P.array(),contacts=P.array()}
  if p.profile=="rose" then
    assert(p.jamb==nil and p.excess==nil and p.drop==nil,"tracery-arch-parameters-on-rose")
    local radius=p.width/2
    local c={x+radius,y+radius}
    local ports=foils(b,"rose/foils",c,radius,p.foils or 6,pi/2,p.recursion or 0,meta)
    ring(b,"rose/border",c,radius,ports,meta)
  else
    assert(p.jamb and p.excess,"tracery-arch-parameters-required")
    assert(p.profile=="rosette" or (p.foils==nil and p.recursion==nil),"tracery-foils-require-rosette")
    local w,h,e,drop=p.width,p.jamb,p.excess,p.drop or 0
    assert(drop<h-.2,"tracery-collapsed-subwindow")
    local left,axis,right=x,x+w/2,x+w
    local spring,lower=y+h,y+h-drop
    local bl,bm,br=b.vertex("bottom/left",{left,y}),b.vertex("bottom/mid",{axis,y}),b.vertex("bottom/right",{right,y})
    local ll,rr=b.vertex("outer/left-spring",{left,spring}),b.vertex("outer/right-spring",{right,spring})
    local sl,sr=ll,rr
    if drop>EPS then
      sl=b.vertex("sub/left-spring",{left,lower})
      sr=b.vertex("sub/right-spring",{right,lower})
      b.line("jamb/left-upper",sl,ll)
      b.line("jamb/right-upper",sr,rr)
    else
      assert(drop==0,"tracery-near-zero-drop")
    end
    local sm=b.vertex("sub/mid-spring",{axis,lower})
    b.line("jamb/left",bl,sl);b.line("jamb/right",br,sr);b.line("jamb/mullion",bm,sm)
    b.line("sill/left",bl,bm);b.line("sill/right",bm,br)
    local outer,ol,orr=arch(b,"outer",left,right,y,spring,e,{ll,rr})
    local inner_a,_,il=arch(b,"sub/left",left,axis,y,lower,e,{sl,sm})
    local inner_b,ir=arch(b,"sub/right",axis,right,y,lower,e,{sm,sr})
    meta.arches={outer,inner_a,inner_b}
    if p.profile=="rosette" then
      local c,r=rosette_center(outer,inner_a)
      local ports=foils(b,"crown/foils",c,r,p.foils or 4,pi/2,p.recursion or 0,meta)
      for i,arc in ipairs{ol,orr,il,ir} do
        local q=tangency(c,arc.center,arc.radius)
        assert(math.abs(distance(c,q)-r)<EPS,"tracery-rosette-contact-residual")
        local id=b.vertex("crown/contact/"..i,q)
        b.split(arc,id)
        for _,port in ipairs(ports) do
          assert(distance(q,b.point(port))>EPS,"tracery-crown-contact-coincides-with-foil-tip")
        end
        ports[#ports+1]=id
        meta.contacts[i]={id=id,arc=arc.id,kind=i<=2 and "internal" or "external",center=c,radius=r}
      end
      ring(b,"crown/border",c,r,ports,meta)
    end
  end
  local graph,curves=b.finish()
  if context then context:consume("objects",#graph.vertices+#graph.edges);context:consume("operations",#graph.edges*8) end
  return graph,curves,meta
end

function M.definition()
  return P.definition({id="ornament/gothic-tracery",version="1",family="analytic-tracery-grammar",
    units="cm",capabilities={"graph"},parameters={
      profile={type="string",enum={"prototype","rosette","rose"},required=true},
      width={type="number",minimum=2,maximum=16,required=true},
      jamb={type="number",minimum=.5,maximum=18},excess={type="number",minimum=.55,maximum=1.8},
      drop={type="number",minimum=0,maximum=8},
      foils={type="integer",minimum=3,maximum=9},recursion={type="integer",minimum=0,maximum=2}},
    transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Two-centered pointed arch, dependent paired bays and tangent circular rosette",
      "Rounded foil arcs and bounded recursive circular subdivisions",
      "Analytic 2D structure and separately evaluated ornamental profiles"}})
end
local function validate(x)
  local e=x.extensions.tracery
  assert(P.serialize(e.request.frame)==P.serialize(x.frame),"tracery-frame-provenance")
  local graph,curves,meta=construct(P.plain(e.request))
  assert(P.serialize(graph)==P.serialize(x.structures.graph) and P.serialize(curves)==P.serialize(e.curves)
    and P.serialize(meta)==P.serialize(e.grammar),"tracery-dependency-reconstruction")
  local neighbors={}
  for _,edge in ipairs(graph.edges) do
    neighbors[edge.from]=neighbors[edge.from] or {}
    neighbors[edge.to]=neighbors[edge.to] or {}
    neighbors[edge.from][#neighbors[edge.from]+1]=edge.to
    neighbors[edge.to][#neighbors[edge.to]+1]=edge.from
  end
  local first=graph.vertices[1].id
  local queue,seen={first},{[first]=true}
  local i=1
  while queue[i] do
    for _,id in ipairs(neighbors[queue[i]] or {}) do
      if not seen[id] then seen[id]=true;queue[#queue+1]=id end
    end
    i=i+1
  end
  assert(#queue==#graph.vertices,"tracery-disconnected-arc-network")
  return {ok=true,checks={"positive source radii and reconstructed arch/foil grammar",
    "admitted arc branches and connected exact junction identities",
    "rosette contact residuals within 2e-11cm",
    "bounded recursion and retained construction dependencies"}}
end
function M.validate(x) return validate(P.instance(P.plain(x),M.definition())) end

local function append_arc(out,c,r,start,sweep,last)
  local n=math.ceil(math.abs(sweep)/(pi/4))
  local step=sweep/n
  for i=1,n do
    local a,z=start+(i-1)*step,start+i*step
    local p,q=polar(c,r,a),polar(c,r,z)
    if i==n and last then q=last end
    local k=4/3*math.tan(step/4)*r
    out[#out+1]={"C",p[1]-k*math.sin(a),p[2]+k*math.cos(a),
      q[1]+k*math.sin(z),q[2]-k*math.cos(z),q[1],q[2]}
  end
end
local function arch_contour(out,a,offset)
  local r=a.radius-offset
  local base=a.base+offset
  assert(r>a.center_offset+EPS and base<a.spring-EPS,"tracery-profile-collapsed-arch")
  local left,right=a.left+offset,a.right-offset
  assert(left<right,"tracery-profile-collapsed-width")
  local rise=math.sqrt(r^2-a.center_offset^2)
  local alpha=math.atan(rise,a.center_offset)
  out[#out+1]={"M",left,base}
  out[#out+1]={"L",left,a.spring}
  append_arc(out,a.centers[1],r,pi,-alpha,{a.axis,a.spring+rise})
  append_arc(out,a.centers[2],r,alpha,-alpha,{right,a.spring})
  out[#out+1]={"L",right,base}
  out[#out+1]={"Z"}
end
local function circle_contour(out,c,r)
  assert(r>EPS,"tracery-profile-collapsed-ring")
  local p={c[1]+r,c[2]}
  out[#out+1]={"M",p[1],p[2]}
  append_arc(out,c,r,0,tau,p)
  out[#out+1]={"Z"}
end
local palettes={stone={.24,.38,.45},ink={.14,.23,.37},diagnostic={.19,.38,.52}}
local function lower(x,v,style)
  for k in pairs(style) do assert(k=="profile" or k=="band_cm","tracery-style:"..k) end
  local profile=style.profile or "stone"
  local color=assert(palettes[profile],"tracery-profile")
  local width=style.band_cm or .115
  assert(finite(width) and width>=.015 and width<=.6,"tracery-profile-width")
  local e=x.extensions.tracery
  local ops=P.array()
  local transform=P.plain(v.transform)
  local function emit(id,commands,paint)
    ops[#ops+1]={op="path",semantic_ref=id,commands=commands,transform=transform,paint=paint}
  end
  local detail=profile=="diagnostic"
  if not detail then
    for _,a in ipairs(e.grammar.arches) do
      local commands={}
      arch_contour(commands,a,-width/2)
      arch_contour(commands,a,width/2)
      emit(a.semantic,commands,{fill=color,fill_rule="evenodd"})
    end
    for _,r in ipairs(e.grammar.rings) do
      local commands={}
      circle_contour(commands,r.center,r.radius+width/2)
      circle_contour(commands,r.center,r.radius-width/2)
      emit(r.semantic,commands,{fill=color,fill_rule="evenodd"})
    end
  end
  local points={}
  for _,p in ipairs(x.structures.graph.vertices) do points[p.id]=p.point end
  for _,edge in ipairs(x.structures.graph.edges) do
    local curve=e.curves[edge.id]
    if detail or curve.role=="foil" then
      local a,z=points[edge.from],points[edge.to]
      local commands={{"M",a[1],a[2]}}
      if curve.kind=="arc" then
        assert(detail or width*.6<curve.radius*.45,"tracery-profile-collapsed-foil")
        append_arc(commands,curve.center,curve.radius,curve.start,curve.sweep,z)
      else commands[2]={"L",z[1],z[2]} end
      emit(edge.id,commands,{stroke=color,stroke_width=detail and .025 or width*.6,cap="round",join="round"})
    end
  end
  if detail then
    for _,t in ipairs(e.grammar.contacts) do
      local p=points[t.id]
      local commands={}
      circle_contour(commands,p,.061)
      emit(t.id,commands,{fill={.70,.26,.20}})
    end
  end
  return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
    clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=P.array()}
end
function M.register(registry)
  local d=M.definition()
  registry:register(d,{generate=function(s,c)
    local request={frame=P.plain(c.frame),parameters=P.plain(s.parameters)}
    local graph,curves,meta=construct(request,c)
    return {id="tracery/"..H.value("tracery/construction",request),definition_ref={id=d.id,version=d.version},
      frame=P.plain(c.frame),structures={graph=graph},
      provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},
      extensions={tracery={request=request,curves=curves,grammar=meta}}}
  end,validate=validate,lower=lower})
  return d
end
return M
