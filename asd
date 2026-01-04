
--// Services
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer
local PlayerScripts = LocalPlayer.PlayerScripts

--// Paths
local Controllers = PlayerScripts.Controllers
local Modules = ReplicatedStorage.Modules

--// Modules
local EnumBuilder = require(Modules.EnumBuilder)
EnumBuilder:WaitForEnumBuilder()

local CosmeticService = require(Modules.Cosmetics)
local ViewModelService = require(Modules.ViewModelService)
local WeaponDataController = require(Controllers.WeaponDataController)

--// State
local EquippedCosmetics = {}
local FavoriteCosmetics = {}

local SAVE_FOLDER = "cosmetics"
local SAVE_FILE = SAVE_FOLDER .. "/loadout.json"

local CurrentWeapon = nil
local ViewingProfilePlayer = nil
local LastKillWeapon = nil

--// Grant all cosmetics
CosmeticService.OwnsCosmeticNormally = function() return true end
CosmeticService.OwnsCosmeticUniversally = function() return true end
CosmeticService.OwnsCosmeticForWeapon = function() return true end

local originalOwns = CosmeticService.OwnsCosmetic
CosmeticService.OwnsCosmetic = function(_, _, category)
	if category and tostring(category):find("Default") then
		return originalOwns(...)
	end
	return true
end

--// Build cosmetic data
local function buildCosmetic(name, slot, options)
	local cosmetic = CosmeticService.Cosmetics[name]
	if not cosmetic then return nil end

	local data = {
		Name = name,
		Type = cosmetic.Type or slot,
		Seed = cosmetic.Seed or math.random(1, 1_000_000),
	}

	for k, v in pairs(cosmetic) do
		if data[k] == nil then
			data[k] = v
		end
	end

	if options then
		data.Inverted = options.inverted
		data.OnlyUseFavorites = options.favoritesOnly
	end

	data.Enum = EnumBuilder:ToEnum(name)
	data.ObjectID = data.ObjectID or data.Enum

	return data
end

--// Save cosmetics
local function saveCosmetics()
	if not writefile then return end

	local data = {
		equipped = {},
		favorites = FavoriteCosmetics
	}

	for weapon, slots in pairs(EquippedCosmetics) do
		data.equipped[weapon] = {}
		for slot, cosmetic in pairs(slots) do
			data.equipped[weapon][slot] = {
				name = cosmetic.Name,
				seed = cosmetic.Seed,
				inverted = cosmetic.Inverted
			}
		end
	end

	makefolder(SAVE_FOLDER)
	writefile(SAVE_FILE, HttpService:JSONEncode(data))
end

--// Load cosmetics
local function loadCosmetics()
	if not readfile or not isfile or not isfile(SAVE_FILE) then return end

	local data = HttpService:JSONDecode(readfile(SAVE_FILE))
	FavoriteCosmetics = data.favorites or {}

	for weapon, slots in pairs(data.equipped or {}) do
		EquippedCosmetics[weapon] = {}
		for slot, info in pairs(slots) do
			local cosmetic = buildCosmetic(info.name, slot, {
				inverted = info.inverted
			})
			if cosmetic then
				cosmetic.Seed = info.seed
				EquippedCosmetics[weapon][slot] = cosmetic
			end
		end
	end
end

--// Weapon data override
local originalGetWeaponData = WeaponDataController.GetWeaponData
WeaponDataController.GetWeaponData = function(self, weapon)
	local base = originalGetWeaponData(self, weapon)
	if not base or not EquippedCosmetics[weapon] then
		return base
	end

	local merged = { Name = weapon }
	for k, v in pairs(base) do merged[k] = v end
	for k, v in pairs(EquippedCosmetics[weapon]) do merged[k] = v end

	return merged
end

--// ViewModel injection
local ClientItem = require(
	PlayerScripts.Modules.ClientReplicatedClasses.ClientFighter.ClientItem
)

local originalCreateViewModel = ClientItem._CreateViewModel
ClientItem._CreateViewModel = function(self, data)
	local weapon = self.Name
	local player = self.ClientFighter and self.ClientFighter.Player

	CurrentWeapon = (player == LocalPlayer) and weapon or nil

	if player == LocalPlayer
		and EquippedCosmetics[weapon]
		and EquippedCosmetics[weapon].Skin
		and data and data.Data then

		data.Data.Skin = EquippedCosmetics[weapon].Skin
		data.Data.Name = EquippedCosmetics[weapon].Skin.Name
	end

	local vm = originalCreateViewModel(self, data)
	CurrentWeapon = nil
	return vm
end

--// Finisher replication hook
local ClientEntity = require(
	PlayerScripts.Modules.ClientReplicatedClasses.ClientEntity
)

local originalReplicate = ClientEntity.ReplicateFromServer
ClientEntity.ReplicateFromServer = function(self, event, ...)
	if event == "PlayFinisher" then
		local args = { ... }
		local target = tostring(args[3] or "")

		if target:lower() == LocalPlayer.Name:lower()
			and LastKillWeapon
			and EquippedCosmetics[LastKillWeapon]
			and EquippedCosmetics[LastKillWeapon].Finisher then

			local finisher = EquippedCosmetics[LastKillWeapon].Finisher
			args[2] = finisher.Enum or EnumBuilder:ToEnum(finisher.Name)
			return originalReplicate(self, event, unpack(args))
		end
	end

	return originalReplicate(self, event, ...)
end

--// Load saved cosmetics
loadCosmetics()

--// Auto-save on exit (best effort)
pcall(function()
	game:BindToClose(saveCosmetics)
end)

print("[Cosmetic Spoofer] Loaded successfully")
