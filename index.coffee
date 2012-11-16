colors			= require 'colors'
express			= require 'express'
util			= require 'util'

GLOBAL.config	= require './config'
Drekmore		= require './lib/drekmore'


require 'coffee-trace'
dm = new Drekmore

fn = util.inspect # colorized output :)
util.inspect = (a, b, c) -> fn a, b, c, yes 

	

app = express()
expressSwaggerDoc = require 'express-swagger-doc'
app.use expressSwaggerDoc(__filename, '/docs')

app.use express.static __dirname + "/public"	

sanitizeApp = (app) -> 
	app += '.git' unless app.match /\.git/
	app

### 
Testovaci metoda
###
app.get '/toadwart/add/:ip/:port', (req, res) ->
	db.setupToadwart req.params.ip, req.params.port
	
	

### 
List application processes

:app - application name
:branch - branch name
###
app.get '/apps/:app/:branch/ps', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 
	dm.findInstances app, branch, (instances) ->
		res.json instances


###
Stop all processes

:app - application name
:branch - branch name
###
app.get '/apps/:app/:branch/ps/stop', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 

	dm.findInstances app, branch, (instances) ->
		dm.stopInstances instances, () ->
			res.json 
				status: 'ok'
				message: 'Asi sem je zabil, ale nekontroloval jsem to'


###
Start new process

:app - application name
:branch - branch
###
app.post '/apps/:app/:branch/ps', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 

	buffer = ''
	req.on 'data', (data) ->
		buffer += data
	req.on 'end', () ->
		req.body = JSON.parse buffer
		command = req.body.command

		dm.runProcessRendezvous app, branch, command, (process) ->
			res.json rendezvousURI: process.result.rendezvousURI
			
		
###
Start new process

:app - application name
:branch - branch
###
app.post '/apps/:app/:branch/ps', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 

	buffer = ''
	req.on 'data', (data) ->
		buffer += data
	req.on 'end', () ->
		req.body = JSON.parse buffer
		command = req.body.command

		dm.runProcessRendezvous app, branch, command, (process) ->
			res.json rendezvousURI: process.result.rendezvousURI
				
	
###
Scale

:app - application name
:branch - branch
:scales - {"web": 2, "daemon": 4}
###
app.get '/apps/:app/:branch/ps/scale', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 
	
	dm.scale app, branch, scales, (done) ->
		res.json done
			


###
Get application logs 

:app - application name
:branch - branch name
:tail - bool - enable live tailing
###
app.get '/apps/:app/:branch/logs', (req, res) ->
	app = sanitizeApp req.params.app
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
			

app.listen config.port
util.log "server listening on #{config.port}"

