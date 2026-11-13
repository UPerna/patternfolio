local ARAP = require("pattern_deco_arap")
local M = {}

local function determinant(a, b, c)
  return (b[1] - a[1]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[1] - a[1])
end

-- Stations include both ends of the extended overlap. The middle rib row is pinned.
function M.fit(stations, half_width, iterations, limits)
  local rest, initial, pins, faces, edges, seen = {}, {}, {}, {}, {}, {}
  for _, s in ipairs(stations) do
    for row = -1, 1 do
      local t = row * half_width
      local i = #rest + 1
      rest[i] = {s.u, t}
      initial[i] = {s.x + t * s.nx, s.y + t * s.ny}
      if row == 0 then pins[i] = initial[i] end
    end
  end
  local function face(a, b, c)
    faces[#faces + 1] = {a, b, c}
    for _, pair in ipairs({{a,b}, {b,c}, {c,a}}) do
      local i, j = math.min(pair[1], pair[2]), math.max(pair[1], pair[2])
      local key = i .. "/" .. j
      if not seen[key] then
        seen[key] = true
        edges[#edges + 1] = {i, j, 1}
      end
    end
  end
  for s = 1, #stations - 1 do
    for row = 1, 2 do
      local a = (s - 1) * 3 + row
      face(a, a + 3, a + 4)
      face(a, a + 4, a + 1)
    end
  end
  local points, evidence = ARAP.solve(rest, edges, pins, initial, iterations)
  local min_jacobian, max_stretch, min_stretch = math.huge, 0, math.huge
  for _, f in ipairs(faces) do
    local a,b,c = table.unpack(f)
    local jacobian = determinant(points[a],points[b],points[c]) / determinant(rest[a],rest[b],rest[c])
    min_jacobian = math.min(jacobian, min_jacobian)
  end
  for _, edge in ipairs(edges) do
    local i,j = table.unpack(edge)
    local dx,dy = points[i][1]-points[j][1],points[i][2]-points[j][2]
    local ux,uy = rest[i][1]-rest[j][1],rest[i][2]-rest[j][2]
    local stretch = math.sqrt((dx*dx+dy*dy)/(ux*ux+uy*uy))
    min_stretch, max_stretch = math.min(min_stretch,stretch), math.max(max_stretch,stretch)
  end
  evidence.min_jacobian, evidence.min_stretch, evidence.max_stretch = min_jacobian,min_stretch,max_stretch
  if min_jacobian <= limits.min_jacobian or min_stretch < limits.min_stretch
    or max_stretch > limits.max_stretch or evidence.residual > limits.max_residual then
    return nil, "ARAP distortion exceeds limits", evidence
  end
  return {rest=rest, points=points, faces=faces, evidence=evidence}
end

function M.inverse(mesh, x, y)
  local query = {x,y}
  for _, f in ipairs(mesh.faces) do
    local i,j,k = table.unpack(f)
    local a,b,c = mesh.points[i],mesh.points[j],mesh.points[k]
    local area = determinant(a,b,c)
    local u,v = determinant(query,b,c)/area,determinant(a,query,c)/area
    local w = 1-u-v
    if math.min(u,v,w) >= -1e-9 then
      a,b,c = mesh.rest[i],mesh.rest[j],mesh.rest[k]
      return a[1]*u+b[1]*v+c[1]*w, a[2]*u+b[2]*v+c[2]*w
    end
  end
end

return M
