-- Fsynth Usage Examples
-- This file demonstrates various usage patterns for the Fsynth library

local fsynth = require("fsynth")

-- ===========================================================================
-- Example 1: Basic File Operations
-- ===========================================================================
print("=== Example 1: Basic File Operations ===")

-- Create a queue and processor
local queue = fsynth.new_queue()
local processor = fsynth.new_processor()

-- Add some basic operations
queue:add(fsynth.op.create_directory("project/src"))
queue:add(fsynth.op.create_directory("project/tests"))
queue:add(fsynth.op.create_file("project/README.md", "# My Project\n\nWelcome!"))
queue:add(fsynth.op.copy_file("templates/main.lua", "project/src/main.lua"))

-- Execute with standard model
local results = processor:execute(queue, {
    model = "standard",
    dry_run = false
})

if results:is_success() then
    print("Project structure created successfully!")
else
    print("Failed to create project structure")
    for _, err in ipairs(results:get_errors()) do
        print("  Error:", err.message)
    end
end

-- ===========================================================================
-- Example 2: Building Operations Over Time
-- ===========================================================================
print("\n=== Example 2: Building Operations Over Time ===")

-- Initialize a shared queue
local deployment_queue = fsynth.new_queue()

-- Function 1: Prepare build artifacts
local function prepare_artifacts(version)
    deployment_queue:add(fsynth.op.create_directory("build/v" .. version))
    deployment_queue:add(fsynth.op.copy_file("src/app.lua", "build/v" .. version .. "/app.lua", {
        verify_checksum_after = true
    }))
    deployment_queue:add(fsynth.op.copy_file("assets/icon.png", "build/v" .. version .. "/icon.png"))
    print("Added artifact preparation operations")
end

-- Function 2: Create documentation
local function create_docs(version)
    local doc_content = string.format("# Release Notes v%s\n\nGenerated at %s",
        version, os.date())
    deployment_queue:add(fsynth.op.create_file("build/v" .. version .. "/RELEASE.md",
        doc_content))
    deployment_queue:add(fsynth.op.symlink("build/v" .. version, "build/latest", {
        overwrite = true,
        relative = true
    }))
    print("Added documentation operations")
end

-- Function 3: Cleanup old builds
local function cleanup_old_builds(keep_versions)
    -- In real usage, you'd scan the directory and add delete operations
    deployment_queue:add(fsynth.op.delete_directory("build/v1.0.0", {
        recursive = true,
        ignore_if_not_exists = true
    }))
    print("Added cleanup operations")
end

-- Build the queue from different functions
prepare_artifacts("2.0.0")
create_docs("2.0.0")
cleanup_old_builds(3)

-- Execute all operations with validation
print("Total operations queued:", deployment_queue:size())
local deploy_results = processor:execute(deployment_queue, {
    model = "validate_first",
    on_error = "stop"
})

-- ===========================================================================
-- Example 3: Transactional Operations with Rollback
-- ===========================================================================
print("\n=== Example 3: Transactional Operations ===")

local backup_queue = fsynth.new_queue()

-- Add operations that should be atomic
backup_queue:add(fsynth.op.create_directory("backup/data"))
backup_queue:add(fsynth.op.move_file("production/database.db", "backup/data/database.db", {
    verify_checksum = true
}))
backup_queue:add(fsynth.op.copy_file("new_version/database.db", "production/database.db", {
    verify_checksum_before = true,
    verify_checksum_after = true
}))
backup_queue:add(fsynth.op.delete_file("migration.lock"))

-- Execute with transactional model
local backup_results = processor:execute(backup_queue, {
    model = "transactional",
    on_error = "rollback"
})

if not backup_results:is_success() then
    print("Backup operation failed and was rolled back")
    print("Rolled back operations:", backup_results.rollback_count)
end

-- ===========================================================================
-- Example 4: Best Effort Execution
-- ===========================================================================
print("\n=== Example 4: Best Effort Execution ===")

local cleanup_queue = fsynth.new_queue()

-- Add many cleanup operations, some might fail
local temp_files = {
    "/tmp/app_cache_001.tmp",
    "/tmp/app_cache_002.tmp",
    "/var/tmp/old_log.txt",
    "~/Downloads/installer_old.dmg"
}

for _, file in ipairs(temp_files) do
    cleanup_queue:add(fsynth.op.delete_file(file, {
        ignore_if_not_exists = true
    }))
end

-- Execute with best effort - continue even if some operations fail
local cleanup_results = processor:execute(cleanup_queue, {
    model = "best_effort",
    log_level = "warn" -- Only log warnings and errors
})

