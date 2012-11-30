colors			= require 'colors'
express			= require 'express'
util			= require 'util'

GLOBAL.config	= require './config'
Drekmore		= require './lib/drekmore'
redis			= require('redis-url').connect()
tokenParser		= require './lib/tokenParser'

callsite = require('callsite')

require 'coffee-trace'
dm = new Drekmore


##### DEBUG ONLY
fn = util.inspect # colorized output :)
util.inspect = (a, b, c) -> fn a, no, 5, yes 
ul = util.log
util.log = (string) ->
	call = __stack[1]
	basename = call.getFileName().replace(process.cwd() + "/" , '')
	str = '[' + basename + ':' + call.getLineNumber() + ']'


	if process.stdout.getWindowSize
		[rowWidth] = process.stdout.getWindowSize()
		str = '\u001b[s' + # save current position
			'\u001b[' + rowWidth + 'D' + # move to the start of the line
			'\u001b[' + (rowWidth - str.length) + 'C' + # align right
			'\u001b[' + 90 + 'm' + str + '\u001b[39m' +
			'\u001b[u'; # restore current position
	
	if string and string.split
		lines = string.split "\n"
		lines[0] = lines[0] + str
		string = lines.join "\n" 
	ul string 
#####


app = express()
app.use express.bodyParser()

expressSwaggerDoc = require 'express-swagger-doc'
app.use expressSwaggerDoc(__filename, '/docs')
app.use express.static __dirname + "/public"	
app.use tokenParser	
app.use app.router
app.use express.errorHandler()	

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

	dm.stopApplication app, branch, () ->
	res.json 
		status: 'ok'
		message: 'Asi sem je zabil, ale nekontroloval jsem to'



###
Restart all processes

:app - application name
:branch - branch name
###
app.get '/apps/:app/:branch/ps/restart', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 

	dm.restart app, branch, (done) ->
		res.json 
			status: 'ok'
			message: 'Naplanovan restart'



###
Start new process

:app - application name
:branch - branch
###
app.post '/apps/:app/:branch/ps', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 

	command = req.body.command
	userEnv = req.body.env

	dm.runProcessRendezvous app, branch, command, userEnv, (process) ->
		res.json process
			
				
	
###
Get applicatio scaling

:app - application name
:branch - branch
###
app.get '/apps/:app/:branch/ps/scale', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 
	
	dm.getConfig app, branch, (config) ->
		br = config.branches[branch]
		res.json br.scale

			
###
Scale

:app - application name
:branch - branch
:scales - {"web": 2, "daemon": 4}
###
app.post '/apps/:app/:branch/ps/scale', (req, res) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch 
	scales = req.body.scales 
	
	dm.setScaling app, branch, scales, (done) ->
		res.json done


app.all '/git/:repo/*', (req, res, next) ->
	return next 'Unauthorized' if req.token isnt 'cM7I84LFT9s29u0tnxrvZaMze677ZE60'
	next()


###
Callback url for toadwart on successful build
Private! toadwart only
###
app.post '/git/:repo/done', (req, res) ->
	p = req.params
	b = req.body

	dm.saveBuild b, (data) ->
		data.status = 'ok'
		res.json data


###
Build revision from git
Private! githook only
###
app.get '/git/:repo/:branch/:rev', (req, res) ->
	p = req.params
	build = dm.buildStream p.repo, p.branch, p.rev
	
	build.on 'data', (data) ->
		res.write data

	build.on 'end', (exitCode) ->
		res.end "94ed473f82c3d1791899c7a732fc8fd0_exit_#{exitCode}\n"

	build.run()




###

###
app.get '/toadwart/register/:ip/:port', (req, res) ->
	p = req.params
	dm.registerToadwart p.ip, p.port, (done) ->
		res.json done



###
List all applications

###
app.get '/apps/', (req, res) ->
	dm.listApps (applications) ->
			res.json applications
	

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

