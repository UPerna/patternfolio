-- Compatibility bridge for existing neutral-captured primitive mathematics.
local P,B,G,H=require("pattern"),require("pattern_bounds"),require("pattern_geometry"),require("pattern_hash")
local M={}
function M.flower(seed,size)
  local ink,flora=require("ink"),require("flora")
  local operations,receipt=ink.capture(function()
    ink.set_color_mode("color");ink.set_ink(0x24/255,0x56/255,0xC4/255);ink.set_accent(0xB4/255,0x66/255,0x2F/255)
    ink.set_transform({ink.CM,0,0,ink.CM,3*ink.CM,3*ink.CM})
    flora.flower(ink.rng(seed),size)
  end)
  local bounds={};local policy=G.policy("cm",8)
  for _,o in ipairs(operations)do if o.op=="path"then bounds[#bounds+1]=B.path(o.commands,o.paint,nil,policy)end end
  local box=B.union(bounds,"cm");assert(not box.empty,"empty captured flower")
  local content=P.serialize({kind="vector_asset",schema_version=1,unit="cm",operations=operations})
  return {id="example/floral/resource",kind="symbol",unit="cm",bounds=P.plain(box.bounds),
    variants={scene={encoding="utf8",content=content,sha256=H.sha256(content),media_type="application/vnd.pattern.vector+json"}},provenance=receipt}
end
return M
