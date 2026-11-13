local Field = require("pattern_deco_field")
local Refine = require("pattern_deco_refine")
local Vector = require("pattern_deco_vector")

local function rect(left,bottom,right,top)
  return {ring={{left,bottom},{right,bottom},{right,top},{left,top}}}
end

local guide = {{0,0,.6},{1,.04,.6},{2,.12,.6},{3,.24,.6}}
local library = {
  {role="start",length=1,width=.6,turn=0,primitives={rect(.08,-.1,1.5,.1)}},
  {role="middle",length=1,width=.6,turn=0,primitives={
    rect(-.5,-.1,1.5,.1),rect(.42,.04,.60,.22)}},
  {role="finish",length=1,width=.6,turn=0,primitives={rect(-.5,-.1,.92,.1)}},
}
local options = {subdivisions=16,rows=17,iterations=20,outside=.6,
  match={min_steps=1,max_steps=1,min_stretch=.8,max_stretch=1.2,seam_weight=1},
  distortion={min_jacobian=.6,min_stretch=.7,max_stretch=1.3,max_residual=.01}}

local field = assert(Field.synthesize(guide,library,options))
assert(#field.matches==3 and #field.seams==2)
local loops, area = Vector.contours(field)
assert(#loops==1 and area.contour_area>.5 and area.residual<1e-9)

local edited, frozen = {}, {}
for i,p in ipairs(field.grid) do
  if p.x>1.40 and p.x<1.65 and p.y>.18 and p.y<.30 then
    edited[i] = true
  else
    frozen[i] = p.source
  end
end
local index
for i,p in ipairs(field.grid) do
  if edited[i] and p.y>.235 and p.source.distance<-.012 then index=i; break end
end
assert(index,"missing ink on the branch to erase")
local refinement = Refine.apply(field,library,edited,{[index]=false},.13)
assert(#refinement.unsatisfied==0 and field.grid[index].source.distance>0)
for i,p in pairs(frozen) do assert(field.grid[i].source==p) end
local revised, proof = Vector.contours(field)
assert(#revised>=1 and math.abs(proof.contour_area-area.contour_area)>1e-6 and proof.residual<1e-9)
print("DecoBrush integration passed: guide, joins, connected branch, masked erase and vector area")
