name "heat-server_remove"
description "Deactivate Heat Server services"
run_list(
         "recipe[heat::deactivate]"
)
default_attributes()
override_attributes()
