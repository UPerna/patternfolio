local M = {}
local sqrt, abs = math.sqrt, math.abs
local epsilon = 1e-8

local function radicand(value)
  assert(value >= -epsilon, "gothic-invalid-circle-intersection")
  return sqrt(math.max(0, value))
end

function M.top(circle, x)
  local dx = x - circle.center[1]
  return circle.center[2] + circle.branch * radicand(circle.radius ^ 2 - dx ^ 2)
end

function M.side(length, height, join)
  assert(height > length and length > 0 and join > epsilon and join < length - epsilon,
    "gothic-side-chart-requires-height-greater-than-run-and-interior-crossing")
  local r = (length ^ 2 + height ^ 2) / (2 * length)
  local t = join / length
  return {length=length, height=height, join={join, t * height},
    lower={center={t * r, 0}, radius=t * r, curvature=-1},
    upper={center={length - (1 - t) * r, height}, radius=(1 - t) * r, curvature=1}}
end

function M.height(side, x)
  if x <= 0 then return 0 end
  if x >= side.length then return side.height end
  if x <= side.join[1] then
    return radicand(x * (2 * side.lower.radius - x))
  end
  local d = side.length - x
  return side.height - radicand(d * (2 * side.upper.radius - d))
end

function M.point(unit, replica, x)
  return {replica.x + replica.sx * x, replica.y + replica.sy * M.top(unit.circle, x),
    unit.origin[3] + M.height(unit.side, x - unit.start)}
end

-- Intersect the two full compass circles, then retain points on both selected arcs.
function M.crossings(unit, a, b)
  local c = unit.circle.center
  local ax, ay = a.x + a.sx * c[1], a.y + a.sy * c[2]
  local bx, by = b.x + b.sx * c[1], b.y + b.sy * c[2]
  local dx, dy = bx - ax, by - ay
  local d = sqrt(dx ^ 2 + dy ^ 2)
  assert(d > epsilon, "gothic-coincident-replica-circles")
  local result = {}
  local r = unit.circle.radius
  if d >= 2 * r - epsilon then return result end
  local h = radicand(r ^ 2 - d ^ 2 / 4)
  for _, sign in ipairs({-1, 1}) do
    local x, y = (ax + bx) / 2 - sign * h * dy / d, (ay + by) / 2 + sign * h * dx / d
    local ua, ub = a.sx * (x - a.x), b.sx * (x - b.x)
    if ua >= unit.start and ua <= unit.finish and ub >= unit.start and ub <= unit.finish
      and abs(a.y + a.sy * M.top(unit.circle, ua) - y) < epsilon
      and abs(b.y + b.sy * M.top(unit.circle, ub) - y) < epsilon then
      result[#result + 1] = {top={x,y}, a=ua, b=ub, joined=abs(ua-ub)<epsilon}
    end
  end
  return result
end

-- The sole extremum of the graph's deviation from its chord occurs where
-- the circle tangent equals the chord slope. Evaluate that point exactly.
local function chord_error(circle, lo, hi, evaluate)
  local a, b = evaluate(lo), evaluate(hi)
  local slope = (b - a) / (hi - lo)
  local x = circle.center[1] - circle.branch * circle.radius * slope / sqrt(1 + slope ^ 2)
  x = math.max(lo, math.min(hi, x))
  return abs(evaluate(x) - (a + slope * (x - lo)))
end

function M.sample(unit, knots, tolerance, context)
  local result = {knots[1]}
  local function refine(a, b, depth)
    context:consume("operations", 1)
    local x0 = unit.start
    local side = unit.side
    local upper = a >= x0 + side.join[1]
    local arc = upper and side.upper or side.lower
    local circle = {center={x0 + arc.center[1], arc.center[2]}, radius=arc.radius,
      branch=upper and -1 or 1}
    local et = chord_error(unit.circle, a, b, function(x) return M.top(unit.circle, x) end)
    local ez = chord_error(circle, a, b, function(x) return M.height(side, x - x0) end)
    if sqrt(et ^ 2 + ez ^ 2) <= tolerance * .999 then
      context:consume("objects", 1)
      result[#result + 1] = b
      return
    end
    assert(depth < 24, "gothic-sampling-resolution")
    local mid = (a + b) / 2
    refine(a, mid, depth + 1)
    refine(mid, b, depth + 1)
  end
  for i = 2, #knots do refine(knots[i-1], knots[i], 0) end
  return result
end

return M
