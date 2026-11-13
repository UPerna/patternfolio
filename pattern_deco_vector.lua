-- Extract a piecewise-linear zero contour on the same triangulated sampling chart.
local M = {}

function M.contours(field)
  local width, height, grid = field.width, field.height, field.grid
  local vertices, outgoing, boundary = {}, {}, {}
  local function vertex(i)
    local k = tostring(i)
    vertices[k] = grid[i]
    return k
  end
  local function crossing(i,j)
    if j < i then i,j = j,i end
    local a,b = grid[i],grid[j]
    local u,v = a.source.distance,b.source.distance
    if u == 0 then return vertex(i) end
    if v == 0 then return vertex(j) end
    local k = i.."/"..j
    if not vertices[k] then
      local t = u/(u-v)
      vertices[k] = {x=a.x+t*(b.x-a.x),y=a.y+t*(b.y-a.y)}
    end
    return k
  end
  local area = 0
  local function triangle(a,b,c)
    local p,q,r = grid[a],grid[b],grid[c]
    assert((q.x-p.x)*(r.y-p.y)-(q.y-p.y)*(r.x-p.x)>0,"folded contour chart")
    local clipped = {}
    for _,edge in ipairs({{a,b},{b,c},{c,a}}) do
      local i,j = table.unpack(edge)
      local inside = grid[i].source.distance < 0
      if inside then clipped[#clipped+1] = vertex(i) end
      if inside ~= (grid[j].source.distance < 0) then
        clipped[#clipped+1] = crossing(i,j)
      end
    end
    for i,k in ipairs(clipped) do
      local l = clipped[i%#clipped+1]
      if k ~= l then
        local x,y = vertices[k],vertices[l]
        area = area + (x.x*y.y-x.y*y.x)/2
        local reverse = l..":"..k
        if boundary[reverse] then boundary[reverse] = nil
        else boundary[k..":"..l] = {k,l} end
      end
    end
  end
  for y = 1,height-1 do
    for x = 1,width-1 do
      local a = (y-1)*width+x
      triangle(a,a+1,a+width+1)
      triangle(a,a+width+1,a+width)
    end
  end
  local keys = {}
  for k,edge in pairs(boundary) do
    local a,b = table.unpack(edge)
    assert(not outgoing[a],"ambiguous zero-contour vertex")
    outgoing[a] = b
    keys[#keys+1] = k
  end
  table.sort(keys)
  local loops, traced = {}, 0
  for _,k in ipairs(keys) do
    local start = boundary[k][1]
    if outgoing[start] then
      local ring, a = {}, start
      repeat
        local b = assert(outgoing[a],"open zero contour")
        outgoing[a] = nil
        local p,q = vertices[a],vertices[b]
        traced = traced + (p.x*q.y-p.y*q.x)/2
        ring[#ring+1] = {p.x,p.y}
        a = b
      until a == start
      loops[#loops+1] = ring
    end
  end
  return loops,{filled_area=area,contour_area=traced,residual=math.abs(area-traced)}
end

return M
