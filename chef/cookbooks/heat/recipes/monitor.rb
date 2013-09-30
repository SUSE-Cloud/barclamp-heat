svcs = []
node[:heat][:api].each_key do |svc|
   svcs << svc
end
log ("Will monitor heat services: ")

include_recipe "nagios::common" if node["roles"].include?("nagios-client")

template "/etc/nagios/nrpe.d/heat-api_nrpe.cfg" do
  source "heat_nrpe.cfg.erb"
  mode "0644"
  group node[:nagios][:group]
  owner node[:nagios][:user]
  variables( {
    :heat_services => svcs,
    :heat_ports => node[:heat][:api],
    :heat_ip => node.ipaddress
  }
   notifies :restart, "service[nagios-nrpe-server]"
end if node["roles"].include?("nagios-client")

