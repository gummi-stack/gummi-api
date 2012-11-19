$.get('/apps/testing.git/master/ps').done (processes) ->
	# el = $('<table></table>')
	x = '<table>'
	
	for p in processes
		w = JSON.stringify p, no, "\t"
		a = """
		<tr><td>#{p.app}</td><td>- #{p.branch}</td></tr>
		<tr><td colspan=2><pre>#{w}</pre></td>
		</tr>
		"""
		x += a
	x += '</table>'
	

	$('.hero-unit').html(x)

