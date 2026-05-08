import { test, expect } from '@playwright/test';

const DASHBOARD_URL = 'https://app.rt19.runtimeai.io';
const ADMIN_EMAIL = 'admin@acme-corp.com';
const TENANT_ID = 'acme-corp';

test.describe('Customer Onboarding Flow', () => {
  test.beforeEach(async ({ page }) => {
    // Login
    await page.goto(DASHBOARD_URL);
    await page.fill('[data-testid="tenant-id"]', TENANT_ID);
    await page.fill('[data-testid="email"]', ADMIN_EMAIL);
    await page.fill('[data-testid="password"]', 'password123');
    await page.click('[data-testid="login-button"]');
    await page.waitForURL('**/dashboard');
  });

  test('Dashboard loads with all product tabs', async ({ page }) => {
    // Verify main navigation tabs are present
    const tabs = [
      'Dashboard', 'Agents', 'Discovery', 'Governance',
      'Risk', 'Firewall', 'MCP Gateway', 'FinOps',
      'Compliance', 'Marketplace', 'eSign', 'Workflows', 'Audit'
    ];

    for (const tab of tabs) {
      await expect(page.getByRole('link', { name: tab })).toBeVisible();
    }
  });

  test('Agent Registry shows registered agents', async ({ page }) => {
    await page.click('text=Agents');
    await page.waitForSelector('[data-testid="agent-list"]');

    // Should have seeded agents
    const agentRows = page.locator('[data-testid="agent-row"]');
    await expect(agentRows).toHaveCount(8); // 8 agents from seed script
  });

  test('Discovery scanners page loads', async ({ page }) => {
    await page.click('text=Discovery');
    await page.waitForSelector('[data-testid="scanner-dashboard"]');

    // Should show scanner configs
    await expect(page.locator('text=Scanner Dashboard')).toBeVisible();
  });

  test('Compliance frameworks are enabled', async ({ page }) => {
    await page.click('text=Compliance');
    await page.waitForSelector('[data-testid="compliance-dashboard"]');

    // Check for enabled frameworks
    const frameworks = ['SOC 2', 'FedRAMP', 'HIPAA', 'EU AI Act'];
    for (const fw of frameworks) {
      await expect(page.locator(`text=${fw}`)).toBeVisible();
    }
  });

  test('MCP Gateway shows catalog', async ({ page }) => {
    await page.click('text=MCP Gateway');
    await page.waitForSelector('[data-testid="mcp-catalog"]');

    // Should show integration count
    await expect(page.locator('text=integrations')).toBeVisible();
  });

  test('FinOps dashboard loads', async ({ page }) => {
    await page.click('text=FinOps');
    await page.waitForSelector('[data-testid="finops-dashboard"]');

    await expect(page.locator('text=Cost')).toBeVisible();
  });

  test('Audit trail has events', async ({ page }) => {
    await page.click('text=Audit');
    await page.waitForSelector('[data-testid="audit-events"]');

    // Should have audit events from seeding
    const events = page.locator('[data-testid="audit-event-row"]');
    const count = await events.count();
    expect(count).toBeGreaterThan(0);
  });
});
