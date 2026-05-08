\set EQX '1b922b60-64b2-4e9b-974a-b878658838c8'

ALTER TABLE fleets DISABLE ROW LEVEL SECURITY;
ALTER TABLE edge_devices DISABLE ROW LEVEL SECURITY;
ALTER TABLE nhi_drift_events DISABLE ROW LEVEL SECURITY;
ALTER TABLE cloud_workloads DISABLE ROW LEVEL SECURITY;

INSERT INTO fleets (tenant_id, name, description, vertical) VALUES
  (:'EQX'::uuid,'Delivery Drones','Last-mile delivery fleet','drone'),
  (:'EQX'::uuid,'Hospital IoT','Medical devices','medical')
ON CONFLICT DO NOTHING;

INSERT INTO edge_devices (tenant_id, fleet_id, device_serial, hardware_sku, firmware_version, status, trust_tier, location_label, last_seen_at)
SELECT :'EQX'::uuid, f.id, 'DEV-' || lpad(g::text, 6, '0') || '-' || substring(replace(f.name,' ','') from 1 for 3),
  (ARRAY['rpi5','jetson-nano','beagle-bone'])[1+(random()*2)::int],
  '1.4.' || (random()*99)::int,
  (ARRAY['online','online','online','offline','quarantined'])[1+(random()*4)::int],
  (ARRAY['attested','attested','unverified'])[1+(random()*2)::int],
  (ARRAY['floor-A','floor-B','warehouse','dock-3'])[1+(random()*3)::int],
  NOW() - (random()*2 || ' hours')::interval
FROM fleets f, generate_series(1,12) g WHERE f.tenant_id=:'EQX'::uuid
ON CONFLICT DO NOTHING;

INSERT INTO nhi_drift_events (tenant_id, nhi_id, z_score, observed_calls, severity, status, detected_at)
SELECT :'EQX'::uuid, id, (3.2 + random()*2)::numeric(8,4), (random()*5000)::int,
  (ARRAY['low','medium','high','critical'])[1+(random()*3)::int],
  (ARRAY['open','acked'])[1+(random()*1)::int],
  NOW() - (random()*7 || ' days')::interval
FROM nhi_identities WHERE tenant_id=:'EQX'::uuid LIMIT 8;

INSERT INTO cloud_workloads (tenant_id, account_id, resource_type, resource_id, region, risk_score, governance_status, last_seen_at)
SELECT :'EQX'::uuid, id,
  (ARRAY['ec2','rds','s3','lambda','eks-pod'])[1+(random()*4)::int],
  'res-' || gen_random_uuid()::text,
  (ARRAY['us-east-1','us-west-2','eu-west-1'])[1+(random()*2)::int],
  (random()*100)::numeric(5,2),
  (ARRAY['discovered','enrolled','quarantined'])[1+(random()*2)::int],
  NOW() - (random()*30 || ' minutes')::interval
FROM cloud_accounts, generate_series(1,8) WHERE tenant_id=:'EQX'::uuid;

ALTER TABLE fleets ENABLE ROW LEVEL SECURITY;
ALTER TABLE edge_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE nhi_drift_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE cloud_workloads ENABLE ROW LEVEL SECURITY;

SELECT 'fleets' tbl, COUNT(*) FROM fleets WHERE tenant_id=:'EQX'::uuid
UNION ALL SELECT 'edge_devices', COUNT(*) FROM edge_devices WHERE tenant_id=:'EQX'::uuid
UNION ALL SELECT 'nhi_drift_events', COUNT(*) FROM nhi_drift_events WHERE tenant_id=:'EQX'::uuid
UNION ALL SELECT 'cloud_workloads', COUNT(*) FROM cloud_workloads WHERE tenant_id=:'EQX'::uuid;
