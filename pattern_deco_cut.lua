-- Exact integral s/t cut over the overlap lattice.
local M = {}

function M.solve(width, height, capacity)
  assert(width >= 2 and height >= 1 and width * height <= 4096, "invalid overlap lattice")
  local count = width * height
  local source, sink = count + 1, count + 2
  local graph, links, total = {}, {}, 0
  for i = 1, sink do graph[i] = {} end
  local function arc(a, b, cost, back)
    local e = {to = b, remaining = cost}
    local r = {to = a, remaining = back}
    e.reverse, r.reverse = r, e
    graph[a][#graph[a] + 1] = e
    graph[b][#graph[b] + 1] = r
  end
  local function connect(a, b)
    local forward, backward = capacity(a, b), capacity(b, a)
    assert(forward >= 0 and forward % 1 == 0 and backward >= 0 and backward % 1 == 0)
    arc(a, b, forward, backward)
    links[#links + 1] = {a, b, forward, backward}
    total = total + forward + backward
  end
  for y = 1, height do
    for x = 1, width do
      local i = (y - 1) * width + x
      if x < width then connect(i, i + 1) end
      if y < height then connect(i, i + width) end
    end
  end
  local forced = total + 1
  for y = 1, height do
    arc(source, (y - 1) * width + 1, forced, 0)
    arc(y * width, sink, forced, 0)
  end
  local function layers()
    local levels, queue = {[source] = 0}, {source}
    local i = 1
    while queue[i] do
      local a = queue[i]
      for _, e in ipairs(graph[a]) do
        if e.remaining > 0 and not levels[e.to] then
          levels[e.to] = levels[a] + 1
          queue[#queue + 1] = e.to
        end
      end
      i = i + 1
    end
    return levels
  end
  local flow, levels = 0, layers()
  while levels[sink] do
    local next_arc = {}
    local function send(a, amount)
      if a == sink then return amount end
      local i = next_arc[a] or 1
      while graph[a][i] do
        local e = graph[a][i]
        if e.remaining > 0 and levels[e.to] == levels[a] + 1 then
          local used = send(e.to, math.min(amount, e.remaining))
          if used > 0 then
            e.remaining = e.remaining - used
            e.reverse.remaining = e.reverse.remaining + used
            return used
          end
        end
        i = i + 1
        next_arc[a] = i
      end
      return 0
    end
    local pushed = send(source, forced)
    while pushed > 0 do
      flow = flow + pushed
      pushed = send(source, forced)
    end
    levels = layers()
  end
  local labels, cost, straight = {}, 0, 0
  for i = 1, count do labels[i] = levels[i] ~= nil end
  local function middle(i) return (i - 1) % width < math.floor(width / 2) end
  local function contribution(a, b, f, r) return a == b and 0 or (a and f or r) end
  for _, edge in ipairs(links) do
    local a, b, f, r = table.unpack(edge)
    cost = cost + contribution(labels[a], labels[b], f, r)
    straight = straight + contribution(middle(a), middle(b), f, r)
  end
  assert(flow == cost and cost <= straight, "cut certificate mismatch")
  return labels, {flow = flow, energy = cost, straight_energy = straight}
end

return M
