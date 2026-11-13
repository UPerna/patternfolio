-- Named independent adaptation of Wong/Zongker/Salesin1998 sections3.2,4.1,4.2.
-- A bounded grid approximates empty-circle selection; no MAT reproduction claim.
local P,G,N,B,H=require("pattern"),require("pattern_geometry"),require("pattern_predicates"),require("pattern_bounds"),require("pattern_hash")
local M={VERSION="asymmetric-garden-v1"}
local function distance(a,b)return math.sqrt((a[1]-b[1])^2+(a[2]-b[2])^2)end
local function clearance(p,polygon)
  local best=math.huge
  for i,a in ipairs(polygon)do local b=polygon[i%#polygon+1];local dx,dy=b[1]-a[1],b[2]-a[2]
    best=math.min(best,(dx*(p[2]-a[2])-dy*(p[1]-a[1]))/math.sqrt(dx*dx+dy*dy))
  end
  return best
end
local function corners(b)return{{b[1],b[2]},{b[3],b[2]},{b[3],b[4]},{b[1],b[4]}}end
local function overlap(a,b)return a[1]<=b[3]and a[3]>=b[1]and a[2]<=b[4]and a[4]>=b[2]end
local function admitted(box,polygon,masks)
  for _,p in ipairs(corners(box))do if clearance(p,polygon)<=1e-8 then return false end end
  for _,r in ipairs(masks)do if overlap(box,r.bounds)then return false end end
  return true
end
local function region(s)
  assert(next(P.plain(s.inputs))==nil,"panel takes no opaque external inputs")
  for key in pairs(s.constraints)do assert(key=="region","unsupported panel constraint "..key)end
  local r=assert(s.constraints.region,"explicit nonrectangular region required")
  for key in pairs(r)do assert(key=="unit"or key=="points","unsupported region field")end
  assert(r.unit=="cm"and #r.points>=3 and #r.points<=16,"convex region needs3..16 points in cm")
  local polygon=P.plain(r.points)
  for _,p in ipairs(polygon)do G.point(p);assert(p[1]>=s.document.bounds[1]and p[2]>=s.document.bounds[2]and p[1]<=s.document.bounds[3]and p[2]<=s.document.bounds[4],"region exceeds declared document generation area")end
  for i,a in ipairs(polygon)do local b,c=polygon[i%#polygon+1],polygon[(i+1)%#polygon+1]
    assert(N.orient2d(a,b,c)>0,"only strictly convex CCW botanical regions are supported")
    for j,p in ipairs(polygon)do if j~=i and j~=i%#polygon+1 then assert(N.orient2d(a,b,p)>0,"region is nonconvex or self-intersecting")end end
  end
  return polygon
end
local function asset(id,fn,context)
  local ink=require("ink")
  local ops,receipt=ink.capture(function()
    ink.set_ink(0x24/255,0x56/255,0xC4/255);ink.set_accent(0xB4/255,0x66/255,0x2F/255);ink.set_lift(0);ink.set_color_mode("color");fn(ink)
  end)
  local boxes={};local policy=G.policy("cm",32)
  for _,op in ipairs(ops)do if op.op=="path"then boxes[#boxes+1]=B.path(op.commands,op.paint,op.transform,policy)end end
  local b=B.union(boxes,"cm");assert(not b.empty,"empty botanical asset")
  local content=P.serialize({kind="vector_asset",schema_version=1,unit="cm",operations=ops})
  context:consume("operations",#ops);context:consume("bytes",#content)
  return{id=id,kind="symbol",unit="cm",bounds=P.plain(b.bounds),variants={scene={encoding="utf8",content=content,sha256=H.sha256(content),media_type="application/vnd.pattern.vector+json"}},provenance=receipt}
end
local function generate(d,s,c)
  local polygon=region(s);local masks=P.plain(s.document.protected_regions)
  assert(c.planning and c.planning.mode=="adaptive","named panel requires actual common-planner adaptive context")
  local root
  for _,a in ipairs(c.planning.page.anchors)do if a.role=="root"then assert(not root,"one root anchor required");root=P.plain(a.point)end end
  assert(root and clearance(root,polygon)>0.15,"root anchor must lie inside the actual convex panel")
  for _,r in ipairs(masks)do assert(not(root[1]>=r.bounds[1]and root[1]<=r.bounds[3]and root[2]>=r.bounds[2]and root[2]<=r.bounds[4]),"root anchor is protected")end
  local nodes={{id="garden/root",point=root,motif="seed",direction={0,1}}};local tips={nodes[1]};local proxies,resources,placements,attempts={},{},{},{}
  local cells={};local bounds=s.document.bounds;local step=0.4
  assert((bounds[3]-bounds[1])*(bounds[4]-bounds[2])/(step*step)<=4096,"panel grid budget exceeds4096 cells")
  for iy=math.floor(bounds[2]/step),math.ceil(bounds[4]/step)-1 do for ix=math.floor(bounds[1]/step),math.ceil(bounds[3]/step)-1 do
    local p={(ix+0.5)*step,(iy+0.5)*step};if clearance(p,polygon)>0 then cells[#cells+1]={point=p,id=ix.."/"..iy}end
  end end
  local excluded={};local limit=math.max(3,math.floor(12*s.parameters.density));local accepted=0
  for iteration=1,#cells do
    if accepted>=limit then break end
    local best,parent,radius,best_clearance
    for i,cell in ipairs(cells)do if not excluded[i]then
      c:consume("operations",1);local p=cell.point;local free=clearance(p,polygon)
      for _,r in ipairs(masks)do local b=r.bounds;local dx=math.max(b[1]-p[1],0,p[1]-b[3]);local dy=math.max(b[2]-p[2],0,p[2]-b[4]);free=math.min(free,math.sqrt(dx*dx+dy*dy))end
      for _,proxy in ipairs(proxies)do free=math.min(free,distance(p,proxy.center)-proxy.radius)end
      local nearest,near
      for _,tip in ipairs(tips)do local dist=distance(p,tip.point);if not near or dist<near then nearest,near=tip,dist end end
      local available=math.min(free*0.9,0.82)
      if near<=3.5 and available>=0.3/math.sqrt(s.parameters.density)and(not best_clearance or free>best_clearance)then best,parent,radius,best_clearance=i,nearest,available,free end
    end end
    if not best then break end;excluded[best]=true
    local cell=cells[best];local p=cell.point;local id="garden/cell/"..cell.id
    local choice=c:stream("motif-choice",id).int(1,3);local kind=({"flower","leaf","bud"})[choice]
    local motif=asset(id.."/paint",function(ink)
      local rng=ink.rng(c:stream("motif-paint",id).next_integer());local flora=require("flora")
      if kind=="leaf"then flora.leaf(rng,{w=0.26,depth=0.5})else flora[kind](rng,1)end
    end,c)
    local reach=0;for _,q in ipairs(corners(motif.bounds))do reach=math.max(reach,math.sqrt(q[1]^2+q[2]^2))end
    assert(reach>0,"empty motif proxy");local scale=radius/reach;local box={p[1]+scale*motif.bounds[1],p[2]+scale*motif.bounds[2],p[1]+scale*motif.bounds[3],p[2]+scale*motif.bounds[4]}
    local a=parent.point;local len=distance(a,p);local dx,dy=(p[1]-a[1])/len,(p[2]-a[2])/len
    local controls={P.plain(a),{a[1]+parent.direction[1]*len*0.25,a[2]+parent.direction[2]*len*0.25},{p[1]-dx*len*0.25,p[2]-dy*len*0.25},P.plain(p)}
    local curve=require("ink").bezier3(controls[1][1],controls[1][2],controls[2][1],controls[2][2],controls[3][1],controls[3][2],controls[4][1],controls[4][2])
    local samples=require("ink").sample(curve,24)
    local branch=asset(id.."/branch-paint",function()require("flora").stem(samples,0.04,0.018)end,c)
    local ok=admitted(box,polygon,masks)and admitted(branch.bounds,polygon,masks)
    attempts[#attempts+1]={cell=cell.id,radius=radius,status=ok and"accepted"or"conservative-paint-envelope-rejected"}
    if ok then
      accepted=accepted+1;c:consume("objects",2)
      local branch_id=id.."/branch";nodes[#nodes+1]={id=branch_id,parent=parent.id,point=P.plain(a),motif="stem",controls=controls,sampled_points=samples,direction={dx,dy},attachment={point=P.plain(a),parent=parent.id}}
      local node={id=id,parent=branch_id,point=P.plain(p),motif=kind,direction={dx,dy},attachment={point=P.plain(p),parent=branch_id}}
      nodes[#nodes+1]=node;tips[#tips+1]=node;proxies[#proxies+1]={semantic_ref=id,center=P.plain(p),radius=radius}
      resources[#resources+1]=branch;resources[#resources+1]=motif
      placements[#placements+1]={semantic_ref=branch_id,resource_ref=branch.id,transform={1,0,0,1,0,0},bounds=P.plain(branch.bounds)}
      placements[#placements+1]={semantic_ref=id,resource_ref=motif.id,transform={scale,0,0,scale,p[1],p[2]},bounds=box}
    end
  end
  assert(accepted>=3,"bounded panel search could not establish three connected botanical placements; enlarge permitted space or reduce constraints")
  return {id=d.id.."/"..H.value("botanical/panel-input",s),definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),structures={growth={nodes=nodes,roots={"garden/root"}}},
    provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction=M.VERSION},extensions={panel={region=polygon,protected_regions=masks,resources=resources,placements=placements,proxies=proxies,attempts=attempts,
      bounds=P.plain(s.document.bounds),grid_spacing_cm=step,grid_cells=#cells,iteration_limit=#cells,accepted=accepted,density=s.parameters.density,
      source_scope="independent grid/proxy/serial-rule adaptation; no source MAT or paper-figure reproduction",containment="every conservative whole-paint resource AABB admitted before lowering; no panel clip required"}}}
end
function M.validate(x,d)
  x=P.instance(P.plain(x),d);local data=x.extensions.panel;local ns={}
  for _,n in ipairs(x.structures.growth.nodes)do ns[n.id]=n end
  assert(#data.attempts<=data.iteration_limit and data.grid_cells<=4096,"termination bound violated")
  assert(#x.structures.growth.nodes==1+2*data.accepted and #data.placements==2*data.accepted,"rule result count mismatch")
  local resources={};for _,r in ipairs(data.resources)do
    assert(not resources[r.id],"duplicate panel resource");resources[r.id]=r
    local variant=r.variants.scene;assert(H.sha256(variant.content)==variant.sha256,"panel resource digest mismatch")
    local recorded=require("pattern_parse").decode(variant.content);assert(recorded.kind=="vector_asset"and recorded.unit=="cm"and recorded.schema_version==1,"invalid panel asset")
    local measured={};local depth=0
    for _,op in ipairs(recorded.operations)do
      if op.op=="path"then measured[#measured+1]=B.path(op.commands,op.paint,op.transform,G.policy("cm",32))
      elseif op.op=="push_clip"then depth=depth+1 elseif op.op=="pop_clip"then depth=depth-1 else error("unsupported panel asset operation")end
      assert(depth>=0,"panel asset clipping underflow")
    end
    assert(depth==0,"panel asset clipping imbalance")
    local measured_bounds=B.union(measured,"cm");assert(not measured_bounds.empty,"empty panel resource")
    for i=1,4 do assert(math.abs(measured_bounds.bounds[i]-r.bounds[i])<=1e-12,"forged panel paint bounds")end
  end
  for _,p in ipairs(data.placements)do
    assert(ns[p.semantic_ref]and resources[p.resource_ref],"missing placement source/resource")
    local b=resources[p.resource_ref].bounds;local t=p.transform
    assert(t[2]==0 and t[3]==0 and t[1]>0 and t[1]==t[4],"unexpected generated resource transform")
    local actual={b[1]*t[1]+t[5],b[2]*t[4]+t[6],b[3]*t[1]+t[5],b[4]*t[4]+t[6]}
    for i=1,4 do assert(math.abs(actual[i]-p.bounds[i])<=1e-12,"placement envelope mismatch")end
    assert(admitted(actual,data.region,data.protected_regions),"paint envelope leaves permitted region")
  end
  for _,n in ipairs(x.structures.growth.nodes)do if n.parent then
    local parent=ns[n.parent];assert(distance(n.point,parent.controls and parent.controls[4]or parent.point)<=1e-12,"disconnected rule attachment")
    if n.controls then assert(distance(n.controls[1],n.point)<=1e-12 and distance(n.controls[4],n.sampled_points[#n.sampled_points])<=1e-12,"branch endpoint mismatch")end
  end end
  for i,proxy in ipairs(data.proxies)do
    assert(ns[proxy.semantic_ref]and distance(proxy.center,ns[proxy.semantic_ref].point)<=1e-12 and proxy.radius>0,"invalid occupied proxy")
    for j=1,i-1 do assert(distance(proxy.center,data.proxies[j].center)>proxy.radius+data.proxies[j].radius,"occupied motif proxies overlap")end
  end
  return{ok=true,checks={"connected parent/child rule endpoints <=1e-12cm","conservative full-paint envelopes inside convex region before clipping","protected-region envelope exclusion","bounded grid/exclusion-list termination"}}
end
function M.register(registry)
  local d=P.definition({id="botanical/asymmetric-garden",version="1",family="adaptive-botanical-panel",units="cm",capabilities={"growth"},
    parameters={density={type="number",minimum=0.2,maximum=1,required=true}},transforms={metric_constrained=true,reflection=false,uniform_scale=true},
    assumptions={"Named new convex-panel recipe, distinct from legacy defaults","World root anchor, 0.4cm candidate grid and bounded serial proxy rules","Conservative paint-envelope containment, not a claim of source MAT reproduction"}})
  registry:register(d,{validate_inputs=function(s)region(s);return true end,generate=function(s,c)return generate(d,s,c)end,validate=function(x)return M.validate(x,d)end,
    lower=function(x,v,style)
      for key in pairs(style) do assert(key=="palette","unsupported botanical style: "..key) end
      local resources=P.plain(x.extensions.panel.resources)
      if style.palette then
        assert(style.palette=="indigo","unsupported botanical palette")
        for _,resource in ipairs(resources) do
          local variant=resource.variants.scene
          local asset=require("pattern_parse").decode(variant.content)
          for _,operation in ipairs(asset.operations) do
            if operation.op=="path" then
              local paint=operation.paint
              for _,key in ipairs{"fill","stroke"} do
                if paint[key] then
                  local c=paint[key]
                  local shade=.2126*c[1]+.7152*c[2]+.0722*c[3]
                  paint[key]={.12+.71*shade,.16+.71*shade,.32+.57*shade}
                end
              end
            end
          end
          variant.content=P.serialize(asset)
          variant.sha256=H.sha256(variant.content)
        end
      end
      local ops={};for _,p in ipairs(x.extensions.panel.placements)do local a,b=v.transform,p.transform
        ops[#ops+1]={op="symbol",semantic_ref=p.semantic_ref,resource_ref=p.resource_ref,transform={a[1]*b[1],a[2]*b[1],a[3]*b[4],a[4]*b[4],a[1]*b[5]+a[3]*b[6]+a[5],a[2]*b[5]+a[4]*b[6]+a[6]}}
      end
      return{id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)},operations=ops,resources=resources}
    end})
  return d
end
return M
