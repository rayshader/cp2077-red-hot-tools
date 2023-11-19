local Cron = require('Cron')
local Ref = require('Ref')
local PersistentState = require('PersistentState')

-- Utils --

local function isEmpty(value)
    return value == nil or value == 0 or value == '' or value == 'None'
end

local function isNotEmpty(value)
    return value ~= nil and value ~= 0 and value ~= '' and value ~= 'None'
end

local function clamp(value, rangeMin, rangeMax)
    return math.max(rangeMin, math.min(rangeMax, value))
end

local function opacity(abgr)
    return bit32.band(bit32.rshift(abgr, 24), 0xFF)
end

local function fade(abgr, a)
    return bit32.bor(bit32.lshift(bit32.band(a, 0xFF), 24), bit32.band(abgr, 0xFFFFFF))
end

local function insideBox(point, box)
    return point.x >= box.Min.x and point.y >= box.Min.y and point.z >= box.Min.z
        and point.x <= box.Max.x and point.y <= box.Max.y and point.z <= box.Max.z
end

local function enum(...)
    local map = { values = {} }
    for index, value in ipairs({...}) do
        map[value] = value
        map.values[index] = value
        map.values[value] = index
    end
    return map
end

-- App --

local isPluginFound = false
local isTweakXLFound = false

local cameraSystem
local targetingSystem
local spatialQuerySystem
local inspectionSystem

local function initializeEnvironment()
    isPluginFound = type(RedHotTools) == 'userdata'
    isTweakXLFound = type(TweakXL) == 'userdata'

    cameraSystem = Game.GetCameraSystem()
    targetingSystem = Game.GetTargetingSystem()
    spatialQuerySystem = Game.GetSpatialQueriesSystem()
    inspectionSystem = Game.GetInspectionSystem()
end

-- App :: User State --

local ColorScheme = enum('Green', 'Red', 'Yellow', 'White', 'Shimmer')
local OutlineMode = enum('ForSupportedObjects', 'Never')
local MarkerMode = enum('Always', 'WhenOutlineIsUnsupported', 'Never')
local BoundingBoxMode = enum('ForAreaNodes', 'Never')

local userState = {}
local userStateSchema = {
    isInspectorOSD = { type = 'boolean', default = false },
    isInspectorOpen = { type = 'boolean', default = false },
    isScannerOpen = { type = 'boolean', default = false },
    isLookupOpen = { type = 'boolean', default = false },
    isWatcherOpen = { type = 'boolean', default = false },
    scannerDistance = { type = 'number', default = 5.0 },
    highlightColor = { type = ColorScheme, default = ColorScheme.Red },
    outlineMode = { type = OutlineMode, default = OutlineMode.ForSupportedObjects },
    markerMode = { type = MarkerMode, default = MarkerMode.WhenOutlineIsUnsupported },
    boundingBoxMode = { type = BoundingBoxMode, default = BoundingBoxMode.Never },
    highlightInspectorResult = { type = 'boolean', default = true },
    highlightScannerResult = { type = 'boolean', default = true },
    highlightLookupResult = { type = 'boolean', default = false },
    keepLastHoveredResultHighlighted = { type = 'boolean', default = true },
    showMarkerDistance = { type = 'boolean', default = false },
    showBoundingBoxDistances = { type = 'boolean', default = false },
}

local function initializeUserState()
    PersistentState.Initialize('.state', userState, userStateSchema)
end

local function saveUserState()
    PersistentState.Flush()
end

-- App :: Targeting --

local collisionGroups = {
    { name = 'Static', threshold = 0.0, tolerance = 0.2 },
    { name = 'Dynamic', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'Cloth', threshold = 0.2, tolerance = 0.0 },
    --{ name = 'Player', threshold = 0.2, tolerance = 0.0 },
    --{ name = 'AI', threshold = 0.0, tolerance = 0.0 },
    { name = 'Vehicle', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'Tank', threshold = 0.0, tolerance = 0.0 },
    { name = 'Destructible', threshold = 0.0, tolerance = 0.0 },
    { name = 'Terrain', threshold = 0.0, tolerance = 0.0 },
    { name = 'Collider', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'Particle', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'Ragdoll', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'Ragdoll Inner', threshold = 0.0, tolerance = 0.0 },
    { name = 'Debris', threshold = 0.0, tolerance = 0.0 },
    { name = 'PlayerBlocker', threshold = 0.0, tolerance = 0.0 },
    { name = 'VehicleBlocker', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'TankBlocker', threshold = 0.0, tolerance = 0.0 },
    { name = 'DestructibleCluster', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'NPCBlocker', threshold = 0.0, tolerance = 0.0 },
    { name = 'Visibility', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'Audible', threshold = 0.0, tolerance = 0.0 },
    { name = 'Interaction', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'Shooting', threshold = 0.2, tolerance = 0.0 },
    { name = 'Water', threshold = 0.0, tolerance = 0.0 },
    { name = 'NetworkDevice', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'NPCTraceObstacle', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'PhotoModeCamera', threshold = 0.0, tolerance = 0.0 },
    { name = 'FoliageDestructible', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'NPCNameplate', threshold = 0.0, tolerance = 0.0 },
    --{ name = 'NPCCollision', threshold = 0.0, tolerance = 0.0 },
}

local function getCameraData(distance)
	local player = GetPlayer()

	if not IsDefined(player) or IsDefined(GetMountedVehicle(player)) then
        return nil
	end

    local position, forward = targetingSystem:GetCrosshairData(player)
    local destination = position

    if distance ~= nil then
        destination = Vector4.new(
            position.x + forward.x * distance,
            position.y + forward.y * distance,
            position.z + forward.z * distance,
            position.w
        )
    end

    return {
        position = position,
        forward = forward,
        destination = destination,
        instigator = Ref.Weak(player)
    }
end

local function getLookAtTarget(maxDistance)
	local camera = getCameraData(maxDistance or 100)

	if not camera then
        return
	end

    local results = {}

	local entity = targetingSystem:GetLookAtObject(camera.instigator, true, false)
	if IsDefined(entity) then
	    local target = {
	        resolved = true,
	        entity = Ref.Weak(entity),
	        hash = inspectionSystem:GetObjectHash(entity),
	    }

        local distance = Vector4.Distance(camera.position, ToVector4(entity:GetWorldPosition()))

        table.insert(results, {
            distance = distance,
            target = target,
            group = collisionGroups[2],
        })
	end

	for _, group in ipairs(collisionGroups) do
		local success, trace = spatialQuerySystem:SyncRaycastByCollisionGroup(camera.position, camera.destination, group.name, false, false)
		if success then
			local target = inspectionSystem:GetPhysicsTraceObject(trace)
			if target.resolved then
			    local distance = Vector4.Distance(camera.position, ToVector4(trace.position))
			    if distance > group.threshold then
                    table.insert(results, {
                        distance = distance,
                        target = target,
                        group = group,
                    })
                end
			end
		end
	end

	if #results == 0 then
		return nil
	end

	local nearest = results[1]

	for i = 2, #results do
	    local diff = nearest.distance - results[i].distance
		if diff > results[i].group.tolerance then
            nearest = results[i]
		end
	end

	return nearest.target, nearest.group.name, nearest.distance
end

-- App :: Highlighting --

local highlight = {
    target = nil,
    pending = nil,
    projections = {},
    color = 0,
    outline = 0,
}

local shimmer = {
    steps = { 1, 5, 3, 4 },
    reverse = false,
    state = 1,
    tick = 1,
    delay = 1,
}

local colorMapping = {
    [ColorScheme.Green] = 0xFF32FF1D,
    [ColorScheme.Red] = 0xFF050FFF,
    [ColorScheme.Yellow] = 0xFFF0B537,
    [ColorScheme.White] = 0xFFFFFFFF,
    [ColorScheme.Shimmer] = 0xFF0090FF,
}

local outlineMapping = {
    [ColorScheme.Green] = 1,
    [ColorScheme.Red] = 2,
    [ColorScheme.Yellow] = 5,
    [ColorScheme.White] = 7,
    [ColorScheme.Shimmer] = 0,
}

local function configureHighlight()
    highlight.color = colorMapping[userState.highlightColor]
    highlight.outline = outlineMapping[userState.highlightColor]

    if userState.highlightColor == ColorScheme.Shimmer then
        shimmer.state = 1
        shimmer.reverse = false
        highlight.outline = shimmer.steps[shimmer.state]
    end
end

