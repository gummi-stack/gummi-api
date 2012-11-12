async			= require 'async'
colors			= require 'colors'
express			= require 'express'
util			= require 'util'
fs				= require 'fs'
http			= require 'http'
{spawn, exec}	= require 'child_process'
net				= require 'net'
procfile		= require 'procfile'

redis			= require('redis-url').connect()
mongoFactory	= require 'mongo-connection-factory'
ObjectID		= require('mongodb').ObjectID

Igthorn 		= require './lib/igthorn'
Nginx			= require './lib/nginx'
config			= require './config'

mongoUrl = config.mongoUrl


###
TODO
do nastartovanych aplikaci pridat info na kterem nodu bezi
###

igthorn = new Igthorn
# 
# igthorn.start '/shared/slugs/testing.git-master-fa6da3f8eb256f5964a522f55a7d1f356d7ce6b7.tgz', 'node web.js', ->

# return


	
nginx = new Nginx

app = express()

app.post '/', (req, res)->
	buffer = ''
	req.on 'data', (data) ->
		buffer += data
	req.on 'end', () ->


app.get '/reloadrouter', (req, res) ->
	nginx.reload (o) ->
		res.json o


app.get '/apps/:app/:branch/logs', (req, res) ->
	app = req.params.app
	app = app + '.git' unless app.match /\.git/
	branch = req.params.branch 
	tail = req.query.tail
	start = new Date().getTime() * 1000;
	util.log util.inspect tail


	processResponse = (response) ->
		#todo colorizovat podle workeru ?
		for time,i in response by 2
			data = response[i+1]
			date = new Date(time/1000)
			line = date.toJSON().replace(/T/, ' ').replace(/Z/, ' ').cyan
			matches = data.match /([^\s]*)\s- -(.*)/
			worker = matches[1]
			if worker is 'dyno'
				worker = worker.magenta
			else
				worker = worker.yellow
			
			line += "[#{worker}] #{matches[2]}\n"
			res.write line
			# process.stdout.write line

	
	closed = no
	res.on 'close', ->
		closed = yes

	getNext = () ->
		return if closed 
		
		# nacteni novych od posledniho dotazu
		opts = ["#{app}/#{branch}", '+inf', start, 'WITHSCORES']
		start = new Date().getTime() * 1000;

		redis.zrevrangebyscore opts, (err, response) ->
			# util.log 'dalsi ' + start
			# util.log util.inspect res.complete
			
			processResponse response.reverse()
			setTimeout (() -> getNext()), 1000 
		


	opts = ["#{app}/#{branch}", start, '-inf', 'WITHSCORES', 'LIMIT', '0', '10']
	# nacteni odted do historie
	redis.zrevrangebyscore opts, (err, response) ->
		processResponse response.reverse()
		if tail
			getNext()
		else 
			res.end()
			

app.get '/apps/:app/:branch/ps', (req, res) ->
	app = req.params.app
	app = app + '.git' unless app.match /\.git/
	branch = req.params.branch 
	mongoFactory.db mongoUrl, (err, db) ->
	
		db.collection 'instances', (err, instances) ->
			q = 
				app: app
				branch: branch
			instances.find(q).toArray (err, results) ->
				res.json results
	
	


app.get '/apps/:app/:branch/ps/stop', (req, res) ->
	app = req.params.app
	app = app + '.git' unless app.match /\.git/
	branch = req.params.branch 

	mongoFactory.db mongoUrl, (err, db) ->
	
		db.collection 'instances', (err, instances) ->
			q = 
				app: app
				branch: branch
			util.log 'xxx'
			instances.find(q).toArray (err, results) ->
				res.json 
					status: 'ok'
					message: 'Asi sem je zabil, ale nekontroloval jsem to'


				for result in results
					o = 	
						name: result.dynoData.name
						pid: result.dynoData.pid
					do(result) ->
						util.log util.inspect result
						igthorn.softKill o, (res) ->
							
							if res.status is 'ok'
								console.log 'mazu'
								q = _id: result._id
								util.log util.inspect q
								instances.remove q, () ->
									util.log util.inspect arguments
							util.log util.inspect res

	
	

findLatestBuild = (app, branch, done) ->
	mongoFactory.db mongoUrl, (err, db) ->
		db.collection 'builds', (err, collection) ->
			q = 
				app: app
				branch: branch
			collection.find(q).sort(timestamp: -1).limit(1).toArray (err, results) ->
				[build] = results
				done build
					
