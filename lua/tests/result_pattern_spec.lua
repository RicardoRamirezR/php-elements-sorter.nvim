-- lua/tests/result_pattern_spec.lua

local Result = require('php-elements-sorter.utils.result')

describe('Result Pattern', function()
  describe('Basic construction', function()
    it('should create successful result with ok()', function()
      local result = Result.ok(42)

      assert.is_true(result.success)
      assert.equals(42, result.value)
      assert.is_nil(result.error)
    end)

    it('should create error result with err()', function()
      local result = Result.err('Something went wrong')

      assert.is_false(result.success)
      assert.is_nil(result.value)
      assert.equals('Something went wrong', result.error)
    end)

    it('should create error result with context', function()
      local result = Result.err('Failed', 'database')

      assert.is_false(result.success)
      assert.is_true(result.error:match('%[database%]') ~= nil)
    end)
  end)

  describe('Type checking', function()
    it('should identify ok results with is_ok()', function()
      local ok_result = Result.ok('success')
      local err_result = Result.err('failure')

      assert.is_true(Result.is_ok(ok_result))
      assert.is_false(Result.is_ok(err_result))
    end)

    it('should identify error results with is_err()', function()
      local ok_result = Result.ok('success')
      local err_result = Result.err('failure')

      assert.is_false(Result.is_err(ok_result))
      assert.is_true(Result.is_err(err_result))
    end)
  end)

  describe('Unwrapping', function()
    it('should unwrap ok result value (method style)', function()
      local result = Result.ok(123)
      local value = result:unwrap_or(0)

      assert.equals(123, value)
    end)

    it('should unwrap ok result value (functional style)', function()
      local result = Result.ok(123)
      local value = Result.unwrap_or(result, 0)

      assert.equals(123, value)
    end)

    it('should return default for error result', function()
      local result = Result.err('failed')
      local value = result:unwrap_or('default')

      assert.equals('default', value)
    end)

    it('should call function for error with unwrap_or_else() (method style)', function()
      local result = Result.err('failed')
      local value = result:unwrap_or_else(function(err)
        return 'recovered: ' .. err
      end)

      assert.equals('recovered: failed', value)
    end)

    it('should call function for error with unwrap_or_else() (functional style)', function()
      local result = Result.err('failed')
      local value = Result.unwrap_or_else(result, function(err)
        return 'recovered: ' .. err
      end)

      assert.equals('recovered: failed', value)
    end)

    it('should not call function for ok with unwrap_or_else()', function()
      local result = Result.ok('success')
      local called = false

      local value = result:unwrap_or_else(function()
        called = true
        return 'never'
      end)

      assert.equals('success', value)
      assert.is_false(called)
    end)
  end)

  describe('Mapping', function()
    it('should map over ok result (method style)', function()
      local result = Result.ok(5)
      local mapped = result:map(function(x)
        return x * 2
      end)

      assert.is_true(Result.is_ok(mapped))
      assert.equals(10, mapped.value)
    end)

    it('should map over ok result (functional style)', function()
      local result = Result.ok(5)
      local mapped = Result.map(result, function(x)
        return x * 2
      end)

      assert.is_true(Result.is_ok(mapped))
      assert.equals(10, mapped.value)
    end)

    it('should not map over error result', function()
      local result = Result.err('error')
      local mapped = result:map(function(x)
        return x * 2
      end)

      assert.is_true(Result.is_err(mapped))
      assert.equals('error', mapped.error)
    end)

    it('should convert to error if map function fails', function()
      local result = Result.ok(5)
      local mapped = result:map(function()
        error('map failed')
      end)

      assert.is_true(Result.is_err(mapped))
      assert.is_true(mapped.error:match('map failed') ~= nil)
    end)

    it('should map over error with map_err() (method style)', function()
      local result = Result.err('original error')
      local mapped = result:map_err(function(err)
        return 'wrapped: ' .. err
      end)

      assert.is_true(Result.is_err(mapped))
      assert.is_true(mapped.error:match('wrapped:') ~= nil)
    end)

    it('should map over error with map_err() (functional style)', function()
      local result = Result.err('original error')
      local mapped = Result.map_err(result, function(err)
        return 'wrapped: ' .. err
      end)

      assert.is_true(Result.is_err(mapped))
      assert.is_true(mapped.error:match('wrapped:') ~= nil)
    end)

    it('should not map error for ok result', function()
      local result = Result.ok('success')
      local mapped = result:map_err(function()
        return 'never'
      end)

      assert.is_true(Result.is_ok(mapped))
      assert.equals('success', mapped.value)
    end)
  end)

  describe('Chaining', function()
    it('should chain operations with and_then() (method style)', function()
      local result = Result.ok(10)
      local chained = result:and_then(function(x)
        return Result.ok(x / 2)
      end)

      assert.is_true(Result.is_ok(chained))
      assert.equals(5, chained.value)
    end)

    it('should chain operations with and_then() (functional style)', function()
      local result = Result.ok(10)
      local chained = Result.and_then(result, function(x)
        return Result.ok(x / 2)
      end)

      assert.is_true(Result.is_ok(chained))
      assert.equals(5, chained.value)
    end)

    it('should stop chain on error', function()
      local result = Result.err('failed')
      local chained = result:and_then(function(x)
        return Result.ok(x * 2)
      end)

      assert.is_true(Result.is_err(chained))
      assert.equals('failed', chained.error)
    end)

    it('should handle errors in chain function', function()
      local result = Result.ok(10)
      local chained = result:and_then(function()
        error('chain failed')
      end)

      assert.is_true(Result.is_err(chained))
      assert.is_true(chained.error:match('chain failed') ~= nil)
    end)
  end)

  describe('Try operations', function()
    it('should wrap successful function with try()', function()
      local result = Result.try(function()
        return 'success'
      end)

      assert.is_true(Result.is_ok(result))
      assert.equals('success', result.value)
    end)

    it('should wrap failed function with try()', function()
      local result = Result.try(function()
        error('operation failed')
      end)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('operation failed') ~= nil)
    end)

    it('should add context to try()', function()
      local result = Result.try(function()
        error('failed')
      end, 'database_operation')

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('%[database_operation%]') ~= nil)
    end)

    it('should wrap function with arguments using try_with()', function()
      local result = Result.try_with(function(a, b)
        return a + b
      end, 'addition', 5, 3)

      assert.is_true(Result.is_ok(result))
      assert.equals(8, result.value)
    end)
  end)

  describe('Collection', function()
    it('should collect successful results', function()
      local results = {
        Result.ok(1),
        Result.ok(2),
        Result.ok(3),
      }

      local collected = Result.collect(results)

      assert.is_true(Result.is_ok(collected))
      assert.same({ 1, 2, 3 }, collected.value)
    end)

    it('should fail on first error', function()
      local results = {
        Result.ok(1),
        Result.err('failed at 2'),
        Result.ok(3),
      }

      local collected = Result.collect(results)

      assert.is_true(Result.is_err(collected))
      assert.is_true(collected.error:match('failed at 2') ~= nil)
    end)

    it('should handle empty collection', function()
      local results = {}
      local collected = Result.collect(results)

      assert.is_true(Result.is_ok(collected))
      assert.same({}, collected.value)
    end)
  end)

  describe('Pattern matching', function()
    it('should match on ok result', function()
      local result = Result.ok(42)
      local matched = Result.match(result, {
        ok = function(value)
          return 'got: ' .. value
        end,
        err = function()
          return 'error'
        end,
      })

      assert.equals('got: 42', matched)
    end)

    it('should match on error result', function()
      local result = Result.err('failed')
      local matched = Result.match(result, {
        ok = function()
          return 'success'
        end,
        err = function(error)
          return 'error: ' .. error
        end,
      })

      assert.equals('error: failed', matched)
    end)

    it('should handle missing handlers', function()
      local result = Result.ok(42)
      local matched = Result.match(result, {
        err = function()
          return 'error'
        end,
      })

      assert.is_nil(matched)
    end)
  end)

  describe('Vim API integration', function()
    it('should wrap successful vim api call', function()
      vim.cmd('enew')
      local bufnr = vim.api.nvim_get_current_buf()

      local result = Result.from_vim_api(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)

      assert.is_true(Result.is_ok(result))
      assert.is_table(result.value)
    end)

    it('should wrap failed vim api call', function()
      local result = Result.from_vim_api(
        vim.api.nvim_buf_get_lines,
        99999, -- Invalid buffer
        0,
        -1,
        false
      )

      assert.is_true(Result.is_err(result))
    end)
  end)

  describe('Expect and panic', function()
    it('should unwrap ok result with expect()', function()
      local result = Result.ok('value')
      local value = Result.expect(result, 'Should have value')

      assert.equals('value', value)
    end)

    it('should panic on error result with expect()', function()
      local result = Result.err('failed')

      assert.has_error(function()
        Result.expect(result, 'Expected success')
      end)
    end)
  end)

  describe('Nullable conversions', function()
    it('should create ok from non-nil value', function()
      local result = Result.from_nullable(42, 'Value is nil')

      assert.is_true(Result.is_ok(result))
      assert.equals(42, result.value)
    end)

    it('should create error from nil value', function()
      local result = Result.from_nullable(nil, 'Value is nil')

      assert.is_true(Result.is_err(result))
      assert.equals('Value is nil', result.error)
    end)

    it('should handle false as valid value', function()
      local result = Result.from_nullable(false, 'Should not fail')

      assert.is_true(Result.is_ok(result))
      assert.equals(false, result.value)
    end)
  end)

  describe('Boolean conversions', function()
    it('should create ok from true condition', function()
      local result = Result.from_bool(true, 'success', 'failed')

      assert.is_true(Result.is_ok(result))
      assert.equals('success', result.value)
    end)

    it('should create error from false condition', function()
      local result = Result.from_bool(false, 'success', 'Condition failed')

      assert.is_true(Result.is_err(result))
      assert.equals('Condition failed', result.error)
    end)

    it('should use default error message', function()
      local result = Result.from_bool(false, 'success')

      assert.is_true(Result.is_err(result))
      assert.equals('Condition was false', result.error)
    end)
  end)

  describe('Real-world scenarios', function()
    it('should handle file operations chain', function()
      vim.cmd('enew')
      local bufnr = vim.api.nvim_get_current_buf()

      -- Set some content
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { 'line 1', 'line 2' })

      local result = Result.from_vim_api(vim.api.nvim_buf_get_lines, bufnr, 0, -1, false)
        :and_then(function(lines)
          -- Transform lines
          local transformed = {}
          for _, line in ipairs(lines) do
            table.insert(transformed, line:upper())
          end
          return Result.ok(transformed)
        end)
        :map(function(lines)
          return #lines
        end)

      assert.is_true(Result.is_ok(result))
      assert.equals(2, result.value)
    end)

    it('should handle validation pipeline', function()
      local function validate_number(value)
        if type(value) ~= 'number' then
          return Result.err('Not a number')
        end
        return Result.ok(value)
      end

      local function validate_positive(value)
        if value <= 0 then
          return Result.err('Not positive')
        end
        return Result.ok(value)
      end

      local function validate_even(value)
        if value % 2 ~= 0 then
          return Result.err('Not even')
        end
        return Result.ok(value)
      end

      -- Valid case
      local result1 = validate_number(42):and_then(validate_positive):and_then(validate_even)

      assert.is_true(Result.is_ok(result1))
      assert.equals(42, result1.value)

      -- Invalid case
      local result2 = validate_number(42)
        :and_then(validate_positive)
        :and_then(validate_even)
        :and_then(function(x)
          return validate_number(x + 1) -- 43 is odd
            :and_then(validate_even)
        end)

      assert.is_true(Result.is_err(result2))
    end)

    it('should handle multiple operations with collect', function()
      vim.cmd('enew')
      local bufnr = vim.api.nvim_get_current_buf()

      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        'line 1',
        'line 2',
        'line 3',
      })

      local results = {
        Result.from_vim_api(vim.api.nvim_buf_get_lines, bufnr, 0, 1, false),
        Result.from_vim_api(vim.api.nvim_buf_get_lines, bufnr, 1, 2, false),
        Result.from_vim_api(vim.api.nvim_buf_get_lines, bufnr, 2, 3, false),
      }

      local collected = Result.collect(results)

      assert.is_true(Result.is_ok(collected))
      assert.equals(3, #collected.value)
    end)
  end)

  describe('Error recovery patterns', function()
    it('should provide fallback with unwrap_or', function()
      local function risky_operation()
        return Result.err('Failed to fetch')
      end

      local value = Result.unwrap_or(risky_operation(), 'default value')

      assert.equals('default value', value)
    end)

    it('should provide computed fallback with unwrap_or_else', function()
      local function risky_operation()
        return Result.err('Network error')
      end

      local value = Result.unwrap_or_else(risky_operation(), function(err)
        return 'Recovered from: ' .. err
      end)

      assert.equals('Recovered from: Network error', value)
    end)

    it('should transform errors with map_err', function()
      local result = Result.err('low-level error'):map_err(function(err)
        return 'High-level error: ' .. err
      end)

      assert.is_true(Result.is_err(result))
      assert.is_true(result.error:match('High%-level') ~= nil)
    end)
  end)
end)
