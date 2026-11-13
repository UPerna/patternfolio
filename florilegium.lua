-- florilegium.lua -- the TeX-facing side of florilegium.sty: page geometry,
-- colors, seeds, the TikZ transform, and the dispatch of primitives.

local ink = require("ink")
local flora = require("flora")
local settings = require("layout")
local M = { ink = ink, flora = flora }
local frame, recorded = nil, {}
M.layout = settings.resolve()

-- Host operations are replaceable; standalone rendering does not need TeX nodes.
function M.dimen(name)
  if name == "hoffset" or name == "voffset" then return tex[name] or 0 end
  return tex.dimen[name]
end
function M.macro(name) return token.get_macro(name) end
function M.page() return tex and tex.count and tex.count["c@page"] or M.page_number or 1 end
function M.error(message)
  if tex and tex.error then tex.error(message) else error(message, 0) end
end
function M.warning(message) texio.write_nl("florilegium warning: " .. message) end
function M.initial_result(status)
  M.last_initial_status = status
  if tex and tex.count then tex.count["flo@initialok"] = status end
end

-- A setup call persists until the next one. Invalidate animation recordings too:
-- otherwise a new density or whitespace setting could replay the old garden.
function M.configure(key, value)
  local next_layout = {}
  for k, v in pairs(M.layout) do next_layout[k] = v end
  if key == "style" then
    local preset = settings.styles[value]
    if not preset then error("florilegium: style must be classic, quiet, or chapter") end
    for k, v in pairs(preset) do next_layout[k] = v end
  end
  next_layout[key] = value
  M.layout = settings.resolve(next_layout)
  ink.set_color_mode(M.layout.color_mode)
  recorded = {}
end

local SP_CM = 2.54 / (72.27 * 65536)          -- cm per scaled point
local function cm(name) return M.dimen(name) * SP_CM end

-- the page layout, in cm from the lower-left corner of the paper
function M.geometry(text_gap, side)
  local inch = 2.54
  local page = M.page()
  local margin = M.twoside and page % 2 == 0 and "evensidemargin" or "oddsidemargin"
  local g = {
    pw = cm("paperwidth"), ph = cm("paperheight"),
    textleft = inch + cm(margin) + cm("hoffset"),
  }
  g.textright = g.textleft + cm("textwidth")
  g.actual_left, g.actual_right = g.textleft, g.textright
  side = side or "left"
  local recto=not M.twoside or page%2==1
  g.mirror = side == "right" or (side == "outer" and recto) or (side == "inner" and not recto)
  if g.mirror then g.textleft, g.textright = g.pw - g.textright, g.pw - g.textleft end
  g.ytop = g.ph - inch - cm("topmargin") - cm("headheight") - cm("headsep") - cm("voffset")
  g.ybot = g.ytop - cm("textheight")
  -- The existing safety clip extends 2.5 mm beyond the growth column. Account
  -- for that overhang so text-gap is the actual clear space beside the text.
  g.colright = g.textleft - (text_gap and text_gap + settings.SIDE_OVERHANG or 0.4)
  g.headrule = g.ytop + cm("headsep") - 0.1
  g.footy = g.ybot - cm("footskip")
  return g
end

-- colors: `ink` sets the hue of the whole ramp, `accent` the copper
function M.colors(ir, ig, ib, ar, ag, ab)
  M.color_key=table.concat({ir,ig,ib,ar,ag,ab}," ")
  ink.set_ink(ir, ig, ib)
  ink.set_accent(ar, ag, ab)
  ink.set_color_mode(M.layout.color_mode)
end

-- one rng per page; primitives drawn from TeX fork it in call order
local page_rng = ink.rng(1)
function M.seed(page, fixed)
  M.page_number = page
  local index = M.layout.variation=="spread" and math.floor(page/2)+1 or M.layout.variation=="fixed" and 1 or page
  fixed = fixed or M.layout.seed
  local s = fixed and (fixed * 7919 + index * 131) or (index * 97 + 1030)
  page_rng = ink.rng(s)
  return s
