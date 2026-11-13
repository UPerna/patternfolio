-- Exact triangular-chart adaptation of the HatViz H/T/P/F placement data.
-- Copyright (c) 2023, Craig S. Kaplan, BSD-3-Clause.
-- See docs/research/licenses/HATVIZ-BSD-3-Clause.txt and the source receipt.
local P,R=require("pattern"),require("pattern_exact")
local M={}
local function rational(p) return {R.new(p[1]),R.new(p[2])} end
local function chart(points)
  local out={}
  for i,p in ipairs(points) do out[i]=rational(p) end
  return out
end
local function integral(p)
  assert(p[1][2]==1 and p[2][2]==1,"hat-leaf-outside-integer-chart")
  return {p[1][1],p[2][1]}
end
local outline=chart{{0,0},{-1,-1},{0,-2},{2,-2},{2,-1},{4,-2},{5,-1},
  {4,0},{3,0},{2,2},{0,3},{0,2},{-1,2}}
local kite=chart{{0,0},{1,1},{0,2},{-1,2}}
local kite_placements={{0,0,0},{0,0,3},{0,0,4},{0,0,5},{2,2,2},{2,2,3},{4,-2,0},{4,-2,1}}
local function add(a,b) return {R.add(a[1],b[1]),R.add(a[2],b[2])} end
local function sub(a,b) return {R.sub(a[1],b[1]),R.sub(a[2],b[2])} end
local function rotate(p,turn)
  local a,b=p[1],p[2]
  for _=1,turn%6 do a,b=R.neg(b),R.add(a,b) end
  return {a,b}
end
local function linear(p,t)
  if t.reflected then p={R.add(p[1],p[2]),R.neg(p[2])} end
  return rotate(p,t.turn)
end
local function apply(t,p) return add(t.offset,linear(p,t)) end
local function transform(turn,offset,reflected)
  return {turn=turn%6,offset=offset,reflected=reflected or false}
end
local identity=transform(0,rational{0,0})
local function compose(a,b)
  return transform(a.turn+(a.reflected and -b.turn or b.turn),apply(a,b.offset),a.reflected~=b.reflected)
end
local function equal(a,b) return R.compare(a[1],b[1])==0 and R.compare(a[2],b[2])==0 end
local function match(a,b,p,q)
  local source,target=sub(b,a),sub(q,p)
  assert(not equal(source,identity.offset),"hat-degenerate-guide-edge")
  for turn=0,5 do
    if equal(rotate(source,turn),target) then
      return transform(turn,sub(p,rotate(a,turn)))
    end
  end
  error("hat-guide-isometry-mismatch")
end
local function det(a,b) return R.sub(R.mul(a[1],b[2]),R.mul(a[2],b[1])) end
local function intersection(p,q,a,b)
  local x,y=sub(q,p),sub(b,a)
  local d,n=det(x,y),det(sub(a,p),y)
  assert(d[1]~=0,"hat-parallel-guides")
  local t=R.div(n,d)
  return add(p,{R.mul(x[1],t),R.mul(x[2],t)})
end
local function slot(shape,t) return {shape=shape,transform=t} end
local function meta(name,guide,children) return {name=name,guide=guide,children=children} end
local function leaf(name) return {name=name} end
local function seeds()
  local h=chart{{0,0},{8,0},{8,2},{0,10},{-2,10},{-2,2}}
  return {
    H=meta("H",h,{
      slot(leaf("H"),match(outline[6],outline[8],h[6],h[1])),
      slot(leaf("H"),match(outline[10],outline[12],h[2],h[3])),
      slot(leaf("H"),match(outline[6],outline[8],h[4],h[5])),
      slot(leaf("H1"),transform(2,rational{4,2},true))}),
    T=meta("T",chart{{0,0},{6,0},{0,6}},{slot(leaf("T"),transform(0,rational{0,2}))}),
    P=meta("P",chart{{0,0},{8,0},{4,4},{-4,4}},
      {slot(leaf("P"),transform(0,rational{2,2})),slot(leaf("P"),transform(-1,rational{-2,4}))}),
    F=meta("F",chart{{0,0},{6,0},{6,2},{4,4},{-4,4}},
      {slot(leaf("F"),transform(0,rational{2,2})),slot(leaf("F"),transform(-1,rational{-2,4}))}),
  }