local function applyHighlightEffect(target, enabled)
    local effect = entRenderHighlightEvent.new({
        seeThroughWalls = true,
        outlineIndex = enabled and highlight.outline or 0,
        opacity = 1.0
    })

    if IsDefined(target.entity) then
        return inspectionSystem:ApplyHighlightEffect(target.entity, effect)
    end

    if IsDefined(target.nodeInstance) then
        return inspectionSystem:ApplyHighlightEffect(target.nodeInstance, effect)
    end

    return false
end

local function enableHighlight(target)
    local isOutlineActive = false
    if userState.outlineMode == OutlineMode.ForSupportedObjects then
        isOutlineActive = applyHighlightEffect(target, true)

        if isOutlineActive and userState.highlightColor == ColorScheme.Shimmer then
            if shimmer.tick == shimmer.delay then
                if shimmer.reverse then
                    shimmer.state = shimmer.state - 1
                    if shimmer.state == 1 then
                        shimmer.reverse = false
                    end
                else
                    shimmer.state = shimmer.state + 1
                    if shimmer.state == #shimmer.steps then
                        shimmer.reverse = true
                    end
                end
                shimmer.tick = 1
            else
                shimmer.tick = shimmer.tick + 1
            end

            highlight.outline = shimmer.steps[shimmer.state]
        end
    end

    local showMarker = false
    if userState.markerMode == MarkerMode.Always then
        showMarker = true
    elseif userState.markerMode == MarkerMode.WhenOutlineIsUnsupported and not isOutlineActive then
        showMarker = true
    end

    local showBoundindBox = false
    if userState.boundingBoxMode == BoundingBoxMode.ForAreaNodes and target.isAreaNode then
        showBoundindBox = true
    end

    if showMarker or showBoundindBox then
        highlight.projections[target.hash] = {
            target = target,
            color = highlight.color,
            position = showMarker,
            bounds = showBoundindBox,
        }
    else
        highlight.projections[target.hash] = nil
    end
end

local function disableHighlight(target)
    applyHighlightEffect(target, false)
    highlight.projections[target.hash] = nil
end

local function highlightTarget(target)
    highlight.pending = target
end

local function updateHighlights()
    if not highlight.pending then
        if highlight.target then
            disableHighlight(highlight.target)
            highlight.target = nil
        end
        return
    end

    if highlight.target then
        if highlight.target.hash ~= highlight.pending.hash then
            disableHighlight(highlight.target)
        end
    end

    highlight.target = highlight.pending
    highlight.pending = nil

    enableHighlight(highlight.target)
end

-- App :: Resolving --

local function resolveComponents(entity)
    local components = {}

    for _, component in ipairs(inspectionSystem:GetComponents(entity)) do
        local data = {
            componentName = component:GetName().value,
            componentType = component:GetClassName().value,
            meshPath = '',
            morphPath = '',
            meshAppearance = '',
        }

        if component:IsA('entMeshComponent') or component:IsA('entSkinnedMeshComponent') then
            data.meshPath = inspectionSystem:ResolveResourcePath(component.mesh.hash)
            data.meshAppearance = component.meshAppearance.value

            if isEmpty(data.meshPath) then
                data.meshPath = ('%u'):format(component.mesh.hash)
            end
        end

        if component:IsA('entMorphTargetSkinnedMeshComponent') then
            data.morphPath = inspectionSystem:ResolveResourcePath(component.morphResource.hash)
            data.meshAppearance = component.meshAppearance.value

            if isEmpty(data.morphPath) then
                data.morphPath = ('%u'):format(component.morphResource.hash)
            end
        end

        local description = { data.componentType, data.componentName }
        data.description = table.concat(description, ' | ')

        data.hash = inspectionSystem:GetObjectHash(component)

        table.insert(components, data)
    end

    return components
end

