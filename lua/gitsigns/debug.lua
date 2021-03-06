local M = {
   debug_mode = false,
}

function M.dprint(msg, bufnr, caller)
   if not M.debug_mode then
      return
   end
   local name = caller or debug.getinfo(1, 'n').name or ''
   print(string.format('%s(%s): %s\n', name, bufnr, msg))
end

return M
