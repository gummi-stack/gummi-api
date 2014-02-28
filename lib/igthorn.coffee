util = require 'util'
request = require 'request'
http = require 'http'
EventEmitter	= require('events').EventEmitter
JSONParser = require 'jsonparse'

module.exports = class Igthorn
	constructor: (config,@db) ->
		@ip = config.api.host
		@port = config.port
		@apiUrl = "#{config.api.scheme}://#{config.api.host}:#{config.port}"

	start: (data, done) ->
		console.log "SSSSSSSSSS@@@@@"
		return done "Missing toadwart id" unless data.toadwartId
		util.log "Volam start: #{data.slug.Location}, #{data.cmd} #{data.name} #{data.worker} #{data.toadwartId}"
		# util.log util.inspect data.userEnv
		data.env = {} unless data.env
		data.env.GUMMI = 'BEAR'

		@db.collection('toadwarts').findOne {id: data.toadwartId}, (err, toadwart) =>
			return done err if err
			return done "Toadie #{data.toadwartId} not found" unless toadwart
			console.log ">>>>>>>>>>>>>> STTTTTO"
			@request 'POST', toadwart.ip, toadwart.port, '/ps/start', data, (err, res, body) ->
				body.toadwartIp = toadwart.ip
				# console.log "RRRRRRR".cyan
				# console.log err
				# console.log body
				done err, body


	status: (ip, port, done) ->
		@request 'GET', ip, port, '/ps/status', "", (err, res, body) ->
			return done err if err

			try
				body = JSON.parse body
			catch err
				return done err.message

			done null, body


	findToadwartById: (id, done) =>
		@db.collection('toadwarts').findOne id: id, (err, toadwart) ->
			return done err if err
			return done "Toadwart not found" unless toadwart
			done null, toadwart

	softKill: (data, done) ->
		util.log "Volam stop: "
		# util.log util.inspect data

		o =
			name: data?.name
			pid: data?.pid
		# util.log util.inspect o

		@findToadwartById data.toadwartId, (err, toadwart) =>
			return done(err) if err
			ip = toadwart.ip
			port = toadwart.port
			@request 'POST', ip, port, '/ps/kill', data, done

	findToadwartForBuild: (done) =>
		@findToadwartById "8d9cb33c-d62d-43ea-b5c4-7f83edfe4969", done

	request: (method, ip, port, url, data = "", done) ->
		opts=
			method: method
			json: data
			uri: "http://#{ip}:#{port}#{url}"
		request opts, done

	git: (origReq, data, cb) =>
		@findToadwartForBuild (err, toadwart) =>
			return cb err if err
			console.log arguments
			emitter = new EventEmitter
			emitter.run = () ->
				method = 'POST'
				ip = toadwart.ip
				port = toadwart.port
				url = '/git/build'

				data = JSON.stringify data
				headers =
					'Accept': 'application/json'
					'Content-Type': origReq.headers['content-type']
					'x-data': data


				opts =
					host: ip
					port: port
					path: url
					method: method
					headers: headers



				req = http.request opts, (res) =>
					res.setEncoding 'utf8'

					stream = new JSONParser
					stream.onValue = (o) ->
						emitter.emit 'data', o


					res.on 'error', (err) ->
						emitter.emit 'error', err
					res.on 'data', (data) ->
						stream.write data
					res.on 'end', (data) ->
						emitter.emit 'end', data

				req.on 'error', (err) ->
					emitter.emit 'error', err

				#req.write data
				origReq.pipe req
				#req.end()
			return cb null, emitter
