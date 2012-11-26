module.exports = (req, res, next) ->
	req.headers.accept = 'application/json'

	authorization = req.headers.authorization

	if authorization 
		parts = authorization.split ' '

	
		if parts.length is 2
			scheme = parts[0]
			credentials = new Buffer(parts[1], 'base64').toString()
			index = credentials.indexOf ':'
	
			unless 'Basic' isnt scheme or index < 0
				user = credentials.slice(0, index)
				pass = credentials.slice(index + 1)
				req.token = pass

	next()
		