mysql = require 'mysql'

class QuickQueryMysqlColumn
  type: 'column'
  child_type: null
  constructor: (@table,row) ->
    @connection = @table.connection
    @name = row['Field']
    @column = @name # TODO remove
    @primary_key = row["Key"] == "PRI"
    @datatype = row['Type']
    @default = row['Default']
    @nullable = row['Null'] == 'YES'
  toString: ->
    @name
  parent: ->
    @table
  children: (callback)->
    callback([])

class QuickQueryMysqlTable
  type: 'table'
  child_type: 'column'
  constructor: (@database,row,fields) ->
    @connection = @database.connection
    @name = row[fields[0].name]
    @table = @name # TODO remove
  toString: ->
    @name
  parent: ->
    @database
  children: (callback)->
    @connection.getColumns(@,callback)
class QuickQueryMysqlDatabase
  type: 'database'
  child_type: 'table'
  constructor: (@connection,row) ->
    @name = row["Database"]
    @database = @name # TODO remove
  toString: ->
    @name
  parent: ->
    @connection
  children: (callback)->
    @connection.getTables(@,callback)

module.exports =
class QuickQueryMysqlConnection

  fatal: false
  connection: null
  protocol: 'mysql'
  type: 'connection'
  child_type: 'database'
  defaulPort: 3306
  timeout: 5000 #time ot is set in 5s. queries should be fast.

  n_types: 'TINYINT SMALLINT MEDIUMINT INT INTEGER BIGINT FLOAT DOUBLE REAL DECIMAL NUMERIC TIMESTAMP YEAR ENUM SET'.split /\s+/
  s_types: 'CHAR VARCHAR TINYBLOB TINYTEXT MEDIUMBLOB MEDIUMTEXT LONGBLOB LONGTEXT BLOB TEXT DATETIME DATE TIME'.split /\s+/

  constructor: (@info)->
    @info.dateStrings = true

  connect: (callback)->
    @connection = mysql.createConnection(@info)
    @connection.connect(callback)

  serialize: ->
    c = @connection.config
    host: c.host,
    port: c.port,
    protocol: @protocol
    user: c.user,
    password: c.password

  dispose: ->
    @connection.end()

  query: (text,callback) ->
    if @fatal
      @connection = mysql.createConnection(@info)
      @fatal = false
    @connection.query {sql: text , timeout: @timeout }, (err, rows, fields)=>
      message = null
      if (err)
        message = { type: 'error' , content: err }
        @fatal = err.fatal
      else if !fields
        message = { type: 'success', content:  rows.affectedRows+" row(s) affected" }
      callback(message,rows,fields)

  setDefaultDatabase: (database)->
    @connection.changeUser database: database

  getDefaultDatabase: ->
    @connection.config.database

  getDatabases: (callback) ->
    text = "SHOW DATABASES"
    @query text , (err, rows, fields) =>
      if !err
        databases = rows.map (row) =>
          new QuickQueryMysqlDatabase(@,row)
        databases = databases.filter (database) => !@hiddenDatabase(database.name)
      callback(databases,err)

  getTables: (database,callback) ->
    database_name = @connection.escapeId(database.name)
    text = "SHOW TABLES IN #{database_name}"
    @query text , (err, rows, fields) =>
      if !err
        tables = rows.map (row) =>
          new QuickQueryMysqlTable(database,row,fields)
        callback(tables)

  getColumns: (table,callback) ->
    table_name = @connection.escapeId(table.name)
    database_name = @connection.escapeId(table.database.name)
    text = "SHOW COLUMNS IN #{table_name} IN #{database_name}"
    @query text , (err, rows, fields) =>
      if !err
        columns = rows.map (row) =>
          new QuickQueryMysqlColumn(table,row)
        callback(columns)

  hiddenDatabase: (database) ->
    database == "information_schema" ||
    database == "performance_schema" ||
    database == "mysql"

  simpleSelect: (table, columns = '*') ->
    if columns != '*'
      columns = columns.map (col) =>
        @connection.escapeId(col.name)
      columns = "\n "+columns.join(",\n ") + "\n"
    table_name = @connection.escapeId(table.name)
    database_name = @connection.escapeId(table.database.name)
    "SELECT #{columns} FROM #{database_name}.#{table_name} LIMIT 1000"


  createDatabase: (model,info)->
    database = @connection.escapeId(info.name)
    "CREATE SCHEMA #{database};"

  createTable: (model,info)->
    database = @connection.escapeId(model.name)
    table = @connection.escapeId(info.name)
    "CREATE TABLE #{database}.#{table} ( \n"+
    " `id` INT NOT NULL ,\n"+
    " PRIMARY KEY (`id`) );"

  createColumn: (model,info)->
    database = @connection.escapeId(model.database.name)
    table = @connection.escapeId(model.name)
    column = @connection.escapeId(info.name)
    nullable = if info.nullable then 'NULL' else 'NOT NULL'
    dafaultValue = @escape(info.default,info.datatype) || 'NULL'
    "ALTER TABLE #{database}.#{table} ADD COLUMN #{column}"+
    " #{info.datatype} #{nullable} DEFAULT #{dafaultValue};"


  alterTable: (model,delta)->
    database = @connection.escapeId(model.database.name)
    newName = @connection.escapeId(delta.new_name)
    oldName = @connection.escapeId(delta.old_name)
    query = "ALTER TABLE #{database}.#{oldName} RENAME TO #{database}.#{newName};"

  alterColumn: (model,delta)->
    database = @connection.escapeId(model.table.database.name)
    table = @connection.escapeId(model.table.name)
    newName = @connection.escapeId(delta.new_name)
    oldName = @connection.escapeId(delta.old_name)
    nullable = if delta.nullable then 'NULL' else 'NOT NULL'
    dafaultValue = @escape(delta.default,delta.datatype) || 'NULL'
    "ALTER TABLE #{database}.#{table} CHANGE COLUMN #{oldName} #{newName}"+
    " #{delta.datatype} #{nullable} DEFAULT #{dafaultValue};"

  dropDatabase: (model)->
    database = @connection.escapeId(model.name)
    "DROP SCHEMA #{database};"

  dropTable: (model)->
    database = @connection.escapeId(model.database.name)
    table = @connection.escapeId(model.name)
    "DROP TABLE #{database}.#{table};"

  dropColumn: (model)->
    database = @connection.escapeId(model.table.database.name)
    table = @connection.escapeId(model.table.name)
    column = @connection.escapeId(model.name)
    "ALTER TABLE #{database}.#{table} DROP COLUMN #{column};"

  getDataTypes: ->
    @n_types.concat(@s_types)

  toString: ->
    @protocol+"://"+@connection.config.user+"@"+@connection.config.host

  escape: (value,type)->
    for t1 in @s_types
      if type.search(new RegExp(t1, "i")) == -1
        return @connection.escape(value)
    str
