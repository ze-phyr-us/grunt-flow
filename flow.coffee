_ = require 'lodash'



class File
	constructor: (@path, @original = null) ->
		@original ?= @path


class MergedFile extends File


class TemporaryFile extends File




class Node
	evaluation: null
	getOutput: () -> []
	evaluate: (inputNode, outputNode) -> []



class EvaluatedNodeData
	constructor: (@nodeName, @data) ->

	hasData: () -> @data.src.length and @data.dest.length

	generateConfig: () ->
		if @hasData()
			embed = (hash, ks, data) ->
				if ks[1] then (embed (hash[ks[0]] = {}), ks[1..], data) else hash[ks[0]] = data
				hash

			config =
				files:
					if @data.dest.length is 1
						[ {src: (file.path for file in @data.src), dest: @data.dest[0].path} ]
					else
						{src: src.path, dest: dest.path} for [src, dest] in _.zip @data.src, @data.dest

			embed {}, (@nodeName.split ':'), config



class Merger extends Node
	constructor: (@nodes) ->

	evaluate: (inputNode, outputNode) ->
		@evaluation = []
		for node in @nodes
			@evaluation.push.apply @evaluation, node.evaluate inputNode, outputNode # FIXME Writer will not work well with Merger
		@evaluation

	getOutput: () ->
		_.flatten (node.getOutput() for node in @nodes), true



class Chain extends Node
	constructor: (@nodes) ->

	evaluate: (inputNode, outputNode) ->
		partitions = _.zip ([inputNode].concat _.initial @nodes), @nodes, (_.tail(@nodes).concat [outputNode])
		@evaluation = _.flatten (node.evaluate prev, next for [prev, node, next] in partitions), true

	getOutput: () ->
		(_.last @nodes).getOutput()



class Reader extends Node
	constructor: (paths) ->
		@input = ((new File path) for path in paths)

	getOutput: () -> @input

	evaluate: (inputNode, outputNode) ->
		@evaluation = [ new EvaluatedNodeData @name, {src: [], dest: (file for file in @input)} ]



class Writer extends Node
	constructor: (@outputPaths) ->

	getFinalOutput: (input) ->
		if @outputPaths.length not in [1, input.length]
			throw "Writer input has #{input.length} nodes but is configured to output #{@outputPaths.length}."

		if @outputPaths.length is 1
			[ new MergedFile @outputPaths[0], input ]
		else
			(new File output, input) for [output, input] in _.zip @outputPaths, input



class Task extends Node
	constructor: (@name) ->

	getTemporaryFiles: (inputFiles) ->
		(new TemporaryFile input.path + '.tmp', input) for input in inputFiles

	evaluate: (inputNode, outputNode) ->
		input = inputNode.getOutput()
		@output = if outputNode.constructor is Writer then outputNode.getFinalOutput input else @getTemporaryFiles input
		@evaluation = if input and @output then [ new EvaluatedNodeData @name, {src: input, dest: @output} ] else []

	getOutput: () ->
		@output



# Helper function that lets us call a function with either an array of arguments or a variable number of arguments.
splatOrFlat = (splat) -> if (splat.length is 1 and splat[0] instanceof Array) then splat[0] else splat






###
Exports: shortcuts and config merger
###

module.exports =
	chain: (nodes...) -> new Chain splatOrFlat nodes
	read: (paths...) -> new Reader splatOrFlat paths
	task: (name) -> new Task name
	write: (paths...) -> new Writer splatOrFlat paths
	merge: (flows...) -> new Merger splatOrFlat flows

	addPaths: (nodes, config) ->
		merged = {}
		concat = (a, b) -> if _.isArray a then a.concat b else undefined

		for node in nodes
			nodeData = node.evaluate()
			for d in nodeData
				part = d.generateConfig()
				if part
					merged = _.merge merged, part, concat

		merged = _.merge merged, config, concat