saveInstance = (instance, done) ->
	mongoFactory.db mongoUrl, (err, db) ->
		db.collection 'instances', (err, collection) ->
			collection.insert instance, done


startProcesses = (build, processes, rendezvous, done) ->
	util.log util.inspect build
	async.forEach processes, ((item, done) ->
		opts = 
			slug: build.slug
			cmd: item.cmd
			name: "#{build.app}/#{build.branch}"
			worker: item.name
			logName: "#{build.app}/#{build.branch}"
			logApp: item.name
			rendezvous: rendezvous
			
		igthorn.start opts, (r) ->
						
			util.log util.inspect r
			item.result = r
			done()
			util.log util.inspect build
						
			o = 
				dynoData: r
				buildId: build._id
				app: build.app
				branch: build.branch
				opts: opts 
				time: new Date
			saveInstance o

	), (err) ->
		done()

app.post '/apps/:app/:branch/ps', (req, res) ->
	buffer = ''
	req.on 'data', (data) ->
		buffer += data
	req.on 'end', () ->
		req.body = JSON.parse buffer
	
		app = req.params.app
		app = app + '.git' unless app.match /\.git/
		branch = req.params.branch 
	
		cmd = req.body.command

		findLatestBuild app, branch, (build) ->
		
			process = {name: "run-X", type: "run" , cmd: cmd}
			startProcesses build, [process], yes, () ->
				console.log '--d-d-d-d-d-d-d-d-d-d-d-d-d-d-dd--d'
				util.log util.inspect process
				res.json rendezvousURI: process.result.rendezvousURI

			
	

app.get '/apps/:app/:branch/ps/restart', (req, res) ->
	app = req.params.app
	app = app + '.git' unless app.match /\.git/
	branch = req.params.branch 
	
				
	findLatestBuild app, branch, (build) ->
		processes = []
		results = []
		## nastartovat nove procesy podle skalovaci tabulky a procfile
				
		for proc, data of build.procfile
			cmd = data.command
			cmd += " " + data.options.join ' ' if data.options
			## todo brat v potaz skalovani a pridelovani spravneho cisla
			## TODO pouze test
			for i in [1..2]
				processes.push {name: "#{proc}-#{i}", type: proc , cmd: cmd}

		startProcesses build, processes, no, () ->
			build.out = processes 
			console.log "#{app} started"
			## TODO ocheckovat jestli vsechno bezi
			## prepnout router
			servers = "\n"
			for state in processes
				ip = state.result.ip
				port = 5000
				servers += "\tserver #{ip}:#{port};\n"
					
			upstream = "#{branch}.#{app}".replace /\./g, ''
			cfg = """					
				upstream #{upstream} {
				   #{servers}
				}

				server {

				  listen 80;
				  server_name #{branch}.#{app}.nibbler.cz;
				  location / {
				    proxy_pass http://#{upstream};
				  }
				}
			"""
			nginx.writeConfig upstream, cfg
			nginx.reload (o) ->
				build.conf = cfg
				build.nginx = o
				res.json build
					
						
			## soft kill starejch
			## pockat jestli se neukonci
			## kill -9 starejch
					


app.get '/ps/start', (req, res) ->
	lxc = new Lxc

	lxc.on 'data', (data) ->
		util.log data

	lxc.on 'error', (data) ->
		util.log 'ERR: ' + data

	lxc.on 'exit', (code) ->
		util.log 'EXIT: ' + code

	lxc.setup dhcp.get(), (name) ->
		approot = "#{lxc.root}app"
		fs.mkdirSync approot

		file = req.query.slug
		env = JSON.parse req.query.env
		cmd = req.query.cmd
		console.log "tar -C #{approot}/ -xzf #{file}"
		for key, val of env
		    util.log key, val	
		    process.env[key] = val	

		process.env.FFF='joooooo'
		exec "tar -C #{approot}/ -xzf #{file}", (error, stdout, stderr) ->
			lxc.exec '/buildpacks/startup /app run ' + cmd, (exitCode) ->
				lxc.dispose () ->
			res.json
				pid: lxc.process.pid
				ip: dhcp.ip.join '.'
				name: lxc.name

app.listen 80
util.log 'server listening on 80'

