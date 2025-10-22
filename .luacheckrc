# ============================================================================
# .luacheckrc
# Luacheck configuration for linting
# ============================================================================

-- Lua version
std = "luajit"

-- Globals
globals = {
  "vim",
}

-- Read-only globals
read_globals = {
  "vim",
}

-- Ignore warnings
ignore = {
  "212", -- Unused argument
  "213", -- Unused loop variable
  "631", -- Line too long
}

-- File-specific ignores
files["lua/tests/"] = {
  ignore = { "212", "213" }
}

-- Max line length
max_line_length = 120

-- Max code complexity
max_cyclomatic_complexity = 20

