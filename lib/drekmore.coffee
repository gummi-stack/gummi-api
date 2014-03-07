async			= require 'async'
fs				= require 'fs'
mongoq			= require("mongoq")
EventEmitter	= require('events').EventEmitter
fs				= require 'fs'
util			= require 'util'
request			= require 'request'
colors = require 'colors'
# uuid			= require 'node-uuid'

nodename		= require './nodename'
Igthorn 		= require './igthorn'
Nginx			= require './nginx'
Book			= require './book'
debug = require('debug') 'drekmore'

db = mongoq config.mongoUrl
db.on 'error', (err) ->
	console.log 'mongo', err

igthorn = new Igthorn process.config, db #todo
nginx = new Nginx
book = new Book process.config #todo


class ToadwartPool
	constructor: ()->
		@toadwarts = []
		@notifications = {}

	updateToadwartOnlineStatus: (id, online, done) ->
		db.collection('toadwarts').update {id}, $set: {online}, done


	getPs: (done) ->
		db.collection('toadwarts').find().toArray (err, toadwarts) =>
			return done err if err

			toadwarts.forEach (toadwart) =>
				igthorn.status toadwart.ip, toadwart.port, (err, status) =>
					console.log "Invalid toadward ", toadwart unless toadwart.id

					if err
						if toadwart.online
							console.log "Stoupa #{toadwart.id} #{toadwart.name} asi down. #{err}".red

						if not toadwart.online? or toadwart.online
							@updateToadwartOnlineStatus toadwart.id, no, (err) ->
								console.log err if err

						return


					unless toadwart.online
						console.log "Stoupa #{toadwart.id} #{toadwart.name} up.".green

					if not toadwart.online? or not toadwart.online
						@updateToadwartOnlineStatus toadwart.id, yes, (err) ->
							console.log err if err

					delete @notifications[toadwart.id]

					done null, status


	getToadwarts: (checkStatus, done)->
		ret = []
		db.collection('toadwarts').find().toArray (err, toadwarts) =>
			return done err if err
			return done(null,toadwarts) unless checkStatus

			async.each toadwarts,(t,next)->
				igthorn.status t.ip, t.port, (err, status)->
					if err
						t.status = err
						return next()
					try
						s = JSON.parse status.body
					catch err
						t.status = err
						return next(err)
					t.status = s
					next(err)
			,(err)->
				done(err,toadwarts)


