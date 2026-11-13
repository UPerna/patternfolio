-- Local/global ARAP over a connected weighted vertex graph.
local M = {}

function M.solve(rest, edges, pins, initial, iterations)
  local positions, adjacency, rotations = {}, {}, {}
  for i, p in ipairs(initial) do
    positions[i] = pins[i] or {p[1], p[2]}
    adjacency[i] = {}
  end
  assert(next(pins), "ARAP requires positional anchors")
  for _, edge in ipairs(edges) do
    local i, j, w = table.unpack(edge)
    assert(i ~= j and adjacency[i] and adjacency[j] and w > 0, "invalid ARAP edge")
    adjacency[i][#adjacency[i] + 1] = {j, w}
    adjacency[j][#adjacency[j] + 1] = {i, w}
  end
  local seen, queue = {}, {}
  for i in pairs(pins) do seen[i] = true; queue[#queue + 1] = i end
  local at = 1
  while queue[at] do
    for _, edge in ipairs(adjacency[queue[at]]) do
      local j = edge[1]
      if not seen[j] then seen[j] = true; queue[#queue + 1] = j end
    end
    at = at + 1
  end
  assert(#queue == #positions, "unanchored ARAP component")
  local function fit_rotations()
    for i, links in ipairs(adjacency) do
      local dot, cross = 0, 0
      for _, edge in ipairs(links) do
        local j, w = table.unpack(edge)
        local ux, uy = rest[i][1] - rest[j][1], rest[i][2] - rest[j][2]
        local vx, vy = positions[i][1] - positions[j][1], positions[i][2] - positions[j][2]
        dot = dot + w * (ux * vx + uy * vy)
        cross = cross + w * (ux * vy - uy * vx)
      end
      local norm = math.sqrt(dot * dot + cross * cross)
      rotations[i] = norm > 1e-12 and {dot / norm, cross / norm} or {1, 0}
    end
  end
  local function target(i, j)
    local ux, uy = rest[i][1] - rest[j][1], rest[i][2] - rest[j][2]
    local a = (rotations[i][1] + rotations[j][1]) / 2
    local b = (rotations[i][2] + rotations[j][2]) / 2
    return a * ux - b * uy, b * ux + a * uy
  end
  local function update(i, links)
    local x, y, weight = 0, 0, 0
    for _, edge in ipairs(links) do
      local j, w = table.unpack(edge)
      local tx, ty = target(i, j)
      x = x + w * (positions[j][1] + tx)
      y = y + w * (positions[j][2] + ty)
      weight = weight + w
    end
    return x / weight, y / weight
  end
  for _ = 1, iterations do
    fit_rotations()
    for _ = 1, 16 do
      for i, links in ipairs(adjacency) do
        if not pins[i] then positions[i] = {update(i, links)} end
      end
    end
  end
  fit_rotations()
  local residual = 0
  for i, links in ipairs(adjacency) do
    if not pins[i] then
      local x, y = update(i, links)
      residual = math.max(residual, math.abs(x - positions[i][1]), math.abs(y - positions[i][2]))
    end
  end
  return positions, {iterations = iterations, residual = residual}
end

return M