end
-- The pinned reference's 0-based placement indices, translated by accessors.
local placement={
  {"H"},{0,0,"P",2},{1,0,"H",2},{2,0,"P",2},{3,0,"H",2},{4,4,"P",2},
  {0,4,"F",3},{2,4,"F",3},{4,1,3,2,"F",0},{8,3,"H",0},{9,2,"P",0},
  {10,2,"H",0},{11,4,"P",2},{12,0,"H",2},{13,0,"F",3},{14,2,"F",1},
  {15,3,"H",4},{8,2,"F",1},{17,3,"H",0},{18,2,"P",0},{19,2,"H",2},
  {20,4,"F",3},{20,0,"P",2},{22,0,"H",2},{23,4,"F",3},{23,0,"F",3},
  {16,0,"P",2},{9,4,0,2,"T",2},{4,0,"F",3},
}
local function next_level(shapes)
  local patch={}
  local function vertex(slot_index,point_index)
    local child=patch[slot_index+1]
    local guide=child.shape.guide
    return apply(child.transform,guide[point_index%#guide+1])
  end
  for _,row in ipairs(placement) do
    if #row==1 then
      patch[#patch+1]=slot(shapes[row[1]],identity)
    else
      local a,b,shape,index
      if #row==4 then
        a,b=vertex(row[1],row[2]+1),vertex(row[1],row[2])
        shape,index=shapes[row[3]],row[4]
      else
        a,b=vertex(row[3],row[4]),vertex(row[1],row[2])
        shape,index=shapes[row[5]],row[6]
      end
      local g=shape.guide
      patch[#patch+1]=slot(shape,match(g[index+1],g[(index+1)%#g+1],a,b))
    end
  end
  local function children(indices)
    local out={}
    for _,i in ipairs(indices) do out[#out+1]=patch[i+1] end
    return out
  end
  local bps1,bps2=vertex(8,2),vertex(21,2)
  local p62,p72,p252=vertex(6,2),vertex(7,2),vertex(25,2)
  local rbps=add(bps1,rotate(sub(bps2,bps1),-2))
  local llc=intersection(bps1,rbps,p62,p72)
  local w=rotate(sub(p62,llc),-1)
  local h2,h3=add(bps1,w),vertex(14,2)
  local h4=sub(h3,rotate(w,-1))
  local t0=add(bps1,sub(h4,p62))
  local t1=add(t0,rotate(sub(h2,t0),-1))
  return {
    H=meta("H",{llc,bps1,h2,h3,h4,p62},children{0,9,16,27,26,6,1,8,10,15}),
    T=meta("T",{t0,t1,h2},children{11}),
    P=meta("P",{p72,add(p72,sub(bps1,llc)),bps1,llc},children{7,2,3,4,28}),
    F=meta("F",{bps2,vertex(24,2),vertex(25,0),p252,add(p252,sub(llc,bps1))},
      children{21,20,22,23,24,25}),
  }
end
local function world_points(shape,t)
  local out={}
  for _,p in ipairs(shape) do out[#out+1]=apply(t,p) end
  return out
end
function M.cluster(root,depth)
  assert(type(depth)=="number" and depth%1==0 and depth>=1 and depth<=3,"hat-depth")
  local shapes=seeds()
  for _=2,depth do shapes=next_level(shapes) end
  local tree=assert(shapes[root],"hat-root")
  local leaves,nodes={},{}
  local lo={}
  local function visit(shape,t,address,parent)
    if shape.children then
      local guide=world_points(shape.guide,t)
      local record={address=address,parent=parent,label=shape.name,guide=guide,transform=t,children={}}
      nodes[#nodes+1]=record
      for i,child in ipairs(shape.children) do
        local path={table.unpack(address)}
        path[#path+1]=i
        record.children[i]=path
        visit(child.shape,compose(t,child.transform),path,address)
      end
    else
      local points=world_points(outline,t)
      for _,p in ipairs(points) do
        for i=1,2 do if not lo[i] or R.compare(p[i],lo[i])<0 then lo[i]=p[i] end end
      end
      leaves[#leaves+1]={address=address,parent=parent,label=shape.name,points=points,transform=t}
    end
  end
  visit(tree,identity,P.array(),nil)
  local lines,reflections={},0
  for i,item in ipairs(leaves) do
    local t=transform(item.transform.turn,sub(item.transform.offset,lo),item.transform.reflected)
    item.transform=transform(t.turn,integral(t.offset),t.reflected)
    local coordinates={}
    item.kites={}
    for j,p in ipairs(item.points) do
      p=integral(sub(p,lo));item.points[j]=p;coordinates[j]=p[1]..","..p[2]
    end
    for j,placed in ipairs(kite_placements) do
      local q=compose(t,transform(placed[3],rational{placed[1],placed[2]}))
      local k=world_points(kite,q)
      for n,p in ipairs(k) do k[n]=integral(p) end
      item.kites[j]=k
    end
    if t.reflected then reflections=reflections+1 end
    lines[i]=table.concat(item.address,".")..":"..item.label..":"..(t.reflected and "-" or "+")..":"..table.concat(coordinates,";")
  end
  for _,item in ipairs(nodes) do
    item.transform=transform(item.transform.turn,sub(item.transform.offset,lo),item.transform.reflected)
    for i,p in ipairs(item.guide) do item.guide[i]=sub(p,lo) end
  end
  return {nodes=nodes,leaves=leaves,reflection_count=reflections,reference_bytes=table.concat(lines,"\n")}
end
return M
