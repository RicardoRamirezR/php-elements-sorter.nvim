-- lua/tests/lsp_validation_spec.lua

local lsp = require('php-elements-sorter.utils.lsp')
local Result = require('php-elements-sorter.utils.result')

describe('LSP Validation', function()
  describe('Position validation', function()
    it('should validate correct position', function()
      local position = { line = 5, character = 10 }
      local result = lsp.validate_position(position)

      assert.is_true(Result.is_ok(result))
      assert.same(position, result.value)
    end)

    it('should reject nil position', function()
      local result = lsp.validate_position(nil)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('not a table') ~= nil)
    end)

    it('should reject position without line', function()
      local position = { character = 10 }
      local result = lsp.validate_position(position)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('missing line') ~= nil)
    end)

    it('should reject position without character', function()
      local position = { line = 5 }
      local result = lsp.validate_position(position)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('missing character') ~= nil)
    end)

    it('should reject position with non-number line', function()
      local position = { line = 'five', character = 10 }
      local result = lsp.validate_position(position)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('not a number') ~= nil)
    end)

    it('should reject position with negative line', function()
      local position = { line = -1, character = 10 }
      local result = lsp.validate_position(position)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('cannot be negative') ~= nil)
    end)

    it('should reject position with negative character', function()
      local position = { line = 5, character = -1 }
      local result = lsp.validate_position(position)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('cannot be negative') ~= nil)
    end)

    it('should accept position with zero values', function()
      local position = { line = 0, character = 0 }
      local result = lsp.validate_position(position)

      assert.is_true(Result.is_ok(result))
    end)
  end)

  describe('Range validation', function()
    it('should validate correct range', function()
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local result = lsp.validate_range(range)

      assert.is_true(Result.is_ok(result))
      assert.same(range, result.value)
    end)

    it('should reject nil range', function()
      local result = lsp.validate_range(nil)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('not a table') ~= nil)
    end)

    it('should reject range without start', function()
      local range = {
        ['end'] = { line = 10, character = 20 },
      }
      local result = lsp.validate_range(range)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('missing start') ~= nil)
    end)

    it('should reject range without end', function()
      local range = {
        start = { line = 5, character = 10 },
      }
      local result = lsp.validate_range(range)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('missing end') ~= nil)
    end)

    it('should reject range with invalid start position', function()
      local range = {
        start = { line = -1, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local result = lsp.validate_range(range)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('Invalid start') ~= nil)
    end)

    it('should reject range with invalid end position', function()
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = -1 },
      }
      local result = lsp.validate_range(range)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('Invalid end') ~= nil)
    end)

    it('should reject range where end is before start', function()
      local range = {
        start = { line = 10, character = 10 },
        ['end'] = { line = 5, character = 20 },
      }
      local result = lsp.validate_range(range)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('before start') ~= nil)
    end)

    it('should reject range where end char is before start char on same line', function()
      local range = {
        start = { line = 10, character = 20 },
        ['end'] = { line = 10, character = 10 },
      }
      local result = lsp.validate_range(range)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('before start') ~= nil)
    end)

    it('should accept range with same start and end', function()
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 5, character = 10 },
      }
      local result = lsp.validate_range(range)

      assert.is_true(Result.is_ok(result))
    end)
  end)

  describe('is_valid_range (legacy)', function()
    it('should return true for valid range', function()
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }

      assert.is_true(lsp.is_valid_range(range))
    end)

    it('should return false for invalid range', function()
      local range = {
        start = { line = -1, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }

      assert.is_false(lsp.is_valid_range(range))
    end)
  end)

  describe('normalize_range', function()
    it('should normalize negative values to zero', function()
      local range = {
        start = { line = -5, character = -10 },
        ['end'] = { line = 10, character = 20 },
      }
      local result = lsp.normalize_range(range)

      assert.is_true(Result.is_ok(result))
      assert.equals(0, result.value.start.line)
      assert.equals(0, result.value.start.character)
    end)

    it('should keep valid positive values', function()
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local result = lsp.normalize_range(range)

      assert.is_true(Result.is_ok(result))
      assert.equals(5, result.value.start.line)
      assert.equals(10, result.value.start.character)
    end)
  end)

  describe('create_range', function()
    it('should create valid range', function()
      local result = lsp.create_range(5, 10, 10, 20)

      assert.is_true(Result.is_ok(result))
      assert.equals(5, result.value.start.line)
      assert.equals(10, result.value.start.character)
      assert.equals(10, result.value['end'].line)
      assert.equals(20, result.value['end'].character)
    end)

    it('should reject invalid range', function()
      local result = lsp.create_range(10, 10, 5, 20)

      assert.is_true(Result.is_err(result))
    end)
  end)

  describe('position_in_range', function()
    it('should detect position inside range', function()
      local position = { line = 7, character = 15 }
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }

      local result = lsp.position_in_range(position, range)

      assert.is_true(Result.is_ok(result))
      assert.is_true(result.value)
    end)

    it('should detect position before range', function()
      local position = { line = 3, character = 5 }
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }

      local result = lsp.position_in_range(position, range)

      assert.is_true(Result.is_ok(result))
      assert.is_false(result.value)
    end)

    it('should detect position after range', function()
      local position = { line = 15, character = 25 }
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }

      local result = lsp.position_in_range(position, range)

      assert.is_true(Result.is_ok(result))
      assert.is_false(result.value)
    end)

    it('should include position at range start', function()
      local position = { line = 5, character = 10 }
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }

      local result = lsp.position_in_range(position, range)

      assert.is_true(Result.is_ok(result))
      assert.is_true(result.value)
    end)

    it('should include position at range end', function()
      local position = { line = 10, character = 20 }
      local range = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }

      local result = lsp.position_in_range(position, range)

      assert.is_true(Result.is_ok(result))
      assert.is_true(result.value)
    end)
  end)

  describe('ranges_equal', function()
    it('should detect equal ranges', function()
      local range1 = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local range2 = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }

      local result = lsp.ranges_equal(range1, range2)

      assert.is_true(Result.is_ok(result))
      assert.is_true(result.value)
    end)

    it('should detect unequal ranges', function()
      local range1 = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local range2 = {
        start = { line = 5, character = 11 },
        ['end'] = { line = 10, character = 20 },
      }

      local result = lsp.ranges_equal(range1, range2)

      assert.is_true(Result.is_ok(result))
      assert.is_false(result.value)
    end)
  end)

  describe('ranges_overlap', function()
    it('should detect overlapping ranges', function()
      local range1 = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local range2 = {
        start = { line = 7, character = 15 },
        ['end'] = { line = 12, character = 25 },
      }

      local result = lsp.ranges_overlap(range1, range2)

      assert.is_true(Result.is_ok(result))
      assert.is_true(result.value)
    end)

    it('should detect non-overlapping ranges', function()
      local range1 = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local range2 = {
        start = { line = 15, character = 25 },
        ['end'] = { line = 20, character = 30 },
      }

      local result = lsp.ranges_overlap(range1, range2)

      assert.is_true(Result.is_ok(result))
      assert.is_false(result.value)
    end)

    it('should detect adjacent but non-overlapping ranges', function()
      local range1 = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local range2 = {
        start = { line = 10, character = 21 },
        ['end'] = { line = 15, character = 25 },
      }

      local result = lsp.ranges_overlap(range1, range2)

      assert.is_true(Result.is_ok(result))
      assert.is_false(result.value)
    end)

    it('should detect touching ranges as overlapping', function()
      local range1 = {
        start = { line = 5, character = 10 },
        ['end'] = { line = 10, character = 20 },
      }
      local range2 = {
        start = { line = 10, character = 20 },
        ['end'] = { line = 15, character = 25 },
      }

      local result = lsp.ranges_overlap(range1, range2)

      assert.is_true(Result.is_ok(result))
      assert.is_true(result.value)
    end)
  end)

  describe('extract_safe_diagnostic', function()
    it('should extract valid diagnostic', function()
      local nvim_diag = {
        message = 'Error message',
        user_data = {
          lsp = {
            range = {
              start = { line = 5, character = 10 },
              ['end'] = { line = 5, character = 20 },
            },
            message = 'LSP message',
            severity = 1,
            code = 'E001',
            source = 'test',
          },
        },
      }

      local result = lsp.extract_safe_diagnostic(nvim_diag)

      assert.is_true(Result.is_ok(result))
      assert.equals('LSP message', result.value.message)
      assert.equals(1, result.value.severity)
    end)

    it('should reject diagnostic without LSP data', function()
      local nvim_diag = {
        message = 'Error message',
      }

      local result = lsp.extract_safe_diagnostic(nvim_diag)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('missing LSP data') ~= nil)
    end)

    it('should reject diagnostic with invalid range', function()
      local nvim_diag = {
        message = 'Error message',
        user_data = {
          lsp = {
            range = {
              start = { line = -1, character = 10 },
              ['end'] = { line = 5, character = 20 },
            },
          },
        },
      }

      local result = lsp.extract_safe_diagnostic(nvim_diag)

      assert.is_true(Result.is_err(result))
    end)
  end)

  describe('build_safe_diagnostics', function()
    it('should filter valid diagnostics', function()
      local diagnostics = {
        {
          message = 'Valid',
          user_data = {
            lsp = {
              range = {
                start = { line = 5, character = 10 },
                ['end'] = { line = 5, character = 20 },
              },
            },
          },
        },
        {
          message = 'Invalid',
          user_data = {
            lsp = {
              range = {
                start = { line = -1, character = 10 },
                ['end'] = { line = 5, character = 20 },
              },
            },
          },
        },
        {
          message = 'Another valid',
          user_data = {
            lsp = {
              range = {
                start = { line = 10, character = 0 },
                ['end'] = { line = 10, character = 10 },
              },
            },
          },
        },
      }

      local safe = lsp.build_safe_diagnostics(diagnostics)

      assert.equals(2, #safe)
    end)

    it('should return empty list for all invalid diagnostics', function()
      local diagnostics = {
        { message = 'No LSP data' },
        { message = 'No user_data', user_data = {} },
      }

      local safe = lsp.build_safe_diagnostics(diagnostics)

      assert.equals(0, #safe)
    end)

    it('should handle empty list', function()
      local safe = lsp.build_safe_diagnostics({})

      assert.equals(0, #safe)
    end)
  end)
end)
