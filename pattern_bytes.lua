-- Portable encodings used by the shared PDF/SVG backends (no native libraries).
local P=require("pattern")
local M={}
local alphabet="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local reverse={};for i=1,#alphabet do reverse[alphabet:sub(i,i)]=i-1 end
function M.base64_decode(text)
  assert(type(text)=="string" and #text%4==0 and #text<=8*1024*1024,"invalid/oversized base64 input")
  local out={}
  for i=1,#text,4 do
    local a,b,c,d=text:sub(i,i),text:sub(i+1,i+1),text:sub(i+2,i+2),text:sub(i+3,i+3)
    assert(reverse[a] and reverse[b] and (reverse[c] or c=="=") and (reverse[d] or d=="="),"invalid base64 alphabet")
    assert((c~="=" or d=="=") and (c~="=" and d~="=" or i==#text-3),"invalid base64 padding")
    local n=reverse[a]*262144+reverse[b]*4096+(reverse[c] or 0)*64+(reverse[d] or 0)
    if c=="=" then assert(reverse[b]%16==0,"noncanonical base64 padding bits") elseif d=="=" then assert(reverse[c]%4==0,"noncanonical base64 padding bits") end
    out[#out+1]=string.char(math.floor(n/65536)%256)
    if c~="=" then out[#out+1]=string.char(math.floor(n/256)%256) end
    if d~="=" then out[#out+1]=string.char(n%256) end
  end
  return table.concat(out)
end
function M.base64_encode(bytes)
  assert(type(bytes)=="string" and #bytes<=6*1024*1024,"base64 bytes exceed limit")
  local out={}
  for i=1,#bytes,3 do
    local a,b,c=bytes:byte(i,i+2);local n=a*65536+(b or 0)*256+(c or 0)
    out[#out+1]=alphabet:sub(math.floor(n/262144)%64+1,math.floor(n/262144)%64+1)
    out[#out+1]=alphabet:sub(math.floor(n/4096)%64+1,math.floor(n/4096)%64+1)
    out[#out+1]=b and alphabet:sub(math.floor(n/64)%64+1,math.floor(n/64)%64+1) or "="
    out[#out+1]=c and alphabet:sub(n%64+1,n%64+1) or "="
  end
  return table.concat(out)
end
function M.utf16_hex(text,bom)
  P.snapshot(text);local out=bom and {"FEFF"} or {}
  for _,cp in utf8.codes(text) do
    if cp<=0xffff then out[#out+1]=string.format("%04X",cp)
    else cp=cp-0x10000;out[#out+1]=string.format("%04X%04X",0xd800+math.floor(cp/1024),0xdc00+cp%1024) end
  end
  return table.concat(out)
end
function M.xml(text)
  P.snapshot(text)
  for _,cp in utf8.codes(text) do assert(cp==9 or cp==10 or cp==13 or cp>=32 and cp~=0xfffe and cp~=0xffff,"text contains a codepoint unsupported by XML1.0") end
  return (text:gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;"):gsub('"',"&quot;"):gsub("'","&apos;"):gsub("\n","&#10;"):gsub("\r","&#13;"):gsub("\t","&#9;"))
end
function M.pdf_number(value)
  local s=P.serialize(value);assert(type(value)=="number","PDF number required")
  if not s:find("e",1,true) then return s end
  local mantissa,exponent=s:match("^(.-)e([+-]?%d+)$");assert(mantissa,"invalid canonical numeric spelling")
  local sign="";if mantissa:sub(1,1)=="-" then sign="-";mantissa=mantissa:sub(2) end
  local whole,fraction=mantissa:match("^(%d+)%.(%d+)$");whole=whole or mantissa;fraction=fraction or ""
  local digits=whole..fraction;local point=#whole+tonumber(exponent)
  if point<=0 then return sign.."0."..string.rep("0",-point)..digits
  elseif point>=#digits then return sign..digits..string.rep("0",point-#digits)
  else return sign..digits:sub(1,point).."."..digits:sub(point+1) end
end
return M
