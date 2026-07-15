import Foundation
import SwiftData

/// Reconciles the local Shopping + Grocery store (grocery lists + shopping
/// templates) with the server, mirroring the recipe ``SyncService`` as closely
/// as the grocery API allows. Offline-first, watermark = the server's own
/// `updated_at`, user deletes are soft-deletes pushed as a DELETE, and
/// server-detected deletes linger in a 30-day purge window.
///
/// Two grocery-specific adaptations vs. recipes:
///
///   1. GROCERY LISTS reconcile PER-ITEM. The server has no whole-list PUT; a
///      list is created (POST name) then items are POSTed under it, and edits
///      are reconciled against a fresh server GET — create new items, PATCH
///      changed ones (or `toggle` when only the checkbox differs), DELETE the
///      ones gone locally. Archive state syncs via the archive/restore
///      endpoints. Item responses carry no `list_id`; each local item stores
///      its own server id.
///
///   2. NO CONFLICT COPY for lists/templates (unlike recipes' Scenario 5). When
///      the server is newer than the local watermark, the server version wins
///      wholesale (pull overwrites local).
///
/// SHOPPING TEMPLATES are simpler: they round-trip as an aggregate (POST create
/// / PUT full-replace / DELETE), so no per-item reconcile is needed.
@MainActor
@Observable
final class GrocerySyncService {
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastSyncError: String?
    private(set) var hasWriteFailures = false

    private let apiClient: APIClient
    private var modelContext: ModelContext?

    init(apiClient: APIClient = .shared) {
        self.apiClient = apiClient
    }

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Force Full Sync

    func forceFullSync() async {
        guard let modelContext else { return }
        do {
            for list in try fetchLocalLists(modelContext) {
                list.lastSyncedAt = nil
            }
            for template in try fetchLocalTemplates(modelContext) {
                template.lastSyncedAt = nil
            }
            try modelContext.save()
        } catch {
            // Non-critical — sync will still work, just won't force re-download.
        }
        await sync()
    }

    // MARK: - Main Entry Point

