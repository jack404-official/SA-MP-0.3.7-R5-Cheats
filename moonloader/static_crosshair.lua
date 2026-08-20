script_name("StaticCrosshair")
script_version("1.0.0")
script_author("Musaigen")
-- > Libraries
local memory = require("memory")

-- > Config
local copy = memory.copy
local patch = {
  use_same_radius_for_all_weapons = false,
  -- If `use_same_radius_for_all_weapons` is false.
  enable_bytecode_no_same = memory.strptr("\xEB\x63\x90"),
  enable_bytecode_no_same_size = 3,
  disable_bytecode_no_same = memory.strptr("\xD9\x40\x08"),
  disable_bytecode_no_same_size = 3,
  -- If `use_same_radius_for_all_weapons` is true.
  enable_bytecode_same = memory.strptr("\x90\x90"),
  enable_bytecode_same_size = 2,
  disable_bytecode_same = memory.strptr("\x7A\x08"),
  disable_bytecode_same_size = 2
}

-- > Entry point
function main()
  -- Enabling patch.
  toggle_patch(true)

  -- Preventing to script die.
  wait(-1)
end

-- > Events
function onScriptTerminate(scr)
  if (scr == script.this) then
    toggle_patch(false)
  end
end

-- > Functions
function toggle_patch(state)
  local use_same_radius = patch.use_same_radius_for_all_weapons
  if (state) then
    if (use_same_radius) then
      copy(0x609D80, patch.enable_bytecode_same,
           patch.enable_bytecode_same_size, true)
    else
      copy(0x609D1D, patch.enable_bytecode_no_same,
           patch.enable_bytecode_no_same_size, true)
    end
  else
    if (use_same_radius) then
      copy(0x609D80, patch.disable_bytecode_same,
           patch.disable_bytecode_same_size, true)
    else
      copy(0x609D1D, patch.disable_bytecode_no_same,
           patch.disable_bytecode_no_same_size, true)
    end
  end
end

