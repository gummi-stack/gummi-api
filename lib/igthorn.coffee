util = require 'util'
request = require 'request'
http = require 'http'

module.exports = class Igthorn
	constructor: (config) ->
		@ip = config.api.host
		@port = config.port
		@apiUrl = "#{config.api.scheme}://#{config.api.host}:#{config.port}"
	
	start: (data, done) ->
		util.log "Volam start: #{data.slug}, #{data.cmd} #{data.name} #{data.worker} #{data.toadwartId}"
		# util.log util.inspect data.userEnv
		data.env = {} unless data.env
		data.env.GUMMI = 'BEAR'
		
		@db.collection('toadwarts').find
			id: data.toadwartId
		.toArray (err, toadwarts) =>
			[toadwart] = toadwarts
			util.log util.inspect toadwart
			@request 'POST', toadwart.ip, toadwart.port, '/ps/start', data, done

	status: (ip, port, done) ->
		@request 'GET', ip, port, '/ps/status', "", done
	
	
	findToadwartById: (id, done) =>
		@db.collection('toadwarts').find
			id: id
		.toArray (err, results) =>
			done results[0]

	softKill: (data, done) ->
		util.log "Volam stop: "
		# util.log util.inspect data
		util.log util.inspect data.toadwartId

		o = 	
			name: data?.name
			pid: data?.pid
		# util.log util.inspect o
		
		@findToadwartById data.toadwartId, (toadwart) =>
			ip = toadwart.ip
			port = toadwart.port 
			@request 'POST', ip, port, '/ps/kill', data, done
		
		
	request: (method, ip, port, url, data = "", done) ->
		opts=
			method: method
			json: data
			uri: "http://#{ip}:#{port}#{url}"
		request opts, done
	git: (data, done) ->
		method = 'POST'
		ip = @ip
		port = @port
		url = '/git/build'
		
		data = JSON.stringify data
		headers =
			'Accept': 'application/json'
			'Content-Type': 'application/json; charset=utf-8'
			'Content-Length': data.length

				
		opts =
			host: ip
			port: port
			path: url
			method: method
			headers: headers
		
		req = http.request opts, (res) =>
			res.setEncoding 'utf8'
			return done(res)

	
		req.on 'error', (err) ->
			util.log "Igthorn.git"
			util.log util.inspect err
			util.log err if err

		req.write data
		req.end()
