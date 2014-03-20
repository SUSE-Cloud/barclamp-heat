unless node[:roles].include?('heat-server')
  node[:heat][:platform][:services].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node.delete('heat')
  node.save
end
