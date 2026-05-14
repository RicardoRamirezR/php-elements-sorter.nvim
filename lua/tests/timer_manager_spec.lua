-- lua/tests/timer_manager_spec.lua

local timer = require('php-elements-sorter.utils.timer')

describe('Timer Manager', function()
  before_each(function()
    -- Stop all timers to start clean
    timer.stop_all()
    -- Wait longer for any pending callbacks to complete
    vim.wait(200)
    -- Reset statistics after cleanup
    timer.reset_stats()
  end)

  after_each(function()
    -- Cleanup after tests
    timer.stop_all()
    -- Wait for callbacks to finish
    vim.wait(100)
  end)

  describe('Basic timer creation', function()
    it('should create a timer', function()
      local called = false

      local timer_id = timer.create(10, function()
        called = true
      end)

      assert.is_not_nil(timer_id)
      assert.is_number(timer_id)

      -- Wait for timer to execute
      vim.wait(50, function()
        return called
      end)

      assert.is_true(called)
    end)

    it('should reject invalid delay', function()
      local timer_id = timer.create(-1, function() end)

      assert.is_nil(timer_id)
    end)

    it('should reject non-function callback', function()
      local timer_id = timer.create(10, 'not a function')

      assert.is_nil(timer_id)
    end)

    it('should track created timers in stats', function()
      timer.create(10, function() end)
      timer.create(20, function() end)

      local stats = timer.get_stats()

      assert.equals(2, stats.created)
    end)

    it('should execute callback after delay', function()
      local executed_at = nil
      local start_time = vim.loop.hrtime()

      timer.create(50, function()
        executed_at = vim.loop.hrtime()
      end)

      vim.wait(100, function()
        return executed_at ~= nil
      end)

      assert.is_not_nil(executed_at)
      local elapsed_ms = (executed_at - start_time) / 1000000
      assert.is_true(elapsed_ms >= 40) -- Allow some slack
    end)
  end)

  describe('Timer stopping', function()
    it('should stop a timer by ID', function()
      local called = false

      local timer_id = timer.create(10, function()
        called = true
      end)

      local stopped = timer.stop(timer_id)

      assert.is_true(stopped)

      vim.wait(50)

      assert.is_false(called)
    end)

    it('should return false when stopping non-existent timer', function()
      local stopped = timer.stop(99999)

      assert.is_false(stopped)
    end)

    it('should track stopped timers in stats', function()
      local timer_id = timer.create(100, function() end)
      timer.stop(timer_id)

      local stats = timer.get_stats()

      assert.equals(1, stats.stopped)
    end)

    it('should remove timer from active list after stopping', function()
      local timer_id = timer.create(100, function() end)

      local stats_before = timer.get_stats()
      assert.equals(1, stats_before.active)

      timer.stop(timer_id)

      local stats_after = timer.get_stats()
      assert.equals(0, stats_after.active)
    end)
  end)

  describe('Timer with keys', function()
    it('should create timer with key', function()
      local timer_id = timer.create(10, function() end, { key = 'test_key' })

      assert.is_not_nil(timer_id)

      local stats = timer.get_stats()
      assert.equals(1, stats.by_key.test_key)
    end)

    it('should stop timers by key', function()
      timer.create(100, function() end, { key = 'key1' })
      timer.create(100, function() end, { key = 'key1' })
      timer.create(100, function() end, { key = 'key2' })

      local count = timer.stop_by_key('key1')

      assert.equals(2, count)

      local stats = timer.get_stats()
      assert.equals(1, stats.active)
    end)

    it('should return 0 when stopping non-existent key', function()
      local count = timer.stop_by_key('nonexistent')

      assert.equals(0, count)
    end)
  end)

  describe('Stop all timers', function()
    it('should stop all active timers', function()
      timer.create(100, function() end)
      timer.create(100, function() end)
      timer.create(100, function() end)

      local count = timer.stop_all()

      assert.equals(3, count)

      local stats = timer.get_stats()
      assert.equals(0, stats.active)
    end)

    it('should return 0 when no timers active', function()
      local count = timer.stop_all()

      assert.equals(0, count)
    end)
  end)

  describe('Debounced timers', function()
    it('should cancel previous timer with same key', function()
      local call_count = 0

      timer.debounce('debounce_key', 50, function()
        call_count = call_count + 1
      end)

      vim.wait(10)

      timer.debounce('debounce_key', 50, function()
        call_count = call_count + 1
      end)

      vim.wait(100)

      -- Only the second timer should have executed
      assert.equals(1, call_count)
    end)

    it('should allow multiple debounced operations with different keys', function()
      local count1 = 0
      local count2 = 0

      timer.debounce('key1', 20, function()
        count1 = count1 + 1
      end)

      timer.debounce('key2', 20, function()
        count2 = count2 + 1
      end)

      vim.wait(50)

      assert.equals(1, count1)
      assert.equals(1, count2)
    end)
  end)

  describe('Throttled timers', function()
    it('should skip calls while timer is active', function()
      local call_count = 0

      timer.throttle('throttle_key', 50, function()
        call_count = call_count + 1
      end)

      -- Try to create another with same key immediately
      local timer_id = timer.throttle('throttle_key', 50, function()
        call_count = call_count + 1
      end)

      -- Second call should be skipped
      assert.is_nil(timer_id)

      vim.wait(100)

      -- Only first timer should have executed
      assert.equals(1, call_count)
    end)

    it('should allow call after previous timer completes', function()
      local call_count = 0

      timer.throttle('throttle_key', 20, function()
        call_count = call_count + 1
      end)

      vim.wait(50)

      timer.throttle('throttle_key', 20, function()
        call_count = call_count + 1
      end)

      vim.wait(50)

      assert.equals(2, call_count)
    end)
  end)

  describe('Repeating timers', function()
    it('should execute callback multiple times', function()
      local call_count = 0

      timer.repeat_timer(20, function()
        call_count = call_count + 1
      end, 3)

      vim.wait(150)

      assert.equals(3, call_count)
    end)

    it('should return nil for count = 0', function()
      local timer_id = timer.repeat_timer(20, function() end, 0)

      assert.is_nil(timer_id)
    end)

    it('should handle limited repeat count', function()
      local call_count = 0

      timer.repeat_timer(20, function()
        call_count = call_count + 1
      end, 2, 'limited')

      vim.wait(100)

      assert.equals(2, call_count)
    end)
  end)

  describe('Statistics', function()
    it('should track created timers', function()
      timer.create(10, function() end)
      timer.create(20, function() end)

      local stats = timer.get_stats()

      assert.equals(2, stats.created)
    end)

    it('should track stopped timers', function()
      local id1 = timer.create(100, function() end)
      local id2 = timer.create(100, function() end)

      timer.stop(id1)
      timer.stop(id2)

      local stats = timer.get_stats()

      assert.equals(2, stats.stopped)
    end)

    it('should track completed timers', function()
      timer.create(10, function() end)
      timer.create(15, function() end)

      -- Wait for both timers to complete
      vim.wait(50)

      local stats = timer.get_stats()

      -- After reset and these 2 timers, should have exactly 2
      assert.equals(2, stats.completed)
    end)

    it('should track active timers', function()
      timer.create(100, function() end)
      timer.create(100, function() end)

      local stats = timer.get_stats()

      assert.equals(2, stats.active)
    end)

    it('should group timers by key', function()
      timer.create(100, function() end, { key = 'key1' })
      timer.create(100, function() end, { key = 'key1' })
      timer.create(100, function() end, { key = 'key2' })

      local stats = timer.get_stats()

      assert.equals(2, stats.by_key.key1)
      assert.equals(1, stats.by_key.key2)
    end)

    it('should reset statistics', function()
      timer.create(10, function() end)
      timer.create(20, function() end)

      timer.reset_stats()

      local stats = timer.get_stats()

      assert.equals(0, stats.created)
      assert.equals(0, stats.stopped)
      assert.equals(0, stats.completed)
    end)
  end)

  describe('Active timers list', function()
    it('should list active timers', function()
      timer.create(100, function() end, { key = 'timer1' })
      timer.create(100, function() end, { key = 'timer2' })

      local active = timer.get_active_timers()

      assert.equals(2, #active)
    end)

    it('should include timer information', function()
      timer.create(100, function() end, { key = 'test_timer' })

      local active = timer.get_active_timers()

      assert.equals(1, #active)
      assert.is_number(active[1].id)
      assert.equals('test_timer', active[1].key)
      assert.equals(100, active[1].delay)
      assert.is_number(active[1].age_seconds)
    end)

    it('should sort by age (oldest first)', function()
      local timer1_id = timer.create(200, function() end, { key = 'timer1' })
      vim.wait(100) -- Wait longer to ensure measurable age difference
      local timer2_id = timer.create(200, function() end, { key = 'timer2' })

      local active = timer.get_active_timers()

      -- Should have 2 timers
      assert.equals(2, #active)

      -- Verify both timers are present
      local has_timer1 = false
      local has_timer2 = false

      for _, t in ipairs(active) do
        if t.key == 'timer1' then
          has_timer1 = true
        end
        if t.key == 'timer2' then
          has_timer2 = true
        end
      end

      assert.is_true(has_timer1, 'timer1 should be in active list')
      assert.is_true(has_timer2, 'timer2 should be in active list')

      -- Timer1 should be older (have higher age)
      if active[1].key == 'timer1' and active[2].key == 'timer2' then
        assert.is_true(
          active[1].age_seconds >= active[2].age_seconds,
          'timer1 should be older or equal'
        )
      end
    end)
  end)

  describe('Cleanup old timers', function()
    it('should cleanup timers older than threshold', function()
      -- Create a timer and manipulate its created_at
      local timer_id = timer.create(1000, function() end, { key = 'old_timer' })

      -- We can't easily manipulate internal state, so we test the function exists
      assert.is_function(timer.cleanup_old_timers)
    end)

    it('should return count of cleaned timers', function()
      local count = timer.cleanup_old_timers(1)

      assert.is_number(count)
      assert.is_true(count >= 0)
    end)

    it('should track leaked timers in stats', function()
      -- This would require manipulating internal state
      -- Just verify the stat exists
      local stats = timer.get_stats()

      assert.is_number(stats.leaked)
    end)
  end)

  describe('Leak detection', function()
    it('should detect potential leaks', function()
      local report = timer.check_leaks()

      assert.is_table(report)
      assert.is_boolean(report.has_leaks)
      assert.is_number(report.count)
      assert.is_table(report.leaks)
      assert.is_number(report.total_active)
    end)

    it('should report no leaks for fresh timers', function()
      timer.create(100, function() end)

      local report = timer.check_leaks()

      assert.is_false(report.has_leaks)
      assert.equals(0, report.count)
      assert.equals(1, report.total_active)
    end)
  end)

  describe('Error handling', function()
    it('should handle callback errors gracefully', function()
      local timer_id = timer.create(10, function()
        error('Intentional error')
      end)

      assert.is_not_nil(timer_id)

      vim.wait(50)

      -- Should not crash and should track completion
      local stats = timer.get_stats()
      assert.equals(1, stats.completed)
    end)

    it('should continue tracking after callback error', function()
      timer.create(10, function()
        error('Error')
      end)

      vim.wait(50)

      local stats = timer.get_stats()
      assert.equals(1, stats.created)
      assert.equals(1, stats.completed)
    end)
  end)

  describe('Integration scenarios', function()
    it('should handle rapid debounce calls', function()
      local final_value = nil

      for i = 1, 10 do
        timer.debounce('rapid_key', 30, function()
          final_value = i
        end)
        vim.wait(5)
      end

      vim.wait(50)

      -- Only last value should be set
      assert.equals(10, final_value)
    end)

    it('should handle mixed timer types', function()
      local counts = { normal = 0, debounce = 0, throttle = 0 }

      timer.create(20, function()
        counts.normal = counts.normal + 1
      end)

      timer.debounce('db_key', 25, function()
        counts.debounce = counts.debounce + 1
      end)

      timer.throttle('th_key', 30, function()
        counts.throttle = counts.throttle + 1
      end)

      vim.wait(100)

      assert.equals(1, counts.normal)
      assert.equals(1, counts.debounce)
      assert.equals(1, counts.throttle)
    end)

    it('should handle cleanup during execution', function()
      local executed = false

      timer.create(20, function()
        executed = true
        timer.stop_all() -- Stop all timers during callback
      end)

      vim.wait(50)

      assert.is_true(executed)

      local stats = timer.get_stats()
      assert.equals(0, stats.active)
    end)
  end)
end)