    func sync() async {
        guard !isSyncing else { return }
        guard KeychainService.loadToken() != nil else { return }
        guard let modelContext else { return }

        isSyncing = true
        var writeFailures = 0

        do {
            writeFailures += try await syncLists(modelContext)
            writeFailures += try await syncTemplates(modelContext)

            purgeExpiredDeletions(modelContext: modelContext)
            try modelContext.save()

            hasWriteFailures = writeFailures > 0
            if writeFailures > 0 {
                lastSyncError = "Could not sync \(writeFailures) item\(writeFailures == 1 ? "" : "s")"
            } else {
                lastSyncError = nil
            }
            lastSyncDate = Date()
        } catch let apiError as APIError where apiError == .unauthorized {
            lastSyncError = "Session expired — sign in again"
        } catch {
            lastSyncError = "Sync failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    // MARK: - Lists

    private func syncLists(_ modelContext: ModelContext) async throws -> Int {
        let serverList = try await apiClient.fetchGroceryListIds()
        let serverIDs = Set(serverList.map { $0.id })
        let serverMap = Dictionary(uniqueKeysWithValues: serverList.map { ($0.id, $0.updatedAt) })

        let localLists = try fetchLocalLists(modelContext)

        let isFirstSync =
            serverList.isEmpty
            && localLists.contains(where: { $0.serverId == nil && !$0.locallyDeleted })

        var failures = 0
        if isFirstSync {
            failures += await performFirstSyncLists(localLists: localLists, modelContext: modelContext)
        } else {
            try await pullLists(
                serverList: serverList,
                serverIDs: serverIDs,
                serverMap: serverMap,
                localLists: localLists,
                modelContext: modelContext
            )
            failures += await pushLists(localLists: localLists, modelContext: modelContext)
            failures += await processListDeletions(localLists: localLists, modelContext: modelContext)
        }
        return failures
    }

    private func pullLists(
        serverList: [GrocerySyncListItemDTO],
        serverIDs: Set<UUID>,
        serverMap: [UUID: Date],
        localLists: [GroceryList],
        modelContext: ModelContext
    ) async throws {
        let localByServerID: [UUID: GroceryList] = Dictionary(
            uniqueKeysWithValues: localLists.compactMap { list in
                guard let sid = list.serverId, let uuid = UUID(uuidString: sid) else { return nil }
                return (uuid, list)
            }
        )

        // Server-only lists -> download & insert.
        for item in serverList where localByServerID[item.id] == nil {
            do {
                let dto = try await apiClient.fetchGroceryList(id: item.id)
                modelContext.insert(serverToLocalList(dto))
            } catch {
                // Transient — retry next sync.
            }
        }

        for (serverID, local) in localByServerID {
            guard serverIDs.contains(serverID) else {
                // Present locally, absent from the server list -> deleted on the server.
                if !local.locallyDeleted {
                    local.locallyDeleted = true
                    local.pendingRemoteDelete = false  // already gone remotely — don't re-push
                    local.deletedAt = Date()
                }
                continue
            }

            guard let serverUpdatedAt = serverMap[serverID] else { continue }
            let localLastSynced = local.lastSyncedAt ?? .distantPast
            guard serverUpdatedAt > localLastSynced else { continue }

            // Server is newer -> server wins wholesale (no conflict copy for lists).
            do {
                let dto = try await apiClient.fetchGroceryList(id: serverID)
                applyServerList(dto, to: local, modelContext: modelContext)
            } catch {
                // Transient — retry next sync.
            }
        }
    }

    private func pushLists(localLists: [GroceryList], modelContext: ModelContext) async -> Int {
        var failures = 0
        let dirty = localLists.filter { $0.needsSync && !$0.locallyDeleted }
        for local in dirty {
            do {
                try await pushOneList(local, modelContext: modelContext)
            } catch {
                // needsSync stays true -> retried next cycle.
                failures += 1
            }
        }
        return failures
    }

    private func performFirstSyncLists(localLists: [GroceryList], modelContext: ModelContext) async -> Int {
        var failures = 0
        let unsynced = localLists.filter { $0.serverId == nil && !$0.locallyDeleted }
        for local in unsynced {
            do {
                try await pushOneList(local, modelContext: modelContext)
            } catch {
                failures += 1
            }
        }
        return failures
    }

    /// Push one local list to the server: create it if new, reconcile its items
    /// (create/patch/toggle/delete) against a fresh server GET, reconcile archive
    /// state, then re-read for the authoritative watermark.
    private func pushOneList(_ local: GroceryList, modelContext: ModelContext) async throws {
        if local.serverId == nil {
            let trimmed = local.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let created = try await apiClient.createGroceryList(name: trimmed.isEmpty ? "Grocery List" : trimmed)
            local.serverId = created.id.uuidString
        }
        guard let sid = local.serverId, let serverUUID = UUID(uuidString: sid) else { return }

        let server = try await apiClient.fetchGroceryList(id: serverUUID)
        try await reconcileItems(local: local, listServerID: serverUUID, server: server)
        try await reconcileArchive(local: local, listServerID: serverUUID, server: server)

        let finalDto = try await apiClient.fetchGroceryList(id: serverUUID)
        if let createdAt = finalDto.createdAt { local.createdAt = createdAt }
        if let updatedAt = finalDto.updatedAt { local.updatedAt = updatedAt }
        local.archivedAt = finalDto.archivedAt
        local.lastSyncedAt = finalDto.updatedAt ?? Date()
        local.needsSync = false
    }

    /// Reconcile a list's items against the server's current item set.
    private func reconcileItems(
        local: GroceryList,
        listServerID: UUID,
        server: GroceryListDTO
    ) async throws {
        let serverById = Dictionary(uniqueKeysWithValues: server.items.map { ($0.id.uuidString, $0) })
        var matched = Set<String>()

        for item in local.items ?? [] {
            guard let sid = item.serverId, let srv = serverById[sid], let itemUUID = UUID(uuidString: sid) else {
                // Local-only item (or one the server no longer has) -> (re)create it.
                let created = try await apiClient.createItem(listId: listServerID, toItemInput(item))
                item.serverId = created.id.uuidString
                continue
            }
            matched.insert(sid)

            let contentChanged =
                item.name != srv.name
                || item.quantity != srv.quantity
                || item.unit != srv.unit
                || item.category != srv.category
                || item.sourceRecipeName != srv.sourceRecipeName
                || item.sourceRecipeId != srv.sourceRecipeId

            if contentChanged {
                // PATCH carries is_checked too, so a combined edit needs one call.
                _ = try await apiClient.patchItem(
                    id: itemUUID,
                    GroceryItemPatchDTO(
                        name: item.name,
                        quantity: item.quantity,
                        unit: item.unit,
                        category: item.category,
                        isChecked: item.isChecked
                    )
                )
            } else if item.isChecked != srv.isChecked {
                // Only the checkbox differs -> the dedicated toggle endpoint.
                _ = try await apiClient.toggleItem(id: itemUUID)
            }
        }

        // Server items no local item points at -> deleted locally -> DELETE remotely.
        for srv in server.items where !matched.contains(srv.id.uuidString) {
            try await apiClient.deleteItem(id: srv.id)
        }
    }

    /// Sync archive state via the archive/restore endpoints (no whole-list PUT).
    private func reconcileArchive(
        local: GroceryList,
        listServerID: UUID,
        server: GroceryListDTO
    ) async throws {
        if local.archivedAt != nil && server.archivedAt == nil {
            _ = try await apiClient.archiveGroceryList(id: listServerID)
        } else if local.archivedAt == nil && server.archivedAt != nil {
            _ = try await apiClient.restoreGroceryList(id: listServerID)
        }
    }

    private func processListDeletions(localLists: [GroceryList], modelContext: ModelContext) async -> Int {
        var failures = 0
        for local in localLists where local.locallyDeleted {
            guard local.pendingRemoteDelete else { continue }  // server-detected delete -> just aged out

            guard let sid = local.serverId, let serverUUID = UUID(uuidString: sid) else {
                modelContext.delete(local)
                continue
            }
            do {
                try await apiClient.deleteGroceryList(id: serverUUID)
                modelContext.delete(local)
            } catch let error as APIError where error == .notFound {
                modelContext.delete(local)
            } catch {
                failures += 1
            }
        }
        return failures
    }

    // MARK: - Templates

    private func syncTemplates(_ modelContext: ModelContext) async throws -> Int {
        let serverList = try await apiClient.fetchTemplateIds()
        let serverIDs = Set(serverList.map { $0.id })
        let serverMap = Dictionary(uniqueKeysWithValues: serverList.map { ($0.id, $0.updatedAt) })

        let localTemplates = try fetchLocalTemplates(modelContext)

        let isFirstSync =
            serverList.isEmpty
            && localTemplates.contains(where: { $0.serverId == nil && !$0.locallyDeleted })

        var failures = 0
        if isFirstSync {
            failures += await performFirstSyncTemplates(localTemplates: localTemplates, modelContext: modelContext)
        } else {
            try await pullTemplates(
                serverList: serverList,
                serverIDs: serverIDs,
                serverMap: serverMap,
                localTemplates: localTemplates,
                modelContext: modelContext
            )
            failures += await pushTemplates(localTemplates: localTemplates, modelContext: modelContext)
            failures += await processTemplateDeletions(localTemplates: localTemplates, modelContext: modelContext)
        }
        return failures
    }

    private func pullTemplates(
        serverList: [GrocerySyncListItemDTO],
        serverIDs: Set<UUID>,
        serverMap: [UUID: Date],
        localTemplates: [ShoppingTemplate],
        modelContext: ModelContext
    ) async throws {
        let localByServerID: [UUID: ShoppingTemplate] = Dictionary(
            uniqueKeysWithValues: localTemplates.compactMap { template in
                guard let sid = template.serverId, let uuid = UUID(uuidString: sid) else { return nil }
                return (uuid, template)
            }
        )

        for item in serverList where localByServerID[item.id] == nil {
            do {
                let dto = try await apiClient.fetchTemplate(id: item.id)
                modelContext.insert(serverToLocalTemplate(dto))
            } catch {
                // Transient — retry next sync.
            }
        }

        for (serverID, local) in localByServerID {
            guard serverIDs.contains(serverID) else {
                if !local.locallyDeleted {
                    local.locallyDeleted = true
                    local.pendingRemoteDelete = false
                    local.deletedAt = Date()
                }
                continue
            }

            guard let serverUpdatedAt = serverMap[serverID] else { continue }
            let localLastSynced = local.lastSyncedAt ?? .distantPast
            guard serverUpdatedAt > localLastSynced else { continue }

            do {
                let dto = try await apiClient.fetchTemplate(id: serverID)
                applyServerTemplate(dto, to: local, modelContext: modelContext)
            } catch {
                // Transient — retry next sync.
            }
        }
    }

    private func pushTemplates(localTemplates: [ShoppingTemplate], modelContext: ModelContext) async -> Int {
        var failures = 0
        let dirty = localTemplates.filter { $0.needsSync && !$0.locallyDeleted }
        for local in dirty {
            do {
                try await pushOneTemplate(local, modelContext: modelContext)
            } catch {
                failures += 1
            }
        }
        return failures
    }

    private func performFirstSyncTemplates(
        localTemplates: [ShoppingTemplate],
        modelContext: ModelContext
    ) async -> Int {
        var failures = 0
        let unsynced = localTemplates.filter { $0.serverId == nil && !$0.locallyDeleted }
        for local in unsynced {
            do {
                try await pushOneTemplate(local, modelContext: modelContext)
            } catch {
                failures += 1
            }
        }
        return failures
    }

    /// Create (POST) or full-replace (PUT) a template as an aggregate.
    private func pushOneTemplate(_ local: ShoppingTemplate, modelContext: ModelContext) async throws {
        let input = toTemplateInput(local)
        let dto: TemplateDTO
        if let sid = local.serverId, let serverUUID = UUID(uuidString: sid) {
            dto = try await apiClient.updateTemplate(id: serverUUID, input)
        } else {
            dto = try await apiClient.createTemplate(input)
        }
        local.serverId = dto.id.uuidString
        if let createdAt = dto.createdAt { local.createdAt = createdAt }
        if let updatedAt = dto.updatedAt { local.updatedAt = updatedAt }
        local.lastSyncedAt = dto.updatedAt ?? Date()
        local.needsSync = false
    }

    private func processTemplateDeletions(
        localTemplates: [ShoppingTemplate],
        modelContext: ModelContext
    ) async -> Int {
        var failures = 0
        for local in localTemplates where local.locallyDeleted {
            guard local.pendingRemoteDelete else { continue }

            guard let sid = local.serverId, let serverUUID = UUID(uuidString: sid) else {
                modelContext.delete(local)
                continue
            }
            do {
                try await apiClient.deleteTemplate(id: serverUUID)
                modelContext.delete(local)
            } catch let error as APIError where error == .notFound {
                modelContext.delete(local)
            } catch {
                failures += 1
            }
        }
        return failures
    }

    // MARK: - Purge Expired Deletions

    private func purgeExpiredDeletions(modelContext: ModelContext) {
        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        do {
            for list in try fetchLocalLists(modelContext) where list.locallyDeleted {
                if let deletedAt = list.deletedAt, deletedAt < thirtyDaysAgo {
                    modelContext.delete(list)
                }
            }
            for template in try fetchLocalTemplates(modelContext) where template.locallyDeleted {
                if let deletedAt = template.deletedAt, deletedAt < thirtyDaysAgo {
                    modelContext.delete(template)
                }
            }
        } catch {
            // Non-critical — will retry next sync.
        }
    }

    // MARK: - DTO Mapping (lists)

    /// Server list -> a brand-new local record (server-only download).
    private func serverToLocalList(_ dto: GroceryListDTO) -> GroceryList {
        let list = GroceryList(name: dto.name)
        if let createdAt = dto.createdAt { list.createdAt = createdAt }
        list.archivedAt = dto.archivedAt
        list.updatedAt = dto.updatedAt ?? Date()
        list.serverId = dto.id.uuidString
        list.lastSyncedAt = dto.updatedAt ?? Date()
        list.needsSync = false
        list.items = dto.items.map { toLocalItem($0) }
        return list
    }

    /// Overwrite an existing local list's content from the server (server wins).
    private func applyServerList(_ dto: GroceryListDTO, to local: GroceryList, modelContext: ModelContext) {
        local.name = dto.name
        if let createdAt = dto.createdAt { local.createdAt = createdAt }
        if let updatedAt = dto.updatedAt { local.updatedAt = updatedAt }
        local.archivedAt = dto.archivedAt

        for old in local.items ?? [] {
            modelContext.delete(old)
        }
        local.items = dto.items.map { toLocalItem($0) }

        local.lastSyncedAt = dto.updatedAt ?? Date()
        local.needsSync = false
    }

    /// Server grocery item -> local shape (fresh local id; keep the server id).
    private func toLocalItem(_ dto: GroceryItemDTO) -> GroceryItem {
        let item = GroceryItem(
            name: dto.name,
            quantity: dto.quantity,
            unit: dto.unit,
            category: dto.category,
            sourceRecipeName: dto.sourceRecipeName,
            sourceRecipeId: dto.sourceRecipeId
        )
        item.isChecked = dto.isChecked
        item.serverId = dto.id.uuidString
        return item
    }

    /// Local grocery item -> the POST body for creating it on the server.
    private func toItemInput(_ item: GroceryItem) -> GroceryItemInput {
        GroceryItemInput(
            name: item.name,
            quantity: item.quantity,
            unit: item.unit,
            category: item.category,
            sourceRecipeName: item.sourceRecipeName,
            sourceRecipeId: item.sourceRecipeId
        )
    }

    // MARK: - DTO Mapping (templates)

    /// Server template -> a brand-new local record (server-only download).
    private func serverToLocalTemplate(_ dto: TemplateDTO) -> ShoppingTemplate {
        let template = ShoppingTemplate(name: dto.name, sortOrder: dto.sortOrder)
        if let createdAt = dto.createdAt { template.createdAt = createdAt }
        template.updatedAt = dto.updatedAt ?? Date()
        template.serverId = dto.id.uuidString
        template.lastSyncedAt = dto.updatedAt ?? Date()
        template.needsSync = false
        template.items = dto.items.map { toLocalTemplateItem($0) }
        return template
    }

    /// Overwrite an existing local template's content from the server (server wins).
    private func applyServerTemplate(_ dto: TemplateDTO, to local: ShoppingTemplate, modelContext: ModelContext) {
        local.name = dto.name
        local.sortOrder = dto.sortOrder
        if let createdAt = dto.createdAt { local.createdAt = createdAt }
        if let updatedAt = dto.updatedAt { local.updatedAt = updatedAt }

        for old in local.items ?? [] {
            modelContext.delete(old)
        }
        local.items = dto.items.map { toLocalTemplateItem($0) }

        local.lastSyncedAt = dto.updatedAt ?? Date()
        local.needsSync = false
    }

    private func toLocalTemplateItem(_ dto: TemplateItemDTO) -> TemplateItem {
        let item = TemplateItem(
            name: dto.name,
            quantity: dto.quantity,
            unit: dto.unit,
            category: dto.category,
            sortOrder: dto.sortOrder
        )
        item.serverId = dto.id.uuidString
        return item
    }

    /// Local template -> the POST/PUT body (aggregate).
    private func toTemplateInput(_ template: ShoppingTemplate) -> TemplateInput {
        let items = (template.items ?? [])
            .sorted { $0.sortOrder < $1.sortOrder }
            .map { item in
                TemplateItemInput(
                    name: item.name,
                    quantity: item.quantity,
                    unit: item.unit,
                    category: item.category,
                    sortOrder: item.sortOrder
                )
            }
        return TemplateInput(name: template.name, sortOrder: template.sortOrder, items: items)
    }

    // MARK: - Helpers

    private func fetchLocalLists(_ modelContext: ModelContext) throws -> [GroceryList] {
        try modelContext.fetch(FetchDescriptor<GroceryList>())
    }

    private func fetchLocalTemplates(_ modelContext: ModelContext) throws -> [ShoppingTemplate] {
        try modelContext.fetch(FetchDescriptor<ShoppingTemplate>())
    }
}
