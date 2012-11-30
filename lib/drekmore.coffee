async			= require 'async'
fs				= require 'fs'
redis			= require('redis-url').connect()
mongoq			= require("mongoq")
EventEmitter	= require('events').EventEmitter
fs				= require 'fs'
util			= require 'util'
request			= require 'request'
# uuid			= require 'node-uuid'

Igthorn 		= require './igthorn'
Nginx			= require './nginx'


db = mongoq config.mongoUrl

igthorn = new Igthorn db
nginx = new Nginx


class ToadwartPool
	constructor: ->
		@toadwarts = []
		
	
	getPs: (done) ->
		db.collection('toadwarts').find().toArray (err, toadwarts) =>
			for toadwart in toadwarts
				igthorn.status toadwart.ip, toadwart.port, (err, status) ->
					if err
						return util.log "Stoupa #{toadwart.id}  #{toadwart.name} asi down"
				
					done status


module.exports = class Drekmore
	constructor: ->
		@db = db
		
		setInterval @checkStatus, 2000
		
		
		@tp = new ToadwartPool
		
	
	matchPsTable: (status, done) =>
		toadwartId = status.id
		
		@db.collection('instances').find
			'dynoData.toadwartId': toadwartId
		.toArray (err, instances) =>
			# zjistim upladle procesy
			instances = instances.filter (instance) =>
				for pid, process of status.processes
					return no if process.uuid is instance.dynoData.uuid
				yes
			
			@removeInstance instance for instance in instances
			
			done()
		
	
	checkStatus: () =>
		# util.log 'check...'

		@listApps (applications) =>
			for application in applications
				# util.log util.inspect application
				for branch, data of application.branches
					@ensureInstances application.name, branch, () ->
						# util.log util.inspect arguments
			
		
		@tp.getPs (status) =>
			@matchPsTable status, () =>
				# console.log 'Check done'
		
	
	listApps: (done) =>
		@db.collection('apps').find().toArray (err, results) =>
			done results
		
	getConfig: (app, branch, done) =>
		@db.collection('apps').find(name: app).toArray (err, results) =>
			[application] = results

			application.branches = {} unless application.branches
			application.branches[branch] = {} unless application.branches[branch]
			binfo = application.branches[branch]
			binfo.scale = {} unless binfo.scale 
			binfo.lastVersion ?= 0

			done application

	setScaling: (app, branch, scales, done) =>
		@getConfig app, branch, (application) =>
			binfo = application.branches[branch]

			for type, count of scales
				binfo.scale[type] = count

			@db.collection('apps').save application, () =>
				# @scale app, branch, binfo.scale, done
				@ensureInstances app, branch, done
				
	restart: (app, branch, done) =>
		@getConfig app, branch, (application) =>
			application.branches[branch].state = 'running'
			@db.collection('apps').save application, () =>
				# @ensureInstances app, branch, done
		
				@findInstances app, branch, (instances) =>
					instancesToDepose = []
							
					for instance in instances
				
						if instance.state is 'running'
							instance.state = 'deposing'
							instancesToDepose.push instance
						
					async.forEach instancesToDepose, ((item, queryDone) =>
						@db.collection('instances').save item, queryDone
					), (err) =>
						# vsechny instance jsou oznaceny jako deposed
						# necham nastartovat nove procesy
						@ensureInstances app, branch, done
			 
		
	ensureInstances: (app, branch, done) =>
		@getConfig app, branch, (application) =>
			binfo = application.branches[branch]
			scales = binfo.scale
			
			@findInstances app, branch, (instances) =>
				@findLatestBuild app, branch, (build) =>
					# util.log util.inspect instances
					return done err: "No build found" unless build
					
					toStart = []
					toKill = []
					
					unless binfo.state is 'stopped'
						# pripravim procesy pro sputeni
						for procType, procCnt of scales
							data = build.procfile[procType]
							continue unless data
							cmd = data.command
							cmd += " " + data.options.join ' ' if data.options
							for i in [0...procCnt]
								toStart.push
									name: "#{procType}-#{i}"
									type: procType
									cmd: cmd
									env: application.env  # todo pripadne opadtchovat branch konfiguraci
						
					for instance in instances
						# odectu od nich jiz bezici
						toStart = toStart.filter (current) =>
							if current.name isnt instance.opts.worker
								return yes
							else if instance.state is 'deposing'
								return yes
							else if instance.state is 'failed'
								@removeInstance instance
								return yes
							return no
				
						# ty co nemaj bezet 
						# todo opravit skalovani kdyz bash
						[_, type, id] = instance.opts.worker.match /(.*)-(\d+)/
						id = parseInt id
						if type is 'run'  # ignore
							continue
						unless scales[type] > id
							toKill.push instance 
						else if instance.state is 'deposing' 
							for instance2 in instances
								# and existuje running nahrada
								if instance2.opts.worker is instance.opts.worker and instance2.state is 'running'
									toKill.push instance
				
				
					async.parallel 
						started: (cb) =>
							if toStart.length
								datacenter = binfo.datacenter
								# util.log util.inspect toStart
								@assignProcessesByInstancesToToadwarts datacenter, toStart, instances, (processes) =>
									@startProcesses build, processes, no , (done) =>	
										util.log util.inspect done
										cb null, done
							else
								cb null, {}
						stopped: (cb) =>
							if toKill.length
								@stopInstances toKill, (done) =>	
									util.log util.inspect done
									cb null, done
							else
								cb null, {}
					
					, (err, result) =>
						@updateRouting app, branch, () ->
							done result
	
	
	assignProcessesByInstancesToToadwarts: (datacenter, processes, instances, done) ->
		@db.collection('datacenters').find
			name: datacenter
		.toArray (err, results) =>
			[dc] = results

			@db.collection('toadwarts').find
				region: 
					"$in": dc.regions
			.toArray (err, toadwarts) =>
				map = {}
				for toadie in toadwarts
					# util.log toadie
					map[toadie.region] = 
						instanceCount: 0
						toadwarts: {}
						
					map[toadie.region].toadwarts[toadie.id] = toadie
					toadie.instanceCount = 0
					
				
				for instance in instances
					continue unless instance.state is 'running'
					
					for toadie in toadwarts
						toadie.instanceCount++ if toadie.id is instance.dynoData.toadwartId
				
				updateMap = () ->
					for regionName, regionData of map
						 # util.log regionData.instanceCount
						 regionData.instanceCount = 0
						 for toadieId, toadie of regionData.toadwarts
							 regionData.instanceCount += toadie.instanceCount
				
				
				getFreeRegion = () ->		 
					lastInstanceCount = 999999 # todo
					selectedRegion = null
					for regionName, regionData of map					
						if lastInstanceCount > regionData.instanceCount
							selectedRegion = regionName
							lastInstanceCount = regionData.instanceCount
							
					selectedRegion
				
				getFreetoadwartFromRegion = (region) ->
					lastInstanceCount = 999999 # todo
					selectedToadwart = null
					
					for id, toadie of map[region].toadwarts
						if lastInstanceCount > toadie.instanceCount
							selectedToadwart = toadie
							lastInstanceCount = toadie.instanceCount
					selectedToadwart 
						
				
				for process in processes
					updateMap()
					region = getFreeRegion()
					toadwart = getFreetoadwartFromRegion region
					toadwart.instanceCount++
					process.toadwartId = toadwart.id
					
				updateMap()
					
				
				
					 # util.log regionData.instanceCount
				
				
				util.log '-----------------------------------------------------------------------------'
				util.log util.inspect map
				util.log '-----------------------------------------------------------------------------'
				# util.log util.inspect region
				# util.log util.inspect toadwart  
				util.log util.inspect processes  
				util.log '-----------------------------------------------------------------------------'
				# throw new Error 'xxx'
		
				done processes 
		
	
					
	runProcessRendezvous: (app, branch, command, userEnv, done) =>
		@getConfig app, branch, (application) =>
		
			@findInstances app, branch, (instances) =>
				running = []
				for instance in instances
					continue unless instance.opts.type is 'run'  # todo hloupe cislovani
					running.push instance.opts.worker

				@findLatestBuild app, branch, (build) =>
					# todo co kdyz neni build
					util.log app, branch
					util.log util.inspect build
					process = 
						name: "run-" + running.length
						type: "run"
						cmd: command
						env: application.env # todo pripadne opatchovat branchi
						userEnv: userEnv 
					processes = [process]
					
					datacenter = application.branches[branch].datacenter
					
					@assignProcessesByInstancesToToadwarts datacenter, processes, instances, (processes) =>
						@startProcesses build, processes, yes, (results) ->
							[result] = results
							# process.result = result.dynoData.rendezvousURI
							# util.log util.inspect process
							done rendezvousURI: result.dynoData.rendezvousURI

		
	findInstances: (app, branch, done) ->
		@db.collection('instances').find
			app: app
			branch: branch
		.toArray (err, results) ->
			done results

					
	saveInstance: (instance, done) ->
		@db.collection('instances').insert instance, done


	findLatestBuild: (app, branch, done) ->
		@getConfig app, branch, (application) =>
			binfo = application.branches[branch]
			util.log "Last #{app}/#{branch} version #{binfo.lastVersion}"
			return done null unless binfo.lastVersion
			
			@db.collection('builds').find
				app: app
				branch: branch
				version: binfo.lastVersion
			.toArray (err, results) ->
				[build] = results
				util.log "Last #{app}/#{branch} build #{build}"
				# util.log util.inspect build
				done build
	
	
	removeInstance: (instance, done) =>
		q = _id: instance._id
		console.log 'mazu'
		util.log util.inspect q
		@db.collection('instances').remove q, done
		
	
	stopApplication: (app, branch) =>
		@getConfig app, branch, (application) =>
			application.branches[branch].state = 'stopped'
			@db.collection('apps').save application, () =>
				@findInstances app, branch, (instances) =>
					@stopInstances instances, () =>
		
			
	stopInstances: (instances, done) =>
		for instance in instances
			do(instance) =>
				instance.state = 'stopping'
				
				@db.collection('instances').save instance, () =>
					
					# util.log util.inspect instance
					if instance.status is 'failed'
						@removeInstance instance, ->
					else
						if instance.dynoData  # byl spusten na stoupovi
							igthorn.softKill instance.dynoData, (err, res) =>
								return util.log 'Nepovedlo se zastavit process' if err		
								# console.log 'rrrrrrrrrrrrrrrrrrrrrrrrrr'
								util.log util.inspect err
								util.log util.inspect res
								if res.status is 'ok'
									@removeInstance instance, ->
										util.log util.inspect arguments
								util.log util.inspect res
						else # neprosel stoupou tak jen smazu 
							@removeInstance instance, ->
								util.log util.inspect arguments
						
	
		# TODO je treba cekat na killy ?
		#TODO routing delat a po smazani vsecho z monga
		@updateRouting 'testing.git', 'master', ->
			done('TODO nemam info o tom co sem zastavil')
	

	startProcesses: (build, processes, rendezvous, done) =>
		# util.log util.inspect build
		
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
				env: item.env
				userEnv: item.userEnv
				toadwartId: item.toadwartId

			# util.log util.inspect opts
			instance = 
				buildId: build._id
				app: build.app
				branch: build.branch
				opts: opts 
				time: new Date

				
			igthorn.start opts, (err, r) =>
				if err
					instance.state = 'failed'
					instance.err = err
				else
					instance.dynoData = r		
					instance.state = 'running'
				# util.log util.inspect r
				# item.result = r
				# util.log util.inspect build
						
				@saveInstance instance, (err, results) ->
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
			# console.log 'XXXXXXXXXXXXXXXXXXXXXXXXXX'
			# console.log instances
			done instances
			

			nodes = []

			for instance in instances
				continue unless instance.opts.type is 'web'
				continue unless instance.state is 'running'
				nodes.push instance.dynoData

			nginx.updateUpstream app, branch, nodes
			nginx.reload (o) ->
				done o


	buildStream: (repo, branch, rev) =>
		em = new EventEmitter
		em.run = () ->
			p = 
				repo: repo
				branch: branch
				rev: rev
				callbackUrl: "http://:cM7I84LFT9s29u0tnxrvZaMze677ZE60@api.nibbler.cz/git/#{repo}/done" # todo do configu

			igthorn.git p, (res) =>
				res.on 'data', (data) =>
					em.emit 'data', data
				res.on 'end', (data) =>
					em.emit 'end', data
		
		return em
	
	saveBuild: (buildData, done) =>
		@getConfig buildData.app, buildData.branch, (application) =>
			binfo = application.branches[buildData.branch]
			
			binfo.lastVersion++
			buildData.version = binfo.lastVersion

			@db.collection('builds').save buildData, () =>
				@db.collection('apps').save application, () =>
					done
						version: binfo.lastVersion

	registerToadwart: (ip, port, done) =>
		request.get "http://#{ip}:#{port}/ps/status", (error, response, body) =>
			info = JSON.parse body
			
			@db.collection('toadwarts').find
				id: info.id
			.toArray (err, results) =>
				[data] = results
				data ?= {}
				
				data.id = info.id
				data.name = info.name
				data.ip = info.ip
				data.port = info.port
					
				@db.collection('toadwarts').save data, () ->
					done data
					
			
		
		
		
