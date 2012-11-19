util = require 'util'
http = require 'http'




module.exports = class Igthorn
	start: (data, done) ->
		util.log "Volam start: #{data.slug}, #{data.cmd} #{data.name} #{data.worker}"
		data.env = {GUMMI: 'BEAR'}
		
		@request '10.1.69.105', 81, '/ps/start', data, done
	
	softKill: (data, done) ->
		util.log "Volam stop: "
		util.log util.inspect data
		@request '10.1.69.105', 81, '/ps/kill', data, done
		
		
	request: (ip, port, url, data, done) ->
		data = JSON.stringify data
		opts = 
			host: ip
			port: 81
			path: url
			method: 'POST'
			headers:
				'Accept': 'application/json'
				'Content-Type': 'application/json; charset=utf-8'
				'Content-Length': data.length
		
		req = http.request opts, (res) =>
			res.setEncoding 'utf8' 
			
			buffer = ''
			res.on 'data', (chunk) ->
				buffer += chunk
			res.on 'end', () ->
				# util.log "----- " + buffer
				data = JSON.parse buffer
				# util.log data
				if data.error
					done data, null
				else
					done null, data
		
		req.on 'error', (err) ->
			util.log err if err
			done err	
		req.write data
		req.end()
	