-- Registration is independent of family semantics and renderer selection.
local P=require("pattern")
local M={}
function M.context(options)
  assert(type(options)=="table" and type(options.source)=="table","construction context requires source provenance")
  local seed=options.seed
  assert(type(seed)=="number" and seed%1==0 and seed>=0 and seed<2^31,"invalid construction seed")
  local limits=P.plain(options.limits or {objects=10000,operations=100000,bytes=2*1024*1024})
  for k,n in pairs(limits) do assert(type(k)=="string" and type(n)=="number" and n%1==0 and n>=0 and n<math.huge,"invalid construction budget") end
  local spent,cancelled={},false
  local on_cancel,provider,input_provider=options.cancelled,options.stream_provider,options.input_provider
  local metadata={seed=seed,source=P.snapshot(options.source),versions=P.snapshot(options.versions or {}),frame=P.snapshot(options.frame or {id="world",unit="cm",dimension=2,handedness="right",origin={0,0}})}
  if options.planning~=nil then metadata.planning=P.snapshot(options.planning)end
  local ctx=setmetatable({},{__index=metadata,__newindex=function(t,k,v) assert(metadata[k]==nil,"immutable construction context metadata");rawset(t,k,v) end})
  function ctx:consume(name,n)
    if cancelled or on_cancel and on_cancel() then cancelled=true;error({code="cancelled",message="construction cancelled"},0) end
    assert(limits[name]~=nil,"unknown budget "..tostring(name))
    assert(type(n)=="number" and n%1==0 and n>=0,"invalid budget charge")
    if (spent[name] or 0)+n>limits[name] then error({code="budget_exhausted",message="construction budget exhausted: "..name},0) end
    spent[name]=(spent[name] or 0)+n
  end
  function ctx:stream(name,semantic_id)
    assert(type(name)=="string" and name~="" and type(semantic_id)=="string" and semantic_id~="","named semantic stream required")
    assert(type(provider)=="function","named stream derivation is not configured; stage 04 supplies it")
    return provider(name,semantic_id,seed)
  end
  function ctx:input(name)
    assert(type(name)=="string" and #name>0 and type(input_provider)=="function","verified named input provider required")
    return input_provider(name)
  end
  function ctx:receipt() return {limits=P.plain(limits),spent=P.plain(spent),cancelled=not not cancelled} end
  return ctx
end
function M.new()
  local entries={};local registry={}
  function registry:register(definition,implementation)
    local d=P.definition(P.plain(definition))
    assert(not entries[d.id],"generator already registered: "..d.id)
    for _,k in ipairs({"generate","validate","lower"}) do assert(type(implementation[k])=="function","generator missing "..k) end
    local owned={};for _,k in ipairs({"generate","validate","lower","validate_inputs"}) do owned[k]=implementation[k] end
    entries[d.id]={definition=d,implementation=owned}
  end
  function registry:definition(id)
    assert(entries[id],"unknown generator "..tostring(id));return entries[id].definition
  end
  function registry:check_specification(id,specification)
    local entry=assert(entries[id],"unknown generator "..tostring(id))
    local spec=P.specification(P.plain(specification),entry.definition)
    if next(P.plain(spec.inputs)) or next(P.plain(spec.constraints)) then
      assert(type(entry.implementation.validate_inputs)=="function","generator does not support supplied inputs/constraints")
      assert(entry.implementation.validate_inputs(spec)==true,"generator input validation failed")
    end
    return spec
  end
  function registry:validate(id,instance,context)
    local entry=assert(entries[id],"unknown generator "..tostring(id))
    local x=P.instance(P.plain(instance),entry.definition)
    local validation=entry.implementation.validate(x,context)
    assert(type(validation)=="table" and validation.ok==true and type(validation.checks)=="table"
      and #validation.checks>0,"structural validation failed or provided no checks")
    return x,validation
  end
  function registry:generate(id,specification,context)
    local entry=assert(entries[id],"unknown generator "..tostring(id))
    local d,impl=entry.definition,entry.implementation
    local spec=P.specification(P.plain(specification),d)
    assert(spec.seed==context.seed,"context seed differs from specification")
    local planning=spec.extensions and spec.extensions.planning_generation
    if planning then
      assert(context.planning and P.serialize(context.planning)==P.serialize(planning),"prepared document inputs differ from construction context")
      assert(context.frame.id==planning.frame.id and context.frame.unit=="cm" and context.frame.dimension==2 and P.serialize(context.frame.origin)==P.serialize(planning.frame.origin),"prepared document frame differs from construction context")
    end
    local function execute()
      context:consume("objects",0)
      self:check_specification(id,spec)
      local instance,validation=self:validate(id,impl.generate(spec,context),context)
      return {instance=instance,definition=d,validation=validation}
    end
    local ok,value=pcall(execute)
    if ok then return value end
    local code=type(value)=="table" and value.code or "failed"
    local message=type(value)=="table" and value.message or tostring(value)
    return nil,{status=code=="cancelled" and "cancelled" or "failed",code=code,diagnostics={message},
      budgets=context:receipt(),solver=type(value)=="table" and value.solver or nil}
  end
  function registry:lower(id,instance,view,style,context)
    local entry=assert(entries[id],"unknown generator "..tostring(id))
    local d=entry.definition
    local x=P.instance(P.plain(instance),d);local v=P.view(P.plain(view),x,d)
    local data=entry.implementation.lower(x,v,P.plain(style),context)
    local scene=P.scene(data,x,v,d)
    context:consume("operations",#scene.operations)
    context:consume("bytes",#P.serialize(scene))
    return scene
  end
  return registry
end
return M
