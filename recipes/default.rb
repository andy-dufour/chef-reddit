#
# Cookbook Name:: reddit
# Recipe:: default
#
# Copyright (C) 2014 Andrew DuFour
#
# All rights reserved - Do Not Redistribute
#

include_recipe "database::postgresql"
include_recipe "java"
include_recipe "runit"

group "reddit" do
	action :create
end


user "reddit" do
	action :create
	comment "Reddit User"
	gid "reddit"
	home "/home/reddit"
	shell "/bin/bash"
	supports :manage_home => true 
end

directory "/home/reddit" do
	owner "reddit"
	group "reddit"
	mode "0755"
	action :create
end

for p in node['reddit']['packages'] do
  package p do
    action [:install]
  end
end

git "/home/reddit/reddit" do
	repository "https://github.com/reddit/reddit.git"
	reference "master"
	user "reddit"
	group "reddit"
	action :sync
end

bash "compile reddit" do
	user "root"
	cwd "/home/reddit/reddit/r2/"
	code <<-EOH
		python setup.py build
		python setup.py develop
		make
	EOH
end

include_recipe "postgresql::server_debian"

bash "add postgres user pw" do
	user "root"
	cwd "/root/"
	code <<-EOH
	sudo -u postgres psql -U postgres -d postgres -c "alter user postgres with password 'password';"
	EOH
end


postgresql_connection_info = {
  :host     => 'localhost',
  :port     => 5432,
  :username => 'postgres',
  :password => 'password'
}

postgresql_database_user 'reddit' do
  connection postgresql_connection_info
  password   'password'
  action     :create
end

postgresql_database 'reddit' do
  connection postgresql_connection_info
  template 'DEFAULT'
  encoding 'utf8'
  tablespace 'DEFAULT'
  connection_limit '-1'
  owner 'reddit'
  action :create
end

bash "import postgresql functions" do
	user "postgres"
	cwd "/home/reddit/reddit/"
	code <<-EOH
		psql reddit < sql/functions.sql
	EOH
end


include_recipe "cassandra::install_from_release"
include_recipe "cassandra::bintools"

template "/home/reddit/reddit-cassandra.txt" do
	source "reddit-cassandra.erb"
	owner "root"
	group "root"
	mode "0644"
end

service "cassandra" do
	Chef::Provider::Service::Init::Debian
	start_command "cd /usr/local/share/cassandra/bin;./cassandra"
	supports :start => true
	action [ :start ]
end


bash "configure cassandra" do
	user "root"
	cwd "/home/reddit/"
	code <<-EOH
		/usr/local/share/cassandra/bin/cassandra-cli -host localhost -port 9160 -f reddit-cassandra.txt
	EOH
end

include_recipe "rabbitmq"

bash "configure rabbitmq" do
	user "root"
	cwd "/home/reddit/"
	code <<-EOH
		rabbitmqctl add_vhost /
		rabbitmqctl add_user reddit reddit
		rabbitmqctl set_permissions -p / reddit ".*" ".*" ".*"
	EOH
end


include_recipe "memcached"

