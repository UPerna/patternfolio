-- Bounded direct evaluation of the normalized polygon turning-function metric.
local P,G=require("pattern"),require("pattern_geometry")
local M={VERSION="turning-l2-anneal-v1"}
local pi,tau=math.pi,2*math.pi
local policy=G.policy("cm",16,1e-12,1e-12)
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
function M.polygon(input)
  assert(type(input)=="table" and #input>=3 and #input<=40,"escher-silhouette-size")
  for _,p in ipairs(input) do
    assert(type(p)=="table" and #p==2 and finite(p[1]) and finite(p[2])
      and math.abs(p[1])<=1024 and math.abs(p[2])<=1024,"escher-silhouette-coordinate")
  end
  return G.region(input,P.array(),policy).outer
end
function M.turning(points)
  local length,total,angles={0},0,{}
  local previous
  for i,p in ipairs(points) do
    local q=points[i%#points+1]
    local dx,dy=q[1]-p[1],q[2]-p[2]
    local l=math.sqrt(dx*dx+dy*dy)
    assert(l>1e-12,"escher-zero-edge")
    local theta=math.atan(dy,dx)
    if previous then theta=previous+(theta-previous+pi)%tau-pi end
    angles[i]=theta;previous=theta
    total=total+l;length[i+1]=total
  end
  for i=2,#length do length[i]=length[i]/total end
  return {breaks=length,angles=angles}
end
local function variance(p,q,offset)
  local n,m=#p.angles,#q.angles
  local i,j,turn,s=1,1,0,0
  while j<m and q.breaks[j+1]<=offset do j=j+1 end
  local mean,square=0,0
  while i<=n and s<1 do
    local qe=q.breaks[j+1]+turn-offset
    local pe=p.breaks[i+1]
    local z=math.min(pe,qe,1)
    local d=p.angles[i]-q.angles[j]-turn*tau
    local width=math.max(0,z-s)
    mean=mean+width*d
    square=square+width*d*d
    s=math.max(z,s)
    if qe<=z then
      if j==m then j=1;turn=turn+1 else j=j+1 end
    end
    if pe<=z then i=i+1 end
  end
  return math.max(0,square-mean*mean)
end
function M.distance(p,q)
  local best=math.huge
  for i=1,#p.angles do
    for j=1,#q.angles do
      local shift=(q.breaks[j]-p.breaks[i])%1
      best=math.min(best,variance(p,q,shift))
    end
  end
  return math.sqrt(best)
end
function M.objective(shapes,goals,context)
  assert(#shapes==#goals,"escher-target-count")
  local errors={}
  for i,p in ipairs(shapes) do
    local ok,ring=pcall(M.polygon,p)
    if not ok then return nil end
    local q=goals[i]
    if context then context:consume("operations",#p*#q.angles*(#p+#q.angles)) end
    errors[i]=M.distance(M.turning(ring),q)
  end
  return math.max(table.unpack(errors)),errors
end
function M.anneal(initial,bounds,steps,rng,evaluate)
  local values=P.plain(initial)
  local score,errors=evaluate(values)
  assert(score,"escher-initial-shape-invalid")
  local best,best_score,best_errors=P.plain(values),score,errors
  local accepted,rejected,improved=0,0,0
  for i=1,steps do
    local progress=(i-1)/math.max(1,steps-1)
    local temperature=.18*(.004/.18)^progress
    local k=rng.int(1,#values)
    local lo,hi=table.unpack(bounds[k])
    local jump=math.max(1,math.floor((hi-lo)*(.25-.225*progress)))
    local proposal=P.plain(values)
    proposal[k]=math.max(lo,math.min(hi,proposal[k]+rng.int(-jump,jump)))
    local candidate,e=evaluate(proposal)
    if not candidate then
      rejected=rejected+1
    elseif candidate<=score or rng.u()<math.exp((score-candidate)/temperature) then
      values,score=proposal,candidate
      accepted=accepted+1
      if score<best_score-1e-12 then
        best,best_score,best_errors=P.plain(values),score,e
        improved=improved+1
      end
    end
  end
  return {values=best,score=best_score,errors=best_errors,accepted=accepted,
    invalid_proposals=rejected,improvements=improved,steps=steps,
    temperature={start=.18,finish=.004,law="geometric"}}
end
return M
