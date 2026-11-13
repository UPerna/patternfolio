-- Real legacy primitives behind new named semantic streams; not full-page migration.
local P,ink,flora=require("pattern"),require("ink"),require("flora")
local M={}
function M.construct(context,visitors)
  local nodes,resources={},{}
  local function motif(id,kind,x,y,size)
    local parts,states={},{};local old=ink.backend
    ink.set_backend({literal=function(s)parts[#parts+1]=s end,extgs=function(k,v)states[k]=v end})
    local ok,err=pcall(function()
      ink.set_color_mode("color");ink.set_ink(0.14,0.34,0.77);ink.set_accent(0.7,0.4,0.2)
      ink.set_transform({ink.CM,0,0,ink.CM,x*ink.CM,y*ink.CM})
      -- Each existing primitive receives its own owned legacy RNG. No call-order fork.
      local rng=ink.rng(context:stream("motifs",id).next_integer())
      flora[kind](rng,size);ink.flush()
    end)
    ink.set_backend(old);assert(ok,err)
    context:consume("objects",1)
    nodes[#nodes+1]={id=id,point={x,y},motif=kind,size=size}
    resources[id]={content=table.concat(parts,"\n"),graphics_states=states}
  end
  motif("plant/root/flower/0","flower",1,1,0.8)
  if visitors then motif("visitors/bee/0","bee",2,2,0.6) end
  motif("plant/root/flower/1","flower",3,1,0.7)
  return P.snapshot({nodes=nodes,resources=resources})
end
return M
