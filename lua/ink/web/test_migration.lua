-- Test script for highlight migration
-- This allows testing the migration system without waiting for real page updates

local migrate_highlights = require("ink.web.migrate_highlights")
local user_highlights = require("ink.user_highlights")
local fs = require("ink.fs")
local data = require("ink.data")

local M = {}

-- Create a fake spine structure for testing
-- @param articles: array of article numbers (e.g., {"1", "2", "3", "4"})
-- @return spine array
local function create_test_spine(articles)
  local spine = {}

  for idx, article_num in ipairs(articles) do
    table.insert(spine, {
      id = "article-" .. article_num,
      href = "#art" .. article_num,
      title = "Art. " .. article_num
    })
  end

  return spine
end

-- Simulate adding highlights to a test page
-- @param slug: page identifier
-- @param chapters: array of chapter indices to add highlights to
function M.create_test_highlights(slug, chapters)
  local highlights = {}

  for _, chapter_idx in ipairs(chapters) do
    table.insert(highlights, {
      chapter = chapter_idx,
      text = "Test highlight text for article " .. chapter_idx,
      context_before = "Before context",
      context_after = "After context",
      color = "yellow",
      created_at = os.time()
    })
  end

  user_highlights.save(slug, highlights)
  print(string.format("Created %d test highlights", #highlights))
end

-- Test migration scenario: article added in the middle
-- Simulates: Articles 1, 2, 3, 4 -> Articles 1, 2, 2-A, 3, 4
function M.test_article_addition()
  print("\n=== Test: Article Addition ===")

  local test_slug = "test-lei-migration"

  -- Create old spine: Articles 1, 2, 3, 4
  local old_spine = create_test_spine({"1", "2", "3", "4"})

  -- Create highlights on articles 3 and 4 (indices 3 and 4)
  M.create_test_highlights(test_slug, {3, 4})

  print("\nBefore migration:")
  print("  Highlight 1: chapter = 3 (Art. 3)")
  print("  Highlight 2: chapter = 4 (Art. 4)")

  -- Create new spine: Articles 1, 2, 2-A, 3, 4
  -- Now Art. 3 is at index 4, Art. 4 is at index 5
  local new_spine = create_test_spine({"1", "2", "2-A", "3", "4"})

  -- Run migration
  local stats = migrate_highlights.migrate_highlights(test_slug, old_spine, new_spine)

  print("\nAfter migration:")
  local hl_data = user_highlights.load(test_slug)
  for i, hl in ipairs(hl_data.highlights) do
    print(string.format("  Highlight %d: chapter = %d", i, hl.chapter))
  end

  print("\nMigration stats:")
  print(string.format("  Migrated: %d", stats.migrated))
  print(string.format("  Unchanged: %d", stats.unchanged))
  print(string.format("  Failed: %d", stats.failed))

  print("\n✓ Expected: Both highlights should be migrated (3->4, 4->5)")
end

-- Test migration scenario: article removed
-- Simulates: Articles 1, 2, 3, 4 -> Articles 1, 2, 4
function M.test_article_removal()
  print("\n=== Test: Article Removal ===")

  local test_slug = "test-lei-removal"

  -- Create old spine: Articles 1, 2, 3, 4
  local old_spine = create_test_spine({"1", "2", "3", "4"})

  -- Create highlight on article 3 (index 3)
  M.create_test_highlights(test_slug, {3})

  print("\nBefore migration:")
  print("  Highlight 1: chapter = 3 (Art. 3)")

  -- Create new spine: Articles 1, 2, 4 (Art. 3 removed)
  local new_spine = create_test_spine({"1", "2", "4"})

  -- Run migration
  local stats = migrate_highlights.migrate_highlights(test_slug, old_spine, new_spine)

  print("\nAfter migration:")
  local hl_data = user_highlights.load(test_slug)
  for i, hl in ipairs(hl_data.highlights) do
    print(string.format("  Highlight %d: chapter = %d", i, hl.chapter))
  end

  print("\nMigration stats:")
  print(string.format("  Migrated: %d", stats.migrated))
  print(string.format("  Unchanged: %d", stats.unchanged))
  print(string.format("  Failed: %d", stats.failed))

  print("\n✓ Expected: Highlight should fail to migrate (article removed)")
end

-- Test migration scenario: multiple additions
-- Simulates: Articles 1, 2, 3 -> Articles 1, 1-A, 1-B, 2, 2-A, 3
function M.test_multiple_additions()
  print("\n=== Test: Multiple Article Additions ===")

  local test_slug = "test-lei-multiple"

  -- Create old spine: Articles 1, 2, 3
  local old_spine = create_test_spine({"1", "2", "3"})

  -- Create highlights on all articles
  M.create_test_highlights(test_slug, {1, 2, 3})

  print("\nBefore migration:")
  print("  Highlight 1: chapter = 1 (Art. 1)")
  print("  Highlight 2: chapter = 2 (Art. 2)")
  print("  Highlight 3: chapter = 3 (Art. 3)")

  -- Create new spine with multiple additions
  local new_spine = create_test_spine({"1", "1-A", "1-B", "2", "2-A", "3"})

  -- Run migration
  local stats = migrate_highlights.migrate_highlights(test_slug, old_spine, new_spine)

  print("\nAfter migration:")
  local hl_data = user_highlights.load(test_slug)
  for i, hl in ipairs(hl_data.highlights) do
    print(string.format("  Highlight %d: chapter = %d", i, hl.chapter))
  end

  print("\nMigration stats:")
  print(string.format("  Migrated: %d", stats.migrated))
  print(string.format("  Unchanged: %d", stats.unchanged))
  print(string.format("  Failed: %d", stats.failed))

  print("\n✓ Expected: Art. 1 unchanged (1->1), Art. 2 migrated (2->4), Art. 3 migrated (3->6)")
end

-- Run all tests
function M.run_all_tests()
  print("=" .. string.rep("=", 60))
  print("Highlight Migration Test Suite")
  print("=" .. string.rep("=", 60))

  M.test_article_addition()
  M.test_article_removal()
  M.test_multiple_additions()

  print("\n" .. string.rep("=", 60))
  print("All tests completed!")
  print("=" .. string.rep("=", 60) .. "\n")
end

return M
