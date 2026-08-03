--!strict

local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")

local shared = game:GetService("ReplicatedStorage"):WaitForChild("LobbyMagicV2"):WaitForChild("Shared")
local Config = require(shared:WaitForChild("LMV2Config"))
local SpellCatalog = require(shared:WaitForChild("LMV2SpellCatalog"))

export type StoredSpell = {
	Name: string,
	Selection: { [string]: string },
}

export type Session = {
	Spells: { StoredSpell },
	ActiveSlot: number,
	Persistent: boolean,
	Dirty: boolean,
}

local dataStore = DataStoreService:GetDataStore(Config.Persistence.DataStoreName)
local sessions: { [Player]: Session } = {}
local Store = {}

local function emptySession(persistent: boolean): Session
	return {
		Spells = {},
		ActiveSlot = 0,
		Persistent = persistent,
		Dirty = false,
	}
end

local function copySelection(source: { [string]: string }): { [string]: string }
	local result: { [string]: string } = {}
	for _, category in ipairs(SpellCatalog.ComponentOrder) do
		result[category] = source[category]
	end
	return result
end

local function normalizeStoredSpell(value: any): StoredSpell?
	if typeof(value) ~= "table" then
		return nil
	end
	local name = SpellCatalog.NormalizeName(value.Name)
	local spell = SpellCatalog.Build(value.Selection)
	if not name or not spell then
		return nil
	end
	return {
		Name = name,
		Selection = copySelection(spell.Selection),
	}
end

local function normalizeData(value: any): Session
	local session = emptySession(true)
	if typeof(value) ~= "table" or value.Version ~= Config.Persistence.DataVersion then
		return session
	end

	if typeof(value.Spells) == "table" then
		for _, rawSpell in ipairs(value.Spells) do
			if #session.Spells >= Config.Inventory.MaximumSpells then
				break
			end
			local spell = normalizeStoredSpell(rawSpell)
			if spell then
				table.insert(session.Spells, spell)
			end
		end
	end

	local requestedSlot = if typeof(value.ActiveSlot) == "number" then math.floor(value.ActiveSlot) else 1
	session.ActiveSlot = if #session.Spells > 0 then math.clamp(requestedSlot, 1, #session.Spells) else 0
	return session
end

local function serialize(session: Session): { [string]: any }
	local spells = {}
	for _, storedSpell in ipairs(session.Spells) do
		table.insert(spells, {
			Name = storedSpell.Name,
			Selection = copySelection(storedSpell.Selection),
		})
	end
	return {
		Version = Config.Persistence.DataVersion,
		ActiveSlot = session.ActiveSlot,
		Spells = spells,
	}
end

function Store.Load(player: Player): (boolean, string?)
	local ok, result = pcall(function()
		return dataStore:GetAsync(string.format("u_%d", player.UserId))
	end)
	if ok then
		sessions[player] = normalizeData(result)
		return true, nil
	end

	if RunService:IsStudio() then
		sessions[player] = emptySession(false)
		return true, "StudioでDataStoreに接続できないため、このPlayテスト中だけ保存します。"
	end
	return false, tostring(result)
end

function Store.Get(player: Player): Session?
	return sessions[player]
end

function Store.MarkDirty(player: Player)
	local session = sessions[player]
	if session then
		session.Dirty = true
	end
end

function Store.Save(player: Player, force: boolean?): (boolean, string?)
	local session = sessions[player]
	if not session or not session.Persistent then
		return session ~= nil, nil
	end
	if not force and not session.Dirty then
		return true, nil
	end

	local payload = serialize(session)
	local ok, result = pcall(function()
		dataStore:UpdateAsync(string.format("u_%d", player.UserId), function()
			return payload
		end)
	end)
	if ok then
		session.Dirty = false
		return true, nil
	end
	return false, tostring(result)
end

function Store.Remove(player: Player)
	sessions[player] = nil
end

function Store.CopySelection(source: { [string]: string }): { [string]: string }
	return copySelection(source)
end

return Store
