-- Browser host transport. All construction/validation/rendering stays in the CLI core.
local P,H,B,C,Parse=require('pattern'),require('pattern_hash'),require('pattern_bytes'),require('pattern_cli_core'),require('pattern_parse')
local M={VERSION='pattern-browser-v1'}
local commands={capabilities=true,schema=true,validate=true,generate=true,['validate-instance']=true,render=true,replay=true,diagnose=true}
function M.session(source,runtime)
  assert(type(source)=='table'and type(runtime)=='string'and #runtime>0,'browser source/runtime required')
  local files,outputs={},nil
  local session={}
  function session.put(name,encoded)
    assert(type(name)=='string'and #name<=160 and name:match('^[%w_.-]+$'),'browser input filename')
    local bytes=B.base64_decode(encoded)
    files[name]=(files[name]or'')..bytes
    assert(#files[name]<=32*1024*1024,'browser input file budget')
  end
  function session.dispatch(text)
    outputs=nil
    local data=Parse.decode(text)
    assert(type(data)=='table'and data.schema_version==1 and commands[data.command],'browser request version/command')
    for key in pairs(data)do assert(key=='schema_version'or key=='command'or key=='family'or key=='formats'or key=='limits'or key=='dependencies'or key=='instance_transport'or key=='previous_recipe'or key=='edits'or key=='input_files','browser request field:'..tostring(key))end
    local total,seen=0,{}
    for _,item in ipairs(data.input_files or{})do
      assert(type(item.name)=='string'and not seen[item.name]and type(item.bytes)=='number'and H.is_digest(item.sha256),'browser input descriptor')
      seen[item.name]=true;assert(files[item.name]and #files[item.name]==item.bytes and H.sha256(files[item.name])==item.sha256,'browser input digest mismatch')
      total=total+item.bytes;assert(total<=32*1024*1024,'browser total input budget')
    end
    for name in pairs(files)do assert(seen[name],'browser undeclared input')end
    data.input_files=nil
    if data.command~='capabilities'and data.command~='schema'and data.command~='diagnose'then
      local recipe=require('pattern_recipe').decode(assert(files['recipe.json'],'browser recipe missing'))
      local selected=data.limits or recipe.design.budget or {objects=10000,operations=100000,bytes=2*1024*1024}
      local caps={objects=100000,operations=48000000,bytes=64*1024*1024}
      for name,value in pairs(selected)do assert(caps[name]and type(value)=='number'and value%1==0 and value>=0 and value<=caps[name],'browser execution budget not admitted:'..tostring(name))end
    end
    local result,problem=C.dispatch(data,{runtime=runtime,read=function(name)return assert(files[name],'browser input missing:'..name)end,source=function()return source end})
    if problem then return P.serialize({ok=false,error={code=problem.code,message=table.concat(problem.messages or{},'\n'),status=problem.status}})end
    if data.command=='capabilities'then
      local report=Parse.decode(result['report.json']);report.core_commands=report.commands
      report.commands=P.array();for name in pairs(commands)do report.commands[#report.commands+1]=name end;table.sort(report.commands,P.byte_less)
      report.browser_runtime=runtime;report.browser_protocol=M.VERSION
      report.optional_providers='Pure Lua bounded search is available; native-process solvers are unavailable. Verified supplied solver caches and precomputed instances may replay.'
      result['report.json']=P.serialize(report)
    end
    local assets=P.array();total=0
    for name,bytes in pairs(result)do
      assert(type(name)=='string'and name:match('^[%w_.-]+$')and type(bytes)=='string','browser output asset')
      total=total+#bytes;assert(total<=64*1024*1024,'browser output byte budget')
      assets[#assets+1]={name=name,bytes=#bytes,sha256=H.sha256(bytes)}
    end
    assert(#assets>=1 and #assets<=1024,'browser output object budget');table.sort(assets,function(a,b)return P.byte_less(a.name,b.name)end)
    outputs=result
    return P.serialize({ok=true,assets=assets,output_bytes=total,protocol=M.VERSION})
  end
  function session.chunk(name,offset,count)
    assert(outputs and outputs[name]and type(offset)=='number'and offset%1==0 and offset>=0,'browser output chunk offset')
    assert(type(count)=='number'and count%1==0 and count>=1 and count<=262144,'browser output chunk size')
    return B.base64_encode(outputs[name]:sub(offset+1,offset+count))
  end
  return session
end
return M
