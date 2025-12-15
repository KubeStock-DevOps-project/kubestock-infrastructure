-- =============================================================================
-- KubeStock - Database Initialization Script
-- =============================================================================
-- This script creates the databases for each microservice.
-- Schema and tables are managed by each service's node-pg-migrate migrations.
-- =============================================================================

-- Create databases for each microservice
CREATE DATABASE product_catalog_db;
CREATE DATABASE inventory_db;
CREATE DATABASE supplier_db;
CREATE DATABASE order_db;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE product_catalog_db TO kubestock_admin;
GRANT ALL PRIVILEGES ON DATABASE inventory_db TO kubestock_admin;
GRANT ALL PRIVILEGES ON DATABASE supplier_db TO kubestock_admin;
GRANT ALL PRIVILEGES ON DATABASE order_db TO kubestock_admin;

-- Add uuid-ossp extension to each database
\c product_catalog_db;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c inventory_db;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c supplier_db;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

\c order_db;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Return to default database
\c kubestock_admin;

-- Log completion
DO $$
BEGIN
  RAISE NOTICE '==============================================';
  RAISE NOTICE 'KubeStock databases initialized successfully!';
  RAISE NOTICE 'Databases created: product_catalog_db, inventory_db, supplier_db, order_db';
  RAISE NOTICE 'Schema will be applied via node-pg-migrate on each service startup';
  RAISE NOTICE '==============================================';
END $$;
