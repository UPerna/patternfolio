-- Versioned planner input, layered identities and reproducible build provenance.
local P,H,Random,R=require("pattern"),require("pattern_hash"),require("pattern_random"),require("pattern_registry")
local M={VERSION=1}
local input_bytes=setmetatable({},{__mode="k"})
local groups={"construction","style","view","renderer"}
local function limits(t)
  t=P.plain(t or {objects=10000,operations=100000,bytes=2*1024*1024})
  for k in pairs(t) do assert(k=="objects" or k=="operations" or k=="bytes","unknown execution budget "..tostring(k)) end
  for _,k in ipairs({"objects","operations","bytes"}) do assert(type(t[k])=="number" and t[k]>=0 and t[k]%1==0 and t[k]<math.huge,"invalid/missing execution budget "..k) end
  return t
end
local function keys(t,allowed,label)
  local set={};for k in allowed:gmatch('%S+') do set[k]=true end
  for k in pairs(t) do assert(set[k],label..": unknown key "..tostring(k)) end
end
local function dependencies(t)
  assert(type(t)=="table","dependency groups required");keys(t,"construction style view renderer","dependencies")
  for _,g in ipairs(groups) do
    assert(type(t[g])=="table","missing dependency group "..g)
    for name,dep in pairs(t[g]) do
      assert(type(name)=="string" and #name>0 and type(dep)=="table","named dependency required")
      keys(dep,"sha256 version configuration","dependency "..name)
      assert(H.is_digest(dep.sha256),"dependency content SHA-256 required: "..name)
      assert(dep.version==nil or type(dep.version)=="string","dependency version must be string")
    end
  end
end
function M.new(data)
  local t=P.plain(data);assert(type(t)=="table","recipe object required")
  keys(t,"kind schema_version id definition design view dimension dependencies","recipe")
  assert(t.kind=="recipe" and t.schema_version==1,"unsupported recipe kind/version; explicit migration required")
  assert(type(t.id)=="string" and #t.id>0 and #t.id<=256,"recipe stable ID required")
  local d=P.definition(t.definition);local s=P.specification(t.design,d)
  require("pattern_output_style").split(s.style)
  keys(t.definition.transforms,"metric_constrained reflection uniform_scale","definition.transforms")
  keys(t.design.document,"unit bounds protected_regions","design.document")
  keys(t.view,"unit transform crop protected_regions derived validity projection extensions","recipe.view")
  if t.view.projection then keys(t.view.projection,"matrix depth_policy","projection") end
  if t.design.budget then limits(t.design.budget) end
  assert(t.dimension==2 or t.dimension==3,"explicit construction dimension required")
  t.view=P.plain(P.view_settings(t.view,d,t.dimension));dependencies(t.dependencies)
  if t.view.extensions then require("pattern_planner").recipe_view_inputs(d,s,t.view,t.dimension)
  else assert(not(s.extensions and s.extensions.planning_generation),"document generation context requires its paired planning view")end
  t.definition=P.plain(d);t.design=P.plain(s)
  return P.snapshot(t)
end
function M.decode(text) return M.new(require("pattern_parse").decode(text)) end
function M.encode(recipe) return P.serialize(M.new(recipe)) end
function M.from_specification(d,s,v,dimension)
  local template=P.plain(v);template.id=nil;template.kind=nil;template.schema_version=nil;template.instance_ref=nil
  return M.new({kind="recipe",schema_version=1,id=s.id.."/recipe",definition=P.plain(d),design=P.plain(s),view=template,dimension=dimension,
    dependencies={construction={},style={},view={},renderer={}}})
end
-- No implicit legacy conversion: unsupported versions remain recoverable inputs.
function M.migrate(data,target)
  assert(target==1,"unsupported migration target")
  assert(data.schema_version==1,"no registered migration from recipe version "..tostring(data.schema_version))
  return M.new(data),{operation="identity-validation",from=1,to=1,input_sha256=H.value("recipe/migration-input",data)}
end
-- Source bytes are supplied by the trusted host, rather than asserted digests.
function M.environment(source,runtime,renderer,inputs)
  assert(type(source)=="table" and type(source.revision)=="string" and #source.revision>0,"exact source revision or working-tree identity required")
  keys(source,"revision files","source")
  assert(type(source.files)=="table","grouped source bytes required");keys(source.files,"construction style view renderer","source.files")
  local manifest={}
  for _,g in ipairs(groups) do
    manifest[g]={};assert(type(source.files[g])=="table","source group required: "..g)
    for name,bytes in pairs(source.files[g]) do
      assert(type(name)=="string" and #name>0 and type(bytes)=="string","source path/bytes required")
      manifest[g][name]=H.sha256(bytes)
    end
  end
  assert(next(manifest.construction),"construction source cannot be empty")
  assert(type(runtime)=="table" and runtime.lua==_VERSION and type(runtime.host)=="string" and #runtime.host>0,"actual Lua/runtime host identity required")
  assert(type(renderer)=="table" and type(renderer.id)=="string" and #renderer.id>0 and type(renderer.version)=="string" and #renderer.version>0,"renderer identity/version required")
  local owned,digests={},{}
  for name,bytes in pairs(inputs or {}) do
    assert(type(name)=="string" and #name>0 and type(bytes)=="string","named input bytes required")
    owned[name]=bytes;digests[name]=H.sha256(bytes)
  end
  local env=P.snapshot({source={revision=source.revision,files=manifest,digest=H.value("source/manifest",manifest)},runtime=runtime,renderer=renderer,inputs=digests})
  input_bytes[env]=owned;return env
end
local function construction_design(recipe)
  local s=P.plain(recipe.design);s.style={};return s
end
function M.structural_digest(recipe)
  local q=M.new(recipe)
  return H.value("recipe/structural-input",{definition=P.plain(q.definition),design=construction_design(q),
    dimension=q.dimension,dependencies=P.plain(q.dependencies.construction)})
end
function M.cache_keys(recipe,environment,options)
  local q=M.new(recipe);local e=P.plain(environment)
  assert(type(e.source)=="table" and type(e.source.files)=="table" and type(e.runtime)=="table" and type(e.renderer)=="table","validated environment required")
  local common={schema=1,hash=H.VERSION,random=Random.VERSION,definition=P.plain(q.definition),design=construction_design(q),dimension=q.dimension,
    dependencies=P.plain(q.dependencies.construction),source=e.source.files.construction,runtime=e.runtime,limits=limits(options and options.limits or q.design.budget)}
  local out={structure=H.value("cache/structure",common)}
  out.style=H.value("cache/style",{structure=out.structure,style=P.plain(q.design.style),dependencies=P.plain(q.dependencies.style),source=e.source.files.style})
  out.view=H.value("cache/view",{structure=out.structure,view=P.plain(q.view),dependencies=P.plain(q.dependencies.view),source=e.source.files.view})
  out.renderer=H.value("cache/renderer",{style=out.style,view=out.view,dependencies=P.plain(q.dependencies.renderer),source=e.source.files.renderer,renderer=e.renderer})
  return P.snapshot(out)
end
local function execute(recipe,registry,environment,options,cached)
  local q=M.new(recipe);local env=P.plain(environment);options=options or {}
  keys(options,"limits cancelled","execution options")
  assert(options.cancelled==nil or type(options.cancelled)=="function","cancellation callback must be a function")
  local declared=registry:definition(q.definition.id)
  assert(P.serialize(declared)==P.serialize(q.definition),"registered definition differs from recipe")
  local cache=M.cache_keys(q,environment,options)
  local verified=assert(input_bytes[environment],"execution requires a fresh environment constructed from actual source/input bytes")
  local declared_inputs={}
  for _,g in ipairs(groups) do for name,dep in pairs(q.dependencies[g]) do
    assert(env.inputs[name]==dep.sha256,"missing or mismatched verified dependency bytes: "..name);declared_inputs[name]=true
  end end
  for name in pairs(verified) do assert(declared_inputs[name],"unused supplied input: "..name) end
  local phase="construction"
  local planning=q.design.extensions and q.design.extensions.planning_generation
  local frame=planning and {id=planning.frame.id,unit="cm",dimension=2,handedness="right",origin=P.plain(planning.frame.origin)} or {id=q.definition.id.."/global",unit=q.definition.units,dimension=q.dimension,handedness="right",origin=q.dimension==3 and {0,0,0} or {0,0}}
  local context=R.context({seed=q.design.seed,source=env.source,versions=env.runtime,limits=limits(options.limits or q.design.budget),cancelled=options.cancelled,planning=planning,
    frame=frame,
    stream_provider=Random.provider(q.design.seed,q.definition.id.."@"..q.definition.version),input_provider=function(name)
      assert(declared_inputs[name] and (phase~="construction" or q.dependencies.construction[name]),"input is undeclared for current phase: "..name)
      return verified[name]
    end})
  local recipe_digest=H.sha256(M.encode(q))
  local previous_recipe=cached and cached.previous_recipe and M.new(cached.previous_recipe) or nil
  local result,problem
  local parent_record,cached_sha
  if cached then
    local ok,value=pcall(function()
      parent_record=P.build_record(P.plain(cached.record))
      local body=P.plain(parent_record);body.id=nil;body.kind=nil;body.schema_version=nil
      assert(parent_record.id=="build/"..H.value("build/record-body",body),"cached build record body digest mismatch")
      if previous_recipe then
        assert(P.serialize(previous_recipe.definition)==P.serialize(q.definition)
          and previous_recipe.dimension==q.dimension,"revision definition or dimension changed")
        assert(P.serialize(construction_design(previous_recipe))==P.serialize(construction_design(q)),
          "style/view revision changed structural design; generate a new instance")
        assert(P.serialize(previous_recipe.dependencies.construction)==P.serialize(q.dependencies.construction),
          "style/view revision changed construction dependencies")
      end
      local parent_recipe_digest=previous_recipe and H.sha256(M.encode(previous_recipe)) or recipe_digest
      assert(parent_record.status=="complete","cached build is incomplete")
      cached_sha=H.sha256(P.serialize(cached.instance))
      local recipe_match,instance_match=false,false
      for _,item in ipairs(parent_record.inputs) do
        recipe_match=recipe_match or item.kind=="recipe" and item.sha256==parent_recipe_digest
      end
      for _,item in ipairs(parent_record.outputs) do
        instance_match=instance_match or item.kind=="instance" and item.sha256==cached_sha
      end
      assert(recipe_match and instance_match,"cached recipe or instance digest mismatch")
      assert(cached.instance.provenance.seed==q.design.seed
        and cached.instance.frame.dimension==q.dimension,"cached instance seed or dimension mismatch")
      registry:check_specification(q.definition.id,construction_design(q))
      context:consume("objects",0)
      local x,validation=registry:validate(q.definition.id,cached.instance,context)
      local replay_keys={}
      for key,digest in pairs(cache) do
        replay_keys[key]=H.value("cache/replay-"..key,{generated=digest,instance=cached_sha})
      end
      cache=P.snapshot(replay_keys)
      return {instance=x,definition=q.definition,validation=validation}
    end)
    if ok then result=value
    else
      local cancelled=type(value)=="table" and value.code=="cancelled"
      problem={status=cancelled and "cancelled" or "failed",
        diagnostics={type(value)=="table" and value.message or tostring(value)}}
    end
  else
    result,problem=registry:generate(q.definition.id,construction_design(q),context)
  end
  local outputs=P.array();local inputs={{kind="recipe",sha256=recipe_digest}}
  local names={};for name in pairs(env.inputs) do names[#names+1]=name end;table.sort(names,P.byte_less)
  for _,name in ipairs(names) do inputs[#inputs+1]={kind="dependency",id=name,sha256=env.inputs[name]} end
  local record={status="failed",source=env.source,runtime={name=env.runtime.lua,version=env.runtime.host,details=env.runtime},seed=q.design.seed,
    inputs=inputs,dependencies={declared=P.plain(q.dependencies),cache=P.plain(cache),renderer=env.renderer,random=Random.VERSION,hash=H.VERSION},
    lineage=P.array(),validation={status="failed",checks=P.array()},outputs=outputs,diagnostics=P.array(),budgets=context:receipt()}
  if cached and result then
    inputs[#inputs+1]={kind="stored_instance",sha256=cached_sha}
    inputs[#inputs+1]={kind="parent_build_record",sha256=H.sha256(P.serialize(parent_record))}
    record.lineage[1]={role=previous_recipe and "validated-style-view-revision" or "validated-instance-replay",parent_ref=parent_record.id,instance_sha256=cached_sha,
      source=P.plain(parent_record.source)}
  end
  local accepted
  if result then
    local ok,value=pcall(function()
      assert(result.instance.frame.dimension==q.dimension,"generated dimension differs from recipe")
      phase="lowering"
      local v,scene,planned
      local family_style,output_profile=require("pattern_output_style").split(q.design.style)
      if q.view.extensions then
        local planner=require("pattern_planner");local input=planner.recipe_view_inputs(q.definition,q.design,q.view,q.dimension)
        local diagnostic;planned,diagnostic=planner.view(result.instance,result.definition,input.document,input.page_id,input.profile,input.options,context)
        if not planned then error({code=diagnostic.code,message=table.concat(P.plain(diagnostic.diagnostics),"; ")},0)end
        local lowered;lowered,diagnostic=planner.lower(registry,q.definition.id,result.instance,result.definition,planned,family_style,context)
        if not lowered then error({code=diagnostic.code,message=table.concat(P.plain(diagnostic.diagnostics),"; ")},0)end
        v,scene=lowered.view,lowered.scene
      else
        v=P.plain(q.view);v.id=result.instance.id.."/view";v.instance_ref=result.instance.id
        v=P.view(v,result.instance,result.definition);scene=registry:lower(q.definition.id,result.instance,v,family_style,context)
      end
      if output_profile and output_profile.mode~="source"then scene=P.scene(require("pattern_output_style").apply(scene,output_profile,context),result.instance,v,result.definition)end
      local ib,sb=P.serialize(result.instance),P.serialize(scene)
      outputs[1]={kind="instance",sha256=H.sha256(ib),semantic_sha256=H.value("instance",result.instance),bytes=#ib}
      outputs[2]={kind="scene",sha256=H.sha256(sb),semantic_sha256=H.value("scene",scene),bytes=#sb}
      return {instance=result.instance,view=v,scene=scene,bytes={instance=ib,scene=sb},planning=planned}
    end)
    if ok then accepted=value;record.status="complete";record.validation={status="passed",checks=P.plain(result.validation.checks)}
      if result.validation.solver then record.extensions={solver=P.plain(result.validation.solver)} end
      if result.validation.construction then
        record.extensions=record.extensions or {}
        record.extensions.construction=P.plain(result.validation.construction)
      end
      if value.planning then
        record.validation.checks[#record.validation.checks+1]="document planner: source-preserving selection and requested physical policies"
        record.validation.planning={document_digest=value.planning.document_digest,source_digest=value.planning.source_digest,page_ref=value.planning.decisions.page_ref}
      end
    else problem={status=type(value)=="table" and value.code=="cancelled" and "cancelled" or "failed",diagnostics={type(value)=="table" and value.message or tostring(value)}} end
  end
  if not accepted then
    record.status=problem.status;record.diagnostics=problem.diagnostics;record.outputs=P.array()
    if problem.solver then record.extensions={solver=P.plain(problem.solver)} end
  end
  record.budgets=context:receipt();record.id="build/"..H.value("build/record-body",record);record=P.build_record(record)
  if not accepted then return {record=record,keys=cache} end
  accepted.record=record;accepted.keys=cache;return accepted
end
function M.execute(recipe,registry,environment,options)
  return execute(recipe,registry,environment,options)
end
function M.replay(recipe,instance,record,registry,environment,options)
  return execute(recipe,registry,environment,options,{instance=instance,record=record})
end
-- Explicit new view/style, checked against the exact prior recipe and build.
-- Structural edits use execute(); this path never calls the generator.
function M.revise(recipe,previous,instance,record,registry,environment,options)
  return execute(recipe,registry,environment,options,{instance=instance,record=record,previous_recipe=previous})
end
return M