end
function M.reset_rng() page_rng = ink.rng(1) end
function M.advance(n) for _ = 1, n do page_rng.fork() end end

-- the current pgf transformation (TikZ scopes) as an ink transform: local cm -> page bp
local function sync_transform()
  local C = ink.CM
  local bp = 72 / 72.27 / 65536
  ink.set_transform({
    tonumber(M.macro("pgf@pt@aa")) * C, tonumber(M.macro("pgf@pt@ab")) * C,
    tonumber(M.macro("pgf@pt@ba")) * C, tonumber(M.macro("pgf@pt@bb")) * C,
    M.dimen("pgf@pt@x") * bp, M.dimen("pgf@pt@y") * bp })
end

-- \florilegiumdraw{name}{s, opts}: one primitive at the origin of the current TikZ scope
local scaled = { leaf = true, leaflet = true, petal = true }
function M.draw(name, s, o)
  local fn = flora[name]
  if not fn then M.error("florilegium: unknown primitive '" .. tostring(name) .. "'") return end
  sync_transform()
  local rng = page_rng.fork()
  if name == "ghost" then
    flora.ghost(o and o.lift, function() M.draw_inner(s, o, rng) end)
  elseif scaled[name] then
    ink.scale(s or 1) fn(rng, o)
  else
    fn(rng, s, o)
  end
  ink.flush()
end
-- \florilegiumdraw{ghost}{"flower", {s=1.4}} draws any primitive pale
function M.draw_inner(name, o, rng)
  o = o or {}
  local fn = flora[name]
  if scaled[name] then ink.scale(o.s or 1) fn(rng, o) else fn(rng, o.s or 1, o) end
end

-- the header: a copper ivy leaf whose stem becomes the head rule
function M.head(g)
  ink.set_transform({ ink.CM, 0, 0, ink.CM, 0, 0 })
  ink.push()
  ink.translate(g.colright - 0.55, g.headrule + 0.02)
  local x, y = flora.hedera(page_rng.fork(), 0.36)
  ink.pop()
  local e = g.textright
  ink.moveto(x, y) ink.curveto(x + 1.0, y, x + 1.5, g.headrule, x + 2.5, g.headrule) ink.lineto(e, g.headrule)
  ink.stroke(ink.accent(0), 0.4)
  ink.circle(e, g.headrule, 0.03) ink.fill(ink.accent(0))
  ink.flush()
end

