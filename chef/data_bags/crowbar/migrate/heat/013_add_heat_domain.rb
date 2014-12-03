def upgrade ta, td, a, d
  # Password is created only at creation time, so we need to create one here.
  # We use a class variable to set the same password in the proposal and in the
  # role.
  unless defined?(@@ceilometer_db_password)
    service = ServiceObject.new "fake-logger"
    @@stack_domain_admin_password = service.random_password
  end

  a['stack_domain_admin'] = ta['stack_domain_admin']
  a['stack_domain_admin_password'] = @@stack_domain_admin_password
  return a, d
end

def downgrade ta, td, a, d
  a.delete('stack_domain_admin')
  a.delete('stack_domain_admin_password')
  return a, d
end
