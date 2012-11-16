fs = require 'fs'
{spawn, exec}	= require 'child_process'

module.exports = class NginxConfig
	updateUpstream: (app, branch, nodes) ->
		upstream = "#{branch}.#{app}".replace /\./g, ''

		servers = ""
		servers += "\tserver #{node.ip}:#{node.port};\n" for node in nodes
		
		cfg = ""
		location = "proxy_pass http://down.nibbler.cz;"
		
		if servers
			cfg = """
					upstream #{upstream} {
				   #{servers}
				}
			"""
			location = "proxy_pass http://#{upstream};"
		
		cfg += """
			server {

			  listen 80;
			  server_name #{branch}.#{app}.nibbler.cz;
			  location / {
				#{location}
			  }
			  location @down {
			     proxy_pass http://down.nibbler.cz;
			  }
			  error_page 504 = @down;
			}
		"""
		
		@_writeConfig upstream, cfg 

	reload: (done) ->
		exec 'ssh -i /root/.ssh/id_rsa 10.1.69.100 -C /etc/init.d/nginx reload', (err, stdout, stderr) ->
			done arguments
	
	_writeConfig: (name, config) ->
		fs.writeFileSync "/nginx/#{name}.conf", config
	
