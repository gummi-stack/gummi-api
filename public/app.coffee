
listApps = () ->
	$.get('/apps/').done (processes) ->
		# el = $('<table></table>')
		x = '<table>'
	
		for p in processes
			w = JSON.stringify p, no, "\t"
			a = """
			<tr><td><a href="#app/#{p.name}">#{p.name}</td></tr>
			<tr><td colspan=1><pre>#{w}</pre></td>
			</tr>
			"""
			x += a
		x += '</table>'

		$('.hero-unit').html(x)


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
		
		if m = hash.match /app\/(.*)/
			return showApp m[1]

		listApps()

	$(window).hashchange()

