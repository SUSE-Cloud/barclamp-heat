unless node[:roles].include?('heat-server')
  # HA part if node is in a cluster
  if File.exist?("/usr/sbin/crm")
    group_name = "g-heat"

    pacemaker_clone "cl-#{group_name}" do
      action [:stop, :delete]
      only_if "crm configure show cl-#{group_name}"
    end

    pacemaker_group group_name do
      action [:stop, :delete]
      only_if "crm configure show #{group_name}"
    end

    ["engine", "api", "api_cfn", "api_cloudwatch"].each do |service|
      primitive_name = "heat-#{service}".gsub("_","-")
      pacemaker_primitive primitive_name do
        action [:stop, :delete]
        only_if "crm configure show heat-#{service}"
      end
    end
  end

  # Non HA part if service is on a standalone node
  node[:heat][:platform][:services].each do |name|
    service name do
      action [:stop, :disable]
    end
  end
  node.delete('heat')

  node.save
end
