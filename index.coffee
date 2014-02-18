(require 'cson-config').load()
colors        = require 'colors'
express       = require 'express'
util          = require 'util'
url           = require 'url'
net           = require 'net'

GLOBAL.config = process.config
config        = process.config
Drekmore      = require './lib/drekmore'
tokenParser   = require './lib/tokenParser'
Book          = require './lib/book'

require 'coffee-trace'
dm = new Drekmore(config)
book = new Book(config)

logstashUrl = url.parse config.logstash
logs = require('./lib/logs') config.elasticsearch

app = express()
app.use (req, res, next)->
	console.log "#{req.method} #{req.path}"
	next()
app.use express.urlencoded()
app.use express.json()
app.use express.logger()
#app.use express.bodyParser()

app.use express.static __dirname + "/public"
app.use tokenParser
app.use app.router
app.use (err, req, res, next) ->
	err = message: err  if typeof err is 'string'
	express.errorHandler()(err, req, res, next)



sanitizeApp = (app) ->
	app += '.git' unless app.match /\.git/
	app


###
List application processes

:app - application name
:branch - branch name
###
app.get '/apps/:app/:branch/ps', (req, res, next) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch
	dm.findInstances app, branch, (err, instances) ->
		return next err if err
		res.json instances


###
Stop all processes

:app - application name
:branch - branch name
###
app.get '/apps/:app/:branch/ps/stop', (req, res, next) ->
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
app.get '/apps/:app/:branch/ps/restart', (req, res, next) ->
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
app.post '/apps/:app/:branch/ps', (req, res, next) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch

	command = req.body.command
	userEnv = req.body.env

	dm.runProcessRendezvous app, branch, command, userEnv, (err, process) ->
		return next err if err
		res.json process



###
Get application scaling

:app - application name
:branch - branch
###
app.get '/apps/:app/:branch/ps/scale', (req, res, next) ->
	app = sanitizeApp req.params.app
	branch = req.params.branch

	dm.getConfig app, branch, (err, config) ->
		console.log arguments
		return next err if err
		br = config.branches[branch]
		res.json br.scale


###
Scale

:app - application name
:branch - branch
:scales - {"web": 2, "daemon": 4}
###
app.post '/apps/:app/:branch/ps/scale', (req, res, next) ->
	return next "Missing scales" unless req.body.scales?

	app = sanitizeApp req.params.app
	branch = req.params.branch
	scales = req.body.scales

	dm.setScaling app, branch, scales, (err, done) ->
		return next err if err
		res.json done


app.all '/git/:repo/*', (req, res, next) ->
	return next 'Unauthorized' if req.token isnt 'cM7I84LFT9s29u0tnxrvZaMze677ZE60'
	next()


###
Callback url for toadwart on successful build
Private! toadwart only
###
app.post '/git/:repo/done', (req, res, next) ->
	p = req.params
	b = req.body

	dm.saveBuild b, (data) ->
		data.status = 'ok'
		res.json data


###
Build revision from git
Private! githook only
###
app.post '/git/:repo/:branch/:rev', (req, res, next) ->
#app.get '/git/:repo/:branch/:rev', (req, res, next) ->
	p = req.params
	dm.buildStream req, p.repo, p.branch, p.rev, (err, build)->
		if err
			console.log err
			res.write "       Sorry, there is no Todie to serve, please try it again later...".yellow
			res.write "\n"
			res.end "94ed473f82c3d1791899c7a732fc8fd0_exit_404\n"
			return

		build.on 'data', (data) ->
			res.write data
		build.on 'end', (exitCode) ->
			exitCode = 1 unless exitCode
			res.end "94ed473f82c3d1791899c7a732fc8fd0_exit_#{exitCode}\n"
		build.on 'error', (error)->
			console.log "error: ",error
			res.write "Stoupa ECONNRESET\n"
			res.end "94ed473f82c3d1791899c7a732fc8fd0_exit_1\n"

		build.run()




###

###
app.get '/toadwart/register/:ip/:port', (req, res, next) ->
	p = req.params

	dm.registerToadwart p.ip, p.port, (err, done) ->
		return next err if err
		res.json done
app.get '/toadwart/unregister/:id', (req, res, next)->
	dm.unRegisterToadwart req.params.id, (err, done)->
		return next err if err
		res.json {done: yes}

app.get '/toadwarts', (req, res, next)->
	dm.getToadwartsStatus yes, (err, data)->
		return next err if err
		res.json data

app.get '/datacenters', (req, res, next)->
	res.json "mrdka": yes

app.get '/datacenter/register/:name', (req, res, next)->
	dm.registerDatacenter req.params.name, [], (err, done)->
		return next err if err
		res.json done

###
List all applications

###
app.get '/apps/', (req, res, next) ->
	dm.listApps (err, applications) ->
		return next err if err
		res.json applications


###
Get application logs

:app - application name
:branch - branch name
:worker - worker
###
app.get '/apps/:app/:branch/:worker/logs', (req, res, next) ->
	###
	app = sanitizeApp req.params.app
	branch = req.params.branch
	tail = req.query.tail

	start = new Date().getTime() * 1000
	util.log util.inspect tail


	# TODO test only
	book.getLogs app, branch, res
	###
	options =
		app: req.params.app
		worker: req.params.worker
		lines: req.query.n || 100

	logs options, (err, data) ->
		return next err if err
		result = data.map format
		res.end result.join('')

###
#Get application logs tail

:app - application name
:branch - branch name
:worker - worker
###
app.get '/apps/:app/:branch/:worker/tail', (req, res) ->
	app = req.params.app
	worker = req.params.worker
	util.log "Tail request start"

	interval = setInterval () ->
		# Send some data for keeping socket alive
		res.write new Buffer [0x00]
	, 30000

	res.on 'close', () ->
		clearInterval interval

	connected = no
	client = new net.Socket()
	client.connect logstashUrl.port, logstashUrl.hostname, ->
		connected = yes

		filter =
			filter:
				gummi_app: app
				gummi_worker: worker
		client.write JSON.stringify filter

	#TODO: json stream parse
	client.on 'data', (data) ->
		try
			msg = JSON.parse data.toString()
			res.write format msg
		catch err
			util.log 'Invalid data: ' + data

	client.on 'end', ->
		res.end()

	client.on 'error', (err) ->
		util.log util.inspect err
		res.end()

	req.on 'close', ->
		util.log "Tail request close"
		client.end() if connected

	req.on 'error', (err) ->
		util.log util.inspect err
		client.end() if connected


format = (msg) ->
	"#{msg['@timestamp']} #{msg['gummi_source'] || 'app'}[#{msg['gummi_worker']}]: #{msg['message']}\n"

app.listen config.port
util.log "server listening on #{config.port}"