local function fillTargetEntityData(target, data)
    if IsDefined(target.entity) then
        local entity = target.entity
        data.entityID = entity:GetEntityID().hash
        data.entityType = entity:GetClassName().value

        local templatePath = inspectionSystem:GetTemplatePath(entity)
        data.templatePath = inspectionSystem:ResolveResourcePath(templatePath.hash)
        data.appearanceName = entity:GetCurrentAppearanceName().value
        if isEmpty(data.templatePath) and isNotEmpty(templatePath.hash) then
            data.templatePath = ('%u'):format(templatePath.hash)
        end

        if entity:IsA('gameObject') then
            local recordID = entity:GetTDBID()
            if TDBID.IsValid(recordID) then
                data.recordID = TDBID.ToStringDEBUG(recordID)
            end
        end

        data.components = resolveComponents(entity)
        data.hasComponents = (#data.components > 0)
    end

    data.entity = target.entity
    data.isEntity = IsDefined(data.entity)
end

local function fillTargetNodeData(target, data)
    local sectorData
    if IsDefined(target.nodeInstance) then
        sectorData = inspectionSystem:ResolveSectorDataFromNodeInstance(target.nodeInstance)
    elseif isNotEmpty(target.nodeID) then
        sectorData = inspectionSystem:ResolveSectorDataFromNodeID(target.nodeID)
    end
    if sectorData and sectorData.sectorHash ~= 0 then
        data.sectorPath = inspectionSystem:ResolveResourcePath(sectorData.sectorHash)
        data.instanceIndex = sectorData.instanceIndex
        data.instanceCount = sectorData.instanceCount
        data.nodeIndex = sectorData.nodeIndex
        data.nodeCount = sectorData.nodeCount
        data.nodeID = sectorData.nodeID
        data.nodeType = sectorData.nodeType.value
    end

    if IsDefined(target.nodeDefinition) then
        local node = target.nodeDefinition
        data.nodeType = inspectionSystem:GetTypeName(node).value

        if inspectionSystem:IsInstanceOf(node, 'worldMeshNode')
        or inspectionSystem:IsInstanceOf(node, 'worldInstancedMeshNode')
        or inspectionSystem:IsInstanceOf(node, 'worldBendedMeshNode')
        or inspectionSystem:IsInstanceOf(node, 'worldFoliageNode')
        or inspectionSystem:IsInstanceOf(node, 'worldPhysicalDestructionNode') then
            data.meshPath = inspectionSystem:ResolveResourcePath(node.mesh.hash)
            data.meshAppearance = node.meshAppearance.value
        end

        if inspectionSystem:IsInstanceOf(node, 'worldTerrainMeshNode') then
            data.meshPath = inspectionSystem:ResolveResourcePath(node.meshRef.hash)
        end

        if inspectionSystem:IsInstanceOf(node, 'worldStaticDecalNode') then
            data.materialPath = inspectionSystem:ResolveResourcePath(node.material.hash)
        end

        if inspectionSystem:IsInstanceOf(node, 'worldEffectNode') then
            data.effectPath = inspectionSystem:ResolveResourcePath(node.effect.hash)
        end

        if inspectionSystem:IsInstanceOf(node, 'worldPopulationSpawnerNode') then
            data.recordID = node.objectRecordId.value
            data.appearanceName = node.appearanceName.value
        end

        if inspectionSystem:IsInstanceOf(node, 'worldEntityNode') then
            data.templatePath = inspectionSystem:ResolveResourcePath(node.entityTemplate.hash)
            data.appearanceName = node.appearanceName.value
        end

        if inspectionSystem:IsInstanceOf(node, 'worldDeviceNode') then
            data.deviceClass = node.deviceClassName.value
        end
    end

    if isNotEmpty(data.nodeID) then
        data.nodeRef = inspectionSystem:ResolveNodeRefFromNodeHash(data.nodeID)
    elseif isNotEmpty(target.nodeID) then
        data.nodeRef = inspectionSystem:ResolveNodeRefFromNodeHash(target.nodeID)
    end

    data.nodeDefinition = target.nodeDefinition
    data.nodeInstance = target.nodeInstance

    data.isNode = IsDefined(data.nodeInstance) or IsDefined(data.nodeDefinition) or isNotEmpty(data.nodeID)
    data.isAreaNode = data.isNode and inspectionSystem:IsInstanceOf(data.nodeDefinition, 'worldAreaShapeNode')
    data.isEntityNode = data.isNode and inspectionSystem:IsInstanceOf(data.nodeDefinition, 'worldEntityNode')
    data.isVisibleNode = data.isNode and isNotEmpty(data.meshPath) or isNotEmpty(data.materialPath) or isNotEmpty(data.templatePath)
end

local function fillTargetDescription(_, data)
    if isNotEmpty(data.nodeType) then
        local description = { data.nodeType }
        if isNotEmpty(data.meshPath) then
            local resourceName = data.meshPath:match('\\([^\\]+)$')
            table.insert(description, resourceName)
        elseif isNotEmpty(data.materialPath) then
            local resourceName = data.materialPath:match('\\([^\\]+)$')
            table.insert(description, resourceName)
        elseif isNotEmpty(data.effectPath) then
            local resourceName = data.effectPath:match('\\([^\\]+)$')
            table.insert(description, resourceName)
        elseif isNotEmpty(data.templatePath) then
            local resourceName = data.templatePath:match('\\([^\\]+)$')
            table.insert(description, resourceName)
        elseif isNotEmpty(data.nodeRef) then
            local nodeAlias = data.nodeRef:match('(#?[^/]+)$')
            table.insert(description, nodeAlias)
        elseif isNotEmpty(data.recordID) then
            table.insert(description, data.recordID)
        elseif isNotEmpty(data.sectorPath) then
            local sectorName = data.sectorPath:match('\\([^\\.]+)%.')
            table.insert(description, sectorName)
            table.insert(description, data.nodeIndex)
        end
        data.description = table.concat(description, ' | ')
    elseif isNotEmpty(data.entityType) then
        data.description = ('%s | %d'):format(data.entityType, data.entityID)
    end
end

local function fillTargetHash(target, data)
    if isNotEmpty(target.hash) then
        data.hash = target.hash
    elseif IsDefined(target.nodeInstance) then
        data.hash = inspectionSystem:GetObjectHash(target.nodeInstance)
    elseif IsDefined(target.nodeDefinition) then
        data.hash = inspectionSystem:GetObjectHash(target.nodeDefinition)
    elseif IsDefined(target.entity) then
        data.hash = inspectionSystem:GetObjectHash(target.entity)
    end
end

local function expandTarget(target)
    if IsDefined(target.entity) and not IsDefined(target.nodeDefinition) then
        local entityID = target.entity:GetEntityID().hash
        local nodeID

        if entityID > 0xFFFFFF then
            nodeID = entityID
        else
            local communityID = inspectionSystem:ResolveCommunityIDFromEntityID(entityID)
            if communityID.hash > 0xFFFFFF then
                nodeID = communityID.hash
            end
        end

        if isNotEmpty(nodeID) then
            local streamingData = inspectionSystem:FindStreamedWorldNode(nodeID)
            target.nodeInstance = streamingData.nodeInstance
            target.nodeDefinition = streamingData.nodeDefinition
            target.nodeID = nodeID
        end
    end
end

local function resolveTargetData(target)
    expandTarget(target)
    local data = {}
    fillTargetEntityData(target, data)
    fillTargetNodeData(target, data)
    fillTargetDescription(target, data)
    fillTargetHash(target, data)
    return data
end

-- App :: Nodes --

local function toggleNodeVisibility(target)
    if target and IsDefined(target.nodeInstance) then
        inspectionSystem:ToggleNodeVisibility(target.nodeInstance)
    end
end

-- App :: Inspector --

local inspector = {
    target = nil,
    result = nil,
}

local function inspectTarget(target, collisionGroup, targetDistance)
    if not target or not target.resolved then
        inspector.target = nil
        inspector.result = nil
        return
    end

    if inspector.target then
        if inspector.target.hash == target.hash then
            inspector.result.targetDistance = targetDistance
            return
        end
    end

    local data = resolveTargetData(target)
    data.collisionGroup = collisionGroup.value
    data.targetDistance = targetDistance

    inspector.target = target
    inspector.result = data
end

local function initializeInspector()
    for _, collisionGroup in ipairs(collisionGroups) do
        collisionGroup.name = CName(collisionGroup.name)
    end
end

local function updateInspector()
    inspectTarget(getLookAtTarget())

    if userState.highlightInspectorResult then
        highlightTarget(inspector.result)
    end
end

-- App :: Lookup --

local lookup = {
    query = nil,
    result = nil,
    empty = true,
}

local function parseLookupHash(lookupQuery)
    local lookupHex = lookupQuery:match('^0x([0-9A-F]+)$') or lookupQuery:match('^([0-9A-F]+)$')
    if lookupHex ~= nil then
        return loadstring('return 0x' .. lookupHex .. 'ULL', '')()
    end

    local lookupDec = lookupQuery:match('^(%d+)ULL$') or lookupQuery:match('^(%d+)$')
    if lookupDec ~= nil then
        return loadstring('return ' .. lookupDec .. 'ULL', '')()
    end

    return nil
end

local function lookupTarget(lookupQuery)
    if isEmpty(lookupQuery) then
        lookup.query = nil
        lookup.result = nil
        return
    end

    if lookup.query == lookupQuery then
        return
    end

    local target = {}

    local lookupHash = parseLookupHash(lookupQuery)
    if lookupHash ~= nil then
        target.resourceHash = lookupHash
        target.tdbidHash = lookupHash
        target.nameHash = lookupHash

        local entity = Game.FindEntityByID(EntityID.new({ hash = lookupHash }))
        if IsDefined(entity) then
            target.entity = entity
        else
            local streamingData = inspectionSystem:FindStreamedWorldNode(lookupHash)
            if IsDefined(streamingData.nodeInstance) then
                target.nodeInstance = streamingData.nodeInstance
                target.nodeDefinition = streamingData.nodeDefinition
            else
                if lookupHash <= 0xFFFFFF then
                    local communityID = inspectionSystem:ResolveCommunityIDFromEntityID(lookupHash)
                    if communityID.hash > 0xFFFFFF then
                        streamingData = inspectionSystem:FindStreamedWorldNode(communityID.hash)
                        if IsDefined(streamingData.nodeInstance) then
                            target.nodeInstance = streamingData.nodeInstance
                            target.nodeDefinition = streamingData.nodeDefinition
                        else
                            target.nodeID = communityID.hash
                        end
                    end
                end
            end
        end
    else
        local resolvedRef = ResolveNodeRef(CreateEntityReference(lookupQuery, {}).reference, GlobalNodeID.GetRoot())
        if isNotEmpty(resolvedRef.hash) then
            local entity = Game.FindEntityByID(EntityID.new({ hash = resolvedRef.hash }))
            if IsDefined(entity) then
                target.entity = entity
            else
                local streamingData = inspectionSystem:FindStreamedWorldNode(resolvedRef.hash)
                target.nodeInstance = streamingData.nodeInstance
                target.nodeDefinition = streamingData.nodeDefinition
                target.nodeID = resolvedRef.hash
            end
        end
    end

    local data = resolveTargetData(target)

    if isNotEmpty(target.resourceHash) then
        data.resolvedPath = inspectionSystem:ResolveResourcePath(target.resourceHash)
    end

    if isNotEmpty(target.tdbidHash) then
		local length = math.floor(tonumber(target.tdbidHash / 0x100000000))
		local hash = tonumber(target.tdbidHash - (length * 0x100000000))
        local name = ToTweakDBID{ hash = hash, length = length }.value
        if name and not name:match('^<') then
            data.resolvedTDBID = name
        end
    end

    if isNotEmpty(target.nameHash) then
        local hi = tonumber(bit32.rshift(target.nameHash, 32))
        local lo = tonumber(bit32.band(target.nameHash, 0xFFFFFFFF))
        data.resolvedName = ToCName{ hash_hi = hi, hash_lo = lo }.value
    end

    lookup.result = data
    lookup.empty = isEmpty(data.entityID) and isEmpty(data.nodeID) and isEmpty(data.sectorPath)
        and isEmpty(data.resourcePath) and isEmpty(data.resolvedTDBID) and isEmpty(data.resolvedName)
    lookup.query = lookupQuery
end

local function updateLookup(lookupQuery)
    lookupTarget(lookupQuery)

    if userState.highlightLookupResult then
        highlightTarget(lookup.result)
    end
end

-- App :: Scanner --

local scanner = {
    requested = false,
    distance = 0,
    finished = false,
    results = {},
    filter = nil,
    filtered = {},
    hovered = nil,
}

local function resolveTargetPosition(camera, target)
    if not target.bounds.Min:IsXYZZero() then
        local distance = 0
        if not insideBox(camera.position, target.bounds) then
            distance = Vector4.DistanceToEdge(camera.position, target.bounds.Min, target.bounds.Max)
        end
        local position = Game['OperatorAdd;Vector4Vector4;Vector4'](target.bounds.Min, target.bounds:GetExtents())
        return position, target.bounds, distance
    end

    if not target.transform.position:IsXYZZero() then
        local distance = Vector4.Distance(camera.position, target.transform.position)
        return target.transform.position, nil, distance
    end

    return nil, nil, 0xFFFF
end

local function requestScan(maxDistance)
    scanner.distance = maxDistance
    scanner.requested = true
end

local function resetHoveredResult()
    scanner.hovered = nil
end

local function setHoveredResult(result)
    scanner.hovered = result
end

local function scanTargets()
    if not scanner.requested then
        return
    end

    scanner.requested = false

	local camera = getCameraData()

	if not camera then
        scanner.results = {}
        scanner.filter = nil
        scanner.filtered = {}
        scanner.hovered = nil
        scanner.finished = true
		return
	end

    local results = {}

    local allNodes = inspectionSystem:GetStreamedWorldNodesInFrustum()
    for _, target in ipairs(allNodes) do
        local position, bounds, distance = resolveTargetPosition(camera, target)
        if distance <= scanner.distance then
            local data = resolveTargetData(target)
            data.description = ('%s @ %.2fm'):format(data.description, distance)
            data.targetDistance = distance
            data.worldPosition = position
            data.worldBounds = bounds
            table.insert(results, data)
        end
    end

    table.sort(results, function(a, b)
        return a.targetDistance < b.targetDistance
    end)

    scanner.results = results
    scanner.filter = nil
    scanner.filtered = results
    scanner.hovered = nil
    scanner.finished = true
end

local function filterTargets(filter)
    if isEmpty(filter) then
        scanner.filtered = scanner.results
        scanner.filter = nil
        return
    end

    if scanner.filter == filter then
        return
    end

    local filtered = {}

    local filterExact = filter:upper()
    local filterEsc = filter:upper():gsub('([^%w])', '%%%1')
    local filterRe = filterEsc:gsub('%s+', '.* ') .. '.*'

    local partialMatchFields = {
        'nodeType',
        'nodeRef',
        'sectorPath',
        'meshPath',
        'materialPath',
        'effectPath',
        'templatePath',
        'recordID',
    }

    local exactMatchFields = {
        'instanceIndex',
    }

    for _, result in ipairs(scanner.results) do
        local match = false
        for _, field in ipairs(exactMatchFields) do
            if isNotEmpty(result[field]) then
                local value = tostring(result[field]):upper()
                if value == filterExact then
                    table.insert(filtered, result)
                    match = true
                    break
                end
            end
        end
        if not match then
            for _, field in ipairs(partialMatchFields) do
                if isNotEmpty(result[field]) then
                    local value = result[field]:upper()
                    if value:find(filterEsc) or value:find(filterRe) then
                        table.insert(filtered, result)
                        break
                    end
                end
            end
        end
    end

    scanner.filter = filter
    scanner.filtered = filtered
end

local function updateScanner(filter)
    scanTargets()
    filterTargets(filter)

    if userState.highlightScannerResult then
        highlightTarget(scanner.hovered)
    end
end

-- App :: Watcher --

local watcher = {
    targets = {},
    results = {},
    numTargets = 0,
}

local function watchTarget(entity)
    if not IsDefined(entity) then
        return
    end

    local key = tostring(entity:GetEntityID().hash)
    local target = { entity = Ref.Weak(entity) }

    watcher.targets[key] = target
    watcher.results[key] = resolveTargetData(target)
    watcher.numTargets = watcher.numTargets + 1
end

local function forgetTarget(entity)
    if not IsDefined(entity) then
        return
    end

    local key = tostring(entity:GetEntityID().hash)

    watcher.targets[key] = nil
    watcher.results[key] = nil
    watcher.numTargets = watcher.numTargets - 1

    collectgarbage()
end

local function initializeWatcher()
    watchTarget(GetPlayer())

    ObserveAfter('PlayerPuppet', 'OnGameAttached', function(this)
        watchTarget(this)
    end)

    ObserveAfter('PlayerPuppet', 'OnDetach', function(this)
        forgetTarget(this)
    end)

    ObserveBefore('gameuiPuppetPreviewGameController', 'OnPreviewInitialized', function(this)
        watchTarget(this:GetGamePuppet())
    end)

    ObserveBefore('gameuiPuppetPreviewGameController', 'OnUninitialize', function(this)
        if this:IsA('gameuiPuppetPreviewGameController') then
            forgetTarget(this:GetGamePuppet())
        end
    end)

    ObserveAfter('PhotoModePlayerEntityComponent', 'SetupInventory', function(this)
        watchTarget(this.fakePuppet)
    end)

    ObserveBefore('PhotoModePlayerEntityComponent', 'ClearInventory', function(this)
        forgetTarget(this.fakePuppet)
    end)
end

local function updateWatcher()
    for key, target in pairs(watcher.targets) do
        watcher.results[key] = resolveTargetData(target)
    end
end

-- GUI --

local viewState = {
    isFirstOpen = true,
    isConsoleOpen = false,
    scannerFilter = '',
    lookupQuery = '',
}

local viewData = {
    maxInputLen = 256,
}

local viewStyle = {
    labelTextColor = 0xFFA5A19B, -- #9F9F9F
    mutedTextColor = 0xFFA5A19B,
    dangerTextColor = 0xFF6666FF,
    disabledButtonColor = 0xFF4F4F4F,
}

local function buildComboOptions(values)
    local options = {}
    for index, value in ipairs(values) do
        options[index] = value:gsub('([a-z])([A-Z])', function(l, u)
            return l .. ' ' .. u:lower()
        end)
    end
    return options
end

local function initializeViewData()
    viewData.colorSchemeOptions = buildComboOptions(ColorScheme.values)
    viewData.outlineModeOptions = buildComboOptions(OutlineMode.values)
    viewData.markerModeOptions = buildComboOptions(MarkerMode.values)
    viewData.boundingBoxModeOptions = buildComboOptions(BoundingBoxMode.values)
end

local function initializeViewStyle()
    if not viewStyle.fontSize then
        viewStyle.fontSize = ImGui.GetFontSize()
        viewStyle.viewScale = viewStyle.fontSize / 13

        viewStyle.windowWidth = 400 * viewStyle.viewScale
        viewStyle.windowHeight = 0

        viewStyle.windowPaddingX = 8 * viewStyle.viewScale
        viewStyle.windowPaddingY = viewStyle.windowPaddingX

        viewStyle.windowX = GetDisplayResolution() - viewStyle.windowWidth - viewStyle.windowPaddingX * 2 - 5
        viewStyle.windowY = 5

        viewStyle.mainWindowFlags = ImGuiWindowFlags.NoResize
            + ImGuiWindowFlags.NoScrollbar + ImGuiWindowFlags.NoScrollWithMouse
        viewStyle.overlayWindowFlags = viewStyle.mainWindowFlags
            + ImGuiWindowFlags.NoTitleBar + ImGuiWindowFlags.NoCollapse
            + ImGuiWindowFlags.NoInputs + ImGuiWindowFlags.NoNav
        viewStyle.projectionWindowFlags = ImGuiWindowFlags.NoSavedSettings
            + ImGuiWindowFlags.NoInputs + ImGuiWindowFlags.NoNav
            + ImGuiWindowFlags.NoResize + ImGuiWindowFlags.NoMove
            + ImGuiWindowFlags.NoDecoration + ImGuiWindowFlags.NoBackground
            + ImGuiWindowFlags.NoFocusOnAppearing + ImGuiWindowFlags.NoBringToFrontOnFocus

        viewStyle.buttonHeight = 21 * viewStyle.viewScale

        viewStyle.scannerDistanceWidth = 110 * viewStyle.viewScale
        viewStyle.scannerFilterWidth = 170 * viewStyle.viewScale
        viewStyle.scannerStatsWidth = ImGui.CalcTextSize('000 / 000') * viewStyle.viewScale

        viewStyle.settingsShortComboRowWidth = 160 * viewStyle.viewScale
        viewStyle.settingsLongComboRowWidth = 240 * viewStyle.viewScale
    end
end

-- GUI :: Utils --

local function sanitizeTextInput(value)
    return value:gsub('`', '')
end

-- GUI :: Extensions --

local extensions = {}

local function registerExtension(plugin)
    if type(plugin.getTargetActions) ~= 'function' then
        return false
    end

    table.insert(extensions, plugin)
    return true
end

-- GUI :: Actions --

local function getTargetActions(target, isInputMode)
    local actions = {}

    if isInputMode then
        if IsDefined(target.nodeInstance) and target.isVisibleNode then
            table.insert(actions, {
                type = 'button',
                label = 'Toggle node',
                callback = toggleNodeVisibility,
            })
        end
    end

    for _, plugin in ipairs(extensions) do
        local result = plugin.getTargetActions(target)
        if type(result) == 'table' then
            if #result == 0 then
                result = { result }
            end
            for _, action in ipairs(result) do
                if isNotEmpty(action.label) and type(action.callback) == 'function' then
                    if action.type == nil then
                        action.type = 'button'
                    end
                    if isInputMode or action.type ~= 'button' then
                        table.insert(actions, action)
                    end
                end
            end
        end
    end

    return actions
end

-- GUI :: Fieldsets --

local function formatDistance(data)
    return ('%.2fm'):format(type(data) == 'number' and data or data.targetDistance)
end

local function useInlineDistance(data)
    return isNotEmpty(data.collisionGroup) and '@'
end

--local function isValidNodeIndex(data)
--    return type(data.nodeIndex) == 'number' and data.nodeIndex >= 0
--        and type(data.nodeCount) == 'number' and data.nodeCount > 0
--end

local function isValidInstanceIndex(data)
    return type(data.instanceIndex) == 'number' and data.instanceIndex >= 0
        and type(data.instanceCount) == 'number' and data.instanceCount > 0
end

local objectSchema = {
    {
        { name = 'collisionGroup', label = 'Collision:' },
        { name = 'targetDistance', label = 'Distance:', format = formatDistance, inline = useInlineDistance },
    },
    {
        { name = 'nodeType', label = 'Node Type:' },
        { name = 'nodeID', label = 'Node ID:', format = '%u' },
        { name = 'nodeRef', label = 'Node Ref:', wrap = true },
        --{ name = 'nodeIndex', label = 'Node Index:', format = '%d', validate = isValidNodeIndex },
        --{ name = 'nodeCount', label = '/', format = '%d', inline = true, validate = isValidNodeIndex },
        { name = 'instanceIndex', label = 'Node Instance:', format = '%d', validate = isValidInstanceIndex },
        { name = 'instanceCount', label = '/', format = '%d', inline = true, validate = isValidInstanceIndex },
        { name = 'sectorPath', label = 'World Sector:', wrap = true },
    },
    {
        { name = 'entityType', label = 'Entity Type:' },
        { name = 'entityID', label = 'Entity ID:', format = '%u' },
        { name = 'recordID', label = 'Record ID:' },
        { name = 'templatePath', label = 'Entity Template:', wrap = true },
        { name = 'appearanceName', label = 'Entity Appearance:' },
        { name = 'deviceClass', label = 'Device Class:' },
        { name = 'meshPath', label = 'Mesh Resource:', wrap = true },
        { name = 'meshAppearance', label = 'Mesh Appearance:' },
        { name = 'materialPath', label = 'Material:', wrap = true },
        { name = 'effectPath', label = 'Effect:', wrap = true },
    },
    {
        { name = 'resolvedPath', label = 'Resource:', wrap = true },
        { name = 'resolvedName', label = 'CName:' },
        { name = 'resolvedTDBID', label = 'TweakDBID:' },
    }
}

local componentSchema = {
    { name = 'componentType', label = 'Component Type:' },
    { name = 'componentName', label = 'Component Name:' },
    { name = 'meshPath', label = 'Mesh Resource:', wrap = true },
    { name = 'morphPath', label = 'Morph Target:', wrap = true },
    { name = 'meshAppearance', label = 'Mesh Appearance:' },
}

local function isVisibleField(field, data)
    if type(field.validate) == 'function' then
        if not field.validate(data, field) then
            return false
        end
    else
        if isEmpty(data[field.name]) then
            return false
        end
    end
    return true
end

local function drawField(field, data)
    local label = field.label
    if field.inline then
        if type(field.inline) == 'function' then
            local inline = field.inline(data, field)
            if inline then
                ImGui.SameLine()
                if type(inline) == 'string' then
                    label = inline
                end
            end
        else
            ImGui.SameLine()
        end
    end

    ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.labelTextColor)
    ImGui.Text(label)
    ImGui.PopStyleColor()

    local value = data[field.name]
    if field.format then
        if type(field.format) == 'function' then
            value = field.format(data, field)
        elseif type(field.format) == 'string' then
            value = (field.format):format(value)
        end
    else
        value = tostring(value)
    end

    ImGui.SameLine()
    if field.wrap then
        ImGui.TextWrapped(value)
    else
        ImGui.Text(value)
    end

    if ImGui.IsItemClicked(ImGuiMouseButton.Middle) then
        ImGui.SetClipboardText(value)
    end
