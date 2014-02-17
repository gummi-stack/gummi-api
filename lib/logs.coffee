request = require 'request'

module.exports = (esUrl) ->
	(options, callback) ->
		app = options.app
		worker = options.worker
		lines = options.lines

		esQuery =
			"query":
				"bool":
					"must": [
						{
							"range":
								"logs.gummi_output":
									"from": "1"
									"to": "2"
						}
					]
					"must_not": []
					"should": []
			"from": 0
			"size": lines
			"sort":[
				{
					"@timestamp":
						"reverse":false
				}
			]

		esQuery['query']['bool']['must'].push {term: {"logs.gummi_app.raw": app}}
		if worker
			esQuery['query']['bool']['must'].push {term: {"logs.gummi_worker": worker}}

		options =
			url: "#{esUrl}/_search"
			method: 'POST'
			body: JSON.stringify esQuery

		request options, (err, esRes, body) ->
			return callback err if err

			data = JSON.parse body
			return callback data.error if data.error

			result = data['hits']['hits'].map (doc) ->
				doc['_source']

			callback null, result
