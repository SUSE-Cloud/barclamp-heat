# Copyright 2013 SUSE, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

heat_path = "/opt/heat"
venv_path = node[:heat][:use_virtualenv] ? "#{heat_path}/.venv" : nil
venv_prefix = node[:heat][:use_virtualenv] ? ". #{venv_path}/bin/activate &&" : nil

db_settings = fetch_database_settings

include_recipe "database::client"
include_recipe "#{db_settings[:backend_name]}::client"
include_recipe "#{db_settings[:backend_name]}::python-client"

crowbar_pacemaker_sync_mark "wait-heat_database"

# Create the Heat Database
database "create #{node[:heat][:db][:database]} database" do
  connection db_settings[:connection]
  database_name node[:heat][:db][:database]
  provider db_settings[:provider]
  action :create
end

database_user "create heat database user" do
  host '%'
  connection db_settings[:connection]
  username node[:heat][:db][:user]
  password node[:heat][:db][:password]
  provider db_settings[:user_provider]
  action :create
end

database_user "grant database access for heat database user" do
  connection db_settings[:connection]
  username node[:heat][:db][:user]
  password node[:heat][:db][:password]
  database_name node[:heat][:db][:database]
  host '%'
  privileges db_settings[:privs]
  provider db_settings[:user_provider]
  action :grant
end

crowbar_pacemaker_sync_mark "create-heat_database"

unless node[:heat][:use_gitrepo]
  node[:heat][:platform][:packages].each do |p|
    package p
  end

else
  pfs_and_install_deps @cookbook_name do
    virtualenv venv_path
    path heat_path
    wrap_bins "heat"
  end

  node[:heat][:platform][:services].each do |s|
    link_service s do
      virtualenv venv_path
    end
  end

  create_user_and_dirs("heat")

end

directory "/var/cache/heat" do
  owner node[:heat][:user]
  group node[:heat][:group]
  mode 00750
  action :create
end

directory "/etc/heat/environment.d" do
  owner "root"
  group "root"
  mode 00755
  action :create
end

keystone_settings = KeystoneHelper.keystone_settings(node, @cookbook_name)

ha_enabled = node[:heat][:ha][:enabled]

if ha_enabled
  admin_address = Chef::Recipe::Barclamp::Inventory.get_network_by_type(node, "admin").address
  bind_host = admin_address
  api_port = node[:heat][:ha][:ports][:api_port]
  cfn_port = node[:heat][:ha][:ports][:cfn_port]
  cloud_watch_port = node[:heat][:ha][:ports][:cloud_watch_port]
else
  bind_host = "0.0.0.0"
  api_port = node[:heat][:api][:port]
  cfn_port = node[:heat][:api][:cfn_port]
  cloud_watch_port = node[:heat][:api][:cloud_watch_port]
end

my_admin_host = CrowbarHelper.get_host_for_admin_url(node, ha_enabled)
my_public_host = CrowbarHelper.get_host_for_public_url(node, node[:heat][:api][:protocol] == "https", ha_enabled)

db_connection = "#{db_settings[:url_scheme]}://#{node[:heat][:db][:user]}:#{node[:heat][:db][:password]}@#{db_settings[:address]}/#{node[:heat][:db][:database]}"

crowbar_pacemaker_sync_mark "wait-heat_register"

keystone_register "heat wakeup keystone" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  action :wakeup
end

keystone_register "register heat user" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name keystone_settings['service_user']
  user_password keystone_settings['service_password']
  tenant_name keystone_settings['service_tenant']
  action :add_user
end

keystone_register "give heat user access" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name keystone_settings['service_user']
  tenant_name keystone_settings['service_tenant']
  role_name "admin"
  action :add_access
end

keystone_register "add heat stack user role" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  user_name keystone_settings['service_user']
  tenant_name keystone_settings['service_tenant']
  role_name "heat_stack_user"
  action :add_role
end

package "python-openstackclient" do
  action :install
end


stack_user_domain_name = "heat"

