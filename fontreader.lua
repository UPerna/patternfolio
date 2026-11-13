-- Optional plain-texlua fontloader bootstrap. Adapted from wilsybubs 6f1d846
-- (MIT). A missing installation remains a supported plain-initial fallback.
local M = {sources={}}
local function record_sources()
  for name in pairs(package.loaded)do
    if type(name)=='string' and (name:match('^fontloader') or name:match('^lualibs'))then
      local path=kpse.find_file(name,'lua') or kpse.find_file(name..'.lua','lua')
      if path then M.sources[path]=true end
    end
  end
end
function M.load()
  if fonts and fonts.handlers and fonts.handlers.otf and fonts.handlers.otf.readers
    and fonts.handlers.otf.readers.loadshapes then record_sources();return true end
  local write,write_nl=texio.write,texio.write_nl
  local search=package.path
  local ok,err=pcall(function()
    kpse.set_program_name("luatex")
    config=config or {}
    config.lualibs={verbose=false,prefer_merged=true,load_extended=true}
    require("lualibs")
    local u=utilities
    texio.write,texio.write_nl=function() end,function() end
    require("fontloader-basics-gen.lua")
    utilities=u
    pdf=pdf or {}
    for _,name in ipairs({"data-con","font-ini","font-con","fonts-enc","font-cid","font-map",
      "font-oti","font-otr","font-ott","font-cff","font-ttf","font-dsp","font-oup","font-onr","font-def"}) do
      require("fontloader-"..name)
    end
  end)
  texio.write,texio.write_nl=write,write_nl
  package.path=search
  record_sources()
  return ok,err
end
return M