end

local function drawComponents(components, maxComponents)
    if maxComponents == nil then
        maxComponents = 10
    end

    if maxComponents > 0 then
        local visibleComponents = maxComponents
        ImGui.BeginChildFrame(1, 0, visibleComponents * ImGui.GetFrameHeightWithSpacing())
    end

    for _, componentData in ipairs(components) do
        local componentID = tostring(componentData.hash)
        if ImGui.TreeNodeEx(componentData.description .. '##' .. componentID, ImGuiTreeNodeFlags.SpanFullWidth) then
            for _, field in ipairs(componentSchema) do
                if isVisibleField(field, componentData) then
                    drawField(field, componentData)
                end
            end
            ImGui.TreePop()
        end
    end

    if maxComponents > 0 then
        ImGui.EndChildFrame()
    end
end

local function drawFieldset(targetData, withInputs, maxComponents, withSeparators)
    if withInputs == nil then
        withInputs = true
    end

    if maxComponents == nil then
        maxComponents = 10
    end

    if withSeparators == nil then
        withSeparators = true
    end

    ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
    ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

    local isFirstGroup = true
    for _, groupSchema in ipairs(objectSchema) do
        local isFirstField = true
        for _, field in ipairs(groupSchema) do
            if isVisibleField(field, targetData) then
                if isFirstField then
                    isFirstField = false
                    if isFirstGroup then
                        isFirstGroup = false
                    elseif withSeparators then
                        ImGui.Spacing()
                        ImGui.Separator()
                        ImGui.Spacing()
                    end
                end
                drawField(field, targetData)
            end
        end
    end

    if targetData.hasComponents and withInputs then
        if withSeparators then
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()
        end
        if ImGui.TreeNodeEx(('Components (%d)##Components'):format(#targetData.components), ImGuiTreeNodeFlags.SpanFullWidth) then
            drawComponents(targetData.components, maxComponents)
            ImGui.TreePop()
        end
        --ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.labelTextColor)
        --ImGui.Text(('Components (%d)'):format(#targetData.components))
        --ImGui.PopStyleColor()
    end

    ImGui.PopStyleColor()
    ImGui.PopStyleVar(2)

    local actions = getTargetActions(targetData, withInputs)
    if #actions > 0 then
        if withSeparators then
            ImGui.Spacing()
            ImGui.Separator()
        end
        ImGui.Spacing()
        for _, action in ipairs(actions) do
            if action.type == 'button' then
                if action.inline then
                    ImGui.SameLine()
                end
                if ImGui.Button(action.label) then
                    action.callback(targetData)
                end
            elseif action.type == 'checkbox' then
                if action.inline then
                    ImGui.SameLine()
                end
                local _, pressed = ImGui.Checkbox(action.label, action.state)
                if pressed then
                    action.callback(targetData)
                end
            end
        end
    end
end

-- GUI :: Inspector --

local function drawInspectorContent(withInputs)
    if inspector.target and inspector.result then
        drawFieldset(inspector.result, withInputs)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
        ImGui.TextWrapped('No target')
        ImGui.PopStyleColor()
    end
end

-- GUI :: Scanner --

local function drawScannerContent()
    ImGui.TextWrapped('Search for non-collision, hidden and unreachable world nodes.')
    ImGui.Spacing()
    ImGui.AlignTextToFramePadding()
    ImGui.Text('Scanning depth:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(viewStyle.scannerDistanceWidth)
    local distance, distanceChanged = ImGui.InputFloat('##ScannerDistance', userState.scannerDistance, 0.5, 1.0, '%.1fm', ImGuiInputTextFlags.None)
    if distanceChanged then
        userState.scannerDistance = clamp(distance, 0.5, 100.0)
    end
    ImGui.Spacing()

    if ImGui.Button('Scan world nodes', viewStyle.windowWidth, viewStyle.buttonHeight) then
        requestScan(userState.scannerDistance)
    end

    if scanner.finished then
        if not userState.keepLastHoveredResultHighlighted then
            resetHoveredResult()
        end

        ImGui.Spacing()
        if #scanner.results > 0 then
            ImGui.Separator()
            ImGui.Spacing()

            ImGui.AlignTextToFramePadding()
            ImGui.Text('Filter results:')
            ImGui.SameLine()
            ImGui.SetNextItemWidth(viewStyle.scannerFilterWidth)
            local filter, filterChanged = ImGui.InputTextWithHint('##ScannerFilter', 'Node type or reference or resource', viewState.scannerFilter, viewData.maxInputLen)
            if filterChanged then
                viewState.scannerFilter = sanitizeTextInput(filter)
            end

            ImGui.SameLine()
            ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
            ImGui.SetNextItemWidth(viewStyle.scannerStatsWidth)
            ImGui.Text(('%d / %d'):format(#scanner.filtered, #scanner.results))
            ImGui.PopStyleColor()
            ImGui.SameLine()
            local expandlAll = ImGui.Button('Expand all')
            ImGui.SameLine()
            local collapseAll = ImGui.Button('Collapse all')
            ImGui.Spacing()

            if #scanner.filtered > 0 then
                ImGui.PushStyleVar(ImGuiStyleVar.IndentSpacing, 0)
                ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
                ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
                ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

                local visibleRows = clamp(#scanner.filtered, 14, 18)
                ImGui.BeginChildFrame(1, 0, visibleRows * ImGui.GetFrameHeightWithSpacing())

                for _, result in ipairs(scanner.filtered) do
                    ImGui.BeginGroup()
                    if expandlAll then
                        ImGui.SetNextItemOpen(true)
                    elseif collapseAll then
                        ImGui.SetNextItemOpen(false)
                    end
                    local resultID = tostring(result.hash)
                    if ImGui.TreeNodeEx(result.description .. '##' .. resultID, ImGuiTreeNodeFlags.SpanFullWidth) then
                        ImGui.PopStyleColor()
                        ImGui.PopStyleVar()
                        drawFieldset(result, true, -1, false)
                        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
                        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)
                        ImGui.TreePop()
                    end
                    ImGui.EndGroup()
                    if ImGui.IsItemHovered() then
                        setHoveredResult(result)
                    end
                end

                ImGui.EndChildFrame()
                ImGui.PopStyleColor()
                ImGui.PopStyleVar(3)
            else
                ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
                ImGui.TextWrapped('No matches')
                ImGui.PopStyleColor()
            end
        else
            ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
            ImGui.TextWrapped('Nothing found')
            ImGui.PopStyleColor()
        end
    end
end

-- GUI :: Lookup --

local function drawLookupContent()
    ImGui.TextWrapped('Lookup world nodes and spawned entities by their identities.')
    ImGui.Spacing()
    ImGui.SetNextItemWidth(viewStyle.windowWidth)
    local query, queryChanged = ImGui.InputTextWithHint('##LookupQuery', 'Enter node reference or entity id or hash', viewState.lookupQuery, viewData.maxInputLen)
    if queryChanged then
        viewState.lookupQuery = sanitizeTextInput(query)
    end

    if lookup.result then
        if not lookup.empty then
            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()
            drawFieldset(lookup.result)
        else
            ImGui.Spacing()
            ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
            ImGui.TextWrapped('Nothing found')
            ImGui.PopStyleColor()
        end
    end
end

-- GUI :: Watcher --

local function drawWatcherContent()
    ImGui.TextWrapped('Watch all player related entities.')

    if watcher.numTargets > 0 then
        ImGui.Spacing()
        ImGui.Separator()
        ImGui.Spacing()

        ImGui.PushStyleVar(ImGuiStyleVar.FrameBorderSize, 0)
        ImGui.PushStyleVar(ImGuiStyleVar.FramePadding, 0, 0)
        ImGui.PushStyleColor(ImGuiCol.FrameBg, 0)

        local visibleRows = clamp(watcher.numTargets, 12, 16)
        ImGui.BeginChildFrame(1, 0, visibleRows * ImGui.GetFrameHeightWithSpacing())

        for _, result in pairs(watcher.results) do
            if ImGui.TreeNodeEx(result.description, ImGuiTreeNodeFlags.SpanFullWidth) then
                drawFieldset(result, true, 0, false)
                ImGui.TreePop()
            end
        end

        ImGui.EndChildFrame()
        ImGui.PopStyleColor()
        ImGui.PopStyleVar(2)
    else
        ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
        ImGui.TextWrapped('No entities to watch')
        ImGui.PopStyleColor()
    end
end

-- GUI :: Settings --

local function drawSettingsContent()
    local state, changed

    ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
    ImGui.SetWindowFontScale(0.85)
    ImGui.Text('TARGET HIGHLIGHTING')
    ImGui.SetWindowFontScale(1.0)
    ImGui.PopStyleColor()
    ImGui.Separator()
    ImGui.Spacing()

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
    ImGui.Text('Highlight color:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(viewStyle.settingsShortComboRowWidth - ImGui.GetCursorPosX())
    state, changed = ImGui.Combo('##HighlightColor', ColorScheme.values[userState.highlightColor] - 1, viewData.colorSchemeOptions, #viewData.colorSchemeOptions)
    if changed then
        userState.highlightColor = ColorScheme.values[state + 1]
        configureHighlight()
    end
    ImGui.EndGroup()

    ImGui.Spacing()

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
    ImGui.Text('Show outline:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(viewStyle.settingsLongComboRowWidth - ImGui.GetCursorPosX())
    state, changed = ImGui.Combo('##OutlineMode', OutlineMode.values[userState.outlineMode] - 1, viewData.outlineModeOptions, #viewData.outlineModeOptions)
    if changed then
        userState.outlineMode = OutlineMode.values[state + 1]
    end
    ImGui.EndGroup()

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
    ImGui.Text('Show marker:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(viewStyle.settingsLongComboRowWidth - ImGui.GetCursorPosX())
    state, changed = ImGui.Combo('##MarkerMode', MarkerMode.values[userState.markerMode] - 1, viewData.markerModeOptions, #viewData.markerModeOptions)
    if markerModeChanged then
        userState.markerMode = MarkerMode.values[state + 1]
    end
    ImGui.EndGroup()
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'Shows marker at the center of a mesh or area,\n' ..
            'or at the world position of a shapeless node.')
    end

    ImGui.BeginGroup()
    ImGui.AlignTextToFramePadding()
    ImGui.Text('Show bounding box:')
    ImGui.SameLine()
    ImGui.SetNextItemWidth(viewStyle.settingsLongComboRowWidth - ImGui.GetCursorPosX())
    state, changed = ImGui.Combo('##BoundingBoxMode', BoundingBoxMode.values[userState.boundingBoxMode] - 1, viewData.boundingBoxModeOptions, #viewData.boundingBoxModeOptions)
    if changed then
        userState.boundingBoxMode = BoundingBoxMode.values[state + 1]
    end
    ImGui.EndGroup()
    if ImGui.IsItemHovered() then
        ImGui.SetTooltip(
            'The bounding box may differ from the actual shape of the area,\n' ..
            'but helps to understand its general location and boundaries.')
    end

    ImGui.Spacing()

    state, changed = ImGui.Checkbox('Show distance to the marker', userState.showMarkerDistance)
    if changed then
        userState.showMarkerDistance = state
    end

    state, changed = ImGui.Checkbox('Show distances to the corners of bounding box', userState.showBoundingBoxDistances)
    if changed then
        userState.showBoundingBoxDistances = state
    end

    ImGui.Spacing()

    state, changed = ImGui.Checkbox('Highlight inspected target', userState.highlightInspectorResult)
    if changed then
        userState.highlightInspectorResult = state
    end

    state, changed = ImGui.Checkbox('Highlight scanned target when hover over', userState.highlightScannerResult)
    if changed then
        userState.highlightScannerResult = state
    end

    ImGui.Indent(ImGui.GetFrameHeightWithSpacing())
    if not userState.highlightScannerResult then
        ImGui.BeginDisabled()
    end
    state, changed = ImGui.Checkbox('Keep last target highlighted when hover out', userState.keepLastHoveredResultHighlighted)
    if changed then
        userState.keepLastHoveredResultHighlighted = state
    end
    if not userState.highlightScannerResult then
        ImGui.EndDisabled()
    end
    ImGui.Unindent(ImGui.GetFrameHeightWithSpacing())

    state, changed = ImGui.Checkbox('Highlight lookup target', userState.highlightLookupResult)
    if changed then
        userState.highlightLookupResult = state
    end
end

-- GUI :: Drawing --

local function getScreenDescriptor(camera)
    local screen = {}
    screen.width, screen.height = GetDisplayResolution()

    screen.centerX = screen.width / 2
    screen.centerY = screen.height / 2

    screen[1] = { x = 0, y = 0 }
    screen[2] = { x = screen.width - 1, y = 0 }
    screen[3] = { x = screen.width - 1, y = screen.height - 1 }
    screen[4] = { x = 0, y = screen.height }

    screen.camera = camera

    return screen
end

local function getScreenPoint(screen, point)
    local projected = inspectionSystem:ProjectWorldPoint(point)

    local result = {
        x = projected.x,
        y = -projected.y,
        off = projected.w <= 0.0 or projected.z <= 0.0,
    }

    if projected.w > 0.0 then
        result.x = result.x / projected.w
        result.y = result.y / projected.w
    end

    result.x = screen.centerX + (result.x * screen.centerX)
    result.y = screen.centerY + (result.y * screen.centerY)

    return result
end

local function getScreenShape(screen, shape)
    local projected = {}
    for i = 1,#shape do
        projected[i] = getScreenPoint(screen, shape[i])
    end
    return projected
end

local function isOffScreenPoint(point)
    return point.off
end

local function isOffScreenShape(points)
    for _, point in ipairs(points) do
        if not isOffScreenPoint(point) then
            return false
        end
    end
    return true
end

local function drawPoint(point, color, radius, thickness)
    if thickness == nil then
        ImGui.ImDrawListAddCircleFilled(ImGui.GetWindowDrawList(), point.x, point.y, radius, color, -1)
    else
        ImGui.ImDrawListAddCircle(ImGui.GetWindowDrawList(), point.x, point.y, radius, color, -1, thickness)
    end
end

local function drawLine(line, color, thickness)
    ImGui.ImDrawListAddLine(ImGui.GetWindowDrawList(),
        line[1].x, line[1].y,
        line[2].x, line[2].y,
        color, thickness or 1)
end

local function drawQuad(quad, color, thickness)
    if thickness == nil then
        ImGui.ImDrawListAddQuadFilled(ImGui.GetWindowDrawList(),
            quad[1].x, quad[1].y,
            quad[2].x, quad[2].y,
            quad[3].x, quad[3].y,
            quad[4].x, quad[4].y,
            color)
    else
        ImGui.ImDrawListAddQuad(ImGui.GetWindowDrawList(),
            quad[1].x, quad[1].y,
            quad[2].x, quad[2].y,
            quad[3].x, quad[3].y,
            quad[4].x, quad[4].y,
            color, thickness)
    end
end

local function drawText(position, color, size, text)
    ImGui.ImDrawListAddText(ImGui.GetWindowDrawList(), size, position.x, position.y, color, tostring(text))
end

local function drawProjectedPoint(screen, point, color, radius, thickness)
    local projected = getScreenPoint(screen, point)
    if not isOffScreenPoint(projected) then
        drawPoint(projected, color, radius, thickness)
    end
end

local function drawProjectedLine(screen, line, color, thickness)
    local projected = getScreenShape(screen, line)
    if not isOffScreenShape(projected) then
        drawLine(projected, color, thickness)
    end
end

local function drawProjectedQuad(screen, quad, color, thickness)
    local projected = getScreenShape(screen, quad)
    if not isOffScreenShape(projected) then
        drawQuad(projected, color, thickness)
    end
end

local function drawProjectedText(screen, position, color, size, text)
    local projected = getScreenPoint(screen, position)
    if not isOffScreenPoint(projected) then
        drawText(projected, color, size, text)
    end
end

local function drawProjectedDistance(screen, position, offsetX, offsetY, fontSize, textColor)
    local projected = getScreenPoint(screen, position)
    if not isOffScreenPoint(projected) then
        local distance = Vector4.Distance(screen.camera.position, position)
        local formattedDistance = formatDistance(distance)
        local textWidth, textHeight = ImGui.CalcTextSize(formattedDistance)
        local fontRatio = fontSize / viewStyle.fontSize

        if type(offsetX) == 'number' then
            projected.x = projected.x + offsetX
        else
            projected.x = projected.x - (textWidth * fontRatio / 2.0)
        end

        if type(offsetY) == 'number' then
            projected.y = projected.y + offsetY
        else
            projected.y = projected.y - (textHeight * fontRatio / 2.0)
        end

        drawText(projected, textColor, fontSize, formattedDistance)
    end
end

local function drawProjectedMarker(screen, position, outerColor, innerColor, distanceColor)
    drawProjectedPoint(screen, position, outerColor, 10, 2)
    drawProjectedPoint(screen, position, innerColor, 5)

    if userState.showMarkerDistance then
        drawProjectedDistance(screen, position, true, -30, viewStyle.fontSize, distanceColor)
    end
end

local function drawProjectedBox(screen, box, faceColor, edgeColor, verticeColor, frame, fill, fadeWithDistance)
    local vertices = {
        ToVector4{ x = box.Min.x, y = box.Min.y, z = box.Min.z, w = 1.0 },
        ToVector4{ x = box.Min.x, y = box.Min.y, z = box.Max.z, w = 1.0 },
        ToVector4{ x = box.Min.x, y = box.Max.y, z = box.Min.z, w = 1.0 },
        ToVector4{ x = box.Min.x, y = box.Max.y, z = box.Max.z, w = 1.0 },
        ToVector4{ x = box.Max.x, y = box.Min.y, z = box.Min.z, w = 1.0 },
        ToVector4{ x = box.Max.x, y = box.Min.y, z = box.Max.z, w = 1.0 },
        ToVector4{ x = box.Max.x, y = box.Max.y, z = box.Min.z, w = 1.0 },
        ToVector4{ x = box.Max.x, y = box.Max.y, z = box.Max.z, w = 1.0 },
    }

    if fill then
        local faces = {
            { vertices[1], vertices[2], vertices[4], vertices[3] },
            { vertices[2], vertices[4], vertices[8], vertices[6] },
            { vertices[1], vertices[2], vertices[6], vertices[5] },
            { vertices[1], vertices[3], vertices[7], vertices[5] },
            { vertices[5], vertices[7], vertices[8], vertices[6] },
            { vertices[3], vertices[4], vertices[8], vertices[7] },
        }

        for _, face in ipairs(faces) do
            drawProjectedQuad(screen, face, faceColor)
        end
    end

    if frame then
        local edges = {
            { vertices[1], vertices[2] },
            { vertices[2], vertices[4] },
            { vertices[4], vertices[3] },
            { vertices[3], vertices[1] },
            { vertices[5], vertices[6] },
            { vertices[6], vertices[8] },
            { vertices[8], vertices[7] },
            { vertices[7], vertices[5] },
            { vertices[1], vertices[5] },
            { vertices[2], vertices[6] },
            { vertices[3], vertices[7] },
            { vertices[4], vertices[8] },
        }

        if fadeWithDistance then
            local edgeOpacity = opacity(edgeColor)
            for _, edge in ipairs(edges) do
                local distance = Vector4.DistanceToEdge(screen.camera.position, edge[1], edge[2])
                local distanceFactor = (clamp(distance, 10, 1010) - 10) / 1000
                local edgeColorAdjusted = fade(edgeColor, edgeOpacity - 0x80 * distanceFactor)
                drawProjectedLine(screen, edge, edgeColorAdjusted, 1)
            end
        else
            for _, edge in ipairs(edges) do
                drawProjectedLine(screen, edge, edgeColor, 1)
            end
        end

        for _, vertice in ipairs(vertices) do
            drawProjectedPoint(screen, vertice, verticeColor, 1)

            if userState.showBoundingBoxDistances then
                drawProjectedDistance(screen, vertice, 4, -20, viewStyle.fontSize, verticeColor)
            end
        end
    end
end

local function drawProjections()
    if next(highlight.projections) == nil then
        return
    end

    local camera = getCameraData()

    if not camera then
        return
    end

    local screen = getScreenDescriptor(camera)

    ImGui.SetNextWindowSize(screen.width, screen.height, ImGuiCond.Always)
    ImGui.SetNextWindowPos(0, 0, ImGuiCond.Always)

    if ImGui.Begin('Red Hot Tools Projection', true, viewStyle.projectionWindowFlags) then
        for _, projection in pairs(highlight.projections) do
            local target = projection.target

            if projection.bounds and target.worldBounds then
                local insideColor = fade(projection.color, 0x1D)
                local faceColor = fade(projection.color, 0x0D)
                local edgeColor = fade(projection.color, 0xF0)
                local verticeColor = projection.color

                if insideBox(camera.position, target.worldBounds) then
                    drawQuad(screen, insideColor)
                    drawProjectedBox(screen, target.worldBounds, faceColor, edgeColor, verticeColor, true, false, true)
                else
                    drawProjectedBox(screen, target.worldBounds, faceColor, edgeColor, verticeColor, true, true, true)
                end
            end

            if projection.position and target.worldPosition then
                local outerColor = fade(projection.color, 0x77)
                local innerColor = projection.color
                local distanceColor = projection.color

                drawProjectedMarker(screen, target.worldPosition, outerColor, innerColor, distanceColor)
            end
        end
    end
end

-- GUI :: Windows --

local function drawInspectorWindow()
    ImGui.Begin('Red Hot Tools', viewStyle.overlayWindowFlags)
    ImGui.SetCursorPosY(ImGui.GetCursorPosY() - 2)
    drawInspectorContent(false)
    ImGui.End()
end

local function drawMainWindow()
    if ImGui.Begin('Red Hot Tools', viewStyle.mainWindowFlags) then
        ImGui.BeginTabBar('Red Hot Tools TabBar')
        local tabFlags

		if ImGui.BeginTabItem(' Reload ') then
            ImGui.Spacing()

            --[[
            ImGui.Text('Archives')
            ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
            ImGui.TextWrapped(
                'Hot load archives from archive/pc/hot.\n' ..
                'New archives will be moved to archive/pc/mod and loaded.\n' ..
                'Existing archives will be unloaded and replaced.')
            ImGui.PopStyleColor()
            ImGui.Spacing()

            ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.dangerTextColor)
            ImGui.Text('Not supported on game version 2.0+ yet')
            ImGui.PopStyleColor()
            ImGui.Spacing()

            --ImGui.Checkbox('Watch for changes', true)

            ImGui.PushStyleColor(ImGuiCol.Button, viewStyle.disabledButtonColor)
            ImGui.PushStyleColor(ImGuiCol.ButtonHovered, viewStyle.disabledButtonColor)
            ImGui.PushStyleColor(ImGuiCol.ButtonActive, viewStyle.disabledButtonColor)
            if ImGui.Button('Reload archives', viewStyle.windowWidth, viewStyle.buttonHeight) then
                --RedHotTools.ReloadArchives()
            end
            ImGui.PopStyleColor(3)

            ImGui.Spacing()
            ImGui.Separator()
            ImGui.Spacing()
            --]]

            ImGui.Text('Scripts')
            ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
            ImGui.TextWrapped('Hot load scripts from r6/scripts.')
            ImGui.PopStyleColor()
            ImGui.Spacing()

            if ImGui.Button('Reload scripts', viewStyle.windowWidth, viewStyle.buttonHeight) then
                RedHotTools.ReloadScripts()
            end

            if isTweakXLFound then
                ImGui.Spacing()
                ImGui.Separator()
                ImGui.Spacing()

                ImGui.Text('Tweaks')
                ImGui.PushStyleColor(ImGuiCol.Text, viewStyle.mutedTextColor)
                ImGui.TextWrapped('Hot load tweaks from r6/tweaks and scriptable tweaks.')
                ImGui.PopStyleColor()
                ImGui.Spacing()

                if ImGui.Button('Reload tweaks', viewStyle.windowWidth, viewStyle.buttonHeight) then
                    RedHotTools.ReloadTweaks()
                end
            end

			ImGui.EndTabItem()
        end

        tabFlags = ImGuiTabItemFlags.None
        if viewState.isFirstOpen and userState.isInspectorOpen then
            tabFlags = ImGuiTabItemFlags.SetSelected
        end

        if ImGui.BeginTabItem(' Inspect ', tabFlags) then
            userState.isInspectorOpen = true
            ImGui.Spacing()
            drawInspectorContent(true)
            ImGui.EndTabItem()
        else
            userState.isInspectorOpen = false
        end

        tabFlags = ImGuiTabItemFlags.None
        if viewState.isFirstOpen and userState.isScannerOpen then
            tabFlags = ImGuiTabItemFlags.SetSelected
        end

        if ImGui.BeginTabItem(' Scan ', tabFlags) then
            userState.isScannerOpen = true
            ImGui.Spacing()
            drawScannerContent()
            ImGui.EndTabItem()
        else
            userState.isScannerOpen = false
        end

        tabFlags = ImGuiTabItemFlags.None
        if viewState.isFirstOpen and userState.isLookupOpen then
            tabFlags = ImGuiTabItemFlags.SetSelected
        end

        if ImGui.BeginTabItem(' Lookup ', tabFlags) then
            userState.isLookupOpen = true
            ImGui.Spacing()
            drawLookupContent()
            ImGui.EndTabItem()
        else
            userState.isLookupOpen = false
        end

        tabFlags = ImGuiTabItemFlags.None
        if viewState.isFirstOpen and userState.isWatcherOpen then
            tabFlags = ImGuiTabItemFlags.SetSelected
        end

        if ImGui.BeginTabItem(' Watch ', tabFlags) then
            userState.isWatcherOpen = true
            ImGui.Spacing()
            drawWatcherContent()
            ImGui.EndTabItem()
        else
            userState.isWatcherOpen = false
        end

		if ImGui.BeginTabItem(' Settings ') then
            ImGui.Spacing()
            drawSettingsContent()
            ImGui.EndTabItem()
        end

        viewState.isFirstOpen = false
    end
    ImGui.End()
end

-- GUI :: Events --

registerForEvent('onOverlayOpen', function()
    viewState.isConsoleOpen = true
end)

registerForEvent('onOverlayClose', function()
    viewState.isConsoleOpen = false
    saveUserState()
end)

registerForEvent('onDraw', function()
    if not isPluginFound then
        return
    end

    if not viewState.isConsoleOpen and not userState.isInspectorOSD then
        return
    end

    initializeViewStyle()
    drawProjections()

    ImGui.SetNextWindowPos(viewStyle.windowX, viewStyle.windowY, ImGuiCond.FirstUseEver)
    ImGui.SetNextWindowSize(viewStyle.windowWidth + viewStyle.windowPaddingX * 2 - 1, viewStyle.windowHeight)
    ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, viewStyle.windowPaddingX, viewStyle.windowPaddingY)

    if viewState.isConsoleOpen then
        drawMainWindow()
    elseif userState.isInspectorOSD then
        drawInspectorWindow()
    end

    ImGui.PopStyleVar()
end)

-- Bindings --

registerHotkey('ToggleInspector', 'Toggle inspector window', function()
    if not viewState.isConsoleOpen then
        userState.isInspectorOSD = not userState.isInspectorOSD

        if userState.isInspectorOSD then
            userState.isInspectorOpen = true
            userState.isScannerOpen = false
            userState.isLookupOpen = false
            userState.isWatcherOpen = false
            viewState.isFirstOpen = true
        end

        saveUserState()
    end
end)

registerHotkey('ToggleNodeState', 'Toggle state of inspected node', function()
    if not viewState.isConsoleOpen and userState.isInspectorOSD then
        toggleNodeVisibility(inspector.target)
    end
end)

-- Main --

registerForEvent('onInit', function()
    initializeEnvironment()

    if isPluginFound then
        initializeUserState()
        configureHighlight()
        initializeInspector()
        initializeWatcher()
        initializeViewData()

        Cron.Every(0.2, function()
            if viewState.isConsoleOpen then
                if userState.isInspectorOpen then
                    updateInspector()
                elseif userState.isScannerOpen then
                    updateScanner(viewState.scannerFilter)
                elseif userState.isLookupOpen then
                    updateLookup(viewState.lookupQuery)
                elseif userState.isWatcherOpen then
                    updateWatcher()
                end
            elseif userState.isInspectorOSD then
                updateInspector()
            end
            updateHighlights()
        end)
    end
end)

registerForEvent('onUpdate', function(delta)
	Cron.Update(delta)
end)

registerForEvent('onShutdown', function()
    saveUserState()
end)

-- API --

return {
    RegisterExtension = registerExtension,
    GetLookAtObject = getLookAtTarget,
    CollectTargetData = resolveTargetData,
    GetInspectorTarget = function()
        return inspector.result
    end,
    GetScannerTargets = function()
        return scanner.results
    end,
    GetLookupTarget = function()
        return lookup.result
    end,
}
