local F=require("pattern_stroke_field")
local M={VERSION="perceptual-stroke-groups-v1"}
local abs,sqrt,min,max,pi=math.abs,math.sqrt,math.min,math.max,math.pi

-- Rank near-equal measurements in fixed bins before breaking ties by declaration order.
local function rank(x)
  return math.floor(x*1e9+.5)
end

local function gap(a,b)
  return sqrt((a[1]-b[1])^2+(a[2]-b[2])^2)
end

local function fit(strokes,indices)
  local cx,cy,n,ink=0,0,0,0
  local dots=true
  for _,i in ipairs(indices) do
    local s=strokes[i]
    ink=max(ink,s.width)
    dots=dots and #s.points==1
    for _,p in ipairs(s.points) do cx,cy,n=cx+p[1],cy+p[2],n+1 end
  end
  cx,cy=cx/n,cy/n
  local a,b,c=0,0,0
  for _,i in ipairs(indices) do
    for _,p in ipairs(strokes[i].points) do
      local x,y=p[1]-cx,p[2]-cy
      a,b,c=a+x*x,b+x*y,c+y*y
    end
  end
  local angle=.5*math.atan(2*b,a-c)
  local u,v=math.cos(angle),math.sin(angle)
  local l,d,r,t=math.huge,math.huge,-math.huge,-math.huge
  for _,i in ipairs(indices) do
    for _,p in ipairs(strokes[i].points) do
      local x,y=p[1]*u+p[2]*v,p[2]*u-p[1]*v
      l,d,r,t=min(l,x),min(d,y),max(r,x),max(t,y)
    end
  end
  local x,y=(l+r)/2,(d+t)/2
  local color=strokes[indices[1]].color
  return {center={x*u-y*v,x*v+y*u},angle=angle,length=r-l+ink,width=t-d+ink,
    color=color,kind=dots and "point" or "line",members=indices,group=strokes[indices[1]].group}
end

local function angle_gap(a,b)
  return abs((a-b+pi/2)%pi-pi/2)
end

local function relation(a,b)
  local dx,dy=b.center[1]-a.center[1],b.center[2]-a.center[2]
  local turn=(b.angle-a.angle+pi/2)%pi-pi/2
  local angle=a.angle+turn/2
  local u,v=math.cos(angle),math.sin(angle)
  local along,across=dx*u+dy*v,dy*u-dx*v
  local projected=(a.length+b.length)*math.cos(turn/2)
  local r={proximity=sqrt(dx*dx+dy*dy),offset={dx,dy},along=along,across=across}
  if a.kind=="line" and b.kind=="line" then
    r.parallelism,r.overlap,r.separation=2*abs(turn)/pi,2*abs(along)/projected,abs(across)
  end
  return r
end

local function nearest(elements,i,group)
  local best,other=math.huge
  for j,v in ipairs(elements) do
    if j~=i and (not group or v.group==elements[i].group) then
      local d=gap(v.center,elements[i].center)
      if rank(d)<rank(best) then best,other=d,j end
    end
  end
  return other,best
end

