require("json")

math.log2 = function(x) return math.log(x) / math.log(2) end





--[[
x+ = UP, y+ = RIGHT
corners:
2   1
  X
4   3 
]]--

function adjustBox(entity, box, initBox, corners)
	if entity.bounding_box.right_bottom.x < box[1] then
		box[1] = math.ceil(entity.bounding_box.right_bottom.x) - 8/32  --8 pixel remains of the lamp, 8 pixels because dont wanna mess with jpg
	elseif entity.bounding_box.left_top.x > box[3] then
		box[3] = math.floor(entity.bounding_box.left_top.x) + 8/32
	end
	if entity.bounding_box.right_bottom.y < box[2] then
		box[2] = math.ceil(entity.bounding_box.right_bottom.y) - 8/32
	elseif entity.bounding_box.left_top.y > box[4] then
		box[4] = math.floor(entity.bounding_box.left_top.y) + 8/32
	end

	if entity.bounding_box.left_top.x > initBox[3] then
		if not (entity.bounding_box.left_top.y < initBox[2]) then corners[1] = 1 end
		if not (entity.bounding_box.right_bottom.y > initBox[4]) then corners[2] = 1 end
	elseif entity.bounding_box.right_bottom.x < initBox[1] then
		if not (entity.bounding_box.left_top.y < initBox[2]) then corners[3] = 1 end
		if not (entity.bounding_box.right_bottom.y > initBox[4]) then corners[4] = 1 end
	end
end

