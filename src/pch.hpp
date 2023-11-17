#pragma once

#include <algorithm>
#include <concepts>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <functional>
#include <future>
#include <map>
#include <memory>
#include <source_location>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#include <vector>

#include <RED4ext/RED4ext.hpp>

#include <RED4ext/ResourceDepot.hpp>
#include <RED4ext/ResourceLoader.hpp>
#include <RED4ext/Scripting/Natives/Generated/Box.hpp>
#include <RED4ext/Scripting/Natives/Generated/CMesh.hpp>
#include <RED4ext/Scripting/Natives/Generated/Transform.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/ColliderComponent.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/ComponentsStorage.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/Entity.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/EntityID.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/IComponent.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/ITransformBinding.hpp>
#include <RED4ext/Scripting/Natives/Generated/ent/RenderHighlightEvent.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/EntityStubComponentPS.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/ICameraSystem.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/IEntityStubSystem.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/IGameSystem.hpp>
#include <RED4ext/Scripting/Natives/Generated/game/ScriptableSystem.hpp>
#include <RED4ext/Scripting/Natives/Generated/ink/WidgetLibraryResource.hpp>
#include <RED4ext/Scripting/Natives/Generated/physics/TraceResult.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/AreaShapeNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/BendedMeshNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/BendedMeshNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/CompiledCommunityAreaNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/EntityNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/EntityNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/FoliageNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/GlobalNodeID.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/GlobalNodeRef.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/INodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/IRuntimeSystem.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/InstancedMeshNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/InstancedMeshNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/MeshNode.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/MeshNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/Node.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/NodeInstanceRegistry.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/PhysicalDestructionNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/RuntimeSystemNodeStreaming.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/StaticDecalNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/StreamingSector.hpp>
#include <RED4ext/Scripting/Natives/Generated/world/TerrainMeshNodeInstance.hpp>
#include <RED4ext/Scripting/Natives/ScriptGameInstance.hpp>

#include <nameof.hpp>
#include <semver.hpp>

#include <FileWatch.hpp>

#include "Core/Raw.hpp"
#include "Core/Stl.hpp"

#include "Red/Alias.hpp"
#include "Red/Engine.hpp"
#include "Red/Specializations.hpp"
#include "Red/TypeInfo.hpp"
#include "Red/Utils.hpp"
