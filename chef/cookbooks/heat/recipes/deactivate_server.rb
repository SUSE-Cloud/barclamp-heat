unless node[:roles].include?('heat-server')
  node[:heat][:platform][:services].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node[:run_list_map].delete('heat-server_remove')
  node[:roles].delete('heat-server_remove')
  node[:recipes].delete('heat::deactivate_server')
  node[:crowbar].delete('heat')
  node.save
end
