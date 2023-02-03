SimpleCov.start do
  enable_coverage :branch

  add_filter('/test/')
  add_filter('/stubs/')
end