local function element_gap(strokes,a,b)
  local best=math.huge
  for _,i in ipairs(a.members) do
    local p=strokes[i].points
    for _,j in ipairs(b.members) do
      local q=strokes[j].points
      for k=1,max(1,#p-1) do
        for l=1,max(1,#q-1) do
          best=min(best,F.segment_gap2(p[k],p[k+1] or p[k],q[l],q[l+1] or q[l]))
        end
      end
    end
  end
  return sqrt(best)
end

function M.analyze(input,threshold)
  assert(type(input)=="table" and #input>=4 and #input<=96,"stroke-example-count")
  local strokes,queue={},{}
  local points=0
  for i,s in ipairs(input) do
    assert(type(s)=="table" and type(s.group)=="string" and s.group:match("^[%w_-]+$"),"stroke-example-group")
    assert(type(s.points)=="table" and #s.points>=1 and #s.points<=24,"stroke-example-point-count")
    assert(F.finite(s.width) and s.width>=.005 and s.width<=.2,"stroke-example-width")
    assert(type(s.color)=="table" and #s.color==3,"stroke-example-paint")
    for _,v in ipairs(s.color) do assert(F.finite(v) and v>=0 and v<=1,"stroke-example-paint") end
    local vertices={}
    for k,p in ipairs(s.points) do
      vertices[k]=F.point(p)
      assert(k==1 or gap(vertices[k-1],vertices[k])>1e-7,"stroke-example-repeated-vertex")
    end
    points=points+#vertices
    assert(points<=600,"stroke-example-analysis-horizon")
    strokes[i]={points=vertices,width=s.width,group=s.group,color={table.unpack(s.color)}}
    queue[i]=fit(strokes,{i})
  end
  local elements,merges={},{}
  while #queue>0 do
    local a=table.remove(queue,1)
    local merged=false
    local j=1
    while j<=#queue do
      local b=queue[j]
      local mode
      if a.group==b.group then
        local r=relation(a,b)
        local distance=element_gap(strokes,a,b)
        if distance<threshold*.5 then mode="proximity"
        elseif distance<threshold and angle_gap(a.angle,b.angle)<.20 and r.separation and r.separation<threshold*.5 then mode="continuation" end
      end
      if mode then
        merges[#merges+1]={left={table.unpack(a.members)},right={table.unpack(b.members)},rule=mode}
        local indices={table.unpack(a.members)}
        for _,k in ipairs(b.members) do indices[#indices+1]=k end
        a=fit(strokes,indices)
        table.remove(queue,j)
        merged=true
      else j=j+1 end
    end
    local out=merged and queue or elements
    out[#out+1]=a
  end
  assert(#elements>=3,"stroke-example-too-few-elements")
  local relations,groups={},{}
  for i,a in ipairs(elements) do
    local g=groups[a.group] or {indices={},pairs={}}
    groups[a.group]=g
    g.indices[#g.indices+1]=i
    local j=nearest(elements,i,true)
    if j then
      local r=relation(a,elements[j])
      r.from,r.to=i,j
      relations[#relations+1]=r
      g.pairs[#g.pairs+1]=#relations
    end
  end
  for _,g in pairs(groups) do assert(#g.indices>=2,"stroke-example-singleton-group") end
  return {elements=elements,strokes=strokes,merges=merges,relations=relations,groups=groups}
end

local function neighborhood(elements,i,scale,radius)
  local origin=elements[i].center
  local out={}
  for j,a in ipairs(elements) do
    if i~=j then
      local x,y=(a.center[1]-origin[1])*scale,(a.center[2]-origin[2])*scale
      local distance=sqrt(x*x+y*y)
      if distance<=radius then out[#out+1]={x=x,y=y,distance=distance,index=j,element=a} end
    end
  end
  table.sort(out,function(a,b)
    if rank(a.distance)==rank(b.distance) then return a.index<b.index end
    return rank(a.distance)<rank(b.distance)
  end)
  while #out>6 do out[#out]=nil end
  return out
end

local function offset_nearest(a,list)
  local best,result=math.huge
  for _,b in ipairs(list) do
    local d=(a.x-b.x)^2+(a.y-b.y)^2
    if rank(d)<rank(best) then best,result=d,b end
  end
  return result,sqrt(best)
end

local function match(reference,target,scale,radius)
  local score,matched=0,0
  for _,a in ipairs(target) do
    local b,d=offset_nearest(a,reference)
    if b and offset_nearest(b,target)==a then
      local u,v=a.element,b.element
      local angle=angle_gap(u.angle,v.angle)
      local length=abs(math.log(u.length/(v.length*scale)))
      local width=abs(u.width-v.width*scale)/radius
      local shape=abs(u.length-u.width-(v.length-v.width)*scale)/radius
      local color=sqrt((u.color[1]-v.color[1])^2+(u.color[2]-v.color[2])^2+(u.color[3]-v.color[3])^2)
      score=score+d/radius+angle/pi+length+width+shape+color+(u.group==v.group and 0 or 1)
      matched=matched+1
    end
  end
  if matched==0 then return 3+#target,0 end
  return score/matched+(#target-matched)/#target,matched
end

local function property(data,indices,key,mode,rng,source)
  if mode=="cloning" then return source[key] end
  if mode=="copying" then return data.elements[indices[rng.int(1,#indices)]][key] end
  local lo,hi,sum,squares=math.huge,-math.huge,0,0
  for _,i in ipairs(indices) do
    local value=data.elements[i][key]
    lo,hi,sum,squares=min(lo,value),max(hi,value),sum+value,squares+value*value
  end
  local mean=sum/#indices
  local deviation=sqrt(max(0,squares/#indices-mean*mean))
  for _=1,8 do
    local value=mean+deviation*sqrt(-2*math.log(max(1e-12,rng.u())))*math.cos(2*pi*rng.u())
    if value>=lo and value<=hi then return value end
  end
  return mean
end

local function copied_strokes(data,source,element)
  local angle=element.angle-source.angle
  local cu,su=math.cos(angle),math.sin(angle)
  local c,s=math.cos(source.angle),math.sin(source.angle)
  local su_scale=element.length/source.length
  local sv_scale=element.width/source.width
  local out={}
  for _,i in ipairs(source.members) do
    local stroke=data.strokes[i]
    local points={}
    for j,p in ipairs(stroke.points) do
      local x,y=p[1]-source.center[1],p[2]-source.center[2]
      local u,v=(x*c+y*s)*su_scale,(y*c-x*s)*sv_scale
      x,y=u*c-v*s,u*s+v*c
      points[j]={element.center[1]+x*cu-y*su,element.center[2]+x*su+y*cu}
    end
    out[#out+1]={points=points,width=stroke.width*min(su_scale,sv_scale),color=element.color,
      role=#points==1 and "dot" or "stroke"}
  end
  return out
end

function M.synthesize(data,sites,controls,rng,allowed)
  local scale,radius=controls.scale,controls.radius
  local references={}
  for i=1,#data.elements do references[i]=neighborhood(data.elements,i,scale,radius) end
  local placed,output,decisions={},{},{}
  for index,site in ipairs(sites) do
    local seed=rng.int(1,#data.elements)
    local target={table.unpack(placed)}
    target[#target+1]={center=site}
    local local_neighbors=neighborhood(target,#target,1,radius)
    local selected,quality,nmatch=seed,0,0
    if controls.profile=="causal" and #local_neighbors>0 then
      local candidates={}
      for j,ref in ipairs(references) do
        local score,count=match(ref,local_neighbors,scale,radius)
        candidates[#candidates+1]={index=j,score=score,count=count}
      end
      table.sort(candidates,function(a,b)
        if rank(a.score)==rank(b.score) then return a.index<b.index end
        return rank(a.score)<rank(b.score)
      end)
      quality,nmatch=candidates[1].score,candidates[1].count
      if quality<=controls.threshold then selected=candidates[1].index end
    end
    local source=data.elements[selected]
    local group=data.groups[source.group]
    local element={center=site,group=source.group,color=source.color,kind=source.kind,
      length=scale*property(data,group.indices,"length",controls.behavior,rng,source),
      width=scale*property(data,group.indices,"width",controls.behavior,rng,source),
      angle=property(data,group.indices,"angle",controls.behavior,rng,source)}
    local pair_id,correction
    if controls.profile=="group" and #local_neighbors>0 and #group.pairs>0 then
      local neighbor=local_neighbors[1].element
      local current=relation(neighbor,element)
      local best=math.huge
      for _,i in ipairs(group.pairs) do
        local delta=abs(data.relations[i].proximity*scale-current.proximity)
        if rank(delta)<rank(best) then best,pair_id=delta,i end
      end
      local pair=data.relations[pair_id]
      local amount=controls.correction
      local corrected_angle=element.angle
      local u,v=math.cos(neighbor.angle),math.sin(neighbor.angle)
      local along,across
      if pair.parallelism and current.parallelism then
        local desired_angle=neighbor.angle+(element.angle>=neighbor.angle and 1 or -1)*pair.parallelism*pi/2
        corrected_angle=element.angle+amount*((desired_angle-element.angle+pi/2)%pi-pi/2)
        local turn=(corrected_angle-neighbor.angle+pi/2)%pi-pi/2
        local bisector=neighbor.angle+turn/2
        u,v=math.cos(bisector),math.sin(bisector)
        along=(current.along>=0 and 1 or -1)*pair.overlap*(neighbor.length+element.length)*math.cos(turn/2)/2
        across=(current.across>=0 and 1 or -1)*pair.separation*scale
      else
        local factor=pair.proximity*scale/max(1e-12,current.proximity)
        local dx,dy=current.offset[1],current.offset[2]
        along,across=(dx*u+dy*v)*factor,(dy*u-dx*v)*factor
      end
      correction={neighbor.center[1]+along*u-across*v,neighbor.center[2]+along*v+across*u}
      element.center={site[1]+amount*(correction[1]-site[1]),site[2]+amount*(correction[2]-site[2])}
      element.angle=corrected_angle
    end
    local strokes=copied_strokes(data,source,element)
    local kept=allowed(strokes,element,placed)
    if kept then
      element.site=index
      placed[#placed+1]=element
      for _,stroke in ipairs(strokes) do stroke.site=index;output[#output+1]=stroke end
    end
    decisions[index]={source=selected,group=source.group,score=quality,matched=nmatch,pair=pair_id,kept=kept,
      fallback=controls.profile=="causal" and #local_neighbors>0 and quality>controls.threshold or false}
  end
  return placed,output,decisions
end

return M


