local old_name= 'xaolon'
vim.ui.input({
  prompt = "New name: ",
  default = old_name,
}, function(new_name)
  if new_name and new_name ~= "" then
    vim.fn.rename(old_name, new_name)
  end
end)
