local SDF = require("pattern_deco_sdf")
local M = {}

-- Match source-coordinate neighborhoods at three spatial scales.
-- The caller supplies the exact editable lattice mask and optional ink constraints.
function M.apply(field, exemplars, editable, constraints, radius)
  assert(radius > 0 and radius < 1, "invalid refinement radius")
  constraints = constraints or {}
  local grid, width, height = field.grid, field.width, field.height
  local samplers = {}
  for i,piece in ipairs(exemplars) do samplers[i] = SDF.prepare(piece.primitives) end
  for i,value in pairs(constraints) do
    assert(editable[i] and grid[i] and type(value)=="boolean","invalid refinement constraint")
  end
  local function adjacent(i, dx, dy)
    local x,y = (i-1)%width+1, math.floor((i-1)/width)+1
    if x+dx>=1 and x+dx<=width and y+dy>=1 and y+dy<=height then
      return grid[i+dy*width+dx]
    end
  end
  local receipt = {}
  for _,stride in ipairs({4,2,1}) do
    local pending, accepted = {}, 0
    local delta = radius*stride/4
    for i,p in ipairs(grid) do
      local prior = p.source
      if editable[i] and prior.piece then
        local neighbors = {{0,0,p}}
        for _,offset in ipairs({{-stride,0},{stride,0},{0,-stride},{0,stride}}) do
          local dx,dy = table.unpack(offset)
          local q = adjacent(i,dx,dy)
          if q then neighbors[#neighbors+1] = {dx,dy,q} end
        end
        local function score(candidate)
          local sample = samplers[candidate.piece]
          local error = 0
          for _,n in ipairs(neighbors) do
            local q = n[3]
            local d = math.sqrt((q.x-p.x)^2+(q.y-p.y)^2)
            local u = n[1] == 0 and 0 or (n[1]>0 and d or -d)
            local v = n[2] == 0 and 0 or (n[2]>0 and d or -d)
            error = error+(sample(candidate.u+u,candidate.v+v)-q.source.distance)^2
          end
          if constraints[i] == true and candidate.distance >= -1e-9
            or constraints[i] == false and candidate.distance <= 1e-9 then
            return math.huge
          end
          return error
        end
        local best, cost = prior, score(prior)
        local function offer(piece,u,v)
          if math.abs(u-prior.u)>radius*2 or math.abs(v-prior.v)>radius*2 then return end
          local candidate = {piece=piece,u=u,v=v,distance=samplers[piece](u,v)}
          local value = score(candidate)
          if value < cost-1e-12 then best,cost=candidate,value end
        end
        for _,offset in ipairs({{-delta,0},{delta,0},{0,-delta},{0,delta}}) do
          offer(prior.piece,prior.u+offset[1],prior.v+offset[2])
        end
        for k=2,#neighbors do
          local dx,dy,q = table.unpack(neighbors[k])
          if q.source.piece then
            local d = math.sqrt((q.x-p.x)^2+(q.y-p.y)^2)
            local u = dx == 0 and 0 or (dx>0 and d or -d)
            local v = dy == 0 and 0 or (dy>0 and d or -d)
            offer(q.source.piece,q.source.u-u,q.source.v-v)
          end
        end
        if best ~= prior then pending[i]=best; accepted=accepted+1 end
      end
    end
    for i,source in pairs(pending) do grid[i].source=source end
    receipt[#receipt+1] = {stride=stride,accepted=accepted}
  end
  local unsatisfied = {}
  for i,value in pairs(constraints) do
    local distance = grid[i].source.distance
    if value and distance >= -1e-9 or not value and distance <= 1e-9 then
      unsatisfied[#unsatisfied+1]=i
    end
  end
  table.sort(unsatisfied)
  return {levels=receipt,unsatisfied=unsatisfied}
end

return M

