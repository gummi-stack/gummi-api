$.get('/apps/testing.git/master/ps').done (processes) ->
	# el = $('<table></table>')
	x = '<table>'
	
	for p in processes
		a = """
		<tr><td>#{p.app}</td><td>- #{p.branch}</td></tr>
		"""
		x += a
	x += '</table>'
	

	$('.hero-unit').html(x)

