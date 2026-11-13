-- Batch XeTeX renderer. Protocol adapted from wilsybubs/florilegium 6f1d846
-- (MIT); settings, physical reservations, fallback and page labels share our core.
local here=arg[0]:match("^(.*)[/\\][^/\\]*$") or "."
package.path=here.."/?.lua;"..package.path
kpse.set_program_name('luatex')
local function main()
local base=assert(arg[1],"usage: texlua florilegium-xe.lua <job base>")
assert(arg[2]==nil or arg[2]=="--botanical-contracts","unsupported Xe renderer option")
if arg[2]then require("pattern_botanical_legacy").install(function(_,d) print("botanical-contract: validated "..d.id)end)end
local M,settings,writer=require("florilegium"),require("layout"),require("pdfwriter").new()
local ink=M.ink
ink.set_backend(writer.backend)
local capture_path=os.getenv("FLORILEGIUM_CAPTURE")
local capture=capture_path and assert(io.open(capture_path,"wb"))
if capture then
  local literal=writer.backend.literal
  writer.backend.literal=function(s)
    if s:sub(1,1)=="q" then capture:write(#s,"\n",s,"\n");capture:flush() end
    literal(s)
  end
end
local SP_CM=2.54/(72.27*65536)
local SP_BP=72/(72.27*65536)
local dims,macros={},{}
M.dimen=function(name) local v=assert(dims[name],"missing page dimension: "..name);return v end
M.macro=function(name) local v=assert(macros[name],"missing transformation: "..name);return v end
M.page=function() return dims.page or M.page_number or 1 end
M.error=function(message) error(message,0) end
M.initial_result=function(status) M.last_initial_status=status end
M.number_text=function(label,box) writer:text(label,box[1]*ink.CM,box[2]*ink.CM) end

local common,common_env=require('pattern_xetex').records()
local items,pages,configurations={},{},{}
local env={
  PAGE=function(t) t.kind="page";items[#items+1]=t;pages[t.n]=t end,
  DRAW=function(t) t.kind="draw";items[#items+1]=t end,
  INITIAL=function(t) t.kind="initial";items[#items+1]=t end,
  CONFIG=function(t) configurations[#configurations+1]=t.settings end,
  MARK=function(t)
    local p=assert(pages[t.n],"mark has no shipped page")
    p.marks=p.marks or {};p.marks[#p.marks+1]=t
  end,
}
for name,callback in pairs(common_env)do env[name]=callback end
local f=assert(io.open(base..".flo","rb"))
local source=f:read(32*1024*1024+1);f:close()
assert(source and #source<=32*1024*1024,'external records exceed the 32 MiB byte limit')
-- Generated records are part of the trusted TeX source, like primitive Lua args.
assert(load(source,"="..base..".flo","t",env))()
table.sort(items,function(a,b) return a.id<b.id end)

local resolved_settings={}
local function configure(commands)
  local parts={}
  for _,command in ipairs(commands or {}) do
    for _,value in ipairs(command) do parts[#parts+1]=#value..":"..value end
  end
  local key=table.concat(parts,";")
  if resolved_settings[key] then
    M.layout=resolved_settings[key]
    ink.set_color_mode(M.layout.color_mode)
    return
  end
  M.layout=settings.resolve()
  for _,command in ipairs(commands or {}) do
    local key,value=command[1],command[2]
    if key=="text_gap_sp" then key,value="text_gap",assert(tonumber(value))*SP_CM end
    M.configure(key,value)
  end
  resolved_settings[key]=M.layout
end
local function replay(r)
  local current=M.layout
  if r.page then
    configure(r.settings)
    M.seed(r.page,r.fixed)
    -- Headers take the first fork after shipout; nothing else in a margin does.
    local header=M.layout.header
    M.layout=current
    if header then M.advance(1) end
  else M.reset_rng() end
  M.advance(r.k)
  ink.set_color_mode(current.color_mode)
end
local function normalize_marks(d)
  local marks={}
  for _,m in ipairs(d.marks or {}) do
    local a=m.arg
    if m.kind=="reserve_page" then
      assert(a.w>0 and a.h>0 and a.pad>=0,"reserve width/height must be positive and padding nonnegative")
      a={(a.x-a.pad)*SP_CM,(a.y-a.pad)*SP_CM,(a.x+a.w+a.pad)*SP_CM,(a.y+a.h+a.pad)*SP_CM}
    elseif m.kind=="reserve_box" then
      assert(a.pad>=0,"reserve padding must be nonnegative")
      a={w=a.w*SP_CM,h=a.h*SP_CM,d=a.d*SP_CM,pad=a.pad*SP_CM}
    end
    marks[#marks+1]={kind=m.kind,arg=a,x=m.x*SP_CM,y=m.y*SP_CM}
  end
  return marks
end

local statuses={}
local font_attempted=false
for _,commands in ipairs(configurations) do configure(commands) end
for i,d in ipairs(items) do
  assert(d.id==i,"drawing IDs are not contiguous")
  configure(d.settings)
  M.initial_fallback=d.fallback or "plain"
  M.colors(d.ink[1],d.ink[2],d.ink[3],d.accent[1],d.accent[2],d.accent[3])
  writer:begin()
  if d.kind=="page" then
    dims=d;M.twoside=d.twoside;M.visitors=d.visitors;M.age=d.age
    local seed=M.seed(d.page,d.fixed)
    if d.frame then M.frame(d.frame.k,d.frame.n,d.frame.explain) end
    if d.aging and d.last then M.auto_age(d.page,d.last) end
    if d.grown then
      local spill=d.endpage==d.page
      M.grown(seed,spill and 1 or 0,spill and M.geometry().ytop-d.endtotal*SP_CM or 0,normalize_marks(d),d.label)
    else M.authored(seed) end
    writer:finish(d.paperwidth*SP_BP,d.paperheight*SP_BP)
  else
    replay(d.rng)
    -- Inline objects have a large transparent canvas about their local origin.
    writer.backend.literal("1 0 0 1 1200 1200 cm")
    if d.kind=="initial" then
      if not font_attempted then
        local ok,err=require("fontreader").load()
        if not ok then M.warning("standalone outline reader: "..tostring(err):match("[^\n]+")) end
        font_attempted=true
      end
      M.initial_font=d.font
      M.initial(d.letter,d.side,d.hang,d.cap)
      statuses[i]=M.last_initial_status
    else
      dims={["pgf@pt@x"]=d.x,["pgf@pt@y"]=d.y}
      macros={["pgf@pt@aa"]=d.aa,["pgf@pt@ab"]=d.ab,["pgf@pt@ba"]=d.ba,["pgf@pt@bb"]=d.bb}
      local call=assert(load("local f=...;return f.draw("..string.format("%q",d.name)..","..d.args..")",
        "=florilegiumdraw{"..d.name.."}"))
      call(M)
    end
    writer:finish(2400,2400)
  end
end
if #items>0 then writer:write(base.."-flo.pdf") end
local out=assert(io.open(base.."-flo.tex.tmp","wb"))
out:write(string.format("\\csname flo@drawn\\endcsname{%d}{%s}\n",#items,md5.sumhexa(source):upper()))
for id=1,#items do if statuses[id] then
  out:write(string.format("\\csname flo@initialstatus\\endcsname{%d}{%d}\n",id,statuses[id]))
end end
assert(out:close())
local pending=assert(io.open(base..'-flo.tex.tmp','rb'));local metadata=pending:read('*a');pending:close()
require('pattern_xetex').replace(base..'-flo.tex',metadata)
local evidence=require('pattern_xetex').render(base,common,here)
local H,P=require('pattern_hash'),require('pattern')
local function hash_file(path)
  local f=assert(io.open(path,'rb'));local bytes=f:read('*a');f:close();return H.sha256(bytes)
end
evidence.outputs[base..'-flo.tex']=hash_file(base..'-flo.tex')
if #items>0 then evidence.outputs[base..'-flo.pdf']=hash_file(base..'-flo.pdf')end
evidence.font_requests=P.array()
evidence.font_results=P.array()
local requested={}
for _,item in ipairs(items)do if item.kind=='initial'then
  evidence.font_results[#evidence.font_results+1]={drawing_id=item.id,font=item.font,status=statuses[item.id],fallback=item.fallback}
  if not requested[item.font]then
    requested[item.font]=true
    local path=kpse.find_file(item.font,'opentype fonts') or kpse.find_file(item.font,'truetype fonts')
    evidence.font_requests[#evidence.font_requests+1]={name=item.font,path=path or false}
    if path then evidence.dependencies[path]=hash_file(path)end
  end
end end
for path in pairs(package.loaded.fontreader and package.loaded.fontreader.sources or {})do evidence.dependencies[path]=hash_file(path)end
evidence.schema_version=1;evidence.status='complete';evidence.record_sha256=H.sha256(source)
require('pattern_xetex').replace(base..'-external.json',P.serialize(evidence))
if capture then assert(capture:close()) end
io.write(string.format("florilegium-xe: %d vector drawings rendered\n",#items))
end
local ok,err=xpcall(main,debug.traceback)
if not ok then io.stderr:write(err,"\n");os.exit(1) end
