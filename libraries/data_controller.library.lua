function string.split(s, p)
    local f = {}
    for v in string.gmatch(s, '([^'..p..']+)') do
        f[#f+1] = v
    end
    return f
end

function table.count(t)
	local n = 0
	for k, v in pairs(t) do
		n = n+1
	end
	return n
end

if (type(table.unpack) == 'nil') then
	function table.unpack(t)
		return unpack(t)
	end
end

function data_controller(module_id)
	local private = {
		allowed_types = {int = true, table = true, boolean = true, string  = true},
		allowed_operators = {['+'] = true, ['='] = true, ['-'] = true, ['*'] = true, ['/'] = true},
		allowed_conditionals = {['='] = true, ['<'] = true, ['>'] = true, ['<='] = true, ['>='] = true, ['~'] = true},
		data_separator = '|',
		table_separator ='&',
		end_separator = '%]',
		id_code = string.format('##%s##', module_id),
		module_id = module_id,
		placeholder = '\174placeholder\175',
		players = {},
		structure = {}
	}

	local public = {}

	function private:find_module_data(saved_data)
		local pattern = string.format('%s%%[(.-)%s', private.id_code, private.end_separator)
		local data_match = string.match(saved_data, pattern)
		return data_match
	end

	function private:add_data_placeholder(saved_data)
		local pattern = string.format('%s%%[(.-)%s', private.id_code, private.end_separator)
		return string.gsub(saved_data, pattern, private.placeholder)
	end

	function private:generate_default_data()
		local final_data = {}
		for column, data in pairs(private.structure) do
			final_data[column] = data.default_value
		end
		return final_data
	end

	function private:generate_from_string(saved_data, inhe)
		local final_data = {}
		local columns = string.split(saved_data, private.data_separator)
		for column, data in pairs(private.structure) do
			if (columns[data.index]) then
				final_data[column] = private:string_to_type(data.data_type, columns[data.index])
			else
				final_data[column] = data.default_value
			end
		end
		return final_data
	end

	function private:string_to_type(vtype, value)
		if (vtype == 'table') then
			return string.split(value, private.table_separator)
		elseif (vtype == 'int') then
			return value * 1
		elseif (vtype == 'boolean') then
			return value * 1 == '1'
		end
		return value
	end

	function private:type_to_string(vtype, value)
		if (vtype == 'table') then
			return table.concat(value, private.table_separator)
		elseif (vtype == 'boolean') then
			return value and '1' or '0'
		else
			return tostring(value)
		end
	end

	function public:load(player, saved_data)
		private.players[player] = {
		}
		if (saved_data) then
			local player_module_data = private:find_module_data(saved_data)
			if (player_module_data) then
				saved_data = private:add_data_placeholder(saved_data)
				private.players[player].data = private:generate_from_string(player_module_data)
			else
				saved_data = saved_data..private.placeholder
				private.players[player].data = private:generate_default_data()
			end
		else
			saved_data = private.placeholder
			private.players[player].data = private:generate_default_data()
		end

		private.players[player].raw = saved_data

		return public:player(player)
	end

	function public:add_column(data_type, column, value)
		if (private.allowed_types[data_type]) then
			if (type(private.structure[column]) == 'nil') then
				private.structure[column] = {
					data_type = data_type,
					default_value = value,
					index = table.count(private.structure)+1
				}
			else
				error(string.format('Column "%s" is already signed', column))
			end
		end

		return public
	end

	function public:where(column, condition, value)
		if (type(column) == 'string') then
			column = {{column, condition, value}}
		end
		local players_met = {}
		local where_methods = {}

		for player, pdata in pairs(private.players) do
			validated_conditions = 0
			for _, val in pairs(column) do
				if (#val == 3) then
					_column, _conditional, _value = table.unpack(val)
					if (type(private.structure[_column]) ~= 'nil') then
						if (private.allowed_conditionals[_conditional]) then
							local player_value = pdata.data[_column]
							if (_conditional == '=') then
								if (_value == player_value) then
									validated_conditions = validated_conditions+1
								end
							elseif (_conditional == '<') then
								if (player_value < _value) then
									validated_conditions = validated_conditions+1
								end
							elseif (_conditional == '>') then
								if (player_value > _value) then
									validated_conditions = validated_conditions+1
								end
							elseif (_conditional == '<=') then
								if (player_value <= _value) then
									validated_conditions = validated_conditions+1
								end
							elseif (_conditional == '>=') then
								if (player_value >= _value) then
									validated_conditions = validated_conditions+1
								end
							elseif (_conditional == '~') then
								if (_value ~= player_value) then
									validated_conditions = validated_conditions+1
								end
							end
						end
					end
				end
			end
			if (validated_conditions == #column) then
				table.insert(players_met, player)
			end
		end

		function where_methods:get_names()
			return players_met
		end

		function where_methods:get(column)
			local values = {}
			for _, player in pairs(players_met) do
				local playerHandler = public:player(player)
				values[player] = playerHandler:get(column)
			end

			return values
		end

		function where_methods:update(column, operator, value)
			if (type(column) == 'string') then
				column = {
					{column, operator, value}
				}
			end
			for _, player in pairs(players_met) do
				local playerHandler = public:player(player)
				local return_v = playerHandler:update(column)
			end
			return where_methods
		end

		return where_methods
	end

	function public:player(player_name)
		if (private.players[player_name]) then
			local player = private.players[player_name]
			local player_methods = {}

			function player_methods:get(column)
				if (type(player.data[column]) ~= 'nil') then
					return player.data[column]
				end
			end

			function player_methods:stringify()
				local data_string = {}
				for column, data in pairs(player.data) do
					local column_index = private.structure[column].index
					local column_type = private.structure[column].data_type
					data_string[column_index] = private:type_to_string(column_type, data)
				end

				data_string = table.concat(data_string, private.data_separator)
				local finished_data = string.gsub(player.raw, private.placeholder, private.id_code..'['..data_string..private.end_separator)
				return finished_data
			end

			function player_methods:update(column, operator, value)
				if (type(column) == 'string') then
					column = {
						{column, operator, value}
					}
				end
				for _, val in pairs(column) do
					local invalid_operation = false
					if (#val == 3) then
						_column, _operator, _value = table.unpack(val)
						if (type(player.data[_column]) ~= 'nil') then
							if (type(_value) == type(player.data[_column])) then
								if (private.allowed_operators[_operator]) then
									if (type(_value) == 'number') then
										if (_operator == '+') then
											player.data[_column] = player.data[_column]+_value
										elseif (_operator == '-') then
											player.data[_column] = player.data[_column]-_value
										elseif (_operator == '*') then
											player.data[_column] = player.data[_column]*_value
										elseif (_operator == '/') then
											player.data[_column] = player.data[_column]/_value
										elseif (_operator == '=') then
											player.data[_column] = _value
										end
									elseif (type == 'string') then
										if (_operator == '+') then
											player.data[_column] = player.data[_column].._value
										elseif (_operator == '=') then
											player.data[_column] = _value
										else
											invalid_operation = true
										end
									else
										if (_operator == '=') then
											player.data[_column] = _value
										else
											invalid_operation = true
										end
									end
									if (invalid_operation) then
										error(string.format('Invalid :update execution at "%s(%s) %s %s", invalid operator for %s type', player_name, _column, _operator, tostring(_value), type(_value)))
									end
								else
									error(string.format('Invalid :update execution at "%s(%s) %s %s", invalid operator', player_name, _column, _operator, tostring(_value)))
								end
							else
								error(string.format('Invalid :update execution at "%s(%s) %s %s", new value has a different type', player_name, _column, _operator, tostring(_value)))
							end
						end
					else
						error(string.format('Invalid :update execution at "%s", needed arguments were not supplied', player_name))
					end
				end
				return player_methods
			end

			return player_methods
		end
	end

	return public
end