print(string.format("Cleanup completed: %d successful, %d failed",
    cleanup_results.executed_count,
    #cleanup_results:get_errors()))

-- ===========================================================================
-- Example 5: Dry Run for Testing
-- ===========================================================================
print("\n=== Example 5: Dry Run Testing ===")

local migration_queue = fsynth.new_queue()

-- Complex migration operations
migration_queue:add(fsynth.op.create_directory("new_structure/components"))
migration_queue:add(fsynth.op.move_file("old/header.lua", "new_structure/components/header.lua"))
migration_queue:add(fsynth.op.move_file("old/footer.lua", "new_structure/components/footer.lua"))
migration_queue:add(fsynth.op.delete_directory("old", { recursive = true }))

-- First, do a dry run to see what would happen
print("Performing dry run...")
local dry_results = processor:execute(migration_queue, {
    model = "validate_first",
    dry_run = true,
    log_level = "debug"
})

-- Check the log to see what would be done
print("Dry run log:")
for _, entry in ipairs(dry_results:get_log()) do
    print("  " .. entry)
end

-- If dry run looks good, execute for real
if dry_results:is_success() then
    print("\nDry run successful, executing for real...")
    migration_queue:clear() -- Clear and rebuild queue (operations were consumed)

    -- Rebuild the queue (in real usage, you might have a function for this)
    migration_queue:add(fsynth.op.create_directory("new_structure/components"))
    migration_queue:add(fsynth.op.move_file("old/header.lua", "new_structure/components/header.lua"))
    migration_queue:add(fsynth.op.move_file("old/footer.lua", "new_structure/components/footer.lua"))
    migration_queue:add(fsynth.op.delete_directory("old", { recursive = true }))

    local real_results = processor:execute(migration_queue, {
        model = "validate_first",
        dry_run = false
    })
end

-- ===========================================================================
-- Example 6: Advanced Options and Checksumming
-- ===========================================================================
print("\n=== Example 6: Advanced Options ===")

local secure_queue = fsynth.new_queue()

-- Copy with strict checksum verification
secure_queue:add(fsynth.op.copy_file("sensitive/config.lua", "deploy/config.lua", {
    verify_checksum_before = true,
    verify_checksum_after = true,
    on_checksum_mismatch = "error", -- Fail if checksums don't match
    overwrite = false               -- Don't overwrite if target exists
}))

-- Create file with specific permissions
secure_queue:add(fsynth.op.create_file("deploy/secrets.env", "API_KEY=...", {
    mode = "600", -- Read/write for owner only
    overwrite = false
}))

-- Delete with backup
secure_queue:add(fsynth.op.delete_file("old_config.lua", {
    backup_before_delete = true,
    backup_suffix = ".backup"
}))

-- Execute with strict validation
local secure_results = processor:execute(secure_queue, {
    model = "validate_first",
    on_error = "stop"
})

-- ===========================================================================
-- Example 7: Queue Inspection and Manipulation
-- ===========================================================================
print("\n=== Example 7: Queue Inspection ===")

local inspect_queue = fsynth.new_queue()

-- Add various operations
inspect_queue:add(fsynth.op.create_file("file1.txt", "content1"))
inspect_queue:add(fsynth.op.create_file("file2.txt", "content2"))
inspect_queue:add(fsynth.op.create_directory("subdir"))
inspect_queue:add(fsynth.op.copy_file("file1.txt", "subdir/file1_copy.txt"))

-- Inspect queue before execution
print("Queue contents before execution:")
local operations = inspect_queue:get_operations()
for i, op in ipairs(operations) do
    print(string.format("  %d. %s: %s", i, op.type, op.target or op.source))
end

-- Conditionally remove an operation
if operations[2].target == "file2.txt" then
    print("Removing operation 2")
    inspect_queue:remove(2)
end

print("Queue size after removal:", inspect_queue:size())

-- ===========================================================================
-- Example 8: Error Handling Patterns
-- ===========================================================================
print("\n=== Example 8: Error Handling ===")

local error_queue = fsynth.new_queue()
local error_processor = fsynth.new_processor()

-- Add operations that might fail
error_queue:add(fsynth.op.copy_file("might_not_exist.txt", "destination.txt"))
error_queue:add(fsynth.op.create_directory("/root/unauthorized")) -- Might fail due to permissions
error_queue:add(fsynth.op.create_file("valid_file.txt", "This should work"))

-- Execute and handle errors
local error_results = error_processor:execute(error_queue, {
    model = "best_effort" -- Continue despite errors
})

-- Detailed error handling
if not error_results:is_success() then
    local errors = error_results:get_errors()
    print(string.format("Encountered %d errors:", #errors))

    for _, err in ipairs(errors) do
        print(string.format("  Operation %d (%s) failed: %s",
            err.operation_index,
            err.operation_type,
            err.message))

        -- Handle specific error types
        if err.message:match("Permission denied") then
            print("    -> This appears to be a permissions issue")
        elseif err.message:match("not found") then
            print("    -> The source file doesn't exist")
        end
    end
end

-- ===========================================================================
-- Example 9: Custom Execution Strategies
-- ===========================================================================
print("\n=== Example 9: Custom Execution Strategies ===")

-- Function to create a reusable deployment strategy
local function deploy_with_verification(source_dir, target_dir)
    local deploy_queue = fsynth.new_queue()

    -- Step 1: Create target structure
    deploy_queue:add(fsynth.op.create_directory(target_dir .. "/bin"))
    deploy_queue:add(fsynth.op.create_directory(target_dir .. "/lib"))
    deploy_queue:add(fsynth.op.create_directory(target_dir .. "/config"))

    -- Step 2: Copy executables with verification
    local executables = { "app", "worker", "cli" }
    for _, exe in ipairs(executables) do
        deploy_queue:add(fsynth.op.copy_file(
            source_dir .. "/bin/" .. exe,
            target_dir .. "/bin/" .. exe,
            {
                verify_checksum_before = true,
                verify_checksum_after = true,
                preserve_attributes = true
            }
        ))
    end

    -- Step 3: Deploy configuration
    deploy_queue:add(fsynth.op.copy_file(
        source_dir .. "/config/production.lua",
        target_dir .. "/config/config.lua",
        { overwrite = true }
    ))

    -- Step 4: Create version marker
    local version_content = string.format("Deployed: %s\nFrom: %s\n",
        os.date(), source_dir)
    deploy_queue:add(fsynth.op.create_file(
        target_dir .. "/VERSION",
        version_content,
        { overwrite = true }
    ))

    return deploy_queue
end

-- Use the deployment strategy
local deployment = deploy_with_verification("build/release", "/opt/myapp")
local deploy_proc = fsynth.new_processor()
local deploy_res = deploy_proc:execute(deployment, {
    model = "transactional",
    dry_run = true -- Test first
})

print("Deployment dry run completed:", deploy_res:is_success())
