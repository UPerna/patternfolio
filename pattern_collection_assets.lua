local P=require("pattern")
local M={}
local kinds={leaf=true,flower=true,divider=true,initial=true,folio=true}

function M.definition()
  return P.definition({id="collection/ornament",version="1",family="original-collection-asset",
    units="cm",capabilities={"growth","text"},
    parameters={size={type="number",minimum=.2,maximum=2}},
    transforms={metric_constrained=false,reflection=false,uniform_scale=true},
    assumptions={"Native original botanical primitives","Upright font outlines and logical text labels"}})
end

local function input(s)
  for k in pairs(s.inputs) do assert(k=="kind" or k=="text" or k=="font","collection-asset-input") end
  assert(next(P.plain(s.constraints))==nil,"collection-asset-constraints")
  local kind=s.inputs.kind
  assert(kinds[kind],"collection-asset-kind")
  local text=s.inputs.text or ""
  assert(type(text)=="string" and utf8.len(text) and #text<=16,"collection-asset-text")
  if kind=="initial" or kind=="folio" then
    assert(#text>0 and (kind~="initial" or utf8.len(text)==1),"collection-label-length")
    assert(type(s.inputs.font)=="table","collection-label-font")
  else assert(text=="","collection-ornament-has-no-text") end
  return kind,text
end

function M.register(registry)
  local d=M.definition()
  registry:register(d,{validate_inputs=function(s) input(s);return true end,
    generate=function(s,c)
      local kind,text=input(s)
      local size=s.parameters.size or 1
      local ink,flora=require("ink"),require("flora")
      local ops=ink.capture(function()
        ink.set_ink(.13,.27,.35);ink.set_accent(.62,.36,.21);ink.set_lift(0);ink.set_color_mode("color")
        ink.translate(2,1.6)
        if kind=="flower" then flora.flower(ink.rng(s.seed),size*.65)
        elseif kind=="divider" then flora.divider(ink.rng(s.seed),size)
        else
          ink.push();ink.translate(-.7,-.5);ink.scale(size*.9)
          flora.leaf(ink.rng(s.seed),{w=.32,bend=.12,lobes=3,depth=.3,tone=.35})
          ink.pop()
        end
      end)
      c:consume("operations",#ops)
      c:consume("objects",#ops)
      for _,op in ipairs(ops) do if op.op=="path" then op.semantic_ref="asset/root" end end
      local runs,order=P.array(),P.array()
      if #text>0 then
        runs[1]={id="asset/label",text=text,direction="ltr"}
        order[1]="asset/label"
      end
      return {id=s.id.."/asset",definition_ref={id=d.id,version=d.version},frame=P.plain(c.frame),
        structures={growth={nodes={{id="asset/root",point={2,1.6},motif=kind}},roots={"asset/root"}},
          text={runs=runs,reading_order=order}},
        provenance={generator=d.id,generator_version=d.version,seed=s.seed,construction="original-collection-asset-v1"},
        extensions={collection_asset={kind=kind,size=size,operations=ops,font=s.inputs.font and P.plain(s.inputs.font)}}}
    end,
    validate=function(x)
      assert(kinds[x.extensions.collection_asset.kind] and #x.extensions.collection_asset.operations>0,
        "collection-asset-empty")
      return {ok=true,checks={"Native botanical primitive emitted neutral paths","Declared upright label semantics"}}
    end,
    lower=function(x,v,style)
      assert(next(style)==nil,"collection-asset-style-use-shared-palette")
      local e=x.extensions.collection_asset
      local ops=P.plain(e.operations)
      local geom=require("pattern_geometry")
      for _,op in ipairs(ops) do
        if op.op~="pop_clip" then op.transform=geom.compose(P.plain(v.transform),op.transform or {1,0,0,1,0,0}) end
      end
      local resources=P.array()
      for _,run in ipairs(x.structures.text.runs) do
        local cmap={}
        for _,g in ipairs(e.font.glyphs) do cmap[g.unicode]=g end
        local glyphs=P.array()
        local advance=0
        for _,cp in utf8.codes(run.text) do
          local glyph=assert(cmap[utf8.char(cp)],"collection-label-unsupported-glyph")
          glyphs[#glyphs+1]={glyph_ref=glyph.id,offset={advance,0}}
          advance=advance+glyph.advance*e.size/e.font.units_per_em
        end
        assert(advance<=2.8,"collection-label-too-wide")
        ops[#ops+1]={op="text",semantic_ref=run.id,text=run.text,font_ref=e.font.id,
          origin={2-advance/2,1.7},size=e.size,glyphs=glyphs,transform=P.plain(v.transform),
          paint={fill={.13,.27,.35}}}
        resources[1]=P.plain(e.font)
      end
      return {id=x.id.."/scene",instance_ref=x.id,view_ref=v.id,unit="cm",validity=v.validity,
        operations=ops,resources=resources,reading_order=P.plain(x.structures.text.reading_order),
        clip={bounds=P.plain(v.crop),protected_regions=P.plain(v.protected_regions)}}
    end})
  return d
end

return M
