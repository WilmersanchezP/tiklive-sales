-- ─────────────────────────────────────────────────────────────────────────────
-- TikLive Sales — Initial Database Schema
-- PostgreSQL + Supabase RLS
-- ─────────────────────────────────────────────────────────────────────────────

-- ── Extensions ────────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm"; -- Fast text search on product names

-- ── Enum types ────────────────────────────────────────────────────────────────
CREATE TYPE user_role AS ENUM ('admin', 'seller', 'warehouse', 'supervisor');
CREATE TYPE payment_method AS ENUM ('CASH', 'COD', 'TRANSFER', 'PENDING');
CREATE TYPE order_status AS ENUM ('PENDING', 'CONFIRMED', 'RESERVED', 'SHIPPED', 'DELIVERED', 'CANCELLED');
CREATE TYPE session_status AS ENUM ('ACTIVE', 'ENDED', 'CANCELLED');

-- ── Profiles (extends auth.users) ─────────────────────────────────────────────
CREATE TABLE profiles (
  id           UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name    TEXT NOT NULL,
  role         user_role NOT NULL DEFAULT 'seller',
  avatar_url   TEXT,
  phone        TEXT,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-create profile on new user signup
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  INSERT INTO public.profiles(id, full_name)
  VALUES (NEW.id, COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email));
  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ── Products ──────────────────────────────────────────────────────────────────
CREATE TABLE products (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name         TEXT NOT NULL,
  description  TEXT,
  image_url    TEXT,
  base_price   NUMERIC(10,2),
  category     TEXT,
  is_active    BOOLEAN NOT NULL DEFAULT true,
  created_by   UUID REFERENCES profiles(id),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_products_name_trgm ON products USING gin(name gin_trgm_ops);
CREATE INDEX idx_products_category ON products(category);

-- ── Product Variants (color + size + stock) ───────────────────────────────────
CREATE TABLE product_variants (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id     UUID NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  color          TEXT,
  size           TEXT,
  sku            TEXT UNIQUE,
  price          NUMERIC(10,2),
  stock_quantity INTEGER NOT NULL DEFAULT 0 CHECK (stock_quantity >= 0),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_variants_product ON product_variants(product_id);
CREATE INDEX idx_variants_stock ON product_variants(stock_quantity);

-- ── Customers ────────────────────────────────────────────────────────────────
CREATE TABLE customers (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name         TEXT NOT NULL,
  phone        TEXT,
  notes        TEXT,
  total_orders INTEGER NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_customers_name_trgm ON customers USING gin(name gin_trgm_ops);

-- ── Live Sessions ─────────────────────────────────────────────────────────────
CREATE TABLE live_sessions (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  title        TEXT NOT NULL,
  seller_id    UUID REFERENCES profiles(id),
  status       session_status NOT NULL DEFAULT 'ACTIVE',
  started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at     TIMESTAMPTZ,
  total_orders INTEGER NOT NULL DEFAULT 0,
  total_revenue NUMERIC(12,2) NOT NULL DEFAULT 0
);

CREATE INDEX idx_sessions_seller ON live_sessions(seller_id);
CREATE INDEX idx_sessions_status ON live_sessions(status);

-- ── Orders ────────────────────────────────────────────────────────────────────
CREATE TABLE orders (
  id                  UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_name        TEXT NOT NULL,
  color               TEXT,
  size                TEXT,
  quantity            INTEGER NOT NULL DEFAULT 1 CHECK (quantity > 0),
  customer_name       TEXT NOT NULL DEFAULT 'Cliente Live',
  customer_phone      TEXT,
  payment_method      payment_method NOT NULL DEFAULT 'PENDING',
  status              order_status NOT NULL DEFAULT 'PENDING',
  unit_price          NUMERIC(10,2),
  total_price         NUMERIC(12,2) GENERATED ALWAYS AS (
                        COALESCE(unit_price, 0) * quantity
                      ) STORED,
  notes               TEXT,
  seller_id           UUID REFERENCES profiles(id),
  product_variant_id  UUID REFERENCES product_variants(id),
  customer_id         UUID REFERENCES customers(id),
  live_session_id     UUID REFERENCES live_sessions(id),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_orders_status ON orders(status);
CREATE INDEX idx_orders_created_at ON orders(created_at DESC);
CREATE INDEX idx_orders_seller ON orders(seller_id);
CREATE INDEX idx_orders_session ON orders(live_session_id);
CREATE INDEX idx_orders_customer_name_trgm ON orders USING gin(customer_name gin_trgm_ops);

-- ── Voice Transcripts (audit log) ─────────────────────────────────────────────
CREATE TABLE voice_transcripts (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  transcript  TEXT NOT NULL,
  order_id    UUID REFERENCES orders(id),
  session_id  UUID REFERENCES live_sessions(id),
  seller_id   UUID REFERENCES profiles(id),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Auto-update updated_at trigger ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_products_updated_at
  BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_variants_updated_at
  BEFORE UPDATE ON product_variants FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_orders_updated_at
  BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── Stock adjustment function (atomic) ────────────────────────────────────────
CREATE OR REPLACE FUNCTION adjust_stock(variant_id UUID, delta INTEGER)
RETURNS VOID LANGUAGE plpgsql AS $$
BEGIN
  UPDATE product_variants
  SET stock_quantity = GREATEST(0, stock_quantity + delta)
  WHERE id = variant_id;
END;
$$;

-- ── Dashboard analytics RPCs ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION get_top_products(from_date TIMESTAMPTZ, limit_count INTEGER DEFAULT 5)
RETURNS TABLE(product_name TEXT, units_sold BIGINT, revenue NUMERIC)
LANGUAGE sql STABLE AS $$
  SELECT
    o.product_name,
    SUM(o.quantity)    AS units_sold,
    SUM(COALESCE(o.total_price, 0)) AS revenue
  FROM orders o
  WHERE o.created_at >= from_date
    AND o.status != 'CANCELLED'
  GROUP BY o.product_name
  ORDER BY units_sold DESC
  LIMIT limit_count;
$$;

CREATE OR REPLACE FUNCTION get_daily_sales(from_date TIMESTAMPTZ)
RETURNS TABLE(sale_date DATE, revenue NUMERIC, order_count BIGINT)
LANGUAGE sql STABLE AS $$
  SELECT
    DATE(o.created_at)               AS sale_date,
    SUM(COALESCE(o.total_price, 0))  AS revenue,
    COUNT(*)                          AS order_count
  FROM orders o
  WHERE o.created_at >= from_date
    AND o.status != 'CANCELLED'
  GROUP BY DATE(o.created_at)
  ORDER BY sale_date ASC;
$$;

-- ── Row Level Security ────────────────────────────────────────────────────────
ALTER TABLE profiles          ENABLE ROW LEVEL SECURITY;
ALTER TABLE products          ENABLE ROW LEVEL SECURITY;
ALTER TABLE product_variants  ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders            ENABLE ROW LEVEL SECURITY;
ALTER TABLE live_sessions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE voice_transcripts ENABLE ROW LEVEL SECURITY;

-- Profiles: users can read all, edit only their own
CREATE POLICY "profiles_read_all"   ON profiles FOR SELECT TO authenticated USING (true);
CREATE POLICY "profiles_edit_own"   ON profiles FOR UPDATE TO authenticated USING (id = auth.uid());

-- Products: all authenticated users can read; admins/supervisors can write
CREATE POLICY "products_read"  ON products FOR SELECT TO authenticated USING (true);
CREATE POLICY "products_write" ON products FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'supervisor')));

CREATE POLICY "variants_read"  ON product_variants FOR SELECT TO authenticated USING (true);
CREATE POLICY "variants_write" ON product_variants FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'supervisor', 'warehouse')));

