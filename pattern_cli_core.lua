local P,Q,R,H,V=require("pattern"),require("pattern_recipe"),require("pattern_registry"),
  require("pattern_hash"),require("pattern_render")
local Parse=require("pattern_parse")
local M={VERSION="pattern-cli-v1"}
local families={
  ["botanical/legacy-authored"]={"pattern_botanical_legacy","authored"},
  ["botanical/legacy-grown"]={"pattern_botanical_legacy","grown"},
  ["botanical/asymmetric-garden"]={"pattern_botanical_panel"},
  ["tiling/periodic"]={"pattern_periodic"},
  ["strand/celtic"]={"pattern_celtic"},
  ["ornament/islamic-pic"]={"pattern_islamic"},
  ["ornament/islamic-freeform"]={"pattern_freeform"},
  ["tiling/finite-substitution"]={"pattern_aperiodic"},
  ["tiling/penrose-p3"]={"pattern_penrose"},
  ["tiling/spectre"]={"pattern_spectre"},
  ["tiling/ammann-beenker"]={"pattern_ammann_beenker"},
  ["tiling/hat"]={"pattern_hat"},
  ["tiling/marked-square-completion"]={"pattern_bounded_tiles"},
  ["ornament/gothic-tracery"]={"pattern_tracery"},
  ["tiling/escherization"]={"pattern_escher"},
  ["mosaic/hausner"]={"pattern_mosaic"},
  ["stroke/fields-and-examples"]={"pattern_stroke"},
  ["maze/image-guided"]={"pattern_maze"},
  ["text/digital-micrography"]={"pattern_micrography"},
  ["decoration/decobrush"]={"pattern_decobrush"},
  ["gothic/spatial-ogee"]={"pattern_gothic_microarchitecture"},
  ["collection/ornament"]={"pattern_collection_assets"},
}

function M.registry(family)
  local entry=assert(families[family],"cli-unsupported-family:"..tostring(family))
  local module=require(entry[1])
  local registry=R.new()
  local definition=module.register(registry,entry[2])
  assert(definition.id==family,"cli-family-catalog-mismatch")
  return registry,definition
end

