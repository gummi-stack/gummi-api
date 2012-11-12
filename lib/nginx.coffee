module.exports = class NginxConfig
	writeConfig: (name, config) ->
		fs.writeFileSync "/nginx/#{name}.conf", config
	
	reload: (done) ->
		exec 'ssh -i /root/.ssh/id_rsa 10.1.69.100 -C /etc/init.d/nginx reload', (err, stdout, stderr) ->
			done arguments
	