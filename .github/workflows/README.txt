 GitHub Actions Caching Tips and Tricks

2. Ubuntu APT Cache Solutions

3. Problem: Permission Issues with Default Cache Location
- The default /var/cache/apt/archives directory causes permission errors during cache saving
- The 'partial' subdirectory is particularly problematic
- Error often looks like: "Cannot open: Permission denied" when attempting to tar the cache

3. Solution: Create Custom Cache Directory
- Create a dedicated cache directory in /tmp with proper permissions:
  --  
  - name: Create apt cache directory
    run: |
      sudo mkdir -p /tmp/apt-cache
      sudo chmod 777 /tmp/apt-cache
  --  yaml

- Configure apt to use this custom location:
  --  
  - name: Configure apt cache
    run: |
      echo "Dir::Cache::Archives /tmp/apt-cache;" | sudo tee -a /etc/apt/apt.conf.d/01cache
  --  yaml

- Use this directory in the cache action:
  --  
  - name: Cache OS dependencies
    uses: actions/cache@v3
    with:
      path: /tmp/apt-cache
      key: ${{ runner.os }}-apt-cache-${{ hashFiles('.github/apt-packages.txt') }}
  --  yaml

2. General Caching Best Practices

1. Be specific with cache paths
   - Cache only what's necessary
   - Avoid caching entire directories that contain temporary files

2. Use precise cache keys
   - Include relevant files in the hash (package lock files, dependency lists)
   - Example: `${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}`

3. Implement fallback strategies with restore-keys
   - List from most specific to least specific
   - Example:
     --  
     restore-keys: |
       ${{ runner.os }}-npm-${{ hashFiles('**/package-lock.json') }}
       ${{ runner.os }}-npm-
     --  yaml

4. Cache size matters
   - GitHub has a 10GB limit per repository
   - Caches unused for 7 days are automatically removed
   - Cache compression happens automatically

5. Validate cache effectiveness
   - Check cache-hit output: `${{ steps.cache-step-id.outputs.cache-hit }}`
   - Monitor workflow execution time with and without cache

2. Common Pitfalls

1. Permissions issues
   - Always ensure write permissions for cache directories
   - Use sudo or chmod when necessary before caching

2. Caching too much
   - Don't cache entire node_modules (too large, contains platform-specific binaries)
   - Better to cache ~/.npm directory for npm or ~/.m2 for Maven

3. Not handling cache misses
   - Always implement proper workflow logic for when cache misses occur
   - Example: `if: steps.cache-step.outputs.cache-hit != 'true'`

4. Overly-specific cache keys
   - If keys are too specific, you'll rarely get cache hits
   - Balance between specificity and reusability

5. Ignoring platform differences
   - Cache keys should include runner.os for cross-platform projects
   - Some dependencies are platform-specific and shouldn't be shared

6. Not clearing corrupt caches
   - If a workflow consistently fails after a cache hit, try changing the cache key

7. Caching secure data
   - Avoid caching sensitive information
   - Remember that forks can access cache in pull requests