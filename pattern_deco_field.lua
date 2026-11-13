local SDF = require("pattern_deco_sdf")
local Match = require("pattern_deco_match")
local Mesh = require("pattern_deco_mesh")
local Cut = require("pattern_deco_cut")
local M = {}

local function guide_stations(points)
  local angles, stations = {}, {}
  for i = 2, #points do
    local dx, dy = points[i][1]-points[i-1][1], points[i][2]-points[i-1][2]
    assert(dx*dx+dy*dy > 1e-12, "duplicate guide station")
    local angle = math.atan(dy,dx)
    local prior = angles[i-2]
    if prior then angle = prior + (angle-prior+math.pi)%(2*math.pi)-math.pi end
    angles[i-1] = angle
  end
  local arc = 0
  for i,p in ipairs(points) do
    local a = angles[i-1] or angles[i]
    local b = angles[i] or a
    assert(math.abs(a-b) < math.pi/2, "guide bend exceeds chart limit")
    if i > 1 then
      local dx,dy = p[1]-points[i-1][1],p[2]-points[i-1][2]
      arc = arc + math.sqrt(dx*dx+dy*dy)
    end
    local turn = (a+b)/2
    assert(p[3] > 0, "guide width must be positive")
    stations[i] = {x=p[1],y=p[2],arc=arc,turn=turn,width=p[3],
      nx=-math.sin(turn),ny=math.cos(turn)}
  end
  return stations
end

local function interpolate(stations, t)
  local i = math.min(#stations-1, math.floor(t))
  local a,b = stations[i],stations[i+1]
  local f = t-i
  local function mix(k) return a[k]+f*(b[k]-a[k]) end
  local turn = mix("turn")
  return {x=mix("x"),y=mix("y"),arc=mix("arc"),width=mix("width"),
    nx=-math.sin(turn),ny=math.cos(turn)}
end

function M.synthesize(points, exemplars, options)
  assert(#points >= 3 and #points <= 65 and #exemplars > 0 and #exemplars <= 32, "guide or library size out of range")
  local subdivisions, height = options.subdivisions, options.rows
  assert(subdivisions >= 4 and subdivisions <= 32 and subdivisions%1 == 0, "invalid guide sampling")
  assert(height >= 4 and height <= 65 and height%1 == 0, "invalid rib sampling")
  local stations, library = guide_stations(points), {}
  for i, piece in ipairs(exemplars) do
    local sample = SDF.prepare(piece.primitives)
    local entry, leave = {}, {}
    for j = 1, 9 do
      local y = (j-5)*piece.width/8
      entry[j], leave[j] = sample(0,y), sample(piece.length,y)
    end
    library[i] = {sample=sample,length=piece.length,width=piece.width,turn=piece.turn,
      role=piece.role,entry_profile=entry,exit_profile=leave}
  end
  local matches, cost = Match.match(stations, library, options.match)
  if not matches then return nil, cost end
  local width = (#points-1)*subdivisions+1
  local grid, evidence = {}, {}
  for _, match in ipairs(matches) do
    local piece = library[match.piece]
    local first,last = match.first,match.last
    local start_arc = stations[first].arc
    local scale = piece.length/(stations[last].arc-start_arc)
    local ribs = {}
    -- Extend each match by half a guide interval at internal joints.
    for twice = math.max(2,2*first-1),math.min(2*#points,2*last+1) do
      local s = interpolate(stations, twice/2)
      s.u = (s.arc-start_arc)*scale
      ribs[#ribs+1] = s
    end
    local mesh, diagnostic = Mesh.fit(ribs,piece.width/2,options.iterations,options.distortion)
    if not mesh then return nil, diagnostic end
    evidence[#evidence+1] = mesh.evidence
    match.mesh = mesh
  end
  local half = math.floor(subdivisions/4)
  local function sample(match,p)
    local u,v = Mesh.inverse(match.mesh,p.x,p.y)
    if not u then return {distance=options.outside} end
    local source = library[match.piece]
    return {distance=source.sample(u,v),piece=match.piece,u=u,v=v}
  end
  local seams, overlap = {}, {}
  local active = 1
  for x = 1,width do
    local right = matches[active+1]
    local center = right and ((right.first-1)*subdivisions+1)
    if center and x > center+half then active = active+1; center = nil end
    local s = interpolate(stations,1+(x-1)/subdivisions)
    for y = 1,height do
      local i = (y-1)*width+x
      local t = ((y-1)/(height-1)-.5)*s.width
      local p = {x=s.x+s.nx*t,y=s.y+s.ny*t}
      grid[i] = p
      p.source = sample(matches[active],p)
      if center and x >= center-half then
        local data = overlap[active] or {}
        overlap[active] = data
        data[(y-1)*(2*half+1)+x-center+half+1] = {i=i,left=p.source,right=sample(right,p)}
      end
    end
  end
  for j,data in ipairs(overlap) do
    local labels, proof = Cut.solve(2*half+1,height,function(a,b)
      local l,r = data[a].left.distance,data[b].right.distance
      local ink = math.max(0,-l)+math.max(0,-r)
      return 1+math.floor(1000*(math.abs(l-r)+ink)+.5)
    end)
    local indices = {}
    for i,pair in ipairs(data) do
      indices[i] = pair.i
      grid[pair.i].source = labels[i] and pair.left or pair.right
    end
    seams[j] = {indices=indices,labels=labels,certificate=proof}
  end
  return {width=width,height=height,grid=grid,seams=seams,matches=matches,
    deformation=evidence,match_cost=cost}
end

return M
