# Docker Image Base Path Verification Report

## Summary

Investigation into whether the latest Docker image contains the chatbot.tsx base path fix.

## Findings

### ✅ Code Changes Are On Main Branch

**Commit:** `fe96c59` - "chatbot baseurl integration"
**Current main HEAD:** `ab717e9` - "Merge branch 'feat/helm-support'"

The chatbot.tsx file on main branch (as of `ab717e9`) contains the fix:
```typescript
// Before:
const { messages, error, append, ... } = useChat({
  api: '/api/chat',
  ...
});

// After (current main):
import { cn, withBasePath } from '@/lib/utils';
const { messages, error, append, ... } = useChat({
  api: withBasePath('/api/chat'),
  ...
});
```

### ❌ Potential Issue Found: NEXT_PUBLIC_BASE_PATH Handling

There's an inconsistency in how `NEXT_PUBLIC_BASE_PATH` is handled compared to other env vars:

**Other environment variables:**
```dockerfile
# Dockerfile - Build time
ENV NEXT_PUBLIC_SUPABASE_URL="__NEXT_PUBLIC_SUPABASE_URL__"
```
```bash
# entrypoint.sh - Runtime
inject_env "__NEXT_PUBLIC_SUPABASE_URL__" "NEXT_PUBLIC_SUPABASE_URL"
```

**But NEXT_PUBLIC_BASE_PATH:**
- ❌ NOT set in Dockerfile ENV section
- ❌ NOT in inject_env() calls in entrypoint.sh
- ✅ Only `/__NEXT_BASEPATH_PLACEHOLDER__` is replaced in files

**Impact:** The `getBasePath()` function's server-side fallback returns empty string:
```typescript
// src/lib/utils.ts
export function getBasePath(): string {
  if (typeof window !== 'undefined') {
    const nextData = window.__NEXT_DATA__ as { basePath?: string } | undefined;
    if (nextData?.basePath) {
      return nextData.basePath;  // ✅ Works on client
    }
  }
  return process.env.NEXT_PUBLIC_BASE_PATH || '';  // ❌ Returns '' on server!
}
```

**However:** Since `chatbot.tsx` is a client component (`'use client'`), the `useChat` hook should only execute client-side where `window.__NEXT_DATA__.basePath` is available. This MIGHT not be the issue.

## Docker Image Build Process

**Trigger:** Pushes to `main` branch (see `.github/workflows/docker-publish.yml`)

**Registry:** `ghcr.io/zees-dev/resume-lm` (or your repo path)

**Tags created on main push:**
- `latest`
- `<commit-sha>` (e.g., `ab717e9`)

**Expected image tag for current main:** `ghcr.io/zees-dev/resume-lm:ab717e9` or `:latest`

## Verification Steps

### Option 1: Check GitHub Actions

1. Go to: https://github.com/YOUR_USERNAME/resume-lm/actions
2. Look for "Build and Push Docker Image" workflow
3. Check if it ran after commit `ab717e9` or `fe96c59`
4. Verify it completed successfully
5. Note the image tags that were pushed

### Option 2: Inspect Image Locally

Run the verification script:
```bash
./verify-docker-image.sh latest
# Or specify a tag:
./verify-docker-image.sh ab717e9
```

This will:
- Pull the image
- Extract the built `.next` directory
- Search for `withBasePath` usage
- Search for `/api/chat` endpoint references
- Check for basePath placeholder

### Option 3: Inspect Image in Registry

Without pulling:
```bash
# List available tags
gh api /orgs/YOUR_ORG/packages/container/resume-lm/versions

# Or using Docker CLI
docker manifest inspect ghcr.io/zees-dev/resume-lm:latest
```

### Option 4: Runtime Verification

If you have access to the deployed cluster:

1. **Check the deployed image tag:**
```bash
kubectl get deployment resumelm -o jsonpath='{.spec.template.spec.containers[0].image}'
```

2. **Exec into a running pod and verify:**
```bash
kubectl exec -it <pod-name> -- sh

# Inside the container:
# Check if withBasePath exists in built files
find /app/.next -name "*.js" -exec grep -l "withBasePath" {} \; | head -5

# Check the placeholder before startup (if possible)
grep -r "__NEXT_BASEPATH_PLACEHOLDER__" /app/.next/static/ | head -3
```

3. **Check browser Network tab:**
   - Open browser DevTools → Network tab
   - Try to use the chatbot
   - Look for the failing request
   - Check if the URL includes the base path correctly
   - Expected: `https://your-domain.com/resumelm/api/chat` (with base path)
   - Wrong: `https://your-domain.com/api/chat` (without base path)

## Possible Issues

### Issue 1: Old Image Deployed
**Symptom:** Image doesn't contain `withBasePath` code
**Cause:** Kubernetes deployment still using old image tag
**Fix:** Update Helm chart to use new image tag, or trigger rollout restart

### Issue 2: Build Failed
**Symptom:** GitHub Actions workflow failed
**Cause:** Build errors, test failures, or registry auth issues
**Fix:** Check GitHub Actions logs, fix issues, re-run workflow

### Issue 3: Wrong Image Tag
**Symptom:** Deployed image tag doesn't match latest commit
**Cause:** Helm values or deployment config using pinned/old tag
**Fix:** Update Helm values to use `:latest` or specific commit SHA

### Issue 4: BasePath Not Set in Helm Values
**Symptom:** App works but basePath is empty/wrong
**Cause:** `NEXT_PUBLIC_BASE_PATH` env var not set in Helm deployment
**Fix:** Ensure Helm values include:
```yaml
env:
  NEXT_PUBLIC_BASE_PATH: "/resumelm"  # Or your base path
```

### Issue 5: Client Hydration Mismatch
**Symptom:** API calls use wrong path
**Cause:** Server-rendered HTML differs from client hydration
**Fix:** Ensure basePath is consistent between build and runtime

## Recommended Fix

If the issue persists after verifying the image contains the fix, update the `getBasePath()` function:

```typescript
// src/lib/utils.ts
export function getBasePath(): string {
  // Client-side: read from Next.js runtime data
  if (typeof window !== 'undefined') {
    const nextData = window.__NEXT_DATA__ as { basePath?: string } | undefined;
    if (nextData?.basePath && nextData.basePath !== '/__NEXT_BASEPATH_PLACEHOLDER__') {
      return nextData.basePath;
    }
  }
  // Server-side: NEVER return the placeholder
  const envBasePath = process.env.NEXT_PUBLIC_BASE_PATH || '';
  return envBasePath === '/__NEXT_BASEPATH_PLACEHOLDER__' ? '' : envBasePath;
}
```

## Next Steps

1. ✅ Verify the Docker image was built from main after commit `fe96c59`
2. ✅ Verify the image tag deployed to Kubernetes
3. ✅ Check if `NEXT_PUBLIC_BASE_PATH` is set in Helm values/deployment
4. ✅ Test in browser DevTools to see actual API call URL
5. ⚠️ If still failing, run the verification script to inspect image contents
