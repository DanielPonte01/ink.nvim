local M = {}

M.block_tags = {
  h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
  p = true, div = true, blockquote = true,
  ul = true, ol = true, li = true,
  br = true, hr = true,
  pre = true, code = true,
  table = true, tr = true, td = true, th = true,
  dl = true, dt = true, dd = true
}

M.highlight_map = {
  h1 = "InkH1",
  h2 = "InkH2",
  h3 = "InkH3",
  h4 = "InkH4",
  h5 = "InkH5",
  h6 = "InkH6",
  b = "InkBold",
  strong = "InkBold",
  i = "InkItalic",
  em = "InkItalic",
  blockquote = "Comment",
  code = "InkCode",
  pre = "InkCode",
  dt = "InkBold",
  mark = "InkHighlight",
  s = "InkStrikethrough",
  strike = "InkStrikethrough",
  del = "InkStrikethrough",
  u = "InkUnderlined"
}

return M