-- ---------------------------------------------------------------- marks in the text
-- \florilegiumbloom[motif] and (option sections) the section headings leave a
-- whatsit in the text. The page box is searched for them at shipout, when the
-- garden is drawn, so the garden knows the height of those lines on the same
-- page in the same run.
local MARK = 0x464C4F                         -- "FLO"
local marks = {}
function M.mark(kind, arg)
  marks[#marks + 1] = { kind = kind, arg = arg }
  local n = node.new("whatsit", "user_defined")
  n.user_id, n.type, n.value = MARK, 100, #marks
  node.write(n)
end
local function dimension(n) return n*SP_CM end
function M.reserve_rect(x,y,w,h,pad)
  if w<=0 or h<=0 or pad<0 then tex.error("florilegium: reserve width/height must be positive and padding nonnegative") return end
  M.mark("reserve_page",{dimension(x-pad),dimension(y-pad),dimension(x+w+pad),dimension(y+h+pad)})
end
function M.reserve_box(w,h,d,pad)
  if pad<0 then tex.error("florilegium: reserve padding must be nonnegative") return end
  M.mark("reserve_box",{w=dimension(w),h=dimension(h),d=dimension(d),pad=dimension(pad)})
end

local HLIST, VLIST, GLUE, KERN, RULE, WHATSIT, USER
local function node_ids()
  HLIST, VLIST, GLUE, KERN, RULE, WHATSIT = node.id("hlist"), node.id("vlist"), node.id("glue"), node.id("kern"), node.id("rule"), node.id("whatsit")
  USER = node.subtype("user_defined")
end
-- walk a box list; y grows downward from the top of the outer box, x rightward
local function walk(head, parent, x, y, vertical, out)
  for n in node.traverse(head) do
    local id = n.id
    if id == HLIST or id == VLIST then
      if vertical then
        local base = y + n.height
        if n.list then walk(n.list, n, x + n.shift, id == VLIST and y or base, id == VLIST, out) end
        y = base + n.depth
      else
        local base = y + n.shift
        if n.list then walk(n.list, n, x, id == VLIST and base - n.height or base, id == VLIST, out) end
        x = x + n.width
      end
    elseif id == GLUE then
      local w = node.effective_glue(n, parent)
      if vertical then y = y + w else x = x + w end
    elseif id == KERN then
      if vertical then y = y + n.kern else x = x + n.kern end
    elseif id == RULE then
      if vertical then y = y + n.height + n.depth else x = x + n.width end
    elseif id == WHATSIT and n.subtype == USER and n.user_id == MARK then
      local m = marks[n.value]
      if m then out[#out + 1] = { kind = m.kind, arg = m.arg, x = x, y = y } end
    elseif not vertical then
      x = x + node.dimensions(n, n.next)
    end
  end
end
-- the marks on the page being shipped out, in page cm from the lower-left corner
local function page_marks(box)
  if type(box) == "table" then return box end
  if not HLIST then node_ids() end
  local b = box and tex.box[box]
  if not b then return {} end
  local out = {}
  walk(b.list, b, 0, 0, b.id == VLIST, out)
  local ph, inch = tex.dimen.paperheight * SP_CM, 2.54
  for _, m in ipairs(out) do
    m.x = inch + tex.hoffset * SP_CM + m.x * SP_CM
    m.y = ph - inch - tex.voffset * SP_CM - m.y * SP_CM
  end
  return out
end
M.page_marks = page_marks

-- ---------------------------------------------------------------- initials
-- \florilegiuminitial: a tile of side `side` (sp) whose top is the cap height
-- above the current baseline and whose left edge is `hang` (sp) to the left of
-- the current point, the start of the paragraph's first, indented line.
M.initial_font = "lmroman10-bold.otf"
M.initial_fallback = "plain"
function M.initial(letter, side, hang, cap)
  if utf8.len(letter)~=1 or letter:match("^%s$") then
    M.initial_result(-1)
    M.error("florilegium: an initial must be exactly one visible Unicode character")
    return
  end
  local bp = 72 / 72.27 / 65536
  ink.set_transform({ ink.CM, 0, 0, ink.CM, -hang * bp, (cap - side) * bp })
  local ok, err = require("initial").draw(page_rng.fork(), side * SP_CM, letter, { font = M.initial_font })
  M.initial_result(ok and 1 or 0)
  if not ok then
    if M.initial_fallback == "error" then M.error("florilegium: " .. tostring(err))
    else M.warning(tostring(err) .. "; using a plain initial") end
  else ink.flush() end
end
-- the letter is also typeset in the text, in PDF's invisible text rendering
-- mode, so that the paragraph still copies and searches as "This", not "his"
function M.hidden(on)
  ink.backend.literal(on and "3 Tr" or "0 Tr", 1)
end
function M.empty_text(on)
  ink.backend.literal(on and "/Span << /ActualText <FEFF> >> BDC" or "EMC", 1)
end

-- ---------------------------------------------------------------- aging
-- a garden's age: 0 spring (buds), 0.5 summer, 1 autumn (seed heads, falling
-- petals); nil leaves it as it always was. \florilegiumage sets it; the option
-- aging spreads it over the document, from the page count of the last run.
M.age = nil
function M.auto_age(page, last) M.age = last > 1 and math.min(1, (page - 1) / (last - 1)) or 0.5 end

-- the growth animation: after \florilegiumframe[explain]{k}{n}, a grown page
-- shows frame k of n of its garden's growth (animation.tex, tools/animate.py).
-- The garden is recorded once and each frame writes the part grown so far.
function M.frame(k, n, explain) frame = { k = k, n = n, explain = explain == "explain" } end

local function grown_frame(g)
  local function signature(value)
    if type(value) ~= "table" then return type(value)..":"..tostring(value) end
    local keys,out={},{}
    for k in pairs(value) do keys[#keys+1]=k end
    table.sort(keys,function(a,b) return tostring(a)<tostring(b) end)
    for _,k in ipairs(keys) do out[#out+1]=signature(k).."="..signature(value[k]) end
    return "{"..table.concat(out,";").."}"
  end
  local key = signature(g)..(M.color_key or "")
  if not recorded[key] then
    g.anim = true
    recorded = { [key] = require("grow").page(g) }      -- keep only the latest garden
  end
  local r = recorded[key]
  -- the last frame is the page: every event finished (r.total itself may round below)
  local t = frame.k >= frame.n and math.huge or r.total * (frame.k - 1) / math.max(1, frame.n - 1)
  ink.emit(r.rec, function(tag)
    if tag.overlay and not frame.explain then return false end
    local e = tag[1]
    local p = (t - e.t0) / e.dur
    return p >= tag[2] and (tag[3] == nil or p < tag[3])
  end)
  return r.stats
end

-- Page labels are also real, invisible text. Their physical position and reading
-- order are independent of the reflected illustration.
function M.number_text(label, box)
  tex.sprint(luatexbase.registernumber("catcodetable@atletter"),string.format(
    "\\flo@numbertext{%.4f}{%.4f}{%s}",box[1]*ink.CM,box[2]*ink.CM,label))
end

-- the grown composition for this page; M.visitors = false (option novisitors)
-- leaves out the butterflies, bees, snails and birds
M.visitors = true
function M.grown(seed, spill, spilly, box, number)
  local g = M.geometry(M.layout.text_gap, M.layout.side)
  if g.colright < 1.8 then
    M.error("florilegium: text-gap leaves less than 18 mm for the garden; reduce text-gap or increase the selected margin")
    return
  end
  g.seed, g.spill, g.spilly, g.visitors, g.age = seed, spill, spilly, M.visitors, M.age
  g.layout = M.layout
  g.number = M.layout.page_number and number or nil
  g.marks,g.reserves = {},{}
  for _,m in ipairs(page_marks(box)) do
    local r
    if m.kind=="reserve_page" then r=m.arg
    elseif m.kind=="reserve_box" then
      local a=m.arg;r={m.x-a.pad,m.y-a.d-a.pad,m.x+a.w+a.pad,m.y+a.h+a.pad}
    else g.marks[#g.marks+1]=m end
    if r then
      if g.mirror then r={g.pw-r[3],r[2],g.pw-r[1],r[4]} end
      g.reserves[#g.reserves+1]=r
    end
  end
  ink.set_page_transform(g.mirror and { -1, 0, 0, 1, g.pw * ink.CM, 0 } or nil)
  ink.set_page_clip(g.pw,g.ph,g.reserves)
  local stats
  if frame then stats=grown_frame(g) else stats=require("grow").page(g) end
  if M.layout.header then M.head(g) end
  ink.set_page_transform(nil)
  ink.set_page_clip(nil,nil,nil)
  if g.number then
    local b=stats and stats.number_box
    if b then
      if g.mirror then b={g.pw-b[3],b[2],g.pw-b[1],b[4]} end
      M.number_text(g.number,b)
    else M.warning("page label '"..g.number.."' could not fit safely; retain the document's ordinary footer") end
  end
end

-- the authored composition for this page
function M.authored(seed)
  local g = M.geometry()
  g.seed, g.visitors = seed, M.visitors
  require("authored").page(g)
  M.head(g)
end

return M
