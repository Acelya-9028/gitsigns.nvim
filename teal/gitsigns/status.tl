local api = vim.api

local Status = {
  status: StatusObj = {},
  formatter: function(StatusObj): string = nil
}

function Status:update(bufnr: number, status: StatusObj)
  if not api.nvim_buf_is_loaded(bufnr) then
    return
  end
  if status then
    self.status = status
  end
  vim.schedule(function()
    api.nvim_buf_set_var(bufnr, 'gitsigns_head', self.status.head or '')
    api.nvim_buf_set_var(bufnr, 'gitsigns_status_dict', self.status)
    api.nvim_buf_set_var(bufnr, 'gitsigns_status', self.formatter(self.status))
  end)
end

function Status:clear(bufnr: number)
  if not api.nvim_buf_is_loaded(bufnr) then
    return
  end
  vim.schedule(function()
    api.nvim_buf_del_var(bufnr, 'gitsigns_head')
    api.nvim_buf_del_var(bufnr, 'gitsigns_status_dict')
    api.nvim_buf_del_var(bufnr, 'gitsigns_status')
  end)
end

function Status:update_head(bufnr: number, head: string)
  self.status.head = head
  Status:update(bufnr)
end

return Status