-- Orders: sellers see their own; admins/supervisors see all
CREATE POLICY "orders_read_own" ON orders FOR SELECT TO authenticated
  USING (seller_id = auth.uid() OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'supervisor')
  ));
CREATE POLICY "orders_insert"   ON orders FOR INSERT TO authenticated WITH CHECK (seller_id = auth.uid());
CREATE POLICY "orders_update"   ON orders FOR UPDATE TO authenticated
  USING (seller_id = auth.uid() OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'supervisor')
  ));

-- Customers: all authenticated
CREATE POLICY "customers_all"  ON customers FOR ALL TO authenticated USING (true);

-- Live sessions
CREATE POLICY "sessions_read"  ON live_sessions FOR SELECT TO authenticated USING (true);
CREATE POLICY "sessions_write" ON live_sessions FOR ALL TO authenticated
  USING (seller_id = auth.uid() OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role IN ('admin', 'supervisor')
  ));

-- Voice transcripts: users see their own; admins see all
CREATE POLICY "transcripts_read" ON voice_transcripts FOR SELECT TO authenticated
  USING (seller_id = auth.uid() OR EXISTS (
    SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin'
  ));
CREATE POLICY "transcripts_insert" ON voice_transcripts FOR INSERT TO authenticated
  WITH CHECK (seller_id = auth.uid());

-- ── Seed demo data (remove in production) ─────────────────────────────────────
-- INSERT INTO products (name, base_price, category) VALUES
--   ('Camisa Básica', 15.00, 'Ropa'),
--   ('Jean Slim', 25.00, 'Ropa'),
--   ('Bolso Casual', 20.00, 'Accesorios');
