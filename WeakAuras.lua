
-- Lua APIs
local tinsert, tconcat, tremove, wipe = table.insert, table.concat, table.remove, wipe
local fmt, tostring, select, pairs, next, type, unpack = string.format, tostring, select, pairs, next, type, unpack
local loadstring, assert, error = loadstring, assert, error
local setmetatable, getmetatable = setmetatable, getmetatable
local coroutine =  coroutine
local _G = _G

local ADDON_NAME = "WeakAuras";
local versionString = WeakAuras.versionString;
WeakAurasTimers = setmetatable({}, {__tostring=function() return "WeakAuras" end});
LibStub("AceTimer-3.0"):Embed(WeakAurasTimers);
WeakAurasAceEvents = setmetatable({}, {__tostring=function() return "WeakAuras" end});
LibStub("AceEvent-3.0"):Embed(WeakAurasAceEvents);
local LDB = LibStub:GetLibrary("LibDataBroker-1.1");

local timer = WeakAurasTimers;
WeakAuras.timer = timer;
local aceEvents = WeakAurasAceEvents

local WeakAuras = WeakAuras;
local L = WeakAuras.L;

-- GLOBALS: WeakAurasTimers WeakAurasAceEvents WeakAurasSaved
-- GLOBALS: FONT_COLOR_CODE_CLOSE RED_FONT_COLOR_CODE
-- GLOBALS: GameTooltip GameTooltip_Hide StaticPopup_Show StaticPopupDialogs STATICPOPUP_NUMDIALOGS DEFAULT_CHAT_FRAME
-- GLOBALS: CombatText_AddMessage COMBAT_TEXT_SCROLL_FUNCTION WorldFrame MAX_NUM_TALENTS
-- GLOBALS: SLASH_WEAKAURAS1 SLASH_WEAKAURAS2 SlashCmdList GTFO UNKNOWNOBJECT

local queueshowooc;
function WeakAuras.OpenOptions(msg)
  if not(IsAddOnLoaded("WeakAurasOptions")) then
    if InCombatLockdown() then
      -- inform the user and queue ooc
      print("|cff9900FF".."WeakAuras Options"..FONT_COLOR_CODE_CLOSE.." will finish loading after combat.")
      queueshowooc = msg or "";
      WeakAuras.frames["Addon Initialization Handler"]:RegisterEvent("PLAYER_REGEN_ENABLED")
      return;
    else
      local loaded, reason = LoadAddOn("WeakAurasOptions");
      if not(loaded) then
        print("|cff9900FF".."WeakAuras Options"..FONT_COLOR_CODE_CLOSE.." could not be loaded: "..RED_FONT_COLOR_CODE.._G["ADDON_"..reason]);
        return;
      end
    end
  end
  WeakAuras.ToggleOptions(msg);
end

SLASH_WEAKAURAS1, SLASH_WEAKAURAS2 = "/weakauras", "/wa";
function SlashCmdList.WEAKAURAS(msg)
  WeakAuras.OpenOptions(msg);
end

-- A alias for WeakAurasSaved, the SavedVariables
-- Noteable properties:
--  debug: If set to true, WeakAura.debug() outputs messages to the chat frame
--  displays: All aura settings, keyed on their id
local db;

local registeredFromAddons;
-- List of addons that registered displays, not sure if anyone addon uses this
WeakAuras.addons = {};
local addons = WeakAuras.addons;

-- A list of tutorials, filled in by the WeakAuraTutorial addon by callling RegisterTutorial
WeakAuras.tutorials = {};
local tutorials = WeakAuras.tutorials;

-- used if a addons tries to register a display under a id, that the user already has a display with that id
WeakAuras.collisions = {};
local collisions = WeakAuras.collisions;

-- While true no events are handled. E.g. WeakAuras is paused while the Options dialog is open
local paused = true;
local importing = false;
local squelch_actions = true;

-- All regions keyed on id, has properties: region, regionType, also see clones
WeakAuras.regions = {};
local regions = WeakAuras.regions;
WeakAuras.auras = {};
local auras = WeakAuras.auras;
WeakAuras.events = {};
local events = WeakAuras.events;
WeakAuras.loaded = {};
local loaded = WeakAuras.loaded;

WeakAuras.specificBosses = {};
local specificBosses = WeakAuras.specificBosses;
WeakAuras.specificUnits = {};
local specificUnits = WeakAuras.specificUnits;

-- contains regions for clones
WeakAuras.clones = {};
local clones = WeakAuras.clones;
-- Unused regions that are kept around for clones
WeakAuras.clonePool = {};
local clonePool = WeakAuras.clonePool;

-- One table per regiontype, see RegisterRegionType, notable properties: create, modify and default
WeakAuras.regionTypes = {};
local regionTypes = WeakAuras.regionTypes;

-- One table per regiontype, see RegisterRegionOptions
WeakAuras.regionOptions = {};
local regionOptions = WeakAuras.regionOptions;

-- Maps from trigger type to trigger system
WeakAuras.triggerTypes = {};
local triggerTypes = WeakAuras.triggerTypes;

-- List of all trigger systems, contains each system onec
WeakAuras.triggerSystems = {}
local triggerSystems = WeakAuras.triggerSystems;

WeakAuras.forceable_events = {};

local from_files = {};

local timers = {};
WeakAuras.timers = timers;

local loaded_events = {};
WeakAuras.loaded_events = loaded_events;
local loaded_auras = {};
WeakAuras.loaded_auras = loaded_auras;

-- Animations
WeakAuras.animations = {};
local animations = WeakAuras.animations;
WeakAuras.pending_controls = {};
local pending_controls = WeakAuras.pending_controls;

WeakAuras.frames = {};

WeakAuras.raidUnits = {};
WeakAuras.partyUnits = {};
do
  for i=1,40 do
  WeakAuras.raidUnits[i] = "raid"..i
  end
  for i=1,4 do
  WeakAuras.partyUnits[i] = "party"..i
  end
end
WeakAuras.me = GetUnitName("player",true)
WeakAuras.myGUID = nil
local playerLevel = UnitLevel("player");

local function_strings = WeakAuras.function_strings;
local anim_function_strings = WeakAuras.anim_function_strings;
local anim_presets = WeakAuras.anim_presets;
local load_prototype = WeakAuras.load_prototype;
local event_prototypes = WeakAuras.event_prototypes;

local levelColors = {
  [0] = "|cFFFFFFFF",
  [1] = "|cFF40FF40",
  [2] = "|cFF6060FF",
  [3] = "|cFFFF4040"
};

function WeakAuras.debug(msg, level)
  if(db.debug) then
  level = (level and levelColors[level] and level) or 2;
  msg = (type(msg) == "string" and msg) or (msg and "Invalid debug message of type "..type(msg)) or "Debug message not specified";
  DEFAULT_CHAT_FRAME:AddMessage(levelColors[level]..msg);
  end
end
local debug = WeakAuras.debug;

function WeakAuras.validate(input, default)
  for field, defaultValue in pairs(default) do
  if(type(defaultValue) == "table" and type(input[field]) ~= "table") then
    input[field] = {};
  elseif(input[field] == nil) then
    input[field] = defaultValue;
  elseif(type(input[field]) ~= type(defaultValue)) then
    input[field] = defaultValue;
  end

  if(type(input[field]) == "table") then
    WeakAuras.validate(input[field], defaultValue);
  end
  end
end



function WeakAuras.RegisterRegionType(name, createFunction, modifyFunction, default)
  if not(name) then
    error("Improper arguments to WeakAuras.RegisterRegionType - name is not defined");
  elseif(type(name) ~= "string") then
    error("Improper arguments to WeakAuras.RegisterRegionType - name is not a string");
  elseif not(createFunction) then
    error("Improper arguments to WeakAuras.RegisterRegionType - creation function is not defined");
  elseif(type(createFunction) ~= "function") then
    error("Improper arguments to WeakAuras.RegisterRegionType - creation function is not a function");
  elseif not(modifyFunction) then
    error("Improper arguments to WeakAuras.RegisterRegionType - modification function is not defined");
  elseif(type(modifyFunction) ~= "function") then
    error("Improper arguments to WeakAuras.RegisterRegionType - modification function is not a function")
  elseif not(default) then
    error("Improper arguments to WeakAuras.RegisterRegionType - default options are not defined");
  elseif(type(default) ~= "table") then
    error("Improper arguments to WeakAuras.RegisterRegionType - default options are not a table");
  elseif(regionTypes[name]) then
    error("Improper arguments to WeakAuras.RegisterRegionType - region type \""..name.."\" already defined");
  else
  regionTypes[name] = {
    create = createFunction,
    modify = modifyFunction,
    default = default
  };
  end
end

function WeakAuras.RegisterRegionOptions(name, createFunction, icon, displayName, createThumbnail, modifyThumbnail, description)
  if not(name) then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - name is not defined");
  elseif(type(name) ~= "string") then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - name is not a string");
  elseif not(createFunction) then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - creation function is not defined");
  elseif(type(createFunction) ~= "function") then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - creation function is not a function");
  elseif not(icon) then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - icon is not defined");
  elseif not(type(icon) == "string" or type(icon) == "function") then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - icon is not a string or a function")
  elseif not(displayName) then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - display name is not defined".." "..name);
  elseif(type(displayName) ~= "string") then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - display name is not a string");
  elseif(regionOptions[name]) then
    error("Improper arguments to WeakAuras.RegisterRegionOptions - region type \""..name.."\" already defined");
  else
  regionOptions[name] = {
    create = createFunction,
    icon = icon,
    displayName = displayName,
    createThumbnail = createThumbnail,
    modifyThumbnail = modifyThumbnail,
    description = description
  };
  end
end

-- This function is replaced in WeakAurasOptions.lua
function WeakAuras.IsOptionsOpen()
  return false;
end

local LBG = LibStub("LibButtonGlow-1.0")
local function WeakAuras_ShowOverlayGlow(frame)
  LBG.ShowOverlayGlow(frame)
end

local function WeakAuras_HideOverlayGlow(frame)
  LBG.HideOverlayGlow(frame)
end

local function forbidden()
  print("|cffffff00A WeakAura that you are using just tried to use a forbidden function but has been blocked from doing so. Please check your auras!|r")
end

local blockedFunctions = {
  -- Lua functions that may allow breaking out of the environment
  getfenv = true,
  setfenv = true,
  loadstring = true,
  pcall = true,
  -- blocked WoW API
  SendMail = true,
  SetTradeMoney = true,
}

local overrideFunctions = {
  ActionButton_ShowOverlayGlow = WeakAuras_ShowOverlayGlow,
  ActionButton_HideOverlayGlow = WeakAuras_HideOverlayGlow,
}

local aura_environments = {};
local current_aura_env = nil;
function WeakAuras.ActivateAuraEnvironment(id)
  if(not id or not db.displays[id]) then
    -- Don't point to the previous aura's environment if an invalid id/display was supplied
    current_aura_env = nil;
  else
    local data = db.displays[id];
    if data.init_completed then
      -- Point the current environment to the correct table
      aura_environments[id] = aura_environments[id] or {};
      current_aura_env = aura_environments[id];
    else
      -- Reset the environment if we haven't completed init, i.e. if we add/update/replace a weakaura
      aura_environments[id] = {};
      current_aura_env = aura_environments[id];
      -- Run the init function if supplied
      local actions = data.actions.init;
      if(actions and actions.do_custom and actions.custom) then
        local func = WeakAuras.LoadFunction("return function() "..(actions.custom).." end");
        if func then
          current_aura_env.id = id;
          func();
        end
      end
      data.init_completed = 1;
    end
    current_aura_env.id = id;
  end
end

local exec_env = setmetatable({}, { __index =
  function(t, k)
    if k == "_G" then
      return t
    elseif k == "aura_env" then
      return current_aura_env;
    elseif blockedFunctions[k] then
      return forbidden
    elseif overrideFunctions[k] then
      return overrideFunctions[k]
    else
      return _G[k]
    end
  end
})

local function_cache = {};
function WeakAuras.LoadFunction(string)
  if function_cache[string] then
    return function_cache[string]
  else
    local loadedFunction, errorString = loadstring(string)
    if errorString then
      print(errorString)
    else
      setfenv(loadedFunction, exec_env)
      local success, func = pcall(assert(loadedFunction))
      if success then
        function_cache[string] = func
        return func
      end
    end
  end
end

local duration_cache = {};
WeakAuras.duration_cache = duration_cache;
local clone_duration_cache = {};
function duration_cache:SetDurationInfo(id, duration, expirationTime, isValue, inverse, cloneId)
  local cache;
  if(cloneId) then
    clone_duration_cache[id] = clone_duration_cache[id] or {};
    clone_duration_cache[id][cloneId] = clone_duration_cache[id][cloneId] or {};
    cache = clone_duration_cache[id][cloneId];
  else
    duration_cache[id] = duration_cache[id] or {};
    cache = duration_cache[id];
  end
  cache.duration = duration;
  cache.expirationTime = expirationTime;
  cache.isValue = isValue;
end

function duration_cache:GetDurationInfo(id, cloneId)
  local cache;
  if(cloneId) then
    --print("GetDurationInfo", id, cloneId);
    --print(clone_duration_cache[id] and clone_duration_cache[id][cloneId]);
    if(clone_duration_cache[id] and clone_duration_cache[id][cloneId]) then
      cache = clone_duration_cache[id][cloneId];
      if(type(cache.isValue) == "function") then
        local value, maxValue = cache.isValue(WeakAuras.GetData(id).trigger);
        return value, maxValue, true;
      else
        return cache.duration, cache.expirationTime, cache.isValue, cache.inverse;
      end
    else
      return 0, math.huge;
    end
    elseif(duration_cache[id]) then
      cache = duration_cache[id]
      if(type(cache.isValue) == "function") then
        local value, maxValue = cache.isValue(WeakAuras.GetData(id).trigger);
        return value, maxValue, true;
      else
        return cache.duration, cache.expirationTime, cache.isValue, cache.inverse;
      end
    else
      return 0, math.huge;
  end
end
WeakAuras.duration_cache = duration_cache;

function WeakAuras.ParseNumber(numString)
  if not(numString and type(numString) == "string") then
  if(type(numString) == "number") then
    return numString, "notastring";
  else
    return nil;
  end
  elseif(numString:sub(-1) == "%") then
  local percent = tonumber(numString:sub(0, -2));
  if(percent) then
    return percent / 100, "percent";
  else
    return nil;
  end
  else
  -- Matches any string with two integers separated by a forward slash
  -- Captures the two integers
  local _, _, numerator, denominator = numString:find("(%d+)%s*/%s*(%d+)");
  numerator, denominator = tonumber(numerator), tonumber(denominator);
  if(numerator and denominator) then
    if(denominator == 0) then
    return nil;
    else
    return numerator / denominator, "fraction";
    end
  else
    local num = tonumber(numString)
    if(num) then
    if(math.floor(num) ~= num) then
      return num, "decimal";
    else
      return num, "whole";
    end
    else
    return nil;
    end
  end
  end
end

