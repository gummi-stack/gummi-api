(require 'cson-config').load()
colors			= require 'colors'
express			= require 'express'
util			= require 'util'

GLOBAL.config	= process.config
config	= process.config
Drekmore		= require './lib/drekmore'
tokenParser		= require './lib/tokenParser'
Book		= require './lib/book'

require 'coffee-trace'
dm = new Drekmore(config)
book = new Book(config)


app = express()
app.use (req, res, next)->
	console.log req.method
	console.log req.path
	next()
app.use express.urlencoded()
app.use express.json()
app.use express.logger()
#app.use express.bodyParser()

app.use express.static __dirname + "/public"
app.use tokenParser
app.use app.router
app.use express.errorHandler()



sanitizeApp = (app) ->
	app += '.git' unless app.match /\.git/
	app


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
Get application scaling

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
	build.on 'error', (error)->
		console.log "error: ",error
	build.run()




###

###
app.get '/toadwart/register/:ip/:port', (req, res) ->
	p = req.params

	dm.registerToadwart p.ip, p.port, (err, done) ->
		res.json {error: err, data: done}



app.get '/datacenters', (req, res)->
	res.json "mrdka": yes

app.get '/datacenter/register/:name', (req, res)->
	dm.registerDatacenter req.params.name, [], (err, done)->
		res.json {error: err, data: done}

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


	# TODO test only
	book.getLogs app, branch, res


app.listen config.port
util.log "server listening on #{config.port}"

