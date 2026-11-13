-- Dynamic programming over guide intervals, retaining the preceding source piece.
local M = {}

local function seam(left, right)
  local cost = 0
  for i, value in ipairs(left.exit_profile) do
    cost = cost + (value - right.entry_profile[i])^2
  end
  return cost / #left.exit_profile
end

function M.match(guide, library, limits)
  local states = {[1] = {{cost = 0}}}
  for first = 1, #guide - 1 do
    for _, prev in ipairs(states[first] or {}) do
      for index, piece in ipairs(library) do
        for count = limits.min_steps, limits.max_steps do
          local last = first + count
          if last <= #guide
            and (piece.role == "start") == (first == 1)
            and (piece.role == "finish") == (last == #guide) then
            local a, b = guide[first], guide[last]
            local length, turn = b.arc - a.arc, b.turn - a.turn
            local stretch = length / piece.length
            if stretch >= limits.min_stretch and stretch <= limits.max_stretch then
              local rib = (a.width + b.width) / 2
              local fit = math.log(stretch)^2 + (turn - piece.turn)^2 + math.log(rib / piece.width)^2
              local join = prev.piece and seam(library[prev.piece], piece) or 0
              local cost = prev.cost + fit + limits.seam_weight * join
              local row = states[last] or {}
              states[last] = row
              local candidate = {piece = index, first = first, last = last, cost = cost,
                fit = fit, join = join, prev = prev}
              local slot
              for i, state in ipairs(row) do
                if state.piece == index then slot = i; break end
              end
              if not slot then row[#row + 1] = candidate
              elseif cost < row[slot].cost - 1e-12 then row[slot] = candidate end
            end
          end
        end
      end
    end
  end
  local best
  for _, state in ipairs(states[#guide] or {}) do
    if not best or state.cost < best.cost - 1e-12 then best = state end
  end
  if not best then return nil, "no endpoint-preserving guide match within stretch limits" end
  local pieces, cost = {}, best.cost
  while best.piece do
    pieces[#pieces + 1] = {piece = best.piece, first = best.first, last = best.last,
      fit = best.fit, join = best.join}
    best = best.prev
  end
  for i = 1, math.floor(#pieces / 2) do
    local j = #pieces + 1 - i
    pieces[i], pieces[j] = pieces[j], pieces[i]
  end
  return pieces, cost
end

return M
