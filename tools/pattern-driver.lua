-- Trusted host bridge. Recipes and cached records are parsed strictly as data.
local job=assert(arg[1],"managed job directory required")
local P,Parse=require("pattern"),require("pattern_parse")
local function read(path)
  local f=assert(io.open(path,"rb"))
  local bytes=assert(f:read("*a"));assert(f:close())
  return bytes
end
local function write(name,bytes)
  assert(name:match("^[a-z][a-z0-9%-]*%.[a-z]+$"),"unexpected managed output name")
  local f=assert(io.open(job.."/out/"..name,"wb"))
  assert(f:write(bytes));assert(f:close())
end
local ok,outputs,problem=pcall(function()
  local request=Parse.decode(read(job.."/request.json"))
  return require("pattern_cli_core").dispatch(request,{
    runtime=PATTERN_CLI_HOST or "texlua/"..tostring(status and status.luatex_version),
    read=function(name)
      assert(name:match("^[a-z][a-z0-9%-]*%.[a-z]+$"),"unexpected managed input name")
      return read(job.."/in/"..name)
    end,
    source=function()
      local files={}
      for name in require("lfs").dir(".") do
        if name:match("%.lua$") then files[name]=read(name):gsub("\r\n","\n") end
      end
      files["tools/pattern-driver.lua"]=read("tools/pattern-driver.lua"):gsub("\r\n","\n")
      return files
    end})
end)
if not ok then
  problem={status="failed",code="invalid_input",messages={type(outputs)=="table" and outputs.message or tostring(outputs)}}
  outputs={}
end
for name,bytes in pairs(outputs) do write(name,bytes) end
write("diagnostic.json",P.serialize(problem or {status="complete",messages=P.array()}))
if problem then os.exit(3) end
