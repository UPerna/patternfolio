-- Exemplar ink is the union of closed polygonal primitives in spine/rib coordinates.
local M = {}
local eps = 1e-10

local function inside(ring, x, y)
  local hit = false
  local a = ring[#ring]
  for _, b in ipairs(ring) do
    if (a[2] > y) ~= (b[2] > y)
      and x < a[1] + (b[1] - a[1]) * (y - a[2]) / (b[2] - a[2]) then
      hit = not hit
    end
    a = b
  end
  return hit
end

local function cross(ax, ay, bx, by) return ax * by - ay * bx end

local function split(edge, other, stops)
  local x, y, u, v = table.unpack(edge)
  local a, b, c, d = table.unpack(other)
  local dx, dy, ex, ey = u - x, v - y, c - a, d - b
  local determinant = cross(dx, dy, ex, ey)
  if math.abs(determinant) > eps then
    local t = cross(a - x, b - y, ex, ey) / determinant
    local s = cross(a - x, b - y, dx, dy) / determinant
    if t > eps and t < 1 - eps and s >= -eps and s <= 1 + eps then
      stops[#stops + 1] = t
    end
  elseif math.abs(cross(a - x, b - y, dx, dy)) < eps then
    local length = dx * dx + dy * dy
    for _, p in ipairs({{a, b}, {c, d}}) do
      local t = ((p[1] - x) * dx + (p[2] - y) * dy) / length
      if t > eps and t < 1 - eps then stops[#stops + 1] = t end
    end
  end
end

function M.prepare(primitives)
  local edges = {}
  for _, primitive in ipairs(primitives) do
    local ring = primitive.ring
    assert(#ring >= 3, "exemplar primitive needs a closed polygon")
    local a = ring[#ring]
    for _, b in ipairs(ring) do
      assert(a[1] ~= b[1] or a[2] ~= b[2], "degenerate exemplar edge")
      edges[#edges + 1] = {a[1], a[2], b[1], b[2]}
      a = b
    end
  end
  assert(#edges > 0 and #edges <= 256, "exemplar edge budget exceeded")
  local function ink(x, y)
    for _, primitive in ipairs(primitives) do
      if inside(primitive.ring, x, y) then return true end
    end
    return false
  end
  local exposed = {}
  for _, edge in ipairs(edges) do
    local stops = {0, 1}
    for _, other in ipairs(edges) do
      if edge ~= other then split(edge, other, stops) end
    end
    table.sort(stops)
    local x, y, u, v = table.unpack(edge)
    local dx, dy = u - x, v - y
    local delta = 1e-8 / math.sqrt(dx * dx + dy * dy)
    for i = 2, #stops do
      local a, b = stops[i - 1], stops[i]
      if b - a > eps then
        local t = (a + b) / 2
        local px, py = x + t * dx, y + t * dy
        if ink(px - delta * dy, py + delta * dx) ~= ink(px + delta * dy, py - delta * dx) then
          exposed[#exposed + 1] = {x + a * dx, y + a * dy, x + b * dx, y + b * dy}
        end
      end
    end
  end
  assert(#exposed > 0, "exemplar has no exposed ink boundary")
  return function(x, y)
    local best = math.huge
    for _, edge in ipairs(exposed) do
      local a, b, c, d = table.unpack(edge)
      local dx, dy = c - a, d - b
      local t = math.max(0, math.min(1, ((x - a) * dx + (y - b) * dy) / (dx * dx + dy * dy)))
      best = math.min(best, (x - a - t * dx)^2 + (y - b - t * dy)^2)
    end
    return (ink(x, y) and -1 or 1) * math.sqrt(best)
  end
end

return M
