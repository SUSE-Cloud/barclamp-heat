unless node[:roles].include?('heat-server')
  # HA part if node is in a cluster
  if File.exist?("/usr/sbin/crm")
    group_name = "g-heat"

    pacemaker_group group_name do
      action [:stop, :delete]
      only_if "crm configure show #{group_name}"
    end

    pacemaker_clone "cl-#{group_name}" do
      action [:stop, :delete]
      only_if "crm configure show cl-#{group_name}"
    end

    node[:heat][:platform][:services].each do |service|
      service.gsub!("openstack-","")
      pacemaker_primitive service do
        action [:stop, :delete]
        only_if "crm configure show #{service}"
      end
    end
  else
    # Non HA part if service is on a standalone node
    node[:heat][:platform][:services].each do |name|
      service name do
        action [:stop, :disable]
      end
    end
  end
  node.delete('heat')

  node.save
end
