async			= require 'async'
fs				= require 'fs'
redis			= require('redis-url').connect()
mongoq			= require("mongoq");
# mongoFactory	= require 'mongo-connection-factory'
# ObjectID		= require('mongodb').ObjectID
fs				= require 'fs'
util			= require 'util'
#http			= require 'http'
#{spawn, exec}	= require 'child_process'

Igthorn 		= require './igthorn'
Nginx			= require './nginx'

igthorn = new Igthorn
nginx = new Nginx


class Applications
	constructor: ->
		@db = mongoq config.mongoUrl
	

module.exports = class Drekmore
	constructor: ->
		@db = mongoq config.mongoUrl
		
	
	scale: (app, branch, scales, done) =>
		#todo ulozit scales
		@db.collection('apps').find(app: app).toArray (err, results) ->
			[app] = results
			done app
		
		
		
		
		
		
	# setuptoad
	runProcessRendezvous: (app, branch, command, done) =>
		@findLatestBuild app, branch, (build) =>
			# todo co kdyz neni build
			util.log app, branch
			util.log util.inspect build
			process = 
				name: "run-X"
				type: "run"
				cmd: command
			
			@startProcesses build, [process], yes, () ->
				util.log util.inspect process
				done process # rendezvousURI: process.result.rendezvousURI

		
	findInstances: (app, branch, done) ->
		@db.collection('instances').find
			app: app
			branch: branch
		.toArray (err, results) ->
			done results

					
	saveInstance: (instance, done) ->
		@db.collection('instances').insert instance, done


	findLatestBuild: (app, branch, done) ->
		@db.collection('builds').find
			app: app
			branch: branch
		.sort(timestamp: -1).limit(1).toArray (err, results) ->
			[build] = results
			done build
	
	
	removeInstance: (instance, done) =>
		q = _id: instance._id
		console.log 'mazu'
		util.log util.inspect q
		@db.collection('instances').remove q, done
		
		
	stopInstances: (instances, done) =>
		for instance in instances
			o = 	
				name: instance.dynoData.name
				pid: instance.dynoData.pid
			do(instance) =>
				util.log util.inspect instance
				igthorn.softKill o, (res) =>
							
					if res.status is 'ok'
						
						
						@removeInstance instance, ->
							util.log util.inspect arguments
					util.log util.inspect res
	
		# TODO je treba cekat na killy ?
		#TODO routing delat a po smazani vsecho z monga
		@updateRouting 'testing.git', 'master', ->
			done()
	

	startProcesses: (build, processes, rendezvous, done) =>
		util.log util.inspect build
		
		instances = []
		
		async.forEach processes, ((item, done) =>
			opts = 
				slug: build.slug
				cmd: item.cmd
				name: "#{build.app}/#{build.branch}"
				worker: item.name
				logName: "#{build.app}/#{build.branch}"
				logApp: item.name
				type: item.type
				rendezvous: rendezvous
			
			igthorn.start opts, (r) =>
						
				util.log util.inspect r
				item.result = r
				util.log util.inspect build
						
				o = 
					dynoData: r
					buildId: build._id
					app: build.app
					branch: build.branch
					opts: opts 
					time: new Date
				@saveInstance o, (err, results) ->
					#todo handle error
					instances.push results[0]
					done()
					

		), (err) ->
			done instances

	updateRouting: (app, branch, done) =>
		#TODO ocheckovat zda nove procesy bezi
		# 
		# prehodit router
		# zabit stare
		
		@findInstances app, branch, (instances) =>
			console.log 'XXXXXXXXXXXXXXXXXXXXXXXXXX'
			console.log instances
			done instances
			

			nodes = []

			for instance in instances
				continue unless instance.opts.type is 'web'
				nodes.push instance.dynoData
		
			
			
			# nodes = []
			# for state in processes
			# 	nodes.push
			# 		ip: state.result.ip
			# 		port: 5000
			# 	
			nginx.updateUpstream app, branch, nodes
			nginx.reload (o) ->
				done o
			# 		
			# 		
		
	restartProcesses: (app, branch, done) =>
		@findLatestBuild app, branch, (build) =>
			processes = []
			results = []
			## nastartovat nove procesy podle skalovaci tabulky a procfile
			@findInstances app, branch, (instances) =>
				util.log 'xxxxIIIIII'
				util.log util.inspect instances	
				for proc, data of build.procfile
					cmd = data.command
					cmd += " " + data.options.join ' ' if data.options
					## todo brat v potaz skalovani a pridelovani spravneho cisla
					## TODO pouze test
					for i in [1..2]
						processes.push {name: "#{proc}-#{i}", type: proc , cmd: cmd}

				@startProcesses build, processes, no, (newInstances) =>
					build.out = processes 
					
					@updateRouting app, branch, () =>
						done 
					
					
					
					
						
					## soft kill starejch
					## pockat jestli se neukonci
					## kill -9 starejch
					
		
	