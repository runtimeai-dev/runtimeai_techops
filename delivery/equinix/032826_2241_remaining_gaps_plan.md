# Remaining Equinix Delivery Gaps — Implementation Plan

**Date**: 2026-03-28 (22:41)
**Target**: `Delivery/Equinix`

Based on the latest architectural review (`032827_architect_review.md`) and codebase synchronization, the following tasks remain to achieve 100% completion for the Equinix edge platform delivery.

---

## 1. P0 Gap: `.env.example` and eSign Storage Wiring

**Problem**: 
The Equinix deployment will fail on `STORAGE_BACKEND=azure` and `SENDGRID_API_KEY` dependencies. While the `esign-service` and `auth-service` Go codebase supports `STORAGE_BACKEND=local|s3` and `EMAIL_PROVIDER=smtp`, the `03-services.yaml` K8s manifest strictly forces the Azure variations without Persistent Volume Claim (PVC) options for eSign.

**Solution**:
1. **Create Environment Template**: Create `deployment/scripts/rt19/k8s/.env.example` defining all domain (`DOMAIN_NAME=runtimeai.local`), storage (`STORAGE_BACKEND=local`), and email (`EMAIL_PROVIDER=smtp`) environment variables required by `configure-environment.sh`.
2. **Dynamic Manifests**: Update `03-services.yaml` to dynamically read `STORAGE_BACKEND` and `EMAIL_PROVIDER`.
3. **Storage Configuration**: Add a `PersistentVolumeClaim` (PVC) block for `esign-service` and update its K8s Deployment to mount `/var/lib/esign/documents`, allowing the `local` backend to function properly.

---

## 2. P1 Gap: API Routing 404s

**Problem**: 
Several critical feature sets mandated in the SoW evaluation are returning `404 Not Found` at the API layer when hit by test scripts:
- MCP Servers (`/api/mcp/servers`)
- SoD Rules (`/api/sod-rules`)
- Active Dashboard Stats
- Compliance Evidence

**Solution**:
1. **Audit API Routes**: Audit main API routing topologies (in `control-plane`) and `nginx/data-proxy` paths.
2. **Fix Handlers**: Implement missing endpoint handlers or fix misaligned trailing slashes (e.g., `/api/mcp/servers` instead of `/api/mcp/servers/`).
3. **RLS Verification**: Ensure these endpoints seamlessly pass Row-Level Security via the newly updated `runtimeai_app` context.

---

## 3. P1 Gap: Jira Ticketing Integration Fallback

**Problem**: 
The SoW mandates Jira ticketing testing (`/api/ticketing/config`), but an active Jira instance is impossible to guarantee in the Equinix testing suite without customer credentials.

**Solution**:
1. **Mock Endpoints**: Provide a mock/simulation toggle for the ticketing API (`/api/ticketing/config` and `/api/ticketing/create`) to succeed and log a mock ticket creation.
2. **Fulfill Demo Requirement**: This fulfills the demo prerequisite without requiring a live Atlassian setup.

---

## 4. Verification Plan

### Automated Tests
- Run `00_sow_test_suite.sh` or local `curl` simulations checking the previously 404-ing endpoints.
- Apply the `.env.example` logic internally and verify `kubectl apply` emits the correct `valueFrom` substitutions without Azure bloat.

### Manual Verification
- Seed via the updated API scripts and ensure documents upload successfully to the mounted `local` PVC without needing an Azure storage account or SendGrid connection.

---

**Status**: Awaiting approval to begin execution.

## 4. P1 Gap: eSign File Type Conversion (DOCX, PNG, JPEG)

**Problem**: 
The eSign file upload and template creation APIs restrict the conversion process to `.docx` files. If a user uploads a PNG, JPEG, or DOCX without strict handling, the platform either rejects the upload (in templates) or stores the raw image without converting it to PDF, breaking the signature placement logic.

**Solution**:
1. **Converter Extensibility**: Update `service/converter.go` to support `image/png` and `image/jpeg` in the `IsSupportedForConversion` list.
2. **Preserve Original Extensions**: Update the LibreOffice conversion loop to preserve the original file extension (`image.png` instead of forcing `image.docx`) so LibreOffice understands how to correctly convert images to PDFs.
3. **Template API Update**: Add `image/png` and `image/jpeg` to the allowed MIME types for template uploads (`handler/template.go`).

## 5. P1 Gap: eSign Frontend 'Sign Here' Arrow & Scrolling UX

**Problem**: 
The "Sign here ↓" indicator in the `GuestSigningPage.tsx` uses hardcoded CSS offsets (`translateX`, `-6%`) causing it to float away from the actual signature box coordinates. Furthermore, the user's viewport does not scroll to the signature field when it becomes their turn to sign.

**Solution**:
1. **Dynamic Arrow Anchoring**: Refactor the absolute positioning in `GuestSigningPage.tsx` to directly lock the arrow to the field's `x_position` and `y_position` bounding box (aligning it directly to the top edge).
2. **Auto-Scroll Behavior**: Attach a React `useRef` array or ID-based selector to signature fields. Add a `useEffect` on `activeFieldIndex` that calls `scrollIntoView({ behavior: 'smooth', block: 'center' })` whenever the user clicks "Next" or signs a field.

## 6. P1 Gap: Missing Download Signatures & 'PDF Stamping Failed'

**Problem**: 
Users get a "PDF stamping failed" error or download an empty document after signing. 
*Root Cause*: This is the downstream consequence of Gap #4. Because PNG/JPEG files bypass PDF conversion, the core `pdfcpu` stamping engine attempts to read a raw PNG image and crashes. The handler swallows the panic or catches the syntax error, aborts stamping, and leaves `sign_documents.storage_path` pointing to the blank original file.

**Solution**:
Fixing Gap #4 (enabling LibreOffice image-to-PDF conversion) natively resolves this. I will also add enhanced logging inside `stampSignatureOntoDocument` to fail deterministically instead of silently degrading if a non-PDF sneaks through.

#### [MODIFY] [src/pages/GuestSigningPage.tsx](file:///Users/roshanshaik/work/runtimeai-enterprise/dashboard/src/pages/GuestSigningPage.tsx) (Continued)
- **Auto-Date Field**: Replace the `type="date"` input with a read-only or hidden input that automatically populates with today's formatted date (`new Date().toLocaleDateString()`). It will instantly apply the current date to the field value upon rendering the field step.
