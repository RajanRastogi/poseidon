esprima = require 'esprima'
escodegen = require 'escodegen'
Promise = require 'bluebird'
fs = require 'fs'

class Poseidon

  @Promise: Promise

  constructor:(configuration = {}) ->
    @configuration = configuration
    return

  generate: (path) ->
    files = []
    for className, classSchema of @configuration
      file = {}
      file.name = "#{className.toLowerCase()}.js"

      code = file.code = []

      dependencies = ["Promise = require('poseidon').Promise;"]
      for dependency, dependencyPath of classSchema.require
        dependencies.push "#{dependency} = require('#{dependencyPath}');"

      # Generate class constructor
      code.push """
      function #{className}(#{classSchema.constructor.params.join(", ")}) {
        #{classSchema.constructor.body}
      }
      """
      for functionName, functionSchema of classSchema.functions
        # Set default options
        functionSchema.wrap ?= true

        # Generate class method
        hunk = ["""
          #{className}.prototype.#{functionName} = function () {
            var args = arguments;
        """]

        if classSchema.type is 'promise'
          instanceIdentifier = "instanceValue"
        else
          instanceIdentifier = "this.instance"
        # Use custom body if specified
        if functionSchema.body?
          hunk.push(functionSchema.body)
        else
          # Create deferred and callback if wrap option is true
          if functionSchema.wrap
            hunk.push "var deferred = Promise.pending();"

          if classSchema.type is 'promise'
            hunk.push "this.instance.then(function (instanceValue) {"

          if functionSchema.wrap
            # Code to wrap return values
            castValues = []
            if functionSchema.return?
              for index, constructorName of functionSchema.return
                if constructorName isnt null then castValues.push "arguments[#{parseInt(index)+1}] = new #{constructorName}(arguments[#{parseInt(index)+1}]);"

            hunk.push """
            var callback = function () {
              #{castValues.join("\n")}
              if (arguments[0]) {
                deferred.reject(arguments[0]);
              } else {
                switch(arguments.length) {
                  case 2:
                    deferred.resolve(arguments[1]);
                    break;
                  case 3:
                    deferred.resolve([arguments[1], arguments[2]]);
                    break;
                  case 4:
                    deferred.resolve([arguments[1], arguments[2], arguments[3]]);
                    break;
                  case 5:
                    deferred.resolve([arguments[1], arguments[2], arguments[3], arguments[4]]);
                    break;
                  case 6:
                    deferred.resolve([arguments[1], arguments[2], arguments[3], arguments[4], arguments[5]]);
                    break;
                  default:
                    deferred.resolve(arguments.slice(1));
                    break;
                }
              }
            };
            """

          # Generate optimized function call
          hunk.push """
          switch(args.length) {
            case 0:
              #{if functionSchema.wrap then "" else "result = "}#{instanceIdentifier}.#{functionName}(#{if functionSchema.wrap then "callback" else ""});
              break;
            case 1:
              #{if functionSchema.wrap then "" else "result = "}#{instanceIdentifier}.#{functionName}(args[0]#{if functionSchema.wrap then ", callback" else ""});
              break;
            case 2:
              #{if functionSchema.wrap then "" else "result = "}#{instanceIdentifier}.#{functionName}(args[0], args[1]#{if functionSchema.wrap then ", callback" else ""});
              break;
            case 3:
              #{if functionSchema.wrap then "" else "result = "}#{instanceIdentifier}.#{functionName}(args[0], args[1], args[2]#{if functionSchema.wrap then ", callback" else ""});
              break;
            case 4:
              #{if functionSchema.wrap then "" else "result = "}#{instanceIdentifier}.#{functionName}(args[0], args[1], args[2], args[3]#{if functionSchema.wrap then ", callback" else ""});
              break;
            case 5:
              #{if functionSchema.wrap then "" else "result = "}#{instanceIdentifier}.#{functionName}(args[0], args[1], args[2], args[3], args[4]#{if functionSchema.wrap then ", callback" else ""});
              break;
            default:
              #{if functionSchema.wrap then "" else "result = "}#{instanceIdentifier}.#{functionName}.apply(#{instanceIdentifier}, #{if functionSchema.wrap then "Array.prototype.slice.call(null, args).concat(callback)" else "args"});
              break;
          }
          """
          if classSchema.type is 'promise'
            hunk.push "});"

          # Return promise if wrap option is set
          if functionSchema.wrap
            hunk.push "return deferred.promise;"
          else
            # If no wrap option is allowed only 1 value can be set in return
            if functionSchema.return?
              if functionSchema.return.length > 1 then throw new Error("Only 1 return value allowed when no callback is present")
              hunk.push "return new #{functionSchema.return[0]}(result);"
            else if functionSchema.chain
              hunk.push "return this;"
            else
              hunk.push "return result;"

        # End of function call
        hunk.push "};"
        code.push hunk.join("\n")

      code.push "module.exports = #{className};"
      try
        # Parse code to ensure generated javascript is valid
        code = "#{dependencies.join("\n")}\n#{code.join("\n")}"

        # Pretty format code
        file.code = escodegen.generate(esprima.parse(code))
        files.push file
      catch err
        codeLines = code.split("\n")
        throw new Error("Error generating class #{className}\n#{err.message}\n#{codeLines[err.lineNumber-1]}")

    if path?
      write = Promise.promisify(fs.writeFile, fs)
      Promise.map files, (file) ->
        write("#{path}/#{file.name}", file.code)
      .then ->
        Promise.resolve files
    else
      files

module.exports = Poseidon