function fm.generateMap(data)

	local player = game.players[data.player_index]
	local surface = player.surface

	local forces = {}
	local forceStats = {}
	for _, force in pairs(game.forces) do
		if #force.players > 0 then
			forces[#forces+1] = force.name
			forceStats[force.name] = 0
		end
	end

	game.set_wait_for_screenshots_to_finish()
	
	
	if fm.autorun.mapInfo.maps == nil then
		fm.autorun.mapInfo = {
			seed = game.default_map_gen_settings.seed,
			mapExchangeString = game.get_map_exchange_string(),
			maps = {}
		}
	end


	-- delete folder (if it already exists)
	local basePath = fm.topfolder
	local subPath = basePath .. "Images/" .. fm.autorun.filePath .. "/" .. surface.name .. "/" .. fm.subfolder
	game.remove_path(subPath)
	subPath = subPath .. "/"

	log("Starting surface prescan to target directory: " .. subPath)


	
	-- Number of pixels in an image     -- CHANGE THIS AND REF.PY WILL NEED TO BE CHANGED
	local gridSizes = {256, 512, 1024} -- cant have 2048 anymore. code now relies on it being smaller than one game chunk (32 tiles * 32 pixels)
	local gridSize = gridSizes[2] --always 512x512 pixel images for now, its a good balance (check rest of code before changing this)

	local tilesPerChunk = 32    --hardcoded
	
	local pixelsPerTile = 32
	if fm.autorun.HD == true then
		pixelsPerTile = 64   -- HD textures have 64 pixels/tile
	end

	-- These are the number of tiles per image (gridSize = 512, 32 pixelspertile means 16 by 16 tiles in each image)
	local gridPixelSize = gridSize / pixelsPerTile



	
	if fm.tilenames == nil then
		local blacklist = {
			"water",
			"dirt",
			"grass",
			"lab",
			"out-of-map",
			"desert",
			"sand",
			"tutorial",
			"ghost"
		}

		local tilenamedict = {}
		for _, item in pairs(game.item_prototypes) do 
			if item.place_as_tile_result ~= nil and tilenamedict[item.place_as_tile_result.result.name] == nil then
				for _, keyword in pairs(blacklist) do
					if string.match(item.place_as_tile_result.result.name, keyword) then
						tilenamedict[item.place_as_tile_result.result.name] = false
						goto continue
					end
				end
				tilenamedict[item.place_as_tile_result.result.name] = true
			end
			::continue::
		end

		fm.tilenames = {}
		for tilename, value in pairs(tilenamedict) do
			if value then
				fm.tilenames[#fm.tilenames+1] = tilename
			end
		end
	end

	

	local spawn = player.force.get_spawn_position(surface)


	

	local minX = spawn.x
	local minY = spawn.y
	local maxX = spawn.x
	local maxY = spawn.y

	local allGrid = {}
	local mapIndex = 0
	if fm.autorun.chunkCache then
		for mapTick, v in pairs(fm.autorun.chunkCache) do
			if tonumber(mapTick) <= fm.autorun.tick and v[surface.name] ~= nil then
				for s in v[surface.name]:gmatch("%-?%d+ %-?%d+") do
					local gridX, gridY = s:match("(%-?%d+) (%-?%d+)")
					gridX = tonumber(gridX)
					gridY = tonumber(gridY)

					allGrid[s] = {x = gridX, y = gridY}

					minX = math.min(minX, gridX)
					minY = math.min(minY, gridY)
					maxX = math.max(maxX, gridX)
					maxY = math.max(maxY, gridY)
				end
				if tonumber(mapTick) == fm.autorun.tick then
					for i, map in pairs(fm.autorun.mapInfo.maps) do
						if map.tick == mapTick then
							mapIndex = i
							break
						end
					end
				end
			end
		end
	end

	local buildChunks = {}
	local allGridString = ""
	local imageStats = {
		charted = 0,
		not_cached = 0,
		build_range = 0,
		smaller_range = 0,
		tags = 0,
		player = 0,
		smoothed = 0
	}
	if mapIndex == 0 then
		for chunk in surface.get_chunks() do
			for _, force in pairs(game.forces) do
				if #force.players > 0 and force.is_chunk_charted(surface, chunk) then
					forceStats[force.name] = forceStats[force.name] + 1
					imageStats.charted = imageStats.charted + 1
					for gridX = (chunk.x) * tilesPerChunk / gridPixelSize, (chunk.x + 1) * tilesPerChunk / gridPixelSize - 1 do
						for gridY = (chunk.y) * tilesPerChunk / gridPixelSize, (chunk.y + 1) * tilesPerChunk / gridPixelSize - 1 do
							if allGrid[gridX .. " " .. gridY] == nil then
								imageStats.not_cached = imageStats.not_cached + 1
								for k = 0, fm.autorun.around_build_range * pixelsPerTile / tilesPerChunk, 1 do
									for l = 0, fm.autorun.around_build_range * pixelsPerTile / tilesPerChunk, 1 do
										for m = 1, k > 0 and -1 or 1, -2 do
											for n = 1, l > 0 and -1 or 1, -2 do
												local i = k * m
												local j = l * n
												local dist = math.pow(i * tilesPerChunk / pixelsPerTile, 2) + math.pow(j * tilesPerChunk / pixelsPerTile, 2)
												if dist <= math.pow(fm.autorun.around_build_range + 0.5, 2) then
													local x = gridX + i + (tilesPerChunk / gridPixelSize) / 2 - 1
													local y = gridY + j + (tilesPerChunk / gridPixelSize) / 2 - 1
													local area = {{gridPixelSize * (x-.5), gridPixelSize * (y-.5)}, {gridPixelSize * (x+.5), gridPixelSize * (y+.5)}}
													if buildChunks[x .. " " .. y] == nil then
														local powerCount = 0
														if fm.autorun.smaller_types and #fm.autorun.smaller_types > 0 then
															powerCount = surface.count_entities_filtered({ force=forces, area=area, type=fm.autorun.smaller_types })
														end
														local excludeCount = powerCount + surface.count_entities_filtered({ force=forces, area=area, type={"player"} })
														if surface.count_entities_filtered({ force=forces, area=area, limit=excludeCount + 1 }) > excludeCount or surface.count_tiles_filtered({ force=forces, area=area, limit=excludeCount + 1, name=fm.tilenames }) > 0 then
															buildChunks[x .. " " .. y] = 2
														elseif powerCount > 0 then
															buildChunks[x .. " " .. y] = 1
														else
															buildChunks[x .. " " .. y] = 0
														end
													end
													if buildChunks[x .. " " .. y] == 2 or (buildChunks[x .. " " .. y] == 1 and dist <= math.pow(fm.autorun.around_smaller_range + 0.5, 2)) then
														allGrid[gridX .. " " .. gridY] = {x = gridX, y = gridY}
														allGridString = allGridString .. gridX .. " " .. gridY .. "|"

														minX = math.min(minX, gridX)
														minY = math.min(minY, gridY)
														maxX = math.max(maxX, gridX)
														maxY = math.max(maxY, gridY)
														
														if buildChunks[x .. " " .. y] == 2 then
															imageStats.build_range = imageStats.build_range + 1
														else
															imageStats.smaller_range = imageStats.smaller_range + 1
														end

														goto done
													end
												end
											end
										end
									end
								end
							end
							::done::
						end
					end
					break
				end
			end
		end



		-- tag range
		for _, force in pairs(game.forces) do
			if #force.players > 0 then
				for _, tag in pairs(force.find_chart_tags(surface)) do
					for k = 0, fm.autorun.around_tag_range * pixelsPerTile / tilesPerChunk, 1 do
						for l = 0, fm.autorun.around_tag_range * pixelsPerTile / tilesPerChunk, 1 do
							for m = 1, k > 0 and -1 or 1, -2 do
								for n = 1, l > 0 and -1 or 1, -2 do
									local i = k * m
									local j = l * n
									local x = tag.position.x / gridPixelSize + i
									local y = tag.position.y / gridPixelSize + j
									local dist = math.pow(i * tilesPerChunk / pixelsPerTile, 2) + math.pow(j * tilesPerChunk / pixelsPerTile, 2)
									local chunk = {x = math.floor(x * gridPixelSize / tilesPerChunk), y = math.floor(y * gridPixelSize / tilesPerChunk)}
									if dist <= math.pow(fm.autorun.around_tag_range + 0.5, 2) and force.is_chunk_charted(surface, chunk) then
										local gridX = math.floor(x)
										local gridY = math.floor(y)
										allGrid[gridX .. " " .. gridY] = {x = gridX, y = gridY}
										allGridString = allGridString .. gridX .. " " .. gridY .. "|"

										minX = math.min(minX, gridX)
										minY = math.min(minY, gridY)
										maxX = math.max(maxX, gridX)
										maxY = math.max(maxY, gridY)

										imageStats.tags = imageStats.tags + 1
									end
								end
							end
						end
					end
				end
			end
		end





		-- add around player on empty
		if #allGrid == 0 then
			range = math.max(fm.autorun.around_tag_range, fm.autorun.around_build_range)
			for k = 0, range * pixelsPerTile / tilesPerChunk, 1 do
				for l = 0, range * pixelsPerTile / tilesPerChunk, 1 do
					for m = 1, k > 0 and -1 or 1, -2 do
						for n = 1, l > 0 and -1 or 1, -2 do
							local i = k * m
							local j = l * n
							local x = player.position.x / gridPixelSize + i
							local y = player.position.y / gridPixelSize + j
							local dist = math.pow(i * tilesPerChunk / pixelsPerTile, 2) + math.pow(j * tilesPerChunk / pixelsPerTile, 2)
							local chunk = {x = math.floor(x * gridPixelSize / tilesPerChunk), y = math.floor(y * gridPixelSize / tilesPerChunk)}
							if dist <= math.pow(range + 0.5, 2) then
								local gridX = math.floor(x)
								local gridY = math.floor(y)
								allGrid[gridX .. " " .. gridY] = {x = gridX, y = gridY}
								allGridString = allGridString .. gridX .. " " .. gridY .. "|"

								minX = math.min(minX, gridX)
								minY = math.min(minY, gridY)
								maxX = math.max(maxX, gridX)
								maxY = math.max(maxY, gridY)

								imageStats.player = imageStats.player + 1
							end
						end
					end
				end
			end
		end




		
	
		-- smoothing
		local cont = true
		while cont do
			cont = false
			tmp = {}
			for _, p in pairs(allGrid) do
				for _, o in pairs({ {x=1, y=0}, {x=-1, y=0}, {x=0, y=1}, {x=0, y=-1} }) do
					if allGrid[(p.x+o.x) .. " " .. (p.y+o.y)] == nil then
						local count = 0
						for _, pos in pairs({ {x=p.x+2*o.x, y=p.y+2*o.y}, {x=p.x+o.x+o.y, y=p.y+o.y+o.x}, {x=p.x+o.x-o.y, y=p.y+o.y-o.x} }) do
							if allGrid[pos.x .. " " .. pos.y] ~= nil then
								count = count + 1
								if count >= 2 then
									tmp[#tmp + 1] = {x=p.x+o.x, y=p.y+o.y}
									cont = true
								end
							end
						end
					end
				end
			end
			cont = #tmp > 0
			for _, v in pairs(tmp) do
				allGrid[v.x .. " " .. v.y] = v 
				allGridString = allGridString .. v.x .. " " .. v.y .. "|"

				minX = math.min(minX, v.x)
				minY = math.min(minY, v.y)
				maxX = math.max(maxX, v.x)
				maxY = math.max(maxY, v.y)
								
				imageStats.smoothed = imageStats.smoothed + 1
			end
		end


		log("FactorioMaps_Debug: imageStats")
		log("FactorioMaps_Debug:     charted:       " .. imageStats.charted * math.pow(tilesPerChunk / gridPixelSize, 2))
		log("FactorioMaps_Debug:     not_cached:    " .. imageStats.not_cached)
		log("FactorioMaps_Debug:     build_range:   " .. imageStats.build_range)
		log("FactorioMaps_Debug:     smaller_range: " .. imageStats.smaller_range)
		log("FactorioMaps_Debug:     tags:          " .. imageStats.tags)
		log("FactorioMaps_Debug:     player:        " .. imageStats.player)
		log("FactorioMaps_Debug:     smoothed:      " .. imageStats.smoothed)
		log("FactorioMaps_Debug: forceStats")
		for force, count in pairs(forceStats) do
			log("FactorioMaps_Debug:     " .. force .. ": " .. count)
		end



		mapIndex = #fm.autorun.mapInfo.maps + 1
		fm.autorun.mapInfo.maps[mapIndex] = {
			tick = fm.autorun.tick,
			path = fm.autorun.filePath,
			date = fm.autorun.date,
			mods = game.active_mods,
			surfaces = {}
		}
	end

	local maxZoom = 20
	if fm.autorun.HD == true then
		maxZoom = 21
	end
	

	-- TODO: THIS SHIT IS BROKEN
	local maxImagesNextToEachotherOnLargestZoom = 2
	local minZoom = (maxZoom - math.max(2, math.ceil(math.min(math.log2(maxX - minX), math.log2(maxY - minY)) + 0.01 - math.log2(maxImagesNextToEachotherOnLargestZoom))))

	if fm.autorun.mapInfo.maps[mapIndex].surfaces[surface.name] == nil then
		fm.autorun.mapInfo.maps[mapIndex].surfaces[surface.name] = {
			spawn = spawn, -- this only includes spawn point of the player taking the screenshots
			zoom = { min = minZoom, max = maxZoom },
			playerPosition = player.position,
			tags = {}
		}
		for _, force in pairs(game.forces) do
			if #force.players > 0 then
				for i, tag in pairs(force.find_chart_tags(surface)) do
					if tag.icon == nil then
						fm.autorun.mapInfo.maps[mapIndex].surfaces[surface.name].tags[i] = {
							position 	= tag.position,
							text 		= tag.text,
							last_user	= tag.last_user and tag.last_user.name,
							force	    = force.name
						}
					else
						name = tag.icon["name"] or tag.icon.type
						fm.autorun.mapInfo.maps[mapIndex].surfaces[surface.name].tags[i] = {
							iconType 	= tag.icon.type,
							iconName 	= name,
							iconPath    = "Images/labels/" .. tag.icon.type .. "/" .. name .. ".png",
							position 	= tag.position,
							text 		= tag.text,
							last_user	= tag.last_user and tag.last_user.name,
							force	    = force.name
						}
					end
				end
			end
		end

		if fm.autorun.chunkCache[fm.autorun.tick] == nil then
			fm.autorun.chunkCache[fm.autorun.tick] = {}
		end
		fm.autorun.chunkCache[fm.autorun.tick][surface.name] = allGridString:sub(1, -2)
		game.write_file(basePath .. "chunkCache.json", prettyjson(fm.autorun.chunkCache), false, data.player_index)
	
	end
	fm.autorun.mapInfo.maps[mapIndex].surfaces[surface.name][fm.subfolder] = true


	
	-- -- in 0.17, we will hopefully be able to use writefile in the data stage instead..
	-- local rawTagStrings = {}
	-- for _, damageType in pairs(game.damage_prototypes) do
	-- 	local match = damageType.name:match("FMh%d+_")
	-- 	if match ~= nil then
	-- 		rawTagStrings[tonumber(match:sub(4, -2)) + 1] = damageType.name:sub(match:len() + 1) .. damageType.order
	-- 	end
	-- end
	-- local rawTagString = ""
	-- for i = 1, #rawTagStrings, 1 do
	-- 	rawTagString = rawTagString .. rawTagStrings[i]
	-- end
	-- local rawTags = {}
	-- for typeName, path in rawTagString:gmatch("([^:|]+):([^:|]+)") do
	-- 	rawTags[typeName] = path
	-- end
	
	-- game.write_file(basePath .. "rawTags.json", json(rawTags), false, data.player_index)

   
	local extension = "bmp"


	
	log("Starting surface capture to target directory: " .. subPath)

	game.write_file(basePath .. "mapInfo.json", json(fm.autorun.mapInfo), false, data.player_index)


	local cropText = ""
	for _, chunk in pairs(allGrid) do   
		local positionTable = {(chunk.x + 0.5) * gridPixelSize, (chunk.y + 0.5) * gridPixelSize}

		local box = { positionTable[1], positionTable[2], positionTable[1] + gridPixelSize, positionTable[2] + gridPixelSize } -- -X -Y X Y
		local initialBox = { box[1], box[2], box[3], box[4] }
		local area = {{box[1] - 16, box[2] - 16}, {box[3] + 16, box[4] + 16}}
		
		local corners = {0, 0, 0, 0}

		for _, t in pairs(surface.find_entities_filtered{area=area, name="big-electric-pole"}) do 
			adjustBox(t, box, initialBox, corners)
		end
		for _, t in pairs(surface.find_entities_filtered{area=area, type="lamp"}) do 
			local control = t.get_control_behavior()
			if t.energy > 1 and (control and not control.disabled) or (not control and surface.darkness > 0.3) then
				adjustBox(t, box, initialBox, corners)
			end
		end
		if box[1] < positionTable[1] or box[2] < positionTable[2] or box[3] > positionTable[1] + gridPixelSize or box[4] > positionTable[2] + gridPixelSize then
			cropText = cropText .. "\n" .. chunk.x .. " " .. chunk.y .. " " .. (positionTable[1] - box[1])*pixelsPerTile .. " " .. (positionTable[2] - box[2])*pixelsPerTile .. " " .. string.format("%x", corners[1] + 2*corners[2] + 4*corners[3] + 8*corners[4])
		end

		local pathText = subPath .. maxZoom .. "/" .. chunk.x .. "/" .. chunk.y .. "." .. extension
		game.take_screenshot({by_player=player, position = {(box[1] + box[3]) / 2, (box[2] + box[4]) / 2}, resolution = {(box[3] - box[1])*pixelsPerTile, (box[4] - box[2])*pixelsPerTile}, zoom = fm.autorun.HD and 2 or 1, path = pathText, show_entity_info = fm.autorun.alt_mode})                        
	end 
	
	
	game.write_file(subPath .. "crop.txt", gridSize .. cropText, false, data.player_index)
	
end