function WeakAuras.ConstructFunction(prototype, trigger, inverse)
  local input = {"event"};
  local required = {};
  local tests = {};
  local debug = {};
  local init;
  if(prototype.init) then
    init = prototype.init(trigger);
  else
    init = "";
  end
  for index, arg in pairs(prototype.args) do
    local enable = true;
    if(type(arg.enable) == "function") then
      enable = arg.enable(trigger);
    end
    if(enable) then
      local name = arg.name;
      if not(arg.name or arg.hidden) then
        tinsert(input, "_");
      else
        if(arg.init == "arg") then
          tinsert(input, name);
        end
        if(arg.hidden or arg.type == "tristate" or arg.type == "toggle" or (arg.type == "multiselect" and trigger["use_"..name] ~= nil) or ((trigger["use_"..name] or arg.required) and trigger[name])) then
          if(arg.init and arg.init ~= "arg") then
            init = init.."local "..name.." = "..arg.init.."\n";
          end
          local number = tonumber(trigger[name]);
          local test;
          if(arg.type == "tristate") then
            if(trigger["use_"..name] == false) then
              test = "(not "..name..")";
            elseif(trigger["use_"..name]) then
              if(arg.test) then
                test = "("..arg.test:format(trigger[name])..")";
              else
                test = name;
              end
            end
          elseif(arg.type == "multiselect") then
            if(trigger["use_"..name] == false) then
              test = "(";
              local any = false;
              for value, _ in pairs(trigger[name].multi) do
                if not arg.test then
                  test = test..name.."=="..(tonumber(value) or "\""..value.."\"").." or ";
                else
                  test = test..arg.test:format(tonumber(value) or "\""..value.."\"").." or ";
                end
                any = true;
              end
              if(any) then
                test = test:sub(0, -5);
              else
                test = "(false";
              end
              test = test..")";
            elseif(trigger["use_"..name]) then
              local value = trigger[name].single;
              if not arg.test then
                test = trigger[name].single and "("..name.."=="..(tonumber(value) or "\""..value.."\"")..")";
              else
                test = trigger[name].single and "("..arg.test:format(tonumber(value) or "\""..value.."\"")..")";
              end
            end
          elseif(arg.type == "toggle") then
            if(trigger["use_"..name]) then
              if(arg.test) then
                test = "("..arg.test:format(trigger[name])..")";
              else
                test = name;
              end
            end
          elseif(arg.test) then
            test = "("..arg.test:format(trigger[name])..")";
          elseif(arg.type == "longstring" and trigger[name.."_operator"]) then
            if(trigger[name.."_operator"] == "==") then
              test = "("..name.."==\""..trigger[name].."\")";
            else
              test = "("..name..":"..trigger[name.."_operator"]:format(trigger[name])..")";
            end
          else
            if(type(trigger[name]) == "table") then
              trigger[name] = "error";
            end
            -- if arg.type == "number" and (trigger[name]) and not number then trigger[name] = 0 number = 0 end -- fix corrupt data, ticket #366
            test = "("..name..(trigger[name.."_operator"] or "==")..(number or "\""..(trigger[name] or "").."\"")..")";
          end
          if(arg.required) then
            tinsert(required, test);
          else
            tinsert(tests, test);
          end
          if(arg.debug) then
            tinsert(debug, arg.debug:format(trigger[name]));
          end
        end
      end
    end
  end
  local ret = "return function("..tconcat(input, ", ")..")\n";
  ret = ret..(init or "");

  ret = ret..(#debug > 0 and tconcat(debug, "\n") or "");

  ret = ret.."if(";
  ret = ret..((#required > 0) and tconcat(required, " and ").." and " or "");
  if(inverse) then
    ret = ret.."not ("..(#tests > 0 and tconcat(tests, " and ") or "true")..")";
  else
    ret = ret..(#tests > 0 and tconcat(tests, " and ") or "true");
  end
  ret = ret..") then\n";
  if(#debug > 0) then
    ret = ret.."print('ret: true');\n";
  end
  ret = ret.."return true else return false end end";

  -- print(ret);

  return ret;
end

local pending_aura_scans = {};

WeakAuras.talent_types_specific = {}
function WeakAuras.CreateTalentCache()
  --Initialize a cache for class-specific talent names and icons
  --This is in SavedVariables so it can persist between different classes
  db.talent_cache = db.talent_cache or {}
  --Initialize types lists for each possible class in both SavedVariable and WeakAuras tables
  --Some of the impermanent entries will get filled and some won't, depending on what is in the talent cache
  --The separation is to prevent problems from out-of-date or incorrect info in the talent cache
  for class in pairs(WeakAuras.class_types) do
    WeakAuras.talent_types_specific[class] = {};
    db.talent_cache[class] = db.talent_cache[class] or {};
  end
  local _, player_class = UnitClass("player")
  --Create an entry for the current character's class
  db.talent_cache[player_class] = db.talent_cache[player_class] or {}
  local talentId = 1;
  local numTalents = _G.MAX_NUM_TALENTS or 21;
  local talentName, talentIcon;
  -- @patch 6.0 compatibility quick fix
  local GetTalentInfo = GetTalentInfo
  if not MAX_NUM_TALENTS then GetTalentInfo = function(t) return select(2, _G.GetTalentInfo(ceil(t/3), (t-1)%3 +1, GetActiveSpecGroup())) end end
  while talentId <= numTalents do
    --Get name and icon info for the current talent of the current class and save it for that class
    talentName, talentIcon = GetTalentInfo(talentId)
    db.talent_cache[player_class][talentId] = {
      name = talentName,
      icon = talentIcon
    }
    --Put an entry in the corresponding index for each specific class
    --If the talent is in db.talent_cache for that class, it will be "beautified" (show name and icon)
    --If not, it will be the same as default
    --Class-specific talent_type lists will only be shown if a Load condition for a certain class is set
    --Otherwise, the default is used
    for class in pairs(WeakAuras.class_types) do
      if(db.talent_cache[class] and db.talent_cache[class][talentId]) then
        --Get the icon and name from the talent cache and record it in the table that will be used by WeakAurasOptions
        WeakAuras.talent_types_specific[class][talentId] = "|T"..(db.talent_cache[class][talentId].icon or "error")..":0|t "..(db.talent_cache[class][talentId].name or "error");
      else
        --If there is no data in the cache, just use the default
        WeakAuras.talent_types_specific[class][talentId] = WeakAuras.talent_types[talentId]
      end
    end
    talentId = talentId + 1;
  end
end

local frame = CreateFrame("FRAME", "WeakAurasFrame", UIParent);
WeakAuras.frames["WeakAuras Main Frame"] = frame;
frame:SetAllPoints(UIParent);
local loadedFrame = CreateFrame("FRAME");
WeakAuras.frames["Addon Initialization Handler"] = loadedFrame;
loadedFrame:RegisterEvent("ADDON_LOADED");
loadedFrame:RegisterEvent("PLAYER_ENTERING_WORLD");
loadedFrame:SetScript("OnEvent", function(self, event, addon)
  if(event == "ADDON_LOADED") then
    if(addon == ADDON_NAME) then
      frame:RegisterEvent("PLAYER_FOCUS_CHANGED");
      frame:RegisterEvent("PLAYER_TARGET_CHANGED");
      frame:RegisterEvent("INSTANCE_ENCOUNTER_ENGAGE_UNIT");
      frame:RegisterEvent("UNIT_AURA");
      frame:SetScript("OnEvent", WeakAuras.HandleEvent);

      WeakAurasSaved = WeakAurasSaved or {};
      db = WeakAurasSaved;

      -- Defines the action squelch period after login
      -- Stored in SavedVariables so it can be changed by the user if they find it necessary
      db.login_squelch_time = db.login_squelch_time or 10;

      -- Deprecated fields with *lots* of data, clear them out
      db.iconCache = nil;
      db.iconHash = nil;

      db.tempIconCache = db.tempIconCache or {};

      db.displays = db.displays or {};
      db.registered = db.registered or {};

      WeakAuras.SyncParentChildRelationships();

      local toAdd = {};
      for id, data in pairs(db.displays) do
      if(id ~= data.id) then
        print("|cFF8800FFWeakAuras|r detected corrupt entry in WeakAuras saved displays - '"..tostring(id).."' vs '"..tostring(data.id).."'" );
        data.id = id;
      end
      tinsert(toAdd, data);
      end
      WeakAuras.AddMany(toAdd);
      WeakAuras.AddManyFromAddons(from_files);
      WeakAuras.RegisterDisplay = WeakAuras.AddFromAddon;

      WeakAuras.ResolveCollisions(function() registeredFromAddons = true; end);
      WeakAuras.FixGroupChildrenOrder();
      WeakAuras.RemoveGTFO();

      --> check in case of a disconnect during an encounter.
      if (db.CurrentEncounter) then
        WeakAuras.CheckForPreviousEncounter()
      end
      WeakAuras.Resume();
    end
  elseif(event == "PLAYER_ENTERING_WORLD") then
    -- Schedule events that need to be handled some time after login
    WeakAuras.myGUID = WeakAuras.myGUID or UnitGUID("player")
    timer:ScheduleTimer(function()
         WeakAuras.HandleEvent(frame, "WA_DELAYED_PLAYER_ENTERING_WORLD");
         WeakAuras.CheckCooldownReady();
       end,
       0.5);  -- Data not available
    timer:ScheduleTimer(function() squelch_actions = false; end, db.login_squelch_time);      -- No sounds while loading
    WeakAuras.CreateTalentCache() -- It seems that GetTalentInfo might give info about whatever class was previously being played, until PLAYER_ENTERING_WORLD
  elseif(event == "PLAYER_REGEN_ENABLED") then
    if (queueshowooc) then
      WeakAuras.OpenOptions(queueshowooc)
      queueshowooc = nil
      WeakAuras.frames["Addon Initialization Handler"]:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
  end
end);

function WeakAuras.SetImporting(b)
  importing = b;
end

function WeakAuras.IsImporting()
  return importing;
end

function WeakAuras.IsPaused()
  return paused;
end

function WeakAuras.Pause()
  paused = true;
  -- Forcibly hide all displays, and clear all trigger information (it will be restored on Resume due to forced events)
  for id, region in pairs(regions) do
    region.region:Collapse(); -- ticket 366
    region.region.trigger_count = 0;
    region.region.triggers = region.region.triggers or {};
    wipe(region.region.triggers);
  end

  for id, cloneList in pairs(clones) do
    for cloneId, clone in pairs(cloneList) do
      clone:Collapse();
      clone.trigger_count = 0;
      clone.triggers = clone.triggers or {};
      wipe(clone.triggers);
    end
  end
end

function WeakAuras.Resume()
  paused = false;
  squelch_actions = true;
  WeakAuras.ScanAll();
  squelch_actions = false;
end

function WeakAuras.Toggle()
  if(paused) then
    WeakAuras.Resume();
  else
    WeakAuras.Pause();
  end
end

function WeakAuras.ScanAll()
  for id, region in pairs(regions) do
    region.region:Collapse();
    region.region.trigger_count = 0;
    region.region.triggers = region.region.triggers or {};
    wipe(region.region.triggers);
  end

  for id, cloneList in pairs(clones) do
  for cloneId, clone in pairs(cloneList) do
    clone:Collapse();
    clone.trigger_count = 0;
    clone.triggers = clone.triggers or {};
    wipe(clone.triggers);
  end
  end

  WeakAuras.ReloadAll();

  for unit, auras in pairs(loaded_auras) do
  if(unit == "group") then
    WeakAuras.ScanAurasGroup();
  elseif(WeakAuras.unit_types[unit]) then
    WeakAuras.ScanAuras(unit);
  end
  end
  WeakAuras.ForceEvents();
end

function WeakAuras.ForceEvents()
  for event, v in pairs(WeakAuras.forceable_events) do
    if(type(v) == "table") then
      for index, arg1 in pairs(v) do
      WeakAuras.ScanEvents(event, arg1);
      end
    elseif(event == "SPELL_COOLDOWN_FORCE") then
      WeakAuras.SpellCooldownForce();
    elseif(event == "ITEM_COOLDOWN_FORCE") then
      WeakAuras.ItemCooldownForce();
    elseif(event == "RUNE_COOLDOWN_FORCE") then
      WeakAuras.RuneCooldownForce();
    else
      WeakAuras.ScanEvents(event);
    end
  end
end

local aura_scan_cooldowns = {};
WeakAuras.aura_scan_cooldowns = aura_scan_cooldowns;
local checkingScanCooldowns;
local scanCooldownFrame = CreateFrame("frame");
WeakAuras.frames["Aura Scan Cooldown"] = scanCooldownFrame;

local checkScanCooldownsFunc = function()
  for unit,_ in pairs(aura_scan_cooldowns) do
  aura_scan_cooldowns[unit] = nil;
  WeakAuras.ScanAuras(unit);
  end
  checkingScanCooldowns = nil;
  scanCooldownFrame:SetScript("OnUpdate", nil);
end

function WeakAuras.HandleEvent(frame, event, arg1, arg2, ...)
  if not(paused) then
  if(event == "PLAYER_TARGET_CHANGED") then
    WeakAuras.ScanAuras("target");
  elseif(event == "PLAYER_FOCUS_CHANGED") then
    WeakAuras.ScanAuras("focus");
  elseif(event == "INSTANCE_ENCOUNTER_ENGAGE_UNIT") then
    for unit,_ in pairs(specificBosses) do
    WeakAuras.ScanAuras(unit);
    end
  elseif(event == "UNIT_AURA") then
    if(
    loaded_auras[arg1]
    or (
      loaded_auras["group"]
      and (
      arg1:sub(0, 4) == "raid"
      or arg1:sub(0, 5) == "party"
      )
    )
    or (
      loaded_auras["boss"]
      and arg1:sub(0,4) == "boss"
    )
    ) then
    -- This throttles aura scans to only happen at most once per frame per unit
    if not(aura_scan_cooldowns[arg1]) then
      aura_scan_cooldowns[arg1] = true;
      if not(checkingScanCooldowns) then
      checkingScanCooldowns = true;
      scanCooldownFrame:SetScript("OnUpdate", checkScanCooldownsFunc);
      end
    end
    end
  end
  if(event == "COMBAT_LOG_EVENT_UNFILTERED") then
    if(loaded_events[event] and loaded_events[event][arg2]) then
    WeakAuras.ScanEvents(event, arg1, arg2, ...);
    end
    -- This is triggers the scanning of "hacked" COMBAT_LOG_EVENT_UNFILTERED events that were renamed in order to circumvent
    -- the "proper" COMBAT_LOG_EVENT_UNFILTERED checks
    if(loaded_events["COMBAT_LOG_EVENT_UNFILTERED_CUSTOM"]) then
      WeakAuras.ScanEvents("COMBAT_LOG_EVENT_UNFILTERED_CUSTOM", arg1, arg2, ...);
    end
  else
    if(loaded_events[event]) then
      WeakAuras.ScanEvents(event, arg1, arg2, ...);
    end
  end
  end
end

function WeakAuras.SetEventDynamics(id, triggernum, data, ending)
  local trigger;
  if(triggernum == 0) then
    trigger = db.displays[id] and db.displays[id].trigger;
  else
  trigger = db.displays[id] and db.displays[id].additional_triggers
    and db.displays[id].additional_triggers[triggernum]
    and db.displays[id].additional_triggers[triggernum].trigger;
  end
  if(trigger) then
    WeakAuras.ActivateAuraEnvironment(id);
    if(data.duration) then
      if not(ending) then
        WeakAuras.ActivateEventTimer(id, triggernum, data.duration);
      end
      if(triggernum == 0) then
        if(data.region.SetDurationInfo) then
          local expirationTime = GetTime() + data.duration;
          local resort = data.region.expirationTime ~= expirationTime;
          data.region:SetDurationInfo(data.duration, expirationTime);

          local parent = db.displays[id].parent;
          if (resort and parent and db.displays[parent] and db.displays[parent].regionType == "dynamicgroup") then
            regions[parent].region.ControlChildren();
          end
        end

        duration_cache:SetDurationInfo(id, data.duration, GetTime() + data.duration);
      end
    else
      if(data.durationFunc) then
        local duration, expirationTime, static, inverse = data.durationFunc(trigger);
        duration = type(duration) == "number" and duration or 0;
        expirationTime = type(expirationTime) == "number" and expirationTime or 0;
        if(type(static) == "string") then
          static = data.durationFunc;
        end
        if(duration > 0.01 and not static) then
          local hideOnExpire = true;
          if(data.expiredHideFunc) then
            hideOnExpire = data.expiredHideFunc(trigger);
          end
          if(hideOnExpire and not ending) then
            WeakAuras.ActivateEventTimer(id, triggernum, expirationTime - GetTime());
          end
        end
        if(triggernum == 0) then
          if(data.region.SetDurationInfo) then
            local resort = data.region.expirationTime ~= expirationTime;
            data.region:SetDurationInfo(duration, expirationTime, static, inverse);
            local parent = db.displays[id].parent;
            if (resort and parent and db.displays[parent] and db.displays[parent].regionType == "dynamicgroup") then
              regions[parent].region.ControlChildren();
            end
          end

          duration_cache:SetDurationInfo(id, duration, expirationTime, static, inverse);
        end
      elseif(triggernum == 0) then
        if(data.region.SetDurationInfo) then
          local resort = data.region.expirationTime ~= math.huge;
          data.region:SetDurationInfo(0, math.huge);

          local parent = db.displays[id].parent;
          if (resort and parent and db.displays[parent] and db.displays[parent].regionType == "dynamicgroup") then
            regions[parent].region.ControlChildren();
          end
        end

        duration_cache:SetDurationInfo(id, 0, math.huge);
      end
    end
    if(triggernum == 0) then
      if(data.region.SetName) then
        if(data.nameFunc) then
          data.region:SetName(data.nameFunc(trigger));
        else
          data.region:SetName();
        end
      end
      if(data.region.SetIcon) then
        if(data.iconFunc) then
          data.region:SetIcon(data.iconFunc(trigger));
        else
          data.region:SetIcon();
        end
      end
      if(data.region.SetTexture) then
        if(data.textureFunc) then
          data.region:SetTexture(data.textureFunc(trigger));
        end
      end
      if(data.region.SetStacks) then
        if(data.stacksFunc) then
          data.region:SetStacks(data.stacksFunc(trigger));
        else
          data.region:SetStacks();
        end
      end
      if(data.region.UpdateCustomText and not WeakAuras.IsRegisteredForCustomTextUpdates(data.region)) then
        data.region.UpdateCustomText();
      end
      WeakAuras.UpdateMouseoverTooltip(data.region)
    end
    WeakAuras.ActivateAuraEnvironment(nil);
  else
  error("Event with id \""..id.." and trigger number "..triggernum.." tried to activate, but does not exist");
  end
end

function WeakAuras.ActivateEventTimer(id, triggernum, duration)
  if not(paused) then
    local trigger;
    if(triggernum == 0) then
      trigger = db.displays[id] and db.displays[id].trigger;
    else
      trigger = db.displays[id] and db.displays[id].additional_triggers
      and db.displays[id].additional_triggers[triggernum]
      and db.displays[id].additional_triggers[triggernum].trigger;
    end
    if(trigger and trigger.type == "event" or trigger.type == "custom") then
      local expirationTime = GetTime() + duration;
      local doTimer;
      if(timers[id] and timers[id][triggernum]) then
        if(timers[id][triggernum].expirationTime ~= expirationTime) then
          timer:CancelTimer(timers[id][triggernum].handle);
          doTimer = "change";
        else
          debug("Timer for "..id.." ("..triggernum..") did not change");
        end
      else
        doTimer = "new";
      end

      if(doTimer) then
        timers[id] = timers[id] or {};
        timers[id][triggernum] = timers[id][triggernum] or {};
        local record = timers[id][triggernum];
        if(doTimer == "change") then
          debug("Timer for "..id.." ("..triggernum..") changed from "..(record.expirationTime or "none").." to "..expirationTime);
        elseif(doTimer == "new") then
          debug("Timer for "..id.." ("..triggernum..") will end at "..expirationTime.." ("..duration..")");
        end
        record.handle = timer:ScheduleTimer(function() WeakAuras.EndEvent(id, triggernum, true) end, duration);
        record.expirationTime = expirationTime;
      end
    end
  end
end

-- encounter stuff ~encounter
function WeakAuras.StoreBossGUIDs()
  if (WeakAuras.CurrentEncounter and WeakAuras.CurrentEncounter.boss_guids) then
    for i = 1, 5 do
      if (UnitExists ("boss" .. i)) then
        local guid = UnitGUID ("boss" .. i)
        if (guid) then
          WeakAuras.CurrentEncounter.boss_guids [guid] = true
          --print ("|cFFFFFFAAWeakAuras|r: guid stored for npc", UnitName ("boss" .. i))
        end
      end
    end
    db.CurrentEncounter = WeakAuras.CurrentEncounter
  end
end

function WeakAuras.CheckForPreviousEncounter()
  if (UnitAffectingCombat ("player") or InCombatLockdown()) then
    for i = 1, 5 do
      if (UnitExists ("boss" .. i)) then
        local guid = UnitGUID ("boss" .. i)
        if (guid and db.CurrentEncounter.boss_guids [guid]) then
          --> we are in the same encounter
          WeakAuras.CurrentEncounter = db.CurrentEncounter
          --print ("|cFFFFFFAAWeakAuras|r: found a previous encounter.")
          return true
        end
      end
    end
    db.CurrentEncounter = nil
  else
    db.CurrentEncounter = nil
  end
end

function WeakAuras.DestroyEncounterTable()
  if (WeakAuras.CurrentEncounter) then
    wipe (WeakAuras.CurrentEncounter)
  end
  WeakAuras.CurrentEncounter = nil
  db.CurrentEncounter = nil

  --print ("|cFFFFFFAAWeakAuras|r: Encounter Table destroyed.")
end

function WeakAuras.CreateEncounterTable (encounter_id)
  local _, _, _, _, _, _, _, ZoneMapID = GetInstanceInfo()
  WeakAuras.CurrentEncounter = {
    id = encounter_id,
    zone_id = ZoneMapID,
    boss_guids = {},
  }
  timer:ScheduleTimer(WeakAuras.StoreBossGUIDs, 2)
  --print ("|cFFFFFFAAWeakAuras|r: Encounter Table created.", encounter_id, ZoneMapID)

  return WeakAuras.CurrentEncounter
end

function WeakAuras.ScanForLoads(self, event, arg1)
  -- PET_BATTLE_CLOSE fires twice at the end of a pet battle. IsInBattle evaluates to TRUE during the
  -- first firing, and FALSE during the second. I am not sure if this check is necessary, but the
  -- following IF statement limits the impact of the PET_BATTLE_CLOSE event to the second one.
  if (event == "PET_BATTLE_CLOSE" and C_PetBattles.IsInBattle()) then return end
    if(event == "PLAYER_LEVEL_UP") then
      playerLevel = arg1;
    end

  --> ~encounter id stuff, we are holding the current combat id to further load checks.
  --> there is three ways to unload: encounter_end / zone changed (hearthstone used) / reload or disconnect
  --> regen_enabled isn't good due to combat drop abilities such invisibility, vanish, fake death, etc.
  local encounter_id = WeakAuras.CurrentEncounter and WeakAuras.CurrentEncounter.id or 0

  if (event == "ENCOUNTER_START") then
    encounter_id = tonumber (arg1)
    WeakAuras.CreateEncounterTable (encounter_id)

  elseif (event == "ENCOUNTER_END") then
    encounter_id = 0
    WeakAuras.DestroyEncounterTable()

  elseif (event == "ZONE_CHANGED_NEW_AREA" and WeakAuras.CurrentEncounter) then
    --> player used hearthstone while in a encounter or just left the raid group on raid finder.
    local _, _, _, _, _, _, _, ZoneMapID = GetInstanceInfo()
    --print ("|cFFFFFFAAWeakAuras|r: Zone changed:", ZoneMapID, WeakAuras.CurrentEncounter.zone_id)

    if (ZoneMapID ~= WeakAuras.CurrentEncounter.zone_id) then
      encounter_id = 0
      WeakAuras.DestroyEncounterTable()
    end
  end

  local player, realm, zone, spec, role = UnitName("player"), GetRealmName(),GetRealZoneText(), GetSpecialization(), UnitGroupRolesAssigned("player");
  local _, race = UnitRace("player")
  if role == "NONE" then
    if IsInRaid() then
      for i=1,GetNumGroupMembers() do
        if UnitIsUnit(WeakAuras.raidUnits[i],"player") then
          local _, _, _, _, _, _, _, _, _, raid_role, _, spec_role = GetRaidRosterInfo(i)
          if raid_role and raid_role == "MAINTANK" then role = "TANK" end
          if role == "NONE" then
            if spec and spec > 0 then
              local tmprole = GetSpecializationRole(spec)
              if type(tmprole) == "string" then
                role = tmprole
              end
            end
          end
          break;
        end
      end
    end
  end
  local _, class = UnitClass("player");
  -- 0:none 1:5N 2:5H 3:10N 4:25N 5:10H 6:25H 7:LFR 8:5CH 9:40N
  local inInstance, Type = IsInInstance()
  local _, size, difficulty, instanceType, difficultyIndex;
  local incombat = UnitAffectingCombat("player") -- or UnitAffectingCombat("pet");
  local inpetbattle = C_PetBattles.IsInBattle()
  if (inInstance) then
    _, instanceType, difficultyIndex = GetInstanceInfo();
    size = Type
    if difficultyIndex == 1 then
      size = "party"
      difficulty = "normal"
    elseif difficultyIndex == 2 then
      size = "party"
      difficulty = "heroic"
    elseif difficultyIndex == 3 then
      size = "ten"
      difficulty = "normal"
    elseif difficultyIndex == 4 then
      size = "twentyfive"
      difficulty = "normal"
    elseif difficultyIndex == 5 then
      size = "ten"
      difficulty = "heroic"
    elseif difficultyIndex == 6 then
      size = "twentyfive"
      difficulty = "heroic"
    elseif difficultyIndex == 7 then
      size = "twentyfive"
      difficulty = "lfr"
    elseif difficultyIndex == 8 then
      size = "party"
      difficulty = "challenge"
    elseif difficultyIndex == 9 then
      size = "fortyman"
      difficulty = "normal"
    elseif difficultyIndex == 11 then
      size = "scenario"
      difficulty = "heroic"
    elseif difficultyIndex == 12 then
      size = "scenario"
      difficulty = "normal"
    elseif difficultyIndex == 14 then
      size = "flexible"
      difficulty = "normal"
    elseif difficultyIndex == 15 then
      size = "flexible"
      difficulty = "heroic"
    elseif difficultyIndex == 16 then
      size = "twenty"
      difficulty = "mythic"
    elseif difficultyIndex == 17 then
      size = "flexible"
      difficulty = "lfr"
    end
  else
    size = "none"
    difficulty = "none"
  end

  local changed = 0;
  local shouldBeLoaded, couldBeLoaded;
  for id, triggers in pairs(auras) do
  local _, data = next(triggers);
  shouldBeLoaded = data.load and data.load("ScanForLoads_Auras", incombat, inpetbattle, player, realm, class, spec, race, playerLevel, zone, encounter_id, size, difficulty, role);
  couldBeLoaded = data.load and data.load("ScanForLoads_Auras", true, true, player, realm, class, spec, race, playerLevel, zone, encounter_id, size, difficulty, role);
  if(shouldBeLoaded and not loaded[id]) then
    WeakAuras.LoadDisplay(id);
    changed = changed + 1;
  end
  if(loaded[id] and not shouldBeLoaded) then
    WeakAuras.UnloadDisplay(id);
    data.region.trigger_count = 0;
    data.region.triggers = data.region.triggers or {};
    wipe(data.region.triggers);
    if not(paused) then
    data.region:Collapse();
    WeakAuras.HideAllClones(id);
    end
  end
  if(shouldBeLoaded) then
    loaded[id] = true;
  elseif(couldBeLoaded) then
    loaded[id] = false;
  else
    loaded[id] = nil;
  end
  end
  for id, triggers in pairs(events) do
    local _, data = next(triggers);
    shouldBeLoaded = data.load and data.load("ScanForLoads_Events", incombat, inpetbattle, player, realm, class, spec, race, playerLevel, zone, encounter_id, size, difficulty, role);
    couldBeLoaded = data.load and data.load("ScanForLoads_Events", true, true, player, realm, class, spec, race, playerLevel, zone, encounter_id, size, difficulty, role);
    if(shouldBeLoaded and not loaded[id]) then
      WeakAuras.LoadDisplay(id);
      changed = changed + 1;
    end
    if(loaded[id] and not shouldBeLoaded) then
      WeakAuras.UnloadDisplay(id);
      data.region.trigger_count = 0;
      data.region.triggers = data.region.triggers or {};
      wipe(data.region.triggers);
      if not(paused) then
        data.region:Collapse();
        WeakAuras.HideAllClones(id);
      end
    end
    if(shouldBeLoaded) then
      loaded[id] = true;
    elseif(couldBeLoaded) then
      loaded[id] = false;
    else
      loaded[id] = nil;
    end
  end
  for id, data in pairs(db.displays) do
    if(data.controlledChildren) then
      if(#data.controlledChildren > 0) then
        local any_loaded;
        for index, childId in pairs(data.controlledChildren) do
          if(loaded[childId] ~= nil) then
          any_loaded = true;
          end
        end
        loaded[id] = any_loaded;
      else
        loaded[id] = true;
      end
    end
  end
  if(changed > 0 and not paused) then
    for unit, auras in pairs(loaded_auras) do
      if(unit == "group") then
        WeakAuras.ScanAurasGroup();
      elseif(WeakAuras.unit_types[unit]) then
        WeakAuras.ScanAuras(unit);
      end
    end
    WeakAuras.ForceEvents();
  end
end

local loadFrame = CreateFrame("FRAME");
WeakAuras.loadFrame = loadFrame;
WeakAuras.frames["Display Load Handling"] = loadFrame;

loadFrame:RegisterEvent("ENCOUNTER_START");
loadFrame:RegisterEvent("ENCOUNTER_END");

loadFrame:RegisterEvent("PLAYER_TALENT_UPDATE");
loadFrame:RegisterEvent("ZONE_CHANGED");
loadFrame:RegisterEvent("ZONE_CHANGED_INDOORS");
loadFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA");
loadFrame:RegisterEvent("PLAYER_LEVEL_UP");
loadFrame:RegisterEvent("PLAYER_REGEN_DISABLED");
loadFrame:RegisterEvent("PLAYER_REGEN_ENABLED");

loadFrame:RegisterEvent("PLAYER_ROLES_ASSIGNED");
loadFrame:RegisterEvent("PLAYER_DIFFICULTY_CHANGED");
loadFrame:RegisterEvent("PET_BATTLE_OPENING_START");
loadFrame:RegisterEvent("PET_BATTLE_CLOSE");

loadFrame:SetScript("OnEvent", WeakAuras.ScanForLoads);

function WeakAuras.ReloadAll()
  triggerTypes["aura"].Reloading();
  WeakAuras.UnloadAll();
  WeakAuras.ScanForLoads();
  triggerTypes["aura"].DoneReloading();
end

function WeakAuras.UnloadAll()
  wipe(loaded_events);
  wipe(loaded_auras);
  wipe(loaded);
end

do
  function WeakAuras.LoadDisplay(id)
    for _, triggerSystem in pairs(triggerSystems) do
      triggerSystem.LoadDisplay(id);
    end
  end

  function WeakAuras.UnloadDisplay(id)
    for unitname, auras in pairs(loaded_auras) do
      auras[id] = nil;
    end

    for eventname, events in pairs(loaded_events) do
      if(eventname == "COMBAT_LOG_EVENT_UNFILTERED") then
        for subeventname, subevents in pairs(events) do
          subevents[id] = nil;
        end
      else
        events[id] = nil;
      end
    end
  end
end

function WeakAuras.Delete(data)
  local id = data.id;

  if(data.parent) then
  local parentData = db.displays[data.parent];
  if(parentData and parentData.controlledChildren) then
    for index, childId in pairs(parentData.controlledChildren) do
    if(childId == id) then
      tremove(parentData.controlledChildren, index);
    end
    end
  end
  end

  if(data.controlledChildren) then
  for index, childId in pairs(data.controlledChildren) do
    local childData = db.displays[childId];
    if(childData) then
    childData.parent = nil;
    end
  end
  end

  animations[tostring(regions[id].region)] = nil

  WeakAuras.UnregisterCustomTextUpdates(regions[id].region)
  regions[id].region:SetScript("OnUpdate", nil);
  regions[id].region:SetScript("OnShow", nil);
  regions[id].region:SetScript("OnHide", nil);
  regions[id].region:Hide();

  WeakAuras.HideAllClones(id);

  db.registered[id] = nil;
  if(WeakAuras.importDisplayButtons and WeakAuras.importDisplayButtons[id]) then
  local button = WeakAuras.importDisplayButtons[id];
  button.checkbox:SetChecked(false);
  if(button.updateChecked) then
    button.updateChecked();
  end
  end

  for _, triggerSystem in pairs(triggerSystems) do
    triggerSystem.Delete(id);
  end

  regions[id].region = nil;
  regions[id] = nil;
  loaded[id] = nil;

  db.displays[id] = nil;

  aura_environments[id] = nil;
end

function WeakAuras.Rename(data, newid)
  local oldid = data.id;
  WeakAuras.EveryFrameUpdateRename(oldid, newid)
  if(data.parent) then
  local parentData = db.displays[data.parent];
  if(parentData.controlledChildren) then
    for index, childId in pairs(parentData.controlledChildren) do
    if(childId == data.id) then
      parentData.controlledChildren[index] = newid;
    end
    end
  end
  end

  local temp;

  regions[newid] = regions[oldid];
  regions[oldid] = nil;

  auras[newid] = auras[oldid];
  auras[oldid] = nil;

  loaded_auras[newid] = loaded_auras[oldid];
  loaded_auras[oldid] = nil;

  events[newid] = events[oldid];
  events[oldid] = nil;

  loaded[newid] = loaded[oldid];
  loaded[oldid] = nil;

  for eventname, events in pairs(loaded_events) do
    if(eventname == "COMBAT_LOG_EVENT_UNFILTERED") then
      for subeventname, subevents in pairs(events) do
        subevents[oldid] = subevents[newid];
        subevents[oldid] = nil;
      end
    else
      events[newid] = events[oldid];
      events[oldid] = nil;
    end
  end

  db.displays[newid] = db.displays[oldid];
  db.displays[oldid] = nil;

  if(clones[oldid]) then
    clones[newid] = clones[oldid];
    clones[oldid] = nil;
  end

  db.displays[newid].id = newid;

  if(data.controlledChildren) then
  for index, childId in pairs(data.controlledChildren) do
    local childData = db.displays[childId];
    if(childData) then
    childData.parent = data.id;
    end
  end
  end

  aura_environments[newid] = aura_environments[oldid];
  aura_environments[oldid] = nil;
end

function WeakAuras.Convert(data, newType)
  local id = data.id;
  regions[id].region:SetScript("OnUpdate", nil);
  regions[id].region:Hide();
  WeakAuras.EndEvent(id, 0, true);

  regions[id].region = nil;
  regions[id] = nil;

  data.regionType = newType;
  WeakAuras.Add(data);
end

function WeakAuras.DeepCopy(source, dest)
  local function recurse(source, dest)
  for i,v in pairs(source) do
    if(type(v) == "table") then
    dest[i] = type(dest[i]) == "table" and dest[i] or {};
    recurse(v, dest[i]);
    else
    dest[i] = v;
    end
  end
  end
  recurse(source, dest);
end

function WeakAuras.Copy(sourceid, destid)
  local sourcedata = db.displays[sourceid];
  local destdata = db.displays[destid];
  if(sourcedata and destdata) then
  local oldParent = destdata.parent;
  local oldChildren = destdata.controlledChildren;
  wipe(destdata);
  WeakAuras.DeepCopy(sourcedata, destdata);
  destdata.id = destid;
  destdata.parent = oldParent;
  destdata.controlledChildren = oldChildren;
  WeakAuras.Add(destdata);
  end
end

function WeakAuras.RegisterAddon(addon, displayName, description, icon)
  if(addons[addon]) then
  addons[addon].displayName = displayName;
  addons[addon].description = description;
  addons[addon].icon = icon;
  addons[addon].displays = addons[addon].displays or {};
  else
  addons[addon] = {
    displayName = displayName,
    description = description,
    icon = icon,
    displays = {}
  };
  end
end

function WeakAuras.RegisterDisplay(addon, data, force)
  tinsert(from_files, {addon, data, force});
end

function WeakAuras.AddManyFromAddons(table)
  for _, addData in ipairs(table) do
  WeakAuras.AddFromAddon(addData[1], addData[2], addData[3]);
  end
end

function WeakAuras.AddFromAddon(addon, data, force)
  local id = data.id;
  if(id and addons[addon]) then
  addons[addon].displays[id] = data;
  if(db.registered[id]) then
    -- This display was already registered
    -- It is unnecessary to add it again
  elseif(force and not db.registered[id] == false) then
    if(db.displays[id]) then
    -- ID collision
    collisions[id] = {addon, data};
    else
    db.registered[id] = addon;
    WeakAuras.Add(data);
    end
  end
  end
end

function WeakAuras.CollisionResolved(addon, data, force)
  WeakAuras.AddFromAddon(addon, data, force);
end

function WeakAuras.IsDefinedByAddon(id)
  return db.registered[id];
end

function WeakAuras.ResolveCollisions(onFinished)
  local num = 0;
  for id, _ in pairs(collisions) do
  num = num + 1;
  end

  if(num > 0) then
  local baseText;
  local buttonText;
  if(registeredFromAddons) then
    if(num == 1) then
    baseText = L["Resolve collisions dialog singular"];
    buttonText = L["Done"];
    else
    baseText = L["Resolve collisions dialog"];
    buttonText = L["Next"];
    end
  else
    if(num == 1) then
    baseText = L["Resolve collisions dialog startup singular"];
    buttonText = L["Done"];
    else
    baseText = L["Resolve collisions dialog startup"];
    buttonText = L["Next"];
    end
  end

  local resolved = {};
  local numResolved = 0;
  local currentId = next(collisions);

  local function UpdateText(popup)
    popup.text:SetText(baseText..(numResolved or "error").."/"..(num or "error"));
  end

  StaticPopupDialogs["WEAKAURAS_RESOLVE_COLLISIONS"] = {
    text = baseText,
    button1 = buttonText,
    OnAccept = function(self)
    -- Do the collision resolution
    local newId = self.editBox:GetText();
    if(WeakAuras.OptionsFrame and WeakAuras.OptionsFrame() and WeakAuras.displayButtons and WeakAuras.displayButtons[currentId]) then
      WeakAuras.displayButtons[currentId].callbacks.OnRenameAction(newId)
    else
      local data = WeakAuras.GetData(currentId);
      if(data) then
      WeakAuras.Rename(data, newId);
      else
      print("Data not found");
      end
    end

    WeakAuras.CollisionResolved(collisions[currentId][1], collisions[currentId][2], true);
    resolved[currentId] = newId;
    numResolved = numResolved + 1;

    -- Get the next id to resolve
    currentId = next(collisions, currentId);
    if(currentId) then
      -- There is another conflict to resolve - hook OnHide to reshow the dialog as soon as it hides
      self:SetScript("OnHide", function(self)
      self:Show();
      UpdateText(self);
      self.editBox:SetText(currentId);
      self:SetScript("OnHide", nil);
      if not(next(collisions, currentId)) then
        self.button1:SetText(L["Done"]);
      end
      end);
    else
      self.editBox:SetScript("OnTextChanged", nil);
      wipe(collisions);
      if(onFinished) then
      onFinished();
      end
    end
    end,
    hasEditBox = true,
    hasWideEditBox = true,
    hideOnEscape = true,
    whileDead = true,
    showAlert = true,
    timeout = 0,
    preferredindex = STATICPOPUP_NUMDIALOGS
  };

  local popup = StaticPopup_Show("WEAKAURAS_RESOLVE_COLLISIONS");
  popup.editBox:SetScript("OnTextChanged", function(self)
    local newid = self:GetText();
    if(collisions[newid] or db.displays[newid]) then
    popup.button1:Disable();
    else
    popup.button1:Enable();
    end
  end);
  popup.editBox:SetText(currentId);
  popup.text:SetJustifyH("left");
  popup.icon:SetTexture("Interface\\Addons\\WeakAuras\\icon.tga");
  popup.icon:SetVertexColor(0.833, 0, 1);

  UpdateText(popup);
  elseif(onFinished) then
    onFinished();
  end
end

-- Takes as input a table of display data and attempts to update it to be compatible with the current version
function WeakAuras.Modernize(data)
  -- Add trigger count
  if not data.numTriggers then
    data.numTriggers = 1 + (data.additional_triggers and #data.additional_triggers or 0)
  end

  local load = data.load;
  -- Convert load options into single/multi format
  for index, prototype in pairs(WeakAuras.load_prototype.args) do
    local protoname = prototype.name;
    if(prototype.type == "multiselect") then
      if(not load[protoname] or type(load[protoname]) ~= "table") then
        local value = load[protoname];
        load[protoname] = {};
        if(value) then
          load[protoname].single = value;
        end
      end
      load[protoname].multi = load[protoname].multi or {};
    elseif(load[protoname] and type(load[protoname]) == "table") then
      load[protoname] = nil;
    end
  end

  -- upgrade from singleselecting talents to multi select, see ticket 52
  if (type(load.talent) == "number") then
    local talent = load.talent;
    load.talent = {};
    load.talent.single = talent;
    load.talent.multi = {}
  end
  
  for _, triggerSystem in pairs(triggerSystems) do
    triggerSystem.Modernize(data);
  end

  -- Change English-language class tokens to locale-agnostic versions
  local class_agnosticize = {
  ["Death Knight"] = "DEATHKNIGHT",
  ["Druid"] = "DRUID",
  ["Hunter"] = "HUNTER",
  ["Mage"] = "MAGE",
  ["Monk"] = "MONK",
  ["Paladin"] = "PALADIN",
  ["Priest"] = "PRIEST",
  ["Rogue"] = "ROGUE",
  ["Shaman"] = "SHAMAN",
  ["Warlock"] = "WARLOCK",
  ["Warrior"] = "WARRIOR"
  };
  if(load.class.single) then
    load.class.single = class_agnosticize[load.class.single] or load.class.single;
  end
  if(load.class.multi) then
    for i,v in pairs(load.class.multi) do
      if(class_agnosticize[i]) then
        load.class.multi[class_agnosticize[i]] = true;
        load.class.multi[i] = nil;
      end
    end
  end

  -- Delete conditions fields and convert them to additional triggers
  if(data.conditions) then
    data.additional_triggers = data.additional_triggers or {};
    local condition_trigger = {
      trigger = {
        type = "status",
        unevent = "auto",
        event = "Conditions"
      },
      untrigger = {
      }
    }
    local num = 0;
    for i,v in pairs(data.conditions) do
      if(i == "combat") then
        data.load.use_combat = v;
      else
        condition_trigger.trigger["use_"..i] = v;
        num = num + 1;
      end
    end
    if(num > 0) then
      tinsert(data.additional_triggers, condition_trigger);
    end
    data.conditions = nil;
  end

  -- Add dynamic text info to Progress Bars
  -- Also convert custom displayText to new displayText
  if(data.regionType == "aurabar") then
    data.displayTextLeft = data.displayTextLeft or (not data.auto and data.displayText) or "%n";
    data.displayTextRight = data.displayTextRight or "%p";
  end

  -- Add dynamic text info to icons
  -- Also convert alpha to color
  if(data.regionType == "icon") then
    data.displayStacks = data.displayStacks or "%s";
    if(not data.color) then
      data.color = {1, 1, 1, data.alpha};
    end
  end

  -- Convert Timers to Texts
  if(data.regionType == "timer") then
    data.regionType = "text";
    data.displayText = "%p";
  end

  -- Upgrade some old variables
  if data.regionType == "aurabar" then
    -- "border" changed to "borderEdge"
    if data.border and type(data.border) ~= "boolean" then
      data.borderEdge = data.border;
      data.border = data.borderEdge ~= "None";
    end
    -- Multiple text settings
    if data.textColor then
      if not data.timerColor then
        data.timerColor = {};
        data.timerColor[1] = data.textColor[1];
        data.timerColor[2] = data.textColor[2];
        data.timerColor[3] = data.textColor[3];
        data.timerColor[4] = data.textColor[4];
      end
      if not data.stacksColor then
        data.stacksColor = {};
        data.stacksColor[1] = data.textColor[1];
        data.stacksColor[2] = data.textColor[2];
        data.stacksColor[3] = data.textColor[3];
        data.stacksColor[4] = data.textColor[4];
      end
    end
    -- Multiple text settings
    if data.font then
      if not data.textFont then
        data.textFont = data.font;
      end
      if not data.timerFont then
        data.timerFont = data.font;
      end
      if not data.stacksFont then
        data.stacksFont = data.font;
      end

      data.font = nil;
    end
    -- Multiple text settings
    if data.fontSize then
      if not data.textSize then
        data.textSize = data.fontSize;
      end
      if not data.timerSize then
        data.timerSize = data.fontSize;
      end
      if not data.stacksSize then
        data.stacksSize = data.fontSize;
      end

      data.fontSize = nil;
    end

    -- fontFlags (outline)
    if not data.fontFlags then
        data.fontFlags = "OUTLINE";
    end

  end
end

function WeakAuras.SyncParentChildRelationships(silent)
  local childToParent = {};
  local parentToChild = {};
  for id, data in pairs(db.displays) do
  if(data.parent) then
    if(data.controlledChildren) then
    if not(silent) then
      print("|cFF8800FFWeakAuras|r detected desynchronization in saved variables:", id, "has both child and parent");
    end
    -- A display cannot have both children and a parent
    data.parent = nil;
    elseif(db.displays[data.parent] and db.displays[data.parent].controlledChildren) then
    childToParent[id] = data.parent;
    parentToChild[data.parent] = parentToChild[data.parent] or {};
    parentToChild[data.parent][id] = true;
    else
    if not(silent) then
      print("|cFF8800FFWeakAuras|r detected desynchronization in saved variables:", id, "has a nonexistent parent");
    end
    data.parent = nil;
    end
  end
  end

  for id, data in pairs(db.displays) do
  if(data.controlledChildren) then
    for index, childId in pairs(data.controlledChildren) do
    if not(childToParent[childId] and childToParent[childId] == id) then
      if not(silent) then
      print("|cFF8800FFWeakAuras|r detected desynchronization in saved variables:", id, "thinks it controls", childId, "but does not");
      end
      tremove(data.controlledChildren, index);
    end
    end

    if(parentToChild[id]) then
    for childId, _ in pairs(parentToChild[id]) do
      if not(tContains(data.controlledChildren, childId)) then
      if not(silent) then
        print("|cFF8800FFWeakAuras|r detected desynchronization in saved variables:", id, "does not control", childId, "but should");
      end
      tinsert(data.controlledChildren, childId);
      end
    end
    end
  end
  end
end

function WeakAuras.AddMany(table)
  local idtable = {};
  for _, data in ipairs(table) do
  idtable[data.id] = data;
  end
  local loaded = {};
  local function load(id, depends)
  local data = idtable[id];
  if(data.parent) then
    if(idtable[data.parent]) then
    if(tContains(depends, data.parent)) then
      error("Circular dependency in WeakAuras.AddMany between "..tconcat(depends, ", "));
    else
      if not(loaded[data.parent]) then
      local dependsOut = {};
      for i,v in pairs(depends) do
        dependsOut[i] = v;
      end
      tinsert(dependsOut, data.parent);
      load(data.parent, dependsOut);
      end
    end
    else
    data.parent = nil;
    end
  end
  if not(loaded[id]) then
    WeakAuras.Add(data);
    loaded[id] = true;
  end
  end
  for id, data in pairs(idtable) do
  load(id, {});
  end
  for id, data in pairs(idtable) do
  if(data.regionType == "dynamicgroup") then
    WeakAuras.Add(data);
    regions[id].region:ControlChildren();
  end
  end
end

-- Dummy add function to protect errors from propagating out of the real add function
function WeakAuras.Add(data)
  WeakAuras.Modernize(data);
  WeakAuras.pAdd(data);
  -- local status, err = pcall(WeakAuras.pAdd, data);
  -- if not(status) then
  -- local id = type(data.id) == "string" and data.id or "WeakAurasOptions tempGroup";
  -- print("|cFFFF0000WeakAuras "..id..": "..err);
  -- debug(id..": "..err, 3);
  -- debug(debugstack(1, 6));
  -- WeakAurasFrame:Hide();
  -- error(err);
  -- end
end

function WeakAuras.pAdd(data)
  local id = data.id;
  if not(id) then
    error("Improper arguments to WeakAuras.Add - id not defined");
  elseif (data.controlledChildren) then
    WeakAuras.SetRegion(data);
  else
    local region = WeakAuras.SetRegion(data);
    if (WeakAuras.clones[id]) then
      for cloneId, _ in pairs(WeakAuras.clones[id]) do
        WeakAuras.SetRegion(data, cloneId);
      end
    end

    data.init_completed = nil;
    data.load = data.load or {};
    data.actions = data.actions or {};
    data.actions.init = data.actions.init or {};
    data.actions.start = data.actions.start or {};
    data.actions.finish = data.actions.finish or {};
    local loadFuncStr = WeakAuras.ConstructFunction(load_prototype, data.load);
    local loadFunc = WeakAuras.LoadFunction(loadFuncStr);
    WeakAuras.debug(id.." - Load", 1);
    WeakAuras.debug(loadFuncStr);

    events[id] = nil;
    auras[id] = nil;

    local register_for_frame_updates = false;

    for triggernum=0,(data.numTriggers or 9) do
      local trigger, untrigger;
      if(triggernum == 0) then
      trigger = data.trigger;
      data.untrigger = data.untrigger or {};
      untrigger = data.untrigger;
      elseif(data.additional_triggers and data.additional_triggers[triggernum]) then
      trigger = data.additional_triggers[triggernum].trigger;
      data.additional_triggers[triggernum].untrigger = data.additional_triggers[triggernum].untrigger or {};
      untrigger = data.additional_triggers[triggernum].untrigger;
      end
      local triggerType;
      if(trigger and type(trigger) == "table") then
      triggerType = trigger.type;
      if(triggerType == "aura") then
        trigger.names = trigger.names or {};
          trigger.spellIds = trigger.spellIds or {}
        trigger.unit = trigger.unit or "player";
        trigger.debuffType = trigger.debuffType or "HELPFUL";

        local countFunc, countFuncStr;
        if(trigger.useCount) then
        countFuncStr = function_strings.count:format(trigger.countOperator or ">=", tonumber(trigger.count) or 0);
        countFunc = WeakAuras.LoadFunction(countFuncStr);
        end

        local remFunc, remFuncStr;
        if(trigger.useRem) then
          remFuncStr = function_strings.count:format(trigger.remOperator or ">=", tonumber(trigger.rem) or 0);
          remFunc = WeakAuras.LoadFunction(remFuncStr);
        end

        local group_countFunc, group_countFuncStr;
        if(trigger.unit == "group") then
        local count, countType = WeakAuras.ParseNumber(trigger.group_count);
        if(trigger.group_countOperator and count and countType) then
          if(countType == "whole") then
          group_countFuncStr = function_strings.count:format(trigger.group_countOperator, count);
          else
          group_countFuncStr = function_strings.count_fraction:format(trigger.group_countOperator, count);
          end
        else
          group_countFuncStr = function_strings.count:format(">", 0);
        end
        group_countFunc = WeakAuras.LoadFunction(group_countFuncStr);
        WeakAuras.aura_cache:Watch(id);
        end

        local scanFunc;
        if(trigger.fullscan) then
        scanFunc = function(name, tooltip, isStealable, spellId, debuffClass)
          if (
          (
            (not trigger.use_name) or (
            trigger.name and trigger.name ~= "" and (
              trigger.name_operator == "==" and name == trigger.name
              or trigger.name_operator == "find('%s')" and name:find(trigger.name)
              or trigger.name_operator == "match('%s')" and name:match(trigger.name)
            )
            )
          )
          and (
            (not trigger.use_tooltip) or (
            trigger.tooltip and trigger.tooltip ~= "" and (
              trigger.tooltip_operator == "==" and tooltip == trigger.tooltip
              or trigger.tooltip_operator == "find('%s')" and tooltip:find(trigger.tooltip)
              or trigger.tooltip_operator == "match('%s')" and tooltip:match(trigger.tooltip)
            )
            )
          )
          and ((not trigger.use_stealable) or isStealable)
          and ((not trigger.use_spellId) or spellId == tonumber(trigger.spellId))
          and ((not trigger.use_debuffClass) or debuffClass == trigger.debuffClass)
          ) then
          return true;
          else
          return false;
          end
        end -- end scanFunc
        end

        if(trigger.unit == "multi") then
        WeakAuras.InitMultiAura();
        end

        auras[id] = auras[id] or {};
        auras[id][triggernum] = {
        count = countFunc,
        remFunc = remFunc,
        rem = tonumber(trigger.rem) or 0,
        group_count = group_countFunc,
        fullscan = trigger.fullscan,
        autoclone = trigger.autoclone,
        groupclone = trigger.groupclone,
        subcount = trigger.subcount,
        scanFunc = scanFunc,
        load = loadFunc,
        bar = data.bar,
        timer = data.timer,
        cooldown = data.cooldown,
        icon = data.icon,
        debuffType = trigger.debuffType,
        names = trigger.names,
        spellIds = trigger.spellIds,
        name = trigger.name,
        unit = trigger.unit == "member" and trigger.specificUnit or trigger.unit,
        specificUnit = trigger.unit == "member",
        useCount = trigger.useCount,
        ownOnly = trigger.ownOnly,
        inverse = trigger.inverse and not (trigger.unit == "group" and not trigger.groupclone),
        region = region,
        numAdditionalTriggers = data.additional_triggers and #data.additional_triggers or 0,
        hideAlone = trigger.hideAlone,
        stack_info = trigger.stack_info,
        name_info = trigger.name_info
        };
      elseif(triggerType == "status" or triggerType == "event" or triggerType == "custom") then
        local triggerFuncStr, triggerFunc, untriggerFuncStr, untriggerFunc;
        local trigger_events = {};
        local durationFunc, nameFunc, iconFunc, textureFunc, stacksFunc;
        if(triggerType == "status" or triggerType == "event") then
        if not(trigger.event) then
          error("Improper arguments to WeakAuras.Add - trigger type is \"event\" but event is not defined");
        elseif not(event_prototypes[trigger.event]) then
          if(event_prototypes["Health"]) then
            trigger.event = "Health";
          else
            error("Improper arguments to WeakAuras.Add - no event prototype can be found for event type \""..trigger.event.."\" and default prototype reset failed.");
          end
        elseif(trigger.event == "Combat Log" and not (trigger.subeventPrefix..trigger.subeventSuffix)) then
          error("Improper arguments to WeakAuras.Add - event type is \"Combat Log\" but subevent is not defined");
        else
          triggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], trigger);
          WeakAuras.debug(id.." - "..triggernum.." - Trigger", 1);
          WeakAuras.debug(triggerFuncStr);
          triggerFunc = WeakAuras.LoadFunction(triggerFuncStr);

          durationFunc = event_prototypes[trigger.event].durationFunc;
          nameFunc = event_prototypes[trigger.event].nameFunc;
          iconFunc = event_prototypes[trigger.event].iconFunc;
          textureFunc = event_prototypes[trigger.event].textureFunc;
          stacksFunc = event_prototypes[trigger.event].stacksFunc;

          trigger.unevent = trigger.unevent or "auto";

          if(trigger.unevent == "custom") then
            untriggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], untrigger);
          elseif(trigger.unevent == "auto") then
            untriggerFuncStr = WeakAuras.ConstructFunction(event_prototypes[trigger.event], trigger, true);
          end
          if(untriggerFuncStr) then
            WeakAuras.debug(id.." - "..triggernum.." - Untrigger", 1)
            WeakAuras.debug(untriggerFuncStr);
            untriggerFunc = WeakAuras.LoadFunction(untriggerFuncStr);
          end

          local prototype = event_prototypes[trigger.event];
          if(prototype) then
            trigger_events = prototype.events;
            for index, event in ipairs(trigger_events) do
              frame:RegisterEvent(event);
              -- WeakAuras.cbh.RegisterCallback(WeakAuras.cbh.events, event)
              aceEvents:RegisterMessage(event, WeakAuras.HandleEvent, frame)
              if(type(prototype.force_events) == "boolean" or type(prototype.force_events) == "table") then
              WeakAuras.forceable_events[event] = prototype.force_events;
              end
            end
            if(type(prototype.force_events) == "string") then
              WeakAuras.forceable_events[prototype.force_events] = true;
            end
          end
        end
        else
        triggerFunc = WeakAuras.LoadFunction("return "..(trigger.custom or ""));
        if(trigger.custom_type == "status" or trigger.custom_hide == "custom") then
          untriggerFunc = WeakAuras.LoadFunction("return "..(untrigger.custom or ""));
        end

        if(trigger.customDuration and trigger.customDuration ~= "") then
          durationFunc = WeakAuras.LoadFunction("return "..trigger.customDuration);
        end
        if(trigger.customName and trigger.customName ~= "") then
          nameFunc = WeakAuras.LoadFunction("return "..trigger.customName);
        end
        if(trigger.customIcon and trigger.customIcon ~= "") then
          iconFunc = WeakAuras.LoadFunction("return "..trigger.customIcon);
        end
        if(trigger.customTexture and trigger.customTexture ~= "") then
          textureFunc = WeakAuras.LoadFunction("return "..trigger.customTexture);
        end
        if(trigger.customStacks and trigger.customStacks ~= "") then
          stacksFunc = WeakAuras.LoadFunction("return "..trigger.customStacks);
        end

        if(trigger.custom_type == "status" and trigger.check == "update") then
          register_for_frame_updates = true;
          trigger_events = {"FRAME_UPDATE"};
        else
          trigger_events = WeakAuras.split(trigger.events);
          for index, event in pairs(trigger_events) do
            if(event == "COMBAT_LOG_EVENT_UNFILTERED") then
              -- This is a dirty, lazy, dirty hack. "Proper" COMBAT_LOG_EVENT_UNFILTERED events are indexed by their sub-event types (e.g. SPELL_PERIODIC_DAMAGE),
              -- but custom COMBAT_LOG_EVENT_UNFILTERED events are not guaranteed to have sub-event types. Thus, if the user specifies that they want to use
              -- COMBAT_LOG_EVENT_UNFILTERED, this hack renames the event to COMBAT_LOG_EVENT_UNFILTERED_CUSTOM to circumvent the COMBAT_LOG_EVENT_UNFILTERED checks
              -- that are already in place. Replacing all those checks would be a pain in the ass.
              trigger_events[index] = "COMBAT_LOG_EVENT_UNFILTERED_CUSTOM";
              frame:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED");
            else
              frame:RegisterEvent(event);
              -- WeakAuras.cbh.RegisterCallback(WeakAuras.cbh.events, event)
              aceEvents:RegisterMessage(event, WeakAuras.HandleEvent, frame)
            end
            if(trigger.custom_type == "status") then
              WeakAuras.forceable_events[event] = true;
            end
          end
        end
        end

        events[id] = events[id] or {};
        events[id][triggernum] = {
        trigger = triggerFunc,
        untrigger = untriggerFunc,
        load = loadFunc,
        bar = data.bar,
        timer = data.timer,
        cooldown = data.cooldown,
        icon = data.icon,
        event = trigger.event,
        events = trigger_events,
        inverse = trigger.use_inverse,
        subevent = trigger.event == "Combat Log" and trigger.subeventPrefix and trigger.subeventSuffix and (trigger.subeventPrefix..trigger.subeventSuffix);
        unevent = trigger.unevent,
        durationFunc = durationFunc,
        nameFunc = nameFunc,
        iconFunc = iconFunc,
        textureFunc = textureFunc,
        stacksFunc = stacksFunc,
        expiredHideFunc = triggerType ~= "custom" and event_prototypes[trigger.event].expiredHideFunc,
        region = region,
        numAdditionalTriggers = data.additional_triggers and #data.additional_triggers or 0
        };

        if(
        (
          (
          triggerType == "status"
          or triggerType == "event"
          )
          and trigger.unevent == "timed"
        )
        or (
          triggerType == "custom"
          and trigger.custom_type == "event"
          and trigger.custom_hide == "timed"
        )
        ) then
        events[id][triggernum].duration = tonumber(trigger.duration);
        end
      elseif(triggerType) then
        error("Improper arguments to WeakAuras.Add - display "..id.." trigger type \""..triggerType.."\" is not supported for trigger number "..triggernum);
      end
      end
    end

    if(register_for_frame_updates) then
      WeakAuras.RegisterEveryFrameUpdate(id);
    else
      WeakAuras.UnregisterEveryFrameUpdate(id);
    end

    if(WeakAuras.CanHaveClones(data)) then
      clones[id] = clones[id] or {};
    end

    if not(paused) then
      region:Collapse();
      WeakAuras.ScanForLoads();
    end
  end

  db.displays[id] = data;
end

function WeakAuras.SetRegion(data, cloneId)
  local regionType = data.regionType;
  if not(regionType) then
    error("Improper arguments to WeakAuras.SetRegion - regionType not defined");
  else
    if(regionTypes[regionType]) then
      local id = data.id;
      if not(id) then
        error("Improper arguments to WeakAuras.SetRegion - id not defined");
      else
      local region;
      if(cloneId) then
        region = clones[id][cloneId];
      else
        if((not regions[id]) or (not regions[id].region) or regions[id].regionType ~= regionType) then
          region = regionTypes[regionType].create(frame, data);
          regions[id] = {
            regionType = regionType,
            region = region
          };
        else
          region = regions[id].region;
        end
      end
      WeakAuras.validate(data, regionTypes[regionType].default);

      local parent = frame;
      if(data.parent) then
        if(regions[data.parent]) then
          parent = regions[data.parent].region;
        else
          data.parent = nil;
        end
      end

      local anim_cancelled = WeakAuras.CancelAnimation(region, true, true, true, true, true);

      local pSelfPoint, pAnchor, pAnchorPoint, pX, pY = region:GetPoint(1);

      regionTypes[regionType].modify(parent, region, data);

      if(data.parent and db.displays[data.parent] and db.displays[data.parent].regionType == "dynamicgroup" and pSelfPoint and pAnchor and pAnchorPoint and pX and pY) then
        region:ClearAllPoints();
        region:SetPoint(pSelfPoint, pAnchor, pAnchorPoint, pX, pY);
      end

      data.animation = data.animation or {};
      data.animation.start = data.animation.start or {type = "none"};
      data.animation.main = data.animation.main or {type = "none"};
      data.animation.finish = data.animation.finish or {type = "none"};
      if(WeakAuras.CanHaveDuration(data)) then
        data.animation.start.duration_type = data.animation.start.duration_type or "seconds";
        data.animation.main.duration_type = data.animation.main.duration_type or "seconds";
        data.animation.finish.duration_type = data.animation.finish.duration_type or "seconds";
      else
        data.animation.start.duration_type = "seconds";
        data.animation.main.duration_type = "seconds";
        data.animation.finish.duration_type = "seconds";
      end

      local startMainAnimation = function()
        WeakAuras.Animate("display", id, "main", data.animation.main, region, false, nil, true, cloneId);
      end

      local hideRegion = function()
        region:Hide();
      end

      if(data.parent and db.displays[data.parent] and db.displays[data.parent].regionType == "dynamicgroup") then
        if not(cloneId) then
          parent:PositionChildren();
        end
        function region:Collapse()
          region.toShow = false;
          if(region:IsVisible()) then
            region.toHide = true;
            WeakAuras.PerformActions(data, "finish");
            WeakAuras.Animate("display", id, "finish", data.animation.finish, region, false, hideRegion, nil, cloneId)
            parent:ControlChildren();
          end
        end
        function region:Expand()
          region.toHide = false;

          if(WeakAuras.IsAnimating(region) == "finish" or region.groupHiding or (not region:IsVisible() or (cloneId and region.justCreated))) then
            if(region.preShow) then
              region:PreShow();
            end
            region.toShow = true;
            parent:EnsureTrays();
            region.justCreated = nil;
            WeakAuras.PerformActions(data, "start");
            if not(WeakAuras.Animate("display", id, "start", data.animation.start, region, true, startMainAnimation, nil, cloneId)) then
              startMainAnimation();
            end
            parent:ControlChildren();
          end
        end
      elseif not(data.controlledChildren) then
        function region:Collapse()
          if(region:IsVisible()) then
            WeakAuras.PerformActions(data, "finish");
            if not(WeakAuras.Animate("display", id, "finish", data.animation.finish, region, false, hideRegion, nil, cloneId)) then
            region:Hide();
            end

            if data.parent and db.displays[data.parent] and db.displays[data.parent].regionType == "group" then
            parent:UpdateBorder(region);
            end
          end
        end
        function region:Expand()
          if(WeakAuras.IsAnimating(region) == "finish" or (not region:IsVisible() or (cloneId and region.justCreated))) then
            region.justCreated = nil;
            if(region.PreShow) then
              region:PreShow();
            end
            region:Show();
            WeakAuras.PerformActions(data, "start");
            if not(WeakAuras.Animate("display", id, "start", data.animation.start, region, true, startMainAnimation, nil, cloneId)) then
            startMainAnimation();
            end

            if data.parent and db.displays[data.parent] and db.displays[data.parent].regionType == "group" then
            parent:UpdateBorder(region);
            end
          end
        end
      end
      -- Stubs that allow for polymorphism
      if not region.Collapse then
        function region:Collapse() end
      end
      if not region.Expand then
        function region:Expand() end
      end

      if(cloneId) then
        clonePool[regionType] = clonePool[regionType] or {};
        region:SetScript("OnHide", function()
        if(clones[id]) then
          clones[id][cloneId] = nil;
        end
        clonePool[regionType][#clonePool[regionType]] = region;
        region:SetScript("OnHide", nil);
        end);
      end

      if(data.additional_triggers and #data.additional_triggers > 0) then
        region.trigger_count = region.trigger_count or 0;
        region.triggers = region.triggers or {};

        function region:TestTriggers(trigger_count)
          if(trigger_count > ((data.disjunctive and 0) or #data.additional_triggers)) then
            region:Expand();
            return true;
          else
            region:Collapse();
            return false;
          end
        end

        function region:EnableTrigger(triggernum)
          if not(region.triggers[triggernum]) then
            region.triggers[triggernum] = true;
            region.trigger_count = region.trigger_count + 1;
            return region:TestTriggers(region.trigger_count);
          else
            return nil;
          end
        end

        function region:DisableTrigger(triggernum)
          if(region.triggers[triggernum]) then
            region.triggers[triggernum] = nil;
            region.trigger_count = region.trigger_count - 1;
            return not region:TestTriggers(region.trigger_count);
          else
            return nil;
          end
        end
      end

      if(anim_cancelled) then
        startMainAnimation();
      end

      return region;
      end
    else
      error("Improper arguments to WeakAuras.CreateRegion - regionType \""..data.regionType.."\" is not supported");
    end
  end
end

function WeakAuras.EnsureClone(id, cloneId)
  clones[id] = clones[id] or {};
  if not(clones[id][cloneId]) then
  local data = WeakAuras.GetData(id);
  if(clonePool[data.regionType] and clonePool[data.regionType][1]) then
    clones[id][cloneId] = tremove(clonePool[data.regionType]);
  else
    clones[id][cloneId] = regionTypes[data.regionType].create(frame, data);
  end
  WeakAuras.SetRegion(data, cloneId);
  end
  clones[id][cloneId].justCreated = true;
  return clones[id][cloneId];
end

function WeakAuras.HideAllClones(id)
  if(clones[id]) then
  for i,v in pairs(clones[id]) do
    v:Collapse();
  end
  end
end

function WeakAuras.HideAllClonesExcept(id, list)
  if(clones[id]) then
  for i,v in pairs(clones[id]) do
    if not(list[i]) then
    v:Collapse();
    end
  end
  end
end

-- This function is currently never called if WeakAuras is paused, but it is set up so that it can take a different action
-- if it is called while paused. This is simply because it used to need to deal with that contingency and there's no reason
-- to delete that code (it could be useful in the future)
function WeakAuras.Announce(message, output, _, extra, id, type)
  if(paused) then
    local pausedMessage = "WeakAuras would announce \"%s\" to %s because %s %s, but did not because it is paused.";
    pausedMessage = pausedMessage:format(message, output..(extra and " "..extra or ""), id or "error", type == "start" and "was shown" or type == "finish" and "was hidden" or "error");
    DEFAULT_CHAT_FRAME:AddMessage(pausedMessage);
  else
    SendChatMessage(message, output, _, extra);
  end
end

function WeakAuras.PerformActions(data, type)
  if not(paused or squelch_actions) then
  local actions;
  if(type == "start") then
    actions = data.actions.start;
  elseif(type == "finish") then
    actions = data.actions.finish;
  else
    return;
  end

  if(actions.do_message and actions.message_type and actions.message) then
    if(actions.message_type == "PRINT") then
      DEFAULT_CHAT_FRAME:AddMessage(actions.message, actions.r or 1, actions.g or 1, actions.b or 1);
    elseif(actions.message_type == "COMBAT") then
    if(CombatText_AddMessage) then
      CombatText_AddMessage(actions.message, COMBAT_TEXT_SCROLL_FUNCTION, actions.r or 1, actions.g or 1, actions.b or 1);
    end
    elseif(actions.message_type == "WHISPER") then
    if(actions.message_dest) then
      if(actions.message_dest == "target" or actions.message_dest == "'target'" or actions.message_dest == "\"target\"" or actions.message_dest == "%t" or actions.message_dest == "'%t'" or actions.message_dest == "\"%t\"") then
      WeakAuras.Announce(actions.message, "WHISPER", nil, UnitName("target"), data.id, type);
      else
      WeakAuras.Announce(actions.message, "WHISPER", nil, actions.message_dest, data.id, type);
      end
    end
    elseif(actions.message_type == "CHANNEL") then
    local channel = actions.message_channel and tonumber(actions.message_channel);
    if(GetChannelName(channel)) then
      WeakAuras.Announce(actions.message, "CHANNEL", nil, channel, data.id, type);
    end
    elseif(actions.message_type == "SMARTRAID") then
    if UnitInBattleground("player") then
      SendChatMessage(actions.message, "INSTANCE_CHAT")
    elseif UnitInRaid("player") then
      SendChatMessage(actions.message, "RAID")
    elseif UnitInParty("player") then
      SendChatMessage(actions.message, "PARTY")
    else
      SendChatMessage(actions.message, "SAY")
    end
    else
    WeakAuras.Announce(actions.message, actions.message_type, nil, nil, data.id, type);
    end
  end

  if(actions.do_sound and actions.sound) then
    if(actions.sound == " custom") then
      if(actions.sound_path) then
        PlaySoundFile(actions.sound_path, actions.sound_channel);
      end
      else
        PlaySoundFile(actions.sound, actions.sound_channel);
      end
  end

  if(actions.do_custom and actions.custom) then
    local func = WeakAuras.LoadFunction("return function() "..(actions.custom).." end");
    if func then
      WeakAuras.ActivateAuraEnvironment(data.id);
      func();
      WeakAuras.ActivateAuraEnvironment(nil);
    end
  end

  if(actions.do_glow and actions.glow_action and actions.glow_frame) then
    local glow_frame;
    if(actions.glow_frame:sub(1, 10) == "WeakAuras:") then
      local frame_name = actions.glow_frame:sub(11);
      if(regions[frame_name]) then
        glow_frame = regions[frame_name].region;
      end
    else
      glow_frame = _G[actions.glow_frame];
    end

    if(glow_frame) then
      if(actions.glow_action == "show") then
        WeakAuras_ShowOverlayGlow(glow_frame);
      elseif(actions.glow_action == "hide") then
        WeakAuras_HideOverlayGlow(glow_frame);
      end
    end
  end
  end
end

local updatingAnimations;
local last_update = GetTime();
function WeakAuras.UpdateAnimations()
  for groupId, groupRegion in pairs(pending_controls) do
  pending_controls[groupId] = nil;
  groupRegion:DoControlChildren();
  end
  local time = GetTime();
  local elapsed = time - last_update;
  last_update = time;
  local num = 0;
  for id, anim in pairs(animations) do
  num = num + 1;
  local finished = false;
  if(anim.duration_type == "seconds") then
    if anim.duration > 0 then
      anim.progress = anim.progress + (elapsed / anim.duration);
    else
      anim.progress = anim.progress + (elapsed / 1);
    end
    if(anim.progress >= 1) then
    anim.progress = 1;
    finished = true;
    end
  elseif(anim.duration_type == "relative") then
    local duration, expirationTime, isValue, inverse = duration_cache:GetDurationInfo(anim.name, anim.cloneId);
    if(duration < 0.01) then
    anim.progress = 0;
    if(anim.type == "start" or anim.type == "finish") then
      finished = true;
    end
    else
    local relativeProgress;
    if(isValue) then
      relativeProgress = duration / expirationTime;
    else
      relativeProgress = 1 - ((expirationTime - time) / duration);
    end
    relativeProgress = inverse and (1 - relativeProgress) or relativeProgress;
    anim.progress = relativeProgress / anim.duration
    local iteration = math.floor(anim.progress);
    --anim.progress = anim.progress - iteration;
    if not(anim.iteration) then
      anim.iteration = iteration;
    elseif(anim.iteration ~= iteration) then
      anim.iteration = nil;
      finished = true;
    end
    end
  else
    anim.progress = 1;
  end
  local progress = anim.inverse and (1 - anim.progress) or anim.progress;
  WeakAuras.ActivateAuraEnvironment(anim.name);
  if(anim.translateFunc) then
    anim.region:ClearAllPoints();
    anim.region:SetPoint(anim.selfPoint, anim.anchor, anim.anchorPoint, anim.translateFunc(progress, anim.startX, anim.startY, anim.dX, anim.dY));
  end
  if(anim.alphaFunc) then
    anim.region:SetAlpha(anim.alphaFunc(progress, anim.startAlpha, anim.dAlpha));
  end
  if(anim.scaleFunc) then
    local scaleX, scaleY = anim.scaleFunc(progress, 1, 1, anim.scaleX, anim.scaleY);
    if(anim.region.Scale) then
      anim.region:Scale(scaleX, scaleY);
    else
      anim.region:SetWidth(anim.startWidth * scaleX);
      anim.region:SetHeight(anim.startHeight * scaleY);
    end
  end
  if(anim.rotateFunc and anim.region.Rotate) then
    anim.region:Rotate(anim.rotateFunc(progress, anim.startRotation, anim.rotate));
  end
  if(anim.colorFunc and anim.region.Color) then
    anim.region:Color(anim.colorFunc(progress, anim.startR, anim.startG, anim.startB, anim.startA, anim.colorR, anim.colorG, anim.colorB, anim.colorA));
  end
  WeakAuras.ActivateAuraEnvironment(nil);
  if(finished) then
    if not(anim.loop) then
      if(anim.startX) then
        anim.region:SetPoint(anim.selfPoint, anim.anchor, anim.anchorPoint, anim.startX, anim.startY);
      end
      if(anim.startAlpha) then
        anim.region:SetAlpha(anim.startAlpha);
      end
      if(anim.startWidth) then
        if(anim.region.Scale) then
          anim.region:Scale(1, 1);
        else
          anim.region:SetWidth(anim.startWidth);
          anim.region:SetHeight(anim.startHeight);
        end
      end
      if(anim.startRotation) then
        if(anim.region.Rotate) then
          anim.region:Rotate(anim.startRotation);
        end
      end
      if(anim.startR and anim.startG and anim.startB and anim.startA) then
        if(anim.region.Color) then
          anim.region:Color(anim.startR, anim.startG, anim.startB, anim.startA);
        end
      end
      animations[id] = nil;
      end

      if(anim.onFinished) then
      anim.onFinished();
      end
    end
  end
  -- I tried to have animations only update if there are actually animation data to animate upon.
  -- This caused all start animations to break, and I couldn't figure out why.
  -- May revisit at a later time.
  --[[if(num == 0) then
  WeakAuras.debug("Animation stopped", 3);
  frame:SetScript("OnUpdate", nil);
  updatingAnimations = nil;
  updatingAnimations = nil;
  end]]
end

function WeakAuras.Animate(namespace, id, type, anim, region, inverse, onFinished, loop, cloneId)
  local key = tostring(region);
  local inAnim = anim;
  local valid;
  if(anim and anim.type == "custom" and anim.duration and (anim.use_translate or anim.use_alpha or (anim.use_scale and region.Scale) or (anim.use_rotate and region.Rotate) or (anim.use_color and region.Color))) then
  valid = true;
  elseif(anim and anim.type == "preset" and anim.preset and anim_presets[anim.preset]) then
  anim = anim_presets[anim.preset];
  valid = true;
  end
  if(valid) then
  local progress, duration, selfPoint, anchor, anchorPoint, startX, startY, startAlpha, startWidth, startHeight, startRotation;
  local startR, startG, startB, startA, translateFunc, alphaFunc, scaleFunc, rotateFunc, colorFunc;
  if(animations[key]) then
    if(animations[key].type == type and not loop) then
      return "no replace";
    end
    anim.x = anim.x or 0;
    anim.y = anim.y or 0;
    selfPoint, anchor, anchorPoint, startX, startY = animations[key].selfPoint, animations[key].anchor, animations[key].anchorPoint, animations[key].startX, animations[key].startY;
    anim.alpha = anim.alpha or 0;
    startAlpha = animations[key].startAlpha;
    anim.scalex = anim.scalex or 1;
    anim.scaley = anim.scaley or 1;
    startWidth, startHeight = animations[key].startWidth, animations[key].startHeight;
    anim.rotate = anim.rotate or 0;
    startRotation = animations[key].startRotation;
    anim.colorR = anim.colorR or 1;
    anim.colorG = anim.colorG or 1;
    anim.colorB = anim.colorB or 1;
    anim.colorA = anim.colorA or 1;
    startR = animations[key].startR;
    startG = animations[key].startG;
    startB = animations[key].startB;
    startA = animations[key].startA;
  else
    anim.x = anim.x or 0;
    anim.y = anim.y or 0;
    selfPoint, anchor, anchorPoint, startX, startY = region:GetPoint(1);
    anim.alpha = anim.alpha or 0;
    startAlpha = region:GetAlpha();
    anim.scalex = anim.scalex or 1;
    anim.scaley = anim.scaley or 1;
    startWidth, startHeight = region:GetWidth(), region:GetHeight();
    anim.rotate = anim.rotate or 0;
    startRotation = region.GetRotation and region:GetRotation() or 0;
    anim.colorR = anim.colorR or 1;
    anim.colorG = anim.colorG or 1;
    anim.colorB = anim.colorB or 1;
    anim.colorA = anim.colorA or 1;
    if(region.GetColor) then
      startR, startG, startB, startA = region:GetColor();
    else
      startR, startG, startB, startA = 1, 1, 1, 1;
    end
  end

  if(anim.use_translate) then
    if not(anim.translateType == "custom" and anim.translateFunc) then
      anim.translateType = anim.translateType or "straightTranslate";
      anim.translateFunc = anim_function_strings[anim.translateType] or anim_function_strings.straightTranslate;
    end
    translateFunc = WeakAuras.LoadFunction(anim.translateFunc);
  else
    region:SetPoint(selfPoint, anchor, anchorPoint, startX, startY);
  end
  if(anim.use_alpha) then
    if not(anim.alphaType == "custom" and anim.alphaFunc) then
      anim.alphaType = anim.alphaType or "straight";
      anim.alphaFunc = anim_function_strings[anim.alphaType] or anim_function_strings.straight;
    end
    alphaFunc = WeakAuras.LoadFunction(anim.alphaFunc);
  else
    region:SetAlpha(startAlpha);
  end
  if(anim.use_scale) then
    if not(anim.scaleType == "custom" and anim.scaleFunc) then
      anim.scaleType = anim.scaleType or "straightScale";
      anim.scaleFunc = anim_function_strings[anim.scaleType] or anim_function_strings.straightScale;
    end
    scaleFunc = WeakAuras.LoadFunction(anim.scaleFunc);
  elseif(region.Scale) then
    region:Scale(1, 1);
  end
  if(anim.use_rotate) then
    if not(anim.rotateType == "custom" and anim.rotateFunc) then
      anim.rotateType = anim.rotateType or "straight";
      anim.rotateFunc = anim_function_strings[anim.rotateType] or anim_function_strings.straight;
    end
    rotateFunc = WeakAuras.LoadFunction(anim.rotateFunc);
  elseif(region.Rotate) then
    region:Rotate(startRotation);
  end
  if(anim.use_color) then
    if not(anim.colorType == "custom" and anim.colorFunc) then
      anim.colorType = anim.colorType or "straightColor";
      anim.colorFunc = anim_function_strings[anim.colorType] or anim_function_strings.straightColor;
    end
    colorFunc = WeakAuras.LoadFunction(anim.colorFunc);
  elseif(region.Color) then
    region:Color(startR, startG, startB, startA);
  end

  duration = WeakAuras.ParseNumber(anim.duration) or 0;
  progress = 0;
  if(namespace == "display" and type == "main" and not onFinished and not anim.duration_type == "relative") then
    local data = WeakAuras.GetData(id);
    if(data and data.parent) then
      local parentRegion = regions[data.parent].region;
      if(parentRegion and parentRegion.controlledRegions) then
        for index, regionData in pairs(parentRegion.controlledRegions) do
          local childRegion = regionData.region;
          local childKey = regionData.key;
          if(childKey and childKey ~= tostring(region) and animations[childKey] and animations[childKey].type == "main" and duration == animations[childKey].duration) then
              progress = animations[childKey].progress;
              break;
          end
        end
      end
    end
  end

  if(loop) then
    onFinished = function() WeakAuras.Animate(namespace, id, type, inAnim, region, inverse, onFinished, loop, cloneId) end
  end

  animations[key] = {
    progress = progress,
    startX = startX,
    startY = startY,
    startAlpha = startAlpha,
    startWidth = startWidth,
    startHeight = startHeight,
    startRotation = startRotation,
    startR = startR,
    startG = startG,
    startB = startB,
    startA = startA,
    dX = (anim.use_translate and anim.x),
    dY = (anim.use_translate and anim.y),
    dAlpha = (anim.use_alpha and (anim.alpha - startAlpha)),
    scaleX = (anim.use_scale and anim.scalex),
    scaleY = (anim.use_scale and anim.scaley),
    rotate = anim.rotate,
    colorR = (anim.use_color and anim.colorR),
    colorG = (anim.use_color and anim.colorG),
    colorB = (anim.use_color and anim.colorB),
    colorA = (anim.use_color and anim.colorA),
    translateFunc = translateFunc,
    alphaFunc = alphaFunc,
    scaleFunc = scaleFunc,
    rotateFunc = rotateFunc,
    colorFunc = colorFunc,
    region = region,
    selfPoint = selfPoint,
    anchor = anchor,
    anchorPoint = anchorPoint,
    duration = duration,
    duration_type = anim.duration_type or "seconds",
    inverse = inverse,
    type = type,
    loop = loop,
    onFinished = onFinished,
    name = id,
    cloneId = cloneId
  };
  if not(updatingAnimations) then
    frame:SetScript("OnUpdate", WeakAuras.UpdateAnimations);
    updatingAnimations = true;
  end
  return true;
  else
  if(animations[key]) then
    if(animations[key].type ~= type or loop) then
      WeakAuras.CancelAnimation(region, true, true, true, true, true);
    end
  end
  return false;
  end
end

function WeakAuras.IsAnimating(region)
  local key = tostring(region);
  local anim = animations[key];
  if(anim) then
  return anim.type;
  else
  return nil;
  end
end

function WeakAuras.CancelAnimation(region, resetPos, resetAlpha, resetScale, resetRotation, resetColor, doOnFinished)
  local key = tostring(region);
  local anim = animations[key];

  if(anim) then
    if(resetPos) then
      anim.region:ClearAllPoints();
      anim.region:SetPoint(anim.selfPoint, anim.anchor, anim.anchorPoint, anim.startX, anim.startY);
    end
    if(resetAlpha) then
      anim.region:SetAlpha(anim.startAlpha);
    end
    if(resetScale) then
      if(anim.region.Scale) then
        anim.region:Scale(1, 1);
      else
        anim.region:SetWidth(anim.startWidth);
        anim.region:SetHeight(anim.startHeight);
      end
    end
    if(resetRotation and anim.region.Rotate) then
      anim.region:Rotate(anim.startRotation);
    end
    if(resetColor and anim.region.Color) then
      anim.region:Color(anim.startR, anim.startG, anim.startB, anim.startA);
    end

    animations[key] = nil;
    if(doOnFinished and anim.onFinished) then
      anim.onFinished();
    end
    return true;
    else
      return false;
    end
end

function WeakAuras.GetData(id)
  return id and db.displays[id];
end

function WeakAuras.CanHaveDuration(data)
  local trigger = data.trigger;
  local triggerSystem = triggerTypes[trigger.type];

  if (not triggerSystem) then
    return false;
  end
  return triggerSystem.CanHaveDuration(data);
end

function WeakAuras.CanHaveAuto(data)
  local trigger = data.trigger;
  local triggerSystem = triggerTypes[trigger.type];

  if (not triggerSystem) then
    return false;
  end

  return triggerSystem.CanHaveAuto(data)
end

function WeakAuras.CanGroupShowWithZero(data)
  local trigger = data.trigger;
  local triggerSystem = triggerTypes[trigger.type];

  if (not triggerSystem) then
    return false;
  end

  return triggerSystem.CanGroupShowWithZero(data);
end

function WeakAuras.CanShowNameInfo(data)
  if(data.regionType == "aurabar" or data.regionType == "icon" or data.regionType == "text") then
  return true;
  else
  return false;
  end
end

function WeakAuras.CanShowStackInfo(data)
  if(data.regionType == "aurabar" or data.regionType == "icon" or data.regionType == "text") then
  return true;
  else
  return false;
  end
end

 function WeakAuras.CanHaveClones(data)
  local trigger = data.trigger;
  local triggerSystem = triggerTypes[trigger.type];

  if (not triggerSystem) then
    return false;
  end

  return triggerSystem.CanHaveClones(data);
end

function WeakAuras.CanHaveTooltip(data)
  local trigger = data.trigger;
  if(trigger.type == "aura") then
  if(trigger.unit == "group" and data.trigger.name_info ~= "aura" and not trigger.groupclone) then
    return "playerlist";
  elseif(trigger.fullscan and trigger.unit ~= "group") then
    return "auraindex";
  else
    return "aura";
  end
  elseif(
  (
    data.trigger.type == "event"
    or data.trigger.type == "status"
  )
  and data.trigger.event
  and WeakAuras.event_prototypes[data.trigger.event]
  ) then
  if(WeakAuras.event_prototypes[data.trigger.event].hasSpellID) then
    return "spell";
  elseif(WeakAuras.event_prototypes[data.trigger.event].hasItemID) then
    return "item";
  else
    return false;
  end
  else
  return false;
  end
end

function WeakAuras.CorrectSpellName(input)
  local inputId = tonumber(input);
  if(inputId) then
  local name = GetSpellInfo(inputId);
  if(name) then
    return inputId;
  else
    return nil;
  end
  elseif(input) then
  local link;
  if(input:sub(1,1) == "\124") then
    link = input;
  else
    link = GetSpellLink(input);
  end
  if(link) then
    local itemId = link:match("spell:(%d+)");
    return tonumber(itemId);
  else
    return nil;
  end
  end
end

function WeakAuras.CorrectItemName(input)
  local inputId = tonumber(input);
  if(inputId) then
  local name = GetItemInfo(inputId);
  if(name) then
    return inputId;
  else
    return nil;
  end
  elseif(input) then
  local _, link = GetItemInfo(input);
  if(link) then
    local itemId = link:match("item:(%d+)");
    return tonumber(itemId);
  else
    return nil;
  end
  end
end


local currentTooltipData;
local currentTooltipRegion;
local currentTooltipOwner;
local currentTooltipType;
function WeakAuras.UpdateMouseoverTooltip(region)
  if(region == currentTooltipRegion) then
  WeakAuras.ShowMouseoverTooltip(currentTooltipData, currentTooltipRegion, currentTooltipOwner, currentTooltipType);
  end
end

function WeakAuras.ShowMouseoverTooltip(data, region, owner, tooltipType)
  currentTooltipData = data;
  currentTooltipRegion = region;
  currentTooltipOwner = owner;
  currentTooltipType = tooltipType;
  tooltipType = tooltipType or WeakAuras.CanHaveTooltip(data);

  GameTooltip:SetOwner(owner, "ANCHOR_NONE");
  GameTooltip:SetPoint("LEFT", owner, "RIGHT");
  GameTooltip:ClearLines();
  if(tooltipType == "aura" and region.spellId) then
  GameTooltip:SetSpellByID(region.spellId);
  elseif(tooltipType == "auraindex" and region.index) then
  local unit = data.trigger.unit == "member" and data.trigger.specificUnit or data.trigger.unit;
  if(data.trigger.debuffType == "HELPFUL") then
    GameTooltip:SetUnitBuff(unit, region.index);
  elseif(data.trigger.debuffType == "HARMFUL") then
    GameTooltip:SetUnitDebuff(unit, region.index);
  end
  elseif(tooltipType == "playerlist") then
  local name = "";
  local playerList;
  if(data.trigger.name_info == "players") then
    playerList = WeakAuras.aura_cache:GetAffected(data.trigger.names, data);
    name = L["Affected"]..":";
  elseif(data.trigger.name_info == "nonplayers") then
    playerList = WeakAuras.aura_cache:GetUnaffected(data.trigger.names, data);
    name = L["Missing"]..":";
  end

  local numPlayers = 0;
  for playerName, _ in pairs(playerList) do
    numPlayers = numPlayers + 1;
  end

  if(numPlayers > 0) then
    GameTooltip:AddLine(name);
    local numRaid = IsInRaid() and GetNumGroupMembers() or 0;
    local groupMembers,playersString = {};

    if(numRaid > 0) then
    local playerName, _, subgroup
    for i = 1,numRaid do
      -- Battleground-name, given by GetRaidRosterInfo (name-server) to GetUnitName(...) (name - server) transition
      playerName, _, subgroup = GetRaidRosterInfo(i);

      if(playerName) then
      playerName = playerName:gsub("-", " - ")
      if (playerList[playerName]) then
        groupMembers[subgroup] = groupMembers[subgroup] or {};
        groupMembers[subgroup][playerName] = true
      end
      end
    end
    for subgroup, players in pairs(groupMembers) do
      playersString = L["Group %s"]:format(subgroup)..": ";
      local _,space,class,classColor;
      for playerName, _ in pairs(players) do
      space = playerName:find(" ");
      _, class = UnitClass((space and playerName:sub(0, space - 1) or playerName));
      classColor = WeakAuras.class_color_types[class];
      playersString = playersString..(classColor or "")..(space and playerName:sub(0, space - 1).."*" or playerName)..(classColor and "|r" or "")..(next(players, playerName) and ", " or "");
      end
      GameTooltip:AddLine(playersString);
    end

    else
    local num = 0;
    playersString = "";
    local _,space,class,classColor;
    for playerName, _ in pairs(playerList) do
      space = playerName:find(" ");
      _, class = UnitClass((space and playerName:sub(0, space - 1) or playerName));
      classColor = WeakAuras.class_color_types[class];
      playersString = playersString..(classColor or "")..(space and playerName:sub(0, space - 1).."*" or playerName)..(classColor and "|r" or "")..(next(playerList, playerName) and (", "..(num % 5 == 4 and "\n" or "")) or "");
      num = num + 1;
    end
    GameTooltip:AddLine(playersString);
    end
  else
    GameTooltip:AddLine(name.." "..L["None"]);
  end
  elseif(tooltipType == "spell") then
  GameTooltip:SetSpellByID(data.trigger.spellName);
  elseif(tooltipType == "item") then
  GameTooltip:SetHyperlink("item:"..data.trigger.itemName..":0:0:0:0:0:0:0")
  end
  GameTooltip:Show();
end

function WeakAuras.HideTooltip()
  currentTooltipData = nil;
  currentTooltipRegion = nil;
  currentTooltipOwner = nil;
  currentTooltipType = nil;
  GameTooltip:Hide();
end

do
  local hiddenTooltip;
  function WeakAuras.GetHiddenTooltip()
  if not(hiddenTooltip) then
    hiddenTooltip = CreateFrame("GameTooltip", "WeakAurasTooltip", nil, "GameTooltipTemplate");
    hiddenTooltip:SetOwner(WorldFrame, "ANCHOR_NONE");
    hiddenTooltip:AddFontStrings(
    hiddenTooltip:CreateFontString("$parentTextLeft1", nil, "GameTooltipText"),
    hiddenTooltip:CreateFontString("$parentTextRight1", nil, "GameTooltipText")
    );
  end
  return hiddenTooltip;
  end
end

function WeakAuras.GetAuraTooltipInfo(unit, index, filter)
  local tooltip = WeakAuras.GetHiddenTooltip();
  tooltip:SetUnitAura(unit, index, filter);
  local debuffTypeLine, tooltipTextLine = select(11, tooltip:GetRegions())
  local tooltipText = tooltipTextLine and tooltipTextLine:GetObjectType() == "FontString" and tooltipTextLine:GetText() or "";
  local debuffType = debuffTypeLine and debuffTypeLine:GetObjectType() == "FontString" and debuffTypeLine:GetText() or "";
  local found = false;
  for i,v in pairs(WeakAuras.debuff_class_types) do
  if(v == debuffType) then
    found = true;
    debuffType = i;
    break;
  end
  end
  if not(found) then
  debuffType = "none";
  end
  local tooltipSize,_;
  if(tooltipText) then
    local n2
    _, _, tooltipSize, n2 = tooltipText:find("(%d+),(%d%d%d)")  -- Blizzard likes american digit grouping, e.g. "9123="9,123"   /mikk
  if tooltipSize then
    tooltipSize = tooltipSize..n2
  else
    _, _, tooltipSize = tooltipText:find("(%d+)")
  end
  end
  return tooltipText, debuffType, tonumber(tooltipSize) or 0;
end


local L = WeakAuras.L;
local function tooltip_draw()
  GameTooltip:ClearLines();
  GameTooltip:AddDoubleLine("WeakAuras", versionString, 0.5333, 0, 1, 1, 1, 1);
  GameTooltip:AddDoubleLine(L["By |cFF69CCF0Mirrored|r of Dragonmaw(US) Horde"], "");
  GameTooltip:AddLine(" ");
  if(WeakAuras.IsOptionsOpen()) then
  GameTooltip:AddLine(L["Click to close configuration"], 0, 1, 1);
  else
  GameTooltip:AddLine(L["Click to open configuration"], 0, 1, 1);
  if(paused) then
    GameTooltip:AddLine("|cFFFF0000"..L["Paused"].." - |cFF00FFFF"..L["Shift-Click to resume"], 0, 1, 1);
  else
    GameTooltip:AddLine(L["Shift-Click to pause"], 0, 1, 1);
  end
  end
  GameTooltip:Show();
end

local colorFrame = CreateFrame("frame");
WeakAuras.frames["LDB Icon Recoloring"] = colorFrame;
local colorElapsed = 0;
local colorDelay = 2;
local r, g, b = 0.8, 0, 1;
local r2, g2, b2 = random(2)-1, random(2)-1, random(2)-1;
local tooltip_update_frame = CreateFrame("FRAME");
WeakAuras.frames["LDB Tooltip Updater"] = tooltip_update_frame;
local Broker_WeakAuras;
Broker_WeakAuras = LDB:NewDataObject("WeakAuras", {
  type = "data source",
  text = "WeakAuras",
  icon = "Interface\\AddOns\\WeakAuras\\icon.tga",
  OnClick = function(self, button)
  if(IsShiftKeyDown()) then
    if not(WeakAuras.IsOptionsOpen()) then
    WeakAuras.Toggle();
    end
  else
    WeakAuras.OpenOptions();
  end  end,
  OnEnter = function(self)
  colorFrame:SetScript("OnUpdate", function(self, elaps)
    colorElapsed = colorElapsed + elaps;
    if(colorElapsed > colorDelay) then
    colorElapsed = colorElapsed - colorDelay;
    r, g, b = r2, g2, b2;
    r2, g2, b2 = random(2)-1, random(2)-1, random(2)-1;
    end
    Broker_WeakAuras.iconR = r + (r2 - r) * colorElapsed / colorDelay;
    Broker_WeakAuras.iconG = g + (g2 - g) * colorElapsed / colorDelay;
    Broker_WeakAuras.iconB = b + (b2 - b) * colorElapsed / colorDelay;
  end);

  local elapsed = 0;
  local delay = 1;
  tooltip_update_frame:SetScript("OnUpdate", function(self, elap)
    elapsed = elapsed + elap;
    if(elapsed > delay) then
    elapsed = 0;
    tooltip_draw();
    end
  end);

  -- Section the screen into 6 quadrants (sextrants?) and define the tooltip anchor position based on which quadrant the cursor is in
  local max_x = GetScreenWidth();
  local max_y = GetScreenHeight();
  local x, y = GetCursorPosition();
  local horizontal = (x < (max_x/3) and "LEFT") or ((x >= (max_x/3) and x < ((max_x/3)*2)) and "") or "RIGHT";
  local tooltip_vertical = (y < (max_y/2) and "BOTTOM") or "TOP";
  local anchor_vertical = (y < (max_y/2) and "TOP") or "BOTTOM";

  GameTooltip:SetOwner(self, "ANCHOR_NONE");
  GameTooltip:SetPoint(tooltip_vertical..horizontal, self, anchor_vertical..horizontal);
  tooltip_draw();
  end,
  OnLeave = function(self)
  colorFrame:SetScript("OnUpdate", nil);
  tooltip_update_frame:SetScript("OnUpdate", nil);
  GameTooltip:Hide();
  end,
  iconR = 0.6,
  iconG = 0,
  iconB = 1
});

local FrameTimes = {};
function WeakAuras.ProfileFrames(all)
  UpdateAddOnCPUUsage();
  for name, frame in pairs(WeakAuras.frames) do
  local FrameTime = GetFrameCPUUsage(frame);
  FrameTimes[name] = FrameTimes[name] or 0;
  if(all or FrameTime > FrameTimes[name]) then
    print("|cFFFF0000"..name.."|r -", FrameTime, "-", FrameTime - FrameTimes[name]);
  end
  FrameTimes[name] = FrameTime;
  end
end

local DisplayTimes = {};
function WeakAuras.ProfileDisplays(all)
  UpdateAddOnCPUUsage();
  for id, regionData in pairs(WeakAuras.regions) do
  local DisplayTime = GetFrameCPUUsage(regionData.region, true);
  DisplayTimes[id] = DisplayTimes[id] or 0;
  if(all or DisplayTime > DisplayTimes[id]) then
    print("|cFFFF0000"..id.."|r -", DisplayTime, "-", DisplayTime - DisplayTimes[id]);
  end
  DisplayTimes[id] = DisplayTime;
  end
end

function WeakAuras.RegisterTutorial(name, displayName, description, icon, steps, order)
  tutorials[name] = {
  name = name,
  displayName = displayName,
  description = description,
  icon = icon,
  steps = steps,
  order = order
  };
end

do
  local customTextUpdateFrame;
  local updateRegions = {};

  local function DoCustomTextUpdates()
  for region, _ in pairs(updateRegions) do
    if(region.UpdateCustomText) then
    if(region:IsVisible()) then
      region.UpdateCustomText();
    end
    else
    updateRegions[region] = nil;
    end
  end
  end

  function WeakAuras.InitCustomTextUpdates()
  if not(customTextUpdateFrame) then
    customTextUpdateFrame = CreateFrame("frame");
    customTextUpdateFrame:SetScript("OnUpdate", DoCustomTextUpdates);
  end
  end

  function WeakAuras.RegisterCustomTextUpdates(region)
  WeakAuras.InitCustomTextUpdates();
  updateRegions[region] = true;
  end

  function WeakAuras.UnregisterCustomTextUpdates(region)
  updateRegions[region] = nil;
  end

  function WeakAuras.IsRegisteredForCustomTextUpdates(region)
  return updateRegions[region];
  end
end

function WeakAuras.ValueFromPath(data, path)
  if(#path == 1) then
  return data[path[1]];
  else
  local reducedPath = {};
  for i=2,#path do
    reducedPath[i-1] = path[i];
  end
  return WeakAuras.ValueFromPath(data[path[1]], reducedPath);
  end
end

function WeakAuras.ValueToPath(data, path, value)
  if(#path == 1) then
  data[path[1]] = value;
  else
  local reducedPath = {};
  for i=2,#path do
    reducedPath[i-1] = path[i];
  end
  WeakAuras.ValueToPath(data[path[1]], reducedPath, value);
  end
end

function WeakAuras.FixGroupChildrenOrder()
  for id, data in pairs(db.displays) do
        if(data.controlledChildren) then
      local lowestRegion = WeakAuras.regions[data.controlledChildren[1]] and WeakAuras.regions[data.controlledChildren[1]].region;
      if(lowestRegion) then
        local frameLevel = lowestRegion:GetFrameLevel();
        for i=2,#data.controlledChildren do
          local childRegion = WeakAuras.regions[data.controlledChildren[i]] and WeakAuras.regions[data.controlledChildren[i]].region;
          if(childRegion) then
            frameLevel = frameLevel + 1;
            childRegion:SetFrameLevel(frameLevel);
          end
        end
      end
    end
  end
end

-- Remove GTFO options if GTFO isn't enabled and there are no saved GTFO auras
function WeakAuras.RemoveGTFO()
  if not (WeakAuras.loaded_events["GTFO_DISPLAY"] or (GTFO and GTFO.VersionNumber and tonumber(GTFO.VersionNumber) >= 42000)) then
    for id, data in pairs(db.displays) do
      if (data.trigger.event == "GTFO") then
        return;
      end
      if (data.numTriggers > 1) then
        for i, trigger in pairs(data.additional_triggers) do
          if (trigger.trigger.event == "GTFO") then
            return;
          end
        end
      end
    end
    WeakAuras.event_types["GTFO"] = nil;
  end
end

function WeakAuras.EnsureString(input)
   if (input == nil) then
     return "";
   end
   return tostring(input);
end

-- Handle coroutines
local dynFrame = {};
do
  -- Internal data
  dynFrame.frame = CreateFrame("frame");
  dynFrame.update = {};
  dynFrame.size = 0;

  -- Add an action to be resumed via OnUpdate
  function dynFrame.AddAction(self, name, func)
    if not name then
      name = fmt("NIL", dynFrame.size+1);
    end

    if not dynFrame.update[name] then
      dynFrame.update[name] = func;
      dynFrame.size = dynFrame.size + 1

      dynFrame.frame:Show();
    end
  end

  -- Remove an action from OnUpdate
  function dynFrame.RemoveAction(self, name)
    if dynFrame.update[name] then
      dynFrame.update[name] = nil;
      dynFrame.size = dynFrame.size - 1

      if dynFrame.size == 0 then
        dynFrame.frame:Hide();
      end
    end
  end

  -- Setup frame
  dynFrame.frame:Hide();
  dynFrame.frame:SetScript("OnUpdate", function(self, elapsed)
    -- Start timing
    local start = debugprofilestop();
    local hasData = true;

    -- Resume as often as possible (Limit to 16ms per frame -> 60 FPS)
    while (debugprofilestop() - start < 16 and hasData) do
      -- Stop loop without data
      hasData = false;

      -- Resume all coroutines
      for name, func in pairs(dynFrame.update) do
        -- Loop has data
        hasData = true;

        -- Resume or remove
        if coroutine.status(func) ~= "dead" then
          local err,ret1,ret2 = assert(coroutine.resume(func))
          if err then
            WeakAuras.debug(debugstack(func))
          end
        else
          dynFrame:RemoveAction(name);
        end
      end
    end
  end);
end

WeakAuras.dynFrame = dynFrame;

function WeakAuras.ControlChildren(childid)
  local parent = db.displays[childid].parent;
  if (parent and db.displays[parent] and db.displays[parent].regionType == "dynamicgroup") then
    regions[parent].region.ControlChildren();
  end
end

function WeakAuras.SetTempIconCache(name, icon)
  db.tempIconCache[name] = icon;
end

function WeakAuras.GetTempIconCache(name)
  return db.tempIconCache[name];
end

function WeakAuras.RegisterTriggerSystem(types, triggerSystem)
  for _, v in ipairs(types) do
    triggerTypes[v] = triggerSystem;
  end
  tinsert(triggerSystems, triggerSystem);
end
