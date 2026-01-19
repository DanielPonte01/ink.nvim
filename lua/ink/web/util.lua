-- lua/ink/web/util.lua
-- Shared utilities for the web module

local M = {}

-- Check if URL is from Planalto website
-- @param url: URL string to check
-- @return boolean: true if URL is from planalto.gov.br
function M.is_planalto_url(url)
  return url:match("^https?://[^/]*planalto%.gov%.br/") ~= nil
end

return M
