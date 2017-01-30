service "heat-engine" do
  service_name "openstack-heat-engine" if node.platform == "suse"
  action [ :stop, :disable ]
end
service "heat-api" do
  service_name "openstack-heat-api" if node.platform == "suse"
  action [ :stop, :disable ]
end
service "heat-api-cfn" do
  service_name "openstack-heat-api-cfn" if node.platform == "suse"
  action [ :stop, :disable ]
end
service "heat-api-cloudwatch" do
  service_name "openstack-heat-api-cloudwatch" if node.platform == "suse"
  action [ :stop, :disable ]
end
