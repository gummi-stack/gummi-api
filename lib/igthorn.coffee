util = require 'util'
http = require 'http'




module.exports = class
	start: (data, done) ->
		util.log "Volam start: #{data.slug}, #{data.cmd} #{data.name} #{data.worker}"
		data.env = {GUMMI: 'BEAR'}
		
		@request '10.1.69.105', 81, '/ps/start', data, (res) ->
			done res
			
	
	softKill: (data, done) ->
		@request '10.1.69.105', 81, '/ps/kill', data, (res) ->
			done res
		
		
	request: (ip, port, url, data, done) ->
		data = JSON.stringify data
		opts = 
			host: ip
			port: 81
			path: url
			method: 'POST'
			headers:
				'Content-Type': 'application/json; charset=utf-8'
				'Content-Length': data.length
		
		req = http.request opts, (res) =>
			res.setEncoding 'utf8' 
			
			buffer = ''
			res.on 'data', (chunk) ->
				buffer += chunk
			res.on 'end', () ->
				util.log "----- " + buffer
				done JSON.parse buffer
				
		req.write data
		req.end()
	