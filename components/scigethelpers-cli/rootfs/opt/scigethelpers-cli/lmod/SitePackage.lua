-- Lmod site package, found through LMOD_PACKAGE_PATH=/opt/scigethelpers-cli/lmod
-- (set by before-notebook.d/46-scigethelpers-cli.sh). Generalized from
-- neurodesk/neurodesktop (config/lmod/SitePackage.lua, MIT) for any sciget
-- domain image.
-- Records each loaded CVMFS or sciget container module for `scigethelpers cite`.
-- Module loading must never fail or wait because of this, so the hook catches
-- every error and only appends one line to a local file.

local hook = require("Hook")

local function tracked_roots()
   local data = os.getenv("XDG_DATA_HOME")
   if data == nil or data == "" then
      data = (os.getenv("HOME") or "") .. "/.local/share"
   end
   local roots = {
      "/cvmfs/",
      -- Modules `sciget install` writes for downloaded containers.
      data .. "/sciget/modules/",
      -- Legacy Neurodesk local container modules.
      "/neurodesktop-storage/containers/modules/",
   }
   local local_dir = os.getenv("NEURODESKTOP_LOCAL_CONTAINERS")
   if local_dir ~= nil and local_dir ~= "" then
      roots[#roots + 1] = local_dir:gsub("/+$", "") .. "/modules/"
   end
   return roots
end

local function is_tracked_module(fn)
   for _, root in ipairs(tracked_roots()) do
      if fn:sub(1, #root) == root then
         return true
      end
   end
   return false
end

local function state_dir()
   local state = os.getenv("XDG_STATE_HOME")
   if state == nil or state == "" then
      local home = os.getenv("HOME")
      if home == nil or home == "" then
         return nil
      end
      state = home .. "/.local/state"
   end
   return state .. "/scigethelpers"
end

local function make_dirs(path)
   local lfs = require("lfs")
   local prefix = ""
   for part in path:gmatch("[^/]+") do
      prefix = prefix .. "/" .. part
      if lfs.attributes(prefix, "mode") == nil then
         lfs.mkdir(prefix)
      end
   end
end

local function record_load(t)
   local fn = t.fn
   local full_name = t.modFullName
   if type(fn) ~= "string" or type(full_name) ~= "string" or not is_tracked_module(fn) then
      return
   end
   local dir = state_dir()
   if dir == nil then
      return
   end
   local name, version = full_name:match("^(.*)/([^/]*)$")
   if name == nil then
      name, version = full_name, ""
   end
   make_dirs(dir)
   local log = io.open(dir .. "/module-usage.tsv", "a")
   if log == nil then
      return
   end
   log:write(name, "\t", version, "\t", os.date("!%Y-%m-%dT%H:%M:%SZ"), "\n")
   log:close()
end

hook.register("load", function(t)
   pcall(record_load, t)
end)
