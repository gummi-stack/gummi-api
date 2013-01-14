timer = null

listApps = () ->
	clearTimeout timer?
	
	$.get('/apps/').done (processes) ->
		# el = $('<table></table>')
		x = '<table>'
		#  <small><a href="#">show details</a></small><hr>
		for p in processes
			w = JSON.stringify p, no, "\t"
			o = ""
			for branch, binfo of p.branches
				# binfo.state
				scales = ""
				for name, cnt of binfo.scale
					running = binfo.ps?.running?[name]
					running ?= 0
					type = 'info'
					type = 'important' if cnt > running
						
					scales += """<small> #{name} <span class="label label-#{type} ">#{running}/#{cnt}</span></small>"""
				l = """
				<tr>
				<td style="width:100px">
				<div class="btn-group " >
					 <div class="btn btn-mini btn-success restart" data="#{p.name}/#{branch}">restart</div> 
					 <div class="btn btn-mini btn-danger stop #{'disabled' if binfo.state is 'stopped'}" data="#{p.name}/#{branch}">stop</div>
						 </div>
				</td>
				<td>
						  #{branch}</td><td><span class="label">#{binfo.state}</span></td>
				</td>
				<td style="padding: 0 10px">
				 #{scales}
				</td>
				<td>
				 #{binfo.datacenter}
				</td>
				<td>
				 v#{binfo.lastVersion}
				</td>
				
				</tr>
						  """
				
				
				o += l
			
			a = """
			<tr><td colspan=6><a href="#app/#{p.name}">#{p.name}</a></td></tr>
			<tr><td colspan=6 ><pre style="display:none" >#{w}</pre></td>
			#{o}
			
			
			"""
			x += a
		x += '</table>'

		$('.hero-unit').html(x)
		$('.btn.stop').click (e)->
			clearTimeout timer?
			data = $(e.target).attr('data')
			$.get("apps/#{data}/ps/stop").done ->
				listApps()
				
		$('.btn.restart').click (e)->
			clearTimeout timer?
			data = $(e.target).attr('data')
			$.get("apps/#{data}/ps/restart").done ->
				listApps()
		
		clearTimeout timer?
		console.log 'set'
		timer = setTimeout listApps, 1000

showApp = (app) ->
	$.get("/apps/#{app}/master/ps").done (processes) ->
		# el = $('<table></table>')
		x = '<table>'
	
		for p in processes
			w = JSON.stringify p, no, "\t"
			a = """
			<tr><td>#{p.app}</td><td>- #{p.branch}</td></tr>
			<tr><td colspan=2><pre style="font-size: 50%;">#{w}</pre></td>
			</tr>
			"""
			x += a
		x += '</table>'
	

		$('.hero-unit').html(x)
# 


$ () ->
	$(window).hashchange () ->
		hash = location.hash 
		# return unless hash
		hash = hash.substr 1

		if timer
			clearTimeout timer 
		
		if m = hash.match /app\/(.*)/
			return showApp m[1]

		listApps()

	$(window).hashchange()

