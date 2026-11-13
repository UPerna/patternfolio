-- Small vector-PDF backend, adapted from wilsybubs/florilegium 6f1d846 (MIT).
-- Geometry stays in ink.lua; this module only owns resources and PDF objects.
local M = {}
function M.encode(objs,catalog)
  local buf,offs={"%PDF-1.5\n%\xE2\xE3\xCF\xD3\n"},{}
  local pos=#buf[1]
  for i,o in ipairs(objs) do
    offs[i]=pos
    local s=string.format("%d 0 obj\n%s\nendobj\n",i,o)
    buf[#buf+1]=s;pos=pos+#s
  end
  buf[#buf+1]=string.format("xref\n0 %d\n0000000000 65535 f \n",#objs+1)
  for i=1,#objs do buf[#buf+1]=string.format("%010d 00000 n \n",offs[i]) end
  buf[#buf+1]=string.format("trailer\n<< /Size %d /Root %d 0 R >>\nstartxref\n%d\n%%%%EOF\n",#objs+1,catalog,pos)
  return table.concat(buf)
end
function M.new()
  local self = { pages={}, resources={}, streams={}, has_text=false }
  self.backend = {
    literal=function(s) self.streams[#self.streams+1]=s end,
    extgs=function(name,dict) self.resources[name]=dict end,
  }
  function self:begin() self.streams={} end
  function self:text(label,x,y)
    assert(label:match("^[0-9ivxlcdmIVXLCDM]+$"), "unsupported PDF search label")
    self.has_text=true
    self.streams[#self.streams+1]=string.format(
      "q BT /FloSearch 9 Tf 3 Tr 1 0 0 1 %.4f %.4f Tm (%s) Tj ET Q",x,y,label)
  end
  function self:finish(w,h)
    self.pages[#self.pages+1]={data=table.concat(self.streams,"\n"),w=w,h=h}
  end
  function self:write(path)
    assert(#self.pages>0,"cannot write a PDF without pages")
    local objs={}
    local function obj(s) objs[#objs+1]=s;return #objs end
    local catalog,pages=obj(false),obj(false)
    local names,dict={},{}
    for name in pairs(self.resources) do names[#names+1]=name end
    table.sort(names)
    for _,name in ipairs(names) do dict[#dict+1]="/"..name.." "..self.resources[name] end
    local gs=obj("<< "..table.concat(dict," ").." >>")
    local font=self.has_text and obj("<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>")
    local refs={}
    for _,p in ipairs(self.pages) do
      assert(p.w>0 and p.h>0,"invalid PDF page dimensions")
      local z=zlib.compress(p.data)
      local stream=obj(string.format("<< /Length %d /Filter /FlateDecode >>\nstream\n%s\nendstream",#z,z))
      local pg=obj(string.format("<< /Type /Page /Parent %d 0 R /MediaBox [0 0 %.5f %.5f] /Contents %d 0 R /Resources << /ExtGState %d 0 R %s >> >>",
        pages,p.w,p.h,stream,gs,font and string.format("/Font << /FloSearch %d 0 R >>",font) or ""))
      refs[#refs+1]=pg.." 0 R"
    end
    objs[catalog]=string.format("<< /Type /Catalog /Pages %d 0 R >>",pages)
    objs[pages]=string.format("<< /Type /Pages /Kids [%s] /Count %d >>",table.concat(refs," "),#refs)
    local bytes=M.encode(objs,catalog)
    local f=assert(io.open(path..".tmp","wb"));assert(f:write(bytes));assert(f:close())
    assert(os.rename(path..".tmp",path))
  end
  return self
end
return M
