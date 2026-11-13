-- Strict RFC 8259 grammar with bounded resources and duplicate decoded-key rejection.
-- dkjson decodes only already-validated quoted strings (including escape spelling).
local P,J=require("pattern"),require("pattern_json")
local M={}
local function decode(text,instance)
  local bytes=instance and 32*1024*1024 or 2*1024*1024
  local node_limit=instance and 1000000 or 100000
  assert(type(text)=="string" and #text<=bytes,instance and "instance JSON exceeds 32 MiB limit" or "recipe JSON exceeds 2 MiB limit")
  assert(utf8.len(text),"recipe JSON is not UTF-8")
  local at,nodes=1,0
  local function fail(why) error("recipe JSON byte "..at..": "..why,0) end
  local function ws() while text:sub(at,at):match("[ \t\r\n]") do at=at+1 end end
  local function quoted()
    local start=at;at=at+1
    while at<=#text do
      local ch=text:sub(at,at);local code=text:byte(at)
      if ch=='"' then
        at=at+1;local value,_,err=J.decode(text:sub(start,at-1));if err then fail(err) end;return value
      elseif code<32 then fail("unescaped control character")
      elseif ch=='\\' then
        at=at+1;ch=text:sub(at,at)
        if ch=='u' then
          local hex=text:sub(at+1,at+4);if #hex~=4 or hex:find('[^%da-fA-F]') then fail("invalid Unicode escape") end
          local u=tonumber(hex,16);at=at+5
          if u>=0xd800 and u<=0xdbff then
            if text:sub(at,at+1)~='\\u' then fail("unpaired high surrogate") end
            local low=text:sub(at+2,at+5);local v=tonumber(low,16)
            if #low~=4 or low:find('[^%da-fA-F]') or not v or v<0xdc00 or v>0xdfff then fail("invalid low surrogate") end
            at=at+6
          elseif u>=0xdc00 and u<=0xdfff then fail("unpaired low surrogate") end
        elseif ch:match('["\\/bfnrt]') and ch~='' then at=at+1
        else fail("invalid escape") end
      else at=at+1 end
    end
    fail("unterminated string")
  end
  local value
  value=function(depth)
    nodes=nodes+1;if depth>60 or nodes>node_limit then fail("nesting/node budget exceeded") end
    ws();local ch=text:sub(at,at)
    if ch=='"' then return quoted()
    elseif ch=='{' or ch=='[' then
      local object=ch=='{';local close=object and '}' or ']'
      local out=object and {} or P.array();local seen={};at=at+1;ws()
      if text:sub(at,at)==close then at=at+1;return out end
      while true do
        ws();local key
        if object then
          if text:sub(at,at)~='"' then fail("expected object key") end
          key=quoted();if seen[key] then fail("duplicate object key "..key) end;seen[key]=true
          ws();if text:sub(at,at)~=':' then fail("expected colon") end;at=at+1
        else key=#out+1 end
        out[key]=value(depth+1);ws();ch=text:sub(at,at);at=at+1
        if ch==close then return out end
        if ch~=',' then fail("expected comma or closing delimiter") end
      end
    elseif text:sub(at,at+3)=='true' then at=at+4;return true
    elseif text:sub(at,at+4)=='false' then at=at+5;return false
    elseif text:sub(at,at+3)=='null' then fail("null is not supported in recipes")
    elseif ch=='-' or ch:match('%d') then
      local start=at;if ch=='-' then at=at+1 end
      ch=text:sub(at,at)
      if ch=='0' then at=at+1
      elseif ch:match('[1-9]') then repeat at=at+1 until not text:sub(at,at):match('%d')
      else fail("expected number digit") end
      if text:sub(at,at)=='.' then
        at=at+1;if not text:sub(at,at):match('%d') then fail("fraction needs a digit") end
        repeat at=at+1 until not text:sub(at,at):match('%d')
      end
      ch=text:sub(at,at)
      if ch=='e' or ch=='E' then
        at=at+1;ch=text:sub(at,at);if ch=='+' or ch=='-' then at=at+1 end
        if not text:sub(at,at):match('%d') then fail("exponent needs a digit") end
        repeat at=at+1 until not text:sub(at,at):match('%d')
      end
      -- tonumber obeys Lua's C-locale-independent numeric conversion.
      local v=tonumber(text:sub(start,at-1));if not v or v~=v or math.abs(v)==math.huge then fail("nonfinite number") end
      return v
    end
    fail("expected JSON value")
  end
  local out=value(0);ws();if at<=#text then fail("trailing input") end
  return P.plain(out)
end
-- Input type selects a fixed admission profile; callers cannot supply arbitrary
-- limits. Recipes/requests retain their original smaller limits. Both routes
-- enforce the same strict grammar, duplicate-key, nonfinite and depth checks.
function M.decode(text)return decode(text,false)end
function M.instance(text)return decode(text,true)end
return M
