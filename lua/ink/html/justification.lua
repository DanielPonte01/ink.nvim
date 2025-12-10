-- lua/ink/html/justification.lua
-- Responsabilidade: Pós-processamento de justificação de texto

local utils = require("ink.html.utils")

local M = {}

function M.apply_justification(lines, highlights, links, images, no_justify, max_width)
  local justify_map = {}

  for i, line in ipairs(lines) do
    local line_width = utils.display_width(line)
    if not no_justify[i] and line_width > 0 then
      local min_length = math.floor(max_width * 0.90)
      if line_width >= min_length and line_width < max_width then
        local word_info = {}
        local pos = 1
        while pos <= #line do
          while pos <= #line and line:sub(pos, pos) == " " do
            pos = pos + 1
          end
          if pos > #line then break end

          local word_start = pos
          while pos <= #line and line:sub(pos, pos) ~= " " do
            pos = pos + 1
          end
          local word_end = pos - 1
          local word = line:sub(word_start, word_end)

          table.insert(word_info, {
            word = word,
            orig_start = word_start - 1,
            orig_end = word_end
          })
        end

        if #word_info > 1 then
          local spaces_needed = max_width - line_width
          local gaps = #word_info - 1
          local base_spaces = 1
          local extra_spaces = math.floor(spaces_needed / gaps)
          local remainder = spaces_needed % gaps

          local new_line = word_info[1].word
          word_info[1].new_start = 0
          word_info[1].new_end = #word_info[1].word

          for j = 2, #word_info do
            local space_count = base_spaces + extra_spaces
            if j - 1 <= remainder then
              space_count = space_count + 1
            end
            new_line = new_line .. string.rep(" ", space_count)
            word_info[j].new_start = #new_line
            new_line = new_line .. word_info[j].word
            word_info[j].new_end = #new_line
          end

          justify_map[i] = word_info

          for _, hl in ipairs(highlights) do
            if hl[1] == i then
              hl[2] = utils.forward_map_column(word_info, hl[2])
              hl[3] = utils.forward_map_column(word_info, hl[3])
            end
          end

          for _, link in ipairs(links) do
            if link[1] == i then
              link[2] = utils.forward_map_column(word_info, link[2])
              link[3] = utils.forward_map_column(word_info, link[3])
            end
          end

          for _, img in ipairs(images) do
            if img.line == i then
              img.col_start = utils.forward_map_column(word_info, img.col_start)
              img.col_end = utils.forward_map_column(word_info, img.col_end)
            end
          end

          lines[i] = new_line
        end
      end
    end
  end

  return justify_map
end

return M
