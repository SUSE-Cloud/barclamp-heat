# Copyright 2013, SUSE Inc., Inc.
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

case node["platform"]
when "ubuntu"
  default[:heat][:platform] = {
    :packages => ["heat-engine", "heat-api", "heat-api-cfn",
                  "heat-api-cloudwatch", "python-heat", "heat-common",
                  "python-heatclient"],
    :services => ["heat-engine","heat-api","heat-api-cfn","heat-api-cloudwatch"],
    :aux_dirs => ["/var/cache/heat","/etc/heat/environment.d"]
  }
when "suse"
  default[:heat][:platform] = {
    :packages => ["openstack-heat-engine", "openstack-heat-api",
                  "openstack-heat-api-cfn", "openstack-heat-api-cloudwatch",
                  "python-heatclient"],
    :services => ["openstack-heat-engine", "openstack-heat-api",
                  "openstack-heat-api-cfn", "openstack-heat-api-cloudwatch"],
    :aux_dirs => ["/var/cache/heat", "/etc/heat/environment.d"]
  }
end

default[:heat][:debug] = false
default[:heat][:verbose] = false

default[:heat][:user] = "heat"
default[:heat][:group] = "heat"

default[:heat][:db][:database] = "heat"
default[:heat][:db][:user] = "heat"
default[:heat][:db][:password] = "" # Set by Recipe

default[:heat][:keystone_service_user] = "heat"
default[:heat][:keystone_service_password] = ""

default[:heat][:api][:protocol] = "http"
default[:heat][:api][:cfn_port] = 8000
default[:heat][:api][:engine_port] = 8001
default[:heat][:api][:cloud_watch_port] = 8003
default[:heat][:api][:port] = 8004

default[:heat][:metering_secret] = "" # Set by Recipe

default[:heat][:ha][:enabled] = false
# Ports to bind to when haproxy is used for the real ports
default[:heat][:ha][:ports][:cfn_port] = 5570
default[:heat][:ha][:ports][:api_port] = 5571
default[:heat][:ha][:ports][:cloud_watch_port] = 5572

# Pacemaker bits
# TODO agents for othe services?
default[:heat][:ha][:agent] = "ocf:openstack:heat-engine"
default[:heat][:ha][:op][:monitor][:interval] = "10s"
