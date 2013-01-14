fs = require 'fs'

randft = (from, to) -> Math.floor(Math.random()*(to-from+1)+from)

names = fs.readFileSync "#{__dirname}/nodenames.txt"
names = names.toString().trim().split "\n"

module.exports.get = () ->
	names[randft 0, names.length-1] + '-' + randft(100, 999)
	
	