local function request(data)
  assert(type(data)=="table" and data.schema_version==1,"cli-request-version")
  local fields={schema_version=true,command=true,family=true,formats=true,limits=true,dependencies=true,
    instance_transport=true,previous_recipe=true,edits=true}
  for k in pairs(data) do assert(fields[k],"cli-request-field:"..tostring(k)) end
  assert(data.previous_recipe==nil or data.previous_recipe==true,"cli-previous-recipe-flag")
  assert(not data.previous_recipe or data.command=="render" or data.command=="replay","cli-previous-recipe-command")
  assert(data.edits==nil or type(data.edits)=="table","cli-edits-object")
  assert(data.edits==nil or data.command=="validate"or data.command=="generate"or data.command=="render"or data.command=="replay","cli-edits-command")
  local formats=data.formats or {"pdf","svg"}
  assert(type(formats)=="table" and #formats<=2,"cli-formats")
  local seen={}
  for _,f in ipairs(formats) do
    assert((f=="pdf" or f=="svg") and not seen[f],"cli-format")
    seen[f]=true
  end
  return formats
end

function M.dispatch(data,host)
  local formats=request(data)
  local command=data.command
  local outputs={}
  if command=="capabilities" then
    local list=P.array()
    for family in pairs(families) do list[#list+1]=family end
    table.sort(list,P.byte_less)
    outputs["report.json"]=P.serialize({schema_version=1,cli=M.VERSION,families=list,
      commands={"capabilities","schema","validate","generate","validate-instance","render","replay","batch","diagnose"},
      formats={"pdf","svg"},recipe_schema_version=1,instance_schema_version=1,
      input_limit_bytes=2*1024*1024,recipe_edits={schema_version=1,flag="edits",planner_preserved=true},output_profiles={"source","monochrome","palette"},view_style_revision={flag="previous_recipe",previous_file="previous-recipe.json",structural_generation=false},optional_providers="Declared by each family's schema and recipe"})
    return outputs
  end
  if command=="schema" then
    local _,definition=M.registry(data.family)
    outputs["report.json"]=P.serialize({schema_version=1,definition=P.plain(definition),
      recipe_fields={"kind","schema_version","id","definition","design","view","dimension","dependencies"},
      contracts={"definition","instance","view","scene","build_record"}})
    return outputs
  end
  if command=="diagnose" then
    local record=P.build_record(Parse.decode(host.read("record.json")))
    outputs["report.json"]=P.serialize({status=record.status,diagnostics=P.plain(record.diagnostics),
      validation=P.plain(record.validation),budgets=P.plain(record.budgets),lineage=P.plain(record.lineage)})
    return outputs
  end
  local recipe=Q.decode(host.read("recipe.json"))
  if data.edits then
    local receipt;recipe,receipt=require("pattern_editor").apply(recipe,data.edits)
    outputs["edit-receipt.json"]=P.serialize(receipt);outputs["recipe.json"]=Q.encode(recipe)
  end
  local registry,definition=M.registry(recipe.definition.id)
  assert(P.serialize(definition)==P.serialize(recipe.definition),"cli-definition-version-mismatch")
  registry:check_specification(definition.id,recipe.design)
  if command=="validate" then
    outputs["report.json"]=P.serialize({schema_version=1,status="complete",family=definition.id,
      recipe_sha256=H.sha256(Q.encode(recipe)),structural_input_sha256=Q.structural_digest(recipe),checks={"Recipe schema, registered definition and family input preconditions"}})
    return outputs
  end
  assert(command=="generate" or command=="replay" or command=="render" or command=="validate-instance",
    "cli-unsupported-command")
  local source,hashes=host.source(),{}
  for name,bytes in pairs(source) do hashes[name]=H.sha256(bytes) end
  local dependencies={}
  for i,name in ipairs(data.dependencies or {}) do
    assert(type(name)=="string" and not dependencies[name],"cli-dependency-name")
    dependencies[name]=host.read("dependency-"..i..".bin")
  end
  local environment=Q.environment({revision="source/"..H.value("cli/source",hashes),
      files={construction=source,style={},view={},renderer={}}},
    {lua=_VERSION,host=host.runtime},{id=V.VERSION,version="1"},dependencies)
  local result
  if command=="generate" then
    result=Q.execute(recipe,registry,environment,{limits=data.limits})
  else
    local instance
    if data.instance_transport then
      assert(data.instance_transport=="legacy-neutral-bundle@1"
        and recipe.definition.id:match("^botanical/legacy%-"),"cli-instance-transport")
      instance=require("pattern_botanical_legacy").decode_bundle(host.read("instance.json"),
        function(sha) return host.read("block-"..sha..".json") end,definition)
    else instance=Parse.instance(host.read("instance.json")) end
    if data.previous_recipe then
      result=Q.revise(recipe,Q.decode(host.read("previous-recipe.json")),instance,Parse.decode(host.read("record.json")),
        registry,environment,{limits=data.limits})
    else
      result=Q.replay(recipe,instance,Parse.decode(host.read("record.json")),
        registry,environment,{limits=data.limits})
    end
  end
  outputs["record.json"]=P.serialize(result.record)
  if result.record.status~="complete" then
    return outputs,{status=result.record.status,code="construction_failed",messages=P.plain(result.record.diagnostics)}
  end
  outputs["recipe.json"]=Q.encode(recipe)
  if result.instance.extensions.legacy then
    local manifest,blocks=require("pattern_botanical_legacy").encode_bundle(result.instance)
    outputs["instance.json"]=manifest
    outputs["instance-format.json"]=P.serialize({schema="legacy-neutral-bundle@1",
      instance_sha256=H.sha256(result.bytes.instance),manifest_sha256=H.sha256(manifest)})
    for sha,bytes in pairs(blocks) do outputs["block-"..sha..".json"]=bytes end
  else outputs["instance.json"]=result.bytes.instance end
  outputs["view.json"]=P.serialize(result.view)
  outputs["scene.json"]=result.bytes.scene
  if command~="validate-instance" then
    local plan=V.plan(result.scene,result.instance,result.view,definition)
    for _,format in ipairs(formats) do
      outputs["pattern."..format]=V[format](plan)
    end
    if result.instance.structures.curve3d then
      outputs["network.json"]=require("pattern_gothic_microarchitecture").export(result.instance)
    end
  end
  return outputs
end

return M