module.exports = class Drekmore
	constructor: ()->
		@ensureLock = {}

		setInterval @checkStatus, 2000
		@db = db

		@tp = new ToadwartPool

	getToadwartsStatus: (forceCheck, done)=>
		@tp.getToadwarts forceCheck, done

	matchPsTable: (status, done) =>

		toadwartId = status.id

		@db.collection('instances').find
			'dynoData.toadwartId': toadwartId
		.toArray (err, instances) =>
			return done err if err

			# zjistim upladle procesy
			# return done()
			crashedInstances = instances.filter (instance) =>
				for pid, process of status.processes
					if process.uuid is instance.dynoData.uuid
						process.found = yes
						return no
							# console.log instance
				console.log "Crashed #{instance.app}/#{instance.branch}".red
				yes

			#bezi tam neco navic ?
			for pid, process of status.processes
				unless process.found
					util.log "Zabijim sirotka".blue
					igthorn.softKill process, () ->


			# util.log util.inspect orphans


			@removeInstance instance for instance in crashedInstances

			done()


	checkStatus: () =>
		# util.log 'check...'

		@listApps (err, applications) =>
			return util.log err if err

			for application in applications
				# util.log util.inspect application
				for branch, data of application.branches
					@ensureInstances application.name, branch, (err) ->
						console.log "@ensureInstances", err if err


		@tp.getPs (err, status) =>
			return util.log err if err

			@matchPsTable status, (err) =>
				return util.log err if err

				# console.log 'Check done'


	listApps: (done) =>
		@db.collection('apps').find().toArray (err, apps) =>
			return done err if err

			@db.collection('instances').find().toArray (err, instances) ->
				return done err if err

				for instance in instances
					for app in apps
						if instance.app is app.name and app.branches[instance.branch]
							app.branches[instance.branch].ps ?= {}
							ps = app.branches[instance.branch].ps
							ps[instance.state] ?= {}
							ps[instance.state][instance.opts.type] ?= 0
							ps[instance.state][instance.opts.type]++
							# app.branches[instance.branch].ps = instance


				done null, apps


	getConfig: (app, branch, done) =>
		@db.collection('apps').findOne name: app, (err, application) =>

			# console.log 'zmonomdomsodmsd', arguments
			return done err if err


			# create new app
			application = name: app unless application


			application.branches = {} unless application.branches
			application.branches[branch] = {} unless application.branches[branch]
			binfo = application.branches[branch]
			binfo.scale = {} unless binfo.scale
			binfo.lastVersion ?= 0
			binfo.datacenter ?= 'dc-cechy' # default
			binfo.state ?= 'stopped'

			done null, application


	setScaling: (app, branch, scales, done) =>
		@getConfig app, branch, (err, application) =>
			return done err if err

			binfo = application.branches[branch]

			for type, count of scales
				binfo.scale[type] = count

			@db.collection('apps').save application, () =>
				# @scale app, branch, binfo.scale, done
				@ensureInstances app, branch, done


	restart: (app, branch, done) =>
		@getConfig app, branch, (err, application) =>
			return done err if err

			application.branches[branch].state = 'running'
			@db.collection('apps').save application, () =>
				# @ensureInstances app, branch, done

				@findInstances app, branch, (err, instances) =>
					return done err if err

					instancesToDepose = []

					for instance in instances

						if instance.state is 'running'
							instance.state = 'deposing'
							instancesToDepose.push instance

					async.forEach instancesToDepose, ((item, queryDone) =>
						@db.collection('instances').save item, queryDone
					), (err) =>
						return done err if err
						# vsechny instance jsou oznaceny jako deposed
						# necham nastartovat nove procesy
						@ensureInstances app, branch, done


	ensureInstances: (app, branch, done) =>
		hash = "#{app}/#{branch}"
		if @ensureLock[hash]
			# console.log "Zamknuto pro start: #{app} #{branch} retry: #{@ensureLock[hash]}".red
			return done()

		@ensureLock[hash] = 1

		console.log "Zamykam pro start #{app} #{branch}".yellow
		@getConfig app, branch, (err, application) =>
			return done err if err

			binfo = application.branches[branch]
			scales = binfo.scale

			@findInstances app, branch, (err, instances) =>
				return done err if err

				@findLatestBuild app, branch, (err, build) =>
					return done err if err

					# util.log util.inspect instances
					unless build
						console.log "Mazu zamek #{hash} 1".gree
						delete @ensureLock[hash]
						return done err: "No build found"

					toStart = []
					toKill = []

					unless binfo.state is 'stopped'
						# pripravim procesy pro sputeni
						# console.log "pripravim procesy pro sputeni"
						# console.log scales
						# console.log build
						for procType, procCnt of scales
							data = build.procfile?[procType]
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
						if type is 'run'  # ignore or cleanup
							if instance.state is 'deposing'
								toKill.push instance
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
								# util.log util.inspect toStart
								# console.log '>>>>>>>>>>>>>>>>>>>>>>>'

								datacenter = binfo.datacenter
								unless datacenter
									return cb null, []
								# util.log util.inspect toStart
								@assignProcessesByInstancesToToadwarts datacenter, toStart, instances, (err, processes) =>
									return cb err if err

									@startProcesses build, processes, no, (err, instances) =>
										# util.log util.inspect done
										cb err, instances
							else
								cb null, {}
						stopped: (cb) =>
							if toKill.length
								console.log '>>>KIKIKIKI>>>>>>>>>>>>>>>>>>>>'
								util.log util.inspect toKill
								console.log '>>>KIKIKIKI>>>>>>>>>>>>>>>>>>>>'

								@stopInstances toKill, (done) =>
									# util.log util.inspect done
									cb null, done
							else
								cb null, {}

					, (err, result) =>
						console.log "err1111", err if err
						console.log "Mazu zamek #{hash} 2".green

						delete @ensureLock[hash]

						if toStart.length or toKill.length
							# @updateRouting app, branch, () ->
							return done null, result
						else
							return done null, result


	assignProcessesByInstancesToToadwarts: (datacenter, processes, instances, done) ->
		@db.collection('datacenters').findOne name: datacenter, (err, dc) =>
			return done err if err
			return done "Datacenter #{datacenter} not found" unless dc


			@db.collection('toadwarts').find
				region:
					"$in": dc.regions
				online: yes
			.toArray (err, toadwarts) =>
				return done err if err
				return done "No toadie in datacenter:#{datacenter} found" unless toadwarts

				# console.log 'fjwiejfijfiojweoifjewiofjweoifjweiofjweiofjweoifjweio'
				# util.log util.inspect toadwarts
				map = {}
				for toadie in toadwarts
					map[toadie.region] ?=
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
					# console.log '000000000d-d-d-d--dd-d-', map
					unless map[region]
						return null
					for id, toadie of map[region].toadwarts
						if lastInstanceCount > toadie.instanceCount
							selectedToadwart = toadie
							lastInstanceCount = toadie.instanceCount
					selectedToadwart


				for process in processes
					updateMap()
					region = getFreeRegion()
					unless region
						return done "No free region"

					toadwart = getFreetoadwartFromRegion region
					unless toadwart
						return done "No online toadie in #{region}"

					toadwart.instanceCount++
					process?.toadwartIp = toadwart.ip
					process?.toadwartId = toadwart.id

				updateMap()


				done null, processes



	runProcessRendezvous: (app, branch, command, userEnv, done) =>
		@getConfig app, branch, (err, application) =>
			return done err if err

			@findInstances app, branch, (err, instances) =>
				return done err if err

				running = []
				for instance in instances
					continue unless instance.opts.type is 'run'  # todo hloupe cislovani
					running.push instance.opts.worker

				@findLatestBuild app, branch, (err, build) =>
					return done err if err

					return done 'Missing build' unless build

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
					process.env ?= {}
					console.log build
					# process.env.PATH = build.releaseData.config_vars.PATH
					console.log application
					# datacenter = application.branches[branch].datacenter
					@getConfig app, branch, (err, config) =>
						return done err if err
						console.log 'xxzxxeqweweqwe', config
						datacenter = config.branches[branch].datacenter
						# console.log 'xxxxxxx', datacenter
						@assignProcessesByInstancesToToadwarts datacenter, processes, instances, (err, processes) =>
							return done err if err
							console.log "PRORORORORORORROROROROROROROROROOR", processes
							# console.log arguments
							# console.log "D@# {E#@$@#$@#$@#}"
							# console.log build
							@startProcesses build, processes, yes, (err, processes) ->
								return done err if err
								console.log '-213-123-12-312-33-2-3-'.red, processes
								[process] = processes
								# process.result = result.dynoData.rendezvousURI
								if process.err
									return done process.err
								# util.log util.inspect process
								rendezvousURI = "tcp://#{process.dynoData?.toadwartIp}:#{process.dynoData.port}"
								console.log rendezvousURI
								done null, {rendezvousURI}


	findInstances: (app, branch, done) ->
		@db.collection('instances').find
			app: app
			branch: branch
		.toArray (err, results) ->
			done err, results


	saveInstance: (instance, done) ->
		@db.collection('instances').insert instance, done


	findLatestBuild: (app, branch, done) ->
		# debug "Find build for #{app} #{branch}"
		@getConfig app, branch, (err, application) =>
			return done err if err

			binfo = application.branches[branch]
			# util.log "Last #{app}/#{branch} version #{binfo.lastVersion}"
			return done() unless binfo.lastVersion
			# console.log 'binfo', binfo
			@db.collection('builds').find
				app: app
				branch: branch
				version: binfo.lastVersion
			.toArray (err, results) ->
				return done err if err
				# console.log arguments
				[build] = results
				# util.log "Last #{app}/#{branch} build #{build}"
				# util.log util.inspect build
				done null, build


	removeInstance: (instance, done) =>
		q = _id: instance._id
		# console.log 'mazu'
		# util.log util.inspect q
		@db.collection('instances').remove q, done


	stopApplication: (app, branch) =>
		@getConfig app, branch, (err, application) =>
			return util.log err if err

			application.branches[branch].state = 'stopped'
			@db.collection('apps').save application, () =>
				@findInstances app, branch, (err, instances) =>
					return util.log err if err

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
								# util.log util.inspect res
								if res.status is 'ok'
									@removeInstance instance, ->
										# util.log util.inspect arguments
								# util.log util.inspect res
						else # neprosel stoupou tak jen smazu
							@removeInstance instance, ->
								# util.log util.inspect arguments


		# TODO je treba cekat na killy ?
		#TODO routing delat a po smazani vsecho z monga
		# @updateRouting 'testing.git', 'master', ->
		# 	done('TODO nemam info o tom co sem zastavil')


	startProcesses: (build, processes, rendezvous, done) =>
		return done 'Missing build' unless build?
		# util.log util.inspect build

		instances = []


		async.forEach processes, ((item, done) =>
			# console.log "SSSSSSS"
			# console.log build
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
				hostname: nodename.get()


			opts.env ?= {}
			opts.env.PATH = build.releaseData?.config_vars?.PATH

			# util.log util.inspect opts
			instance =
				buildId: build._id
				app: build.app
				branch: build.branch
				opts: opts
				time: new Date

			# TODO ziskavat idcka najednou
			# book.getId build.app, build.branch, ':dyno', (err, dynouuid) =>
			# 	return done err if err

			# book.getId build.app, build.branch, opts.worker, (err, wuuid) =>
			# 	return done err if err

			opts.logUuid = "LOG-uuid"
			opts.dynoUuid = 'DYNO-ID'
			# util.log util.inspect opts

			igthorn.start opts, (err, r) =>
				util.log util.inspect arguments
				if err or r.error
					instance.state = 'failed'
					instance.err = err
					instance.err ?= r.error
				else
					instance.dynoData = r
					instance.state = 'running'
				# util.log util.inspect r
				# item.result = r
				# util.log util.inspect build

				@saveInstance instance, (err, results) ->
					return done err if err

					#todo handle error
					instances.push results[0]
					console.log "Changed state #{build.app}/#{build.branch} - #{instance.state}".green
					done()


		), (err) ->
			# console.log "----------3333333333333333333"
			done err, instances


	updateRouting: (app, branch, done) =>
		#TODO ocheckovat zda nove procesy bezi
		#
		# prehodit router
		# zabit stare

		@findInstances app, branch, (err, instances) =>
			# console.log 'XXXXXXXXXXXXXXXXXXXXXXXXXX'
			# console.log instances
			return done err if err
			done null, instances


			nodes = []

			for instance in instances
				continue unless instance.opts.type is 'web'
				continue unless instance.state is 'running'
				nodes.push instance.dynoData


			book.getId app, branch, ':routing', (err, bookId) ->
				return done err if err

				nginx.updateUpstream app, branch, nodes, bookId
				nginx.reload (o) ->
					done o


	buildStream: (req, repo, branch, rev, done) =>
		p =
			repo: repo
			branch: branch
			rev: rev
			# callbackUrl: "#{config.api.scheme}://:#{config.api.key}@#{config.api.host}/git/#{repo}/done"
			hostname: nodename.get()
		console.log "RRRR", repo
		igthorn.git req, p, done


	saveBuild: (buildData, done) =>
		@getConfig buildData.app, buildData.branch, (err, application) =>
			console.log "2@@@@@@@@@"
			console.log arguments
			return done err if err

			binfo = application.branches[buildData.branch]
			#neni to uplne atomicky....
			binfo.lastVersion++
			buildData.version = binfo.lastVersion
			console.log application
			@db.collection('builds').save buildData, () =>
				@db.collection('apps').update {name: application.name}, application, upsert: yes, () =>
					console.log arguments
					done null, version: binfo.lastVersion


	registerToadwart: (ip, port, done) =>
		console.log " registering http://#{ip}:#{port}/ps/status"
		request.get "http://#{ip}:#{port}/ps/status", (error, response, body) =>
			return done error if error

			try
				info = JSON.parse body
			catch err
				return done err

			@db.collection('toadwarts').find
				id: info.id
			.toArray (err, results) =>
				return done err if err

				[data] = results
				data ?= {}

				data.id = info.id
				data.name = info.name
				data.ip = ip
				data.port = port

				@db.collection('toadwarts').save data, (err) ->
					done null, data


	unRegisterToadwart: (id, done) =>
		@db.collection('toadwarts').remove {id: id}, done


	registerDatacenter: (name, regions, done)=>
		@db.collection("datacenters").find
			name: name
		.toArray (err, dc)->
			return done err if err

			[data] = dc
			data ?= {}

			data.regions = regions
			@db.collection('datacenters').save data, (err)->
				done err, data


	getReleases: (app, branch, release, done) =>
		q =
			app: app
			branch: branch

		q.rev = release if release

		@db.collection('builds').find(q).sort(version: -1).limit(10)
		.toArray (err, builds) ->
			return done err if err

			done null, builds





