-- Real planner recipes for physical inline print-minimum regressions.
local P,Q,Planner,D=require('pattern'),require('pattern_recipe'),require('pattern_planner'),require('pattern_document')
local M={}
local function read(path)local f=assert(io.open(path,'rb'));local s=f:read('*a');f:close();return s end
function M.text(minimum)
  local q=Q.decode(read('examples/cli/micrography.recipe'))
  local _,definition=require('pattern_cli_core').registry(q.definition.id)
  local document=D.new({id='inline-text/document',unit='cm',frame={id='inline-text/world',origin={0,0}},twoside=false,
    pages={{id='page',number=1,size={13,7},origin={0,0},margins={0,0,0,0},protected_regions=P.array(),anchors=P.array()}},spreads=P.array()})
  local profile=Planner.profile(definition,{mode='view_only',construction_scale=1})
  local recipe,error=Planner.recipe(definition,q.design,document,'page',profile,{}, {minimum_text_size=minimum})
  assert(recipe,type(error)=='table' and error.message or tostring(error));return recipe
end
if arg and arg[0] and arg[0]:match('tex%-inline%-constraints%.lua$')then
  local folder=assert(arg[1],'output folder required')
  local stroke=P.plain(Q.decode(read('examples/cli/penrose.recipe')))
  stroke.view.extensions.document_planning.options.minimum_stroke=.000001
  for name,recipe in pairs({['inline-stroke-minimum']=stroke,['inline-text-minimum']=M.text(.000001)})do
    local f=assert(io.open(folder..'/'..name..'.recipe','wb'));assert(f:write(Q.encode(recipe)));assert(f:close())
  end
end
return M
