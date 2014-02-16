util = require 'util'
http = require 'http'
request = require 'request'



module.exports = class Book

	constructor: (config) ->
		@ip = config.api.host
		@port = config.port
		# tohle je blbe - tady ma bejt url na api gummi booku
		@apiUrl = "#{config.api.scheme}://#{config.api.host}:#{config.port}"


	getLogs: (app, branch, res) =>
		request("#{@apiUrl}/session/#{app}/#{branch}").pipe res
		# request.get
		# 	url: "http://#{@ip}:#{@port}/session/#{app}/#{branch}"
		# , (err, req, body) =>
		#
		# 	util.log util.inspect body
		# 	done body

	getId: (app, branch, type, done) =>
		request.post
			url: "#{@apiUrl}/sessions"
			json:
				app: app
				branch: branch
				type: type
		, (err, req, body) =>
			# TODO error handling
			# util.log util.inspect body
			done err, body.uuid


	# start: (data, done) ->
	# 	util.log "Volam start: #{data.slug}, #{data.cmd} #{data.name} #{data.worker}"
	# 	util.log util.inspect data.userEnv
	# 	data.env = {} unless data.env
	# 	data.env.GUMMI = 'BEAR'
	#
	# 	@db.collection('toadwarts').find
	# 		id: data.toadwartId
	# 	.toArray (err, toadwarts) =>
	# 		[toadwart] = toadwarts
	# 		util.log util.inspect toadwart
	# 		@request 'POST', toadwart.ip, toadwart.port, '/ps/start', data, done
	#
	# status: (ip, port, done) ->
	# 	@request 'GET', ip, port, '/ps/status', "", done
	#
	#
	# findToadwartById: (id, done) =>
	# 	@db.collection('toadwarts').find
	# 		id: id
	# 	.toArray (err, results) =>
	# 		done results[0]
	#
	# softKill: (data, done) ->
	# 	util.log "Volam stop: "
	# 	# util.log util.inspect data
	# 	util.log util.inspect data.toadwartId
	#
	# 	o =
	# 		name: data?.name
	# 		pid: data?.pid
	# 	util.log util.inspect o
	#
	# 	@findToadwartById data.toadwartId, (toadwart) =>
	# 		ip = toadwart.ip
	# 		port = toadwart.port
	# 		@request 'POST', ip, port, '/ps/kill', data, done
	#
	#
	# request: (method, ip, port, url, data = "", done) ->
	# 	length = 0
	# 	if method is 'POST'
	# 		data = JSON.stringify data
	# 		headers =
	# 			'Accept': 'application/json'
	# 			'Content-Type': 'application/json; charset=utf-8'
	# 			'Content-Length': data.length
	#
	# 	else
	# 		headers =
	# 			'Accept': 'application/json'
	#
	# 	opts =
	# 		host: ip
	# 		port: port
	# 		path: url
	# 		method: method
	# 		headers: headers
	#
	# 	req = http.request opts, (res) =>
	# 		res.setEncoding 'utf8'
	#
	# 		buffer = ''
	# 		res.on 'data', (chunk) ->
	# 			buffer += chunk
	# 		res.on 'end', () ->
	# 			# util.log "----- " + buffer
	# 			data = JSON.parse buffer
	# 			# util.log data
	# 			if data.error
	# 				done data, null
	# 			else
	# 				done null, data
	#
	# 	req.on 'error', (err) ->
	# 		util.log err if err
	# 		done err
	# 	if method is 'POST'
	# 		req.write data
	# 	req.end()
	#
	#
	# git: (data, done) ->
	# 	method = 'POST'
	# 	ip = @ip
	# 	port = @port
	# 	url = '/git/build'
	#
	# 	data = JSON.stringify data
	# 	headers =
	# 		'Accept': 'application/json'
	# 		'Content-Type': 'application/json; charset=utf-8'
	# 		'Content-Length': data.length
	#
	#
	# 	opts =
	# 		host: ip
	# 		port: port
	# 		path: url
	# 		method: method
	# 		headers: headers
	#
	# 	req = http.request opts, (res) =>
	# 		res.setEncoding 'utf8'
	# 		return done(res)
	#
	#
	# 	req.on 'error', (err) ->
	# 		util.log err if err
	#
	# 	req.write data
	# 	req.end()

