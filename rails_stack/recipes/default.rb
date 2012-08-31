# Add Dotdeb to apt sources
[ 'deb http://packages.dotdeb.org stable all',
  'deb-src http://packages.dotdeb.org stable all'].each do |line|
  execute "Add Dotdeb apt source: #{line}" do
    command %[echo '#{line}' >> /etc/apt/sources.list]
    not_if "cat /etc/apt/sources.list | grep '#{line}'"
  end
end
execute "wget -q -O - http://www.dotdeb.org/dotdeb.gpg | apt-key add -"
execute 'apt-get update' do
  returns [0,
    100 #Release file expired, ignoring
  ]
end

package 'git'

cookbook_file "/home/vagrant/.irbrc" do
  source 'irbrc'
  owner 'vagrant'
  mode '0644'
end

include_recipe 'postfix'

package 'redis-server'

package 'memcached'

include_recipe "postgresql::server"

gem_package 'bundler'
execute 'bundle install' do
  command "su - vagrant -c 'cd /vagrant && bundle install'"
end

if File.exist? dbyml = '/vagrant/config/database.yml'
  # Snippet from opscode to reload gems
  require 'rubygems'
  Gem.clear_paths

  # Create a database user based on env and db config
  require 'yaml'

  rails_env = node[:rails_env] || 'development'
  if user_name = YAML::load(File.open dbyml).fetch(rails_env, {})['username']
    execute "create database user: #{user_name}" do
      user 'postgres'
      not_if "psql -c '\\du #{user_name}' | grep #{user_name}", :user => 'postgres'
      #TODO: Base createuser options on rails_env. IMO, --superuser is acceptable for development/test only
      command "createuser --superuser #{user_name}"
    end
  end
end

gem_package 'unicorn'
directory '/etc/unicorn'
template "/etc/unicorn/unicorn.rb" do
  source "unicorn.rb.erb"
end
template "/etc/init.d/unicorn" do
  source "unicorn.init.erb"
  mode '0774'
end
service "unicorn" do
  supports :restart => true
  action :enable
  subscribes :restart, resources(:template => ["/etc/init.d/unicorn", "/etc/unicorn/unicorn.rb"])
end

package 'nginx'
template "/etc/nginx/nginx.conf" do
  source "nginx.conf.erb"
end
service "nginx" do
  supports :restart => true
  action :enable
  subscribes :restart, resources(:template => ["/etc/nginx/nginx.conf"])
end

