-- Reset the audit chain implementation
TRUNCATE TABLE audit_evidence CASCADE;
-- Re-queue all audit logs for processing
UPDATE audit_logs SET processed = FALSE;