bash "register heat domain" do
  user "root"
  code <<-EOF

    OS_URL="#{keystone_settings['protocol']}://#{keystone_settings['internal_url_host']}:#{keystone_settings['service_port']}/v3"

    eval $(openstack --os-token #{keystone_settings['admin_token']} \
        --os-url=$OS_URL --os-identity-api-version=3 \
        --os-region-name='#{keystone_settings['endpoint_region']}' domain show -f shell --variable id #{stack_user_domain_name})

    HEAT_DOMAIN_ID=$id

    if [ -z "$HEAT_DOMAIN_ID" ]; then
        HEAT_DOMAIN_ID=$(openstack --os-token #{keystone_settings['admin_token']} \
            --os-url=$OS_URL --os-identity-api-version=3 \
            --os-region-name='#{keystone_settings['endpoint_region']}' \
            domain create #{stack_user_domain_name} \
            --description "Owns users and projects created by heat" \
            | awk '/id/  { print $4 } ')
    fi

    openstack --os-token #{keystone_settings['admin_token']} --os-url=$OS_URL \
        --os-region-name='#{keystone_settings['endpoint_region']}' \
        --os-identity-api-version=3 user create --password #{node[:heat]["stack_domain_admin_password"]} \
        --domain $HEAT_DOMAIN_ID #{node[:heat]["stack_domain_admin"]} \
        --description "Manages users and projects created by heat" || true

    openstack --os-token #{keystone_settings['admin_token']} --os-url=$OS_URL \
        --os-region-name='#{keystone_settings['endpoint_region']}' \
        --os-identity-api-version=3 role add --user #{node[:heat]["stack_domain_admin"]} \
        --domain $HEAT_DOMAIN_ID admin || true
  EOF
end

# Create Heat CloudFormation service
keystone_register "register Heat CloudFormation Service" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  service_name "heat-cfn"
  service_type "cloudformation"
  service_description "Heat CloudFormation Service"
  action :add_service
end

keystone_register "register heat Cfn endpoint" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  endpoint_service "heat-cfn"
  endpoint_region keystone_settings['endpoint_region']
  endpoint_publicURL "#{node[:heat][:api][:protocol]}://#{my_public_host}:#{node[:heat][:api][:cfn_port]}/v1"
  endpoint_adminURL "#{node[:heat][:api][:protocol]}://#{my_admin_host}:#{node[:heat][:api][:cfn_port]}/v1"
  endpoint_internalURL "#{node[:heat][:api][:protocol]}://#{my_admin_host}:#{node[:heat][:api][:cfn_port]}/v1"
  #  endpoint_global true
  #  endpoint_enabled true
  action :add_endpoint_template
end

# Create Heat service
keystone_register "register Heat Service" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  service_name "heat"
  service_type "orchestration"
  service_description "Heat Service"
  action :add_service
end

keystone_register "register heat endpoint" do
  protocol keystone_settings['protocol']
  host keystone_settings['internal_url_host']
  port keystone_settings['admin_port']
  token keystone_settings['admin_token']
  endpoint_service "heat"
  endpoint_region keystone_settings['endpoint_region']
  endpoint_publicURL "#{node[:heat][:api][:protocol]}://#{my_public_host}:#{node[:heat][:api][:port]}/v1/$(tenant_id)s"
  endpoint_adminURL "#{node[:heat][:api][:protocol]}://#{my_admin_host}:#{node[:heat][:api][:port]}/v1/$(tenant_id)s"
  endpoint_internalURL "#{node[:heat][:api][:protocol]}://#{my_admin_host}:#{node[:heat][:api][:port]}/v1/$(tenant_id)s"
  #  endpoint_global true
  #  endpoint_enabled true
  action :add_endpoint_template
end

crowbar_pacemaker_sync_mark "create-heat_register"

shell_get_stack_user_domain = <<-EOF
  export OS_URL="#{keystone_settings['protocol']}://#{keystone_settings['internal_url_host']}:#{keystone_settings['service_port']}/v3"
  eval $(openstack --os-token #{keystone_settings['admin_token']} \
    --os-url=$OS_URL \
    --os-region-name='#{keystone_settings['endpoint_region']}' \
    --os-identity-api-version=3 domain show -f shell --variable id #{stack_user_domain_name});
  echo $id
EOF

template "/etc/heat/heat.conf" do
  source "heat.conf.erb"
  owner "root"
  group node[:heat][:group]
  mode "0640"
  variables(
    :debug => node[:heat][:debug],
    :verbose => node[:heat][:verbose],
    :rabbit_settings => fetch_rabbitmq_settings,
    :keystone_settings => keystone_settings,
    :database_connection => db_connection,
    :bind_host => bind_host,
    :api_port => api_port,
    :cloud_watch_port => cloud_watch_port,
    :instance_user => node[:heat][:default_instance_user],
    :cfn_port => cfn_port,
    :auth_encryption_key => node[:heat][:auth_encryption_key],
    :heat_metadata_server_url => "#{node[:heat][:api][:protocol]}://#{my_public_host}:#{node[:heat][:api][:cfn_port]}",
    :heat_waitcondition_server_url => "#{node[:heat][:api][:protocol]}://#{my_public_host}:#{node[:heat][:api][:cfn_port]}/v1/waitcondition",
    :heat_watch_server_url => "#{node[:heat][:api][:protocol]}://#{my_public_host}:#{node[:heat][:api][:cloud_watch_port]}",
    :stack_user_domain => %x[ #{shell_get_stack_user_domain} ].chomp,
    :stack_domain_admin => node[:heat]["stack_domain_admin"],
    :stack_domain_admin_password => node[:heat]["stack_domain_admin_password"]
  )
end

service "heat-engine" do
  service_name node[:heat][:engine][:service_name]
  supports :status => true, :restart => true
  action [ :enable, :start ]
  subscribes :restart, resources("template[/etc/heat/heat.conf]")
  provider Chef::Provider::CrowbarPacemakerService if ha_enabled
end

template "/etc/heat/loadbalancer.template" do
  source "loadbalancer.template.erb"
  owner "root"
  group node[:heat][:group]
  mode "0640"
  notifies :restart, "service[heat-engine]", :delayed
  only_if { node[:platform] == "suse" }
end

service "heat-api" do
  service_name node[:heat][:api][:service_name]
  supports :status => true, :restart => true
  action [ :enable, :start ]
  subscribes :restart, resources("template[/etc/heat/heat.conf]")
  provider Chef::Provider::CrowbarPacemakerService if ha_enabled
end

service "heat-api-cfn" do
  service_name node[:heat][:api_cfn][:service_name]
  supports :status => true, :restart => true
  action [ :enable, :start ]
  subscribes :restart, resources("template[/etc/heat/heat.conf]")
  provider Chef::Provider::CrowbarPacemakerService if ha_enabled
end

service "heat-api-cloudwatch" do
  service_name node[:heat][:api_cloudwatch][:service_name]
  supports :status => true, :restart => true
  action [ :enable, :start ]
  subscribes :restart, resources("template[/etc/heat/heat.conf]")
  provider Chef::Provider::CrowbarPacemakerService if ha_enabled
end

crowbar_pacemaker_sync_mark "wait-heat_db_sync"

execute "heat-manage db_sync" do
  user node[:heat][:user]
  group node[:heat][:group]
  command "#{venv_prefix}heat-manage db_sync"
  # We only do the sync the first time, and only if we're not doing HA or if we
  # are the founder of the HA cluster (so that it's really only done once).
  only_if { !node[:heat][:db_synced] && (!ha_enabled || CrowbarPacemakerHelper.is_cluster_founder?(node)) }
end

# We want to keep a note that we've done db_sync, so we don't do it again.
# If we were doing that outside a ruby_block, we would add the note in the
# compile phase, before the actual db_sync is done (which is wrong, since it
# could possibly not be reached in case of errors).
ruby_block "mark node for heat db_sync" do
  block do
    node[:heat][:db_synced] = true
    node.save
  end
  action :nothing
  subscribes :create, "execute[heat-manage db_sync]", :immediately
end

crowbar_pacemaker_sync_mark "create-heat_db_sync"

if ha_enabled
  log "HA support for heat is enabled"
  include_recipe "heat::ha"
else
  log "HA support for heat is disabled"
end

node.save
