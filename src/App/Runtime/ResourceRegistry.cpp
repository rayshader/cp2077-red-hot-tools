#include "ResourceRegistry.hpp"

App::ResourceRegistry::ResourceRegistry(const std::filesystem::path& aMetadataDir)
{
    auto resourceList = aMetadataDir / L"Resources.txt";
    if (std::filesystem::exists(resourceList))
    {
        std::thread([resourceList]() {
            LogInfo("ResourceRegistry: Loading metadata...");

            std::ifstream f(resourceList);
            {
                std::unique_lock _(s_resourcePathLock);
                std::string resourcePath;
                while (std::getline(f, resourcePath))
                {
                    s_resourcePathMap[Red::ResourcePath::HashSanitized(resourcePath.data())] = std::move(resourcePath);
                }
            }

            LogInfo("ResourceRegistry: Loaded {} predefined hashes.", s_resourcePathMap.size());
        }).detach();
    }
}

void App::ResourceRegistry::OnBootstrap()
{
    HookAfter<Raw::ResourcePath::Create>(&OnCreateResourcePath);
    HookAfter<Raw::StreamingSector::OnReady>(&OnStreamingSectorReady);
}

void App::ResourceRegistry::OnCreateResourcePath(Red::ResourcePath* aPath, const Red::StringView* aPathStr)
{
    if (aPathStr)
    {
        std::unique_lock _(s_resourcePathLock);
        s_resourcePathMap[*aPath] = {aPathStr->data, aPathStr->size};
    }
}

void App::ResourceRegistry::OnStreamingSectorReady(Red::worldStreamingSector* aSector, uint64_t)
{
    std::unique_lock _(s_nodeSectorLock);
    auto& buffer = Raw::StreamingSector::NodeBuffer::Ref(aSector);

    for (const auto& node : buffer.nodes)
    {
        s_nodePtrToSectorMap[reinterpret_cast<uintptr_t>(node.instance)] = aSector->path;

        if (node->GetType()->IsA(Red::GetType<Red::worldCompiledCommunityAreaNode>()))
        {
            auto& nodeID = node.GetPtr<Red::worldCompiledCommunityAreaNode>()->sourceObjectId.hash;
            s_nodeRefToSectorMap[nodeID] = aSector->path;
        }
    }

    for (auto& nodeRef : buffer.nodeRefs)
    {
        s_nodeRefToSectorMap[nodeRef.hash] = aSector->path;
    }
}

std::string_view App::ResourceRegistry::ResolveResorcePath(Red::ResourcePath aPath)
{
    if (!aPath)
        return {};

    std::shared_lock _(s_resourcePathLock);
    const auto& it = s_resourcePathMap.find(aPath);

    if (it == s_resourcePathMap.end())
        return {};

    return it.value();
}

std::string_view App::ResourceRegistry::ResolveSectorPath(uint64_t aHash)
{
    if (!aHash)
        return {};

    std::shared_lock _(s_nodeSectorLock);
    const auto& it = s_nodeRefToSectorMap.find(aHash);

    if (it == s_nodeRefToSectorMap.end())
        return {};

    return ResolveResorcePath(it.value());
}

std::string_view App::ResourceRegistry::ResolveSectorPath(void* aPtr)
{
    if (!aPtr)
        return {};

    std::shared_lock _(s_nodeSectorLock);
    const auto& it = s_nodePtrToSectorMap.find(reinterpret_cast<uintptr_t>(aPtr));

    if (it == s_nodePtrToSectorMap.end())
        return {};

    return ResolveResorcePath(it.value());
}

void App::ResourceRegistry::ClearRuntimeData()
{
    std::unique_lock _(s_nodeSectorLock);
    LogInfo("ResourceRegistry: Cleaning up {} tracked nodes.", s_nodePtrToSectorMap.size());
    s_nodePtrToSectorMap.clear();
}
