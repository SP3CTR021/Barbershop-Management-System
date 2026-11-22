-- ============================================================================
-- 001_schema_and_constraints.sql
-- Barbershop Management System - PostgreSQL Schema (Supabase)
-- ============================================================================
-- Design notes:
-- 1. All 12 PKs and 16 FKs use UUID (`String` in the Dart domain layer) while
--    preserving your exact table and column names.
-- 2. `users.password_hash` is intentionally omitted: OWNER and STAFF credentials
--    are managed exclusively by Supabase Auth (`auth.users.id = users.user_id`),
--    while BARBER rows do not log in (checked in by STAFF).
-- 3. `attendance.time_in` is nullable for ABSENT / LEAVE rows and required for PRESENT.
-- 4. `transaction_items` snapshots `service_name`, `is_haircut`, and `unit_price`
--    at sale time so catalog updates never corrupt historical receipts/payroll.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ----------------------------------------------------------------------------
-- 1. ROLES (1 : M with users)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.roles (
    role_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_name   VARCHAR(30) NOT NULL UNIQUE CHECK (role_name IN ('OWNER', 'STAFF', 'BARBER')),
    description VARCHAR(100)
);

INSERT INTO public.roles (role_name, description)
VALUES
    ('OWNER',  'Shop owner with full management and payroll approval access'),
    ('STAFF',  'Front desk staff managing attendance, visits, and payments'),
    ('BARBER', 'Service provider earning haircut commission (logged by staff)')
ON CONFLICT (role_name) DO NOTHING;

-- ----------------------------------------------------------------------------
-- 2. USERS (roles 1:M users; users 1:0..1 barbers; audit parent 1:M)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.users (
    user_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    role_id    UUID NOT NULL REFERENCES public.roles(role_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    first_name VARCHAR(50) NOT NULL,
    last_name  VARCHAR(50) NOT NULL,
    username   VARCHAR(50) NOT NULL UNIQUE,
    phone      VARCHAR(20),
    email      VARCHAR(100) UNIQUE,
    is_active  BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_username_lower
    ON public.users (LOWER(username));

CREATE UNIQUE INDEX IF NOT EXISTS idx_users_email_lower
    ON public.users (LOWER(email))
    WHERE email IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_users_role_id
    ON public.users (role_id);

CREATE OR REPLACE FUNCTION public.trg_set_users_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_users_updated_at ON public.users;
CREATE TRIGGER set_users_updated_at
    BEFORE UPDATE ON public.users
    FOR EACH ROW
    EXECUTE FUNCTION public.trg_set_users_updated_at();

-- ----------------------------------------------------------------------------
-- 3. BARBERS (users 1 : 0..1 barbers)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.barbers (
    barber_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id   UUID NOT NULL UNIQUE REFERENCES public.users(user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    hire_date DATE NOT NULL,
    specialty VARCHAR(100),
    status    VARCHAR(10) NOT NULL DEFAULT 'ACTIVE' CHECK (status IN ('ACTIVE', 'INACTIVE'))
);

CREATE INDEX IF NOT EXISTS idx_barbers_status
    ON public.barbers (status);

-- ----------------------------------------------------------------------------
-- 4. CUSTOMERS (customers 0..1 : M transactions)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.customers (
    customer_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    first_name  VARCHAR(50) NOT NULL,
    last_name   VARCHAR(50) NOT NULL,
    phone       VARCHAR(20),
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_customers_name
    ON public.customers (last_name, first_name);

-- ----------------------------------------------------------------------------
-- 5. SERVICES (services 1 : M transaction_items)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.services (
    service_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    service_name VARCHAR(100) NOT NULL UNIQUE,
    is_haircut   BOOLEAN NOT NULL DEFAULT TRUE,
    price        NUMERIC(10, 2) NOT NULL CHECK (price >= 0),
    is_active    BOOLEAN NOT NULL DEFAULT TRUE
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_services_name_lower
    ON public.services (LOWER(service_name));

CREATE INDEX IF NOT EXISTS idx_services_active
    ON public.services (is_active, is_haircut);

-- ----------------------------------------------------------------------------
-- 6. ATTENDANCE (barbers 1:M attendance; users(STAFF) 1:M attendance)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.attendance (
    attendance_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    barber_id     UUID NOT NULL REFERENCES public.barbers(barber_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    recorded_by   UUID NOT NULL REFERENCES public.users(user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    work_date     DATE NOT NULL,
    time_in       TIME,
    time_out      TIME,
    status        VARCHAR(10) NOT NULL CHECK (status IN ('PRESENT', 'ABSENT', 'LEAVE')),
    CONSTRAINT uq_attendance_barber_date UNIQUE (barber_id, work_date),
    CONSTRAINT chk_attendance_times CHECK (
        (status = 'PRESENT' AND time_in IS NOT NULL AND (time_out IS NULL OR time_out >= time_in))
        OR
        (status IN ('ABSENT', 'LEAVE') AND time_in IS NULL AND time_out IS NULL)
    )
);

CREATE INDEX IF NOT EXISTS idx_attendance_work_date
    ON public.attendance (work_date);

CREATE INDEX IF NOT EXISTS idx_attendance_barber_date
    ON public.attendance (barber_id, work_date);

-- ----------------------------------------------------------------------------
-- 7. TRANSACTIONS (customers 0..1:M, barbers 1:M, users(STAFF) 1:M)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.transactions (
    transaction_id   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    customer_id      UUID REFERENCES public.customers(customer_id) ON UPDATE CASCADE ON DELETE SET NULL,
    barber_id        UUID NOT NULL REFERENCES public.barbers(barber_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    logged_by        UUID NOT NULL REFERENCES public.users(user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    transaction_date TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    total_amount     NUMERIC(10, 2) NOT NULL CHECK (total_amount >= 0),
    status           VARCHAR(10) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PAID', 'VOID'))
);

CREATE INDEX IF NOT EXISTS idx_transactions_date
    ON public.transactions (transaction_date DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_barber_date
    ON public.transactions (barber_id, transaction_date DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_status_date
    ON public.transactions (status, transaction_date DESC);

CREATE INDEX IF NOT EXISTS idx_transactions_customer
    ON public.transactions (customer_id)
    WHERE customer_id IS NOT NULL;

-- ----------------------------------------------------------------------------
-- 8. TRANSACTION_ITEMS (transactions 1:M CASCADE; services 1:M RESTRICT)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.transaction_items (
    item_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES public.transactions(transaction_id) ON UPDATE CASCADE ON DELETE CASCADE,
    service_id     UUID NOT NULL REFERENCES public.services(service_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    service_name   VARCHAR(100) NOT NULL,
    is_haircut     BOOLEAN NOT NULL,
    quantity       INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price     NUMERIC(10, 2) NOT NULL CHECK (unit_price >= 0),
    subtotal       NUMERIC(10, 2) NOT NULL CHECK (subtotal >= 0 AND subtotal = ROUND(unit_price * quantity, 2))
);

CREATE INDEX IF NOT EXISTS idx_transaction_items_tx
    ON public.transaction_items (transaction_id);

CREATE INDEX IF NOT EXISTS idx_transaction_items_service
    ON public.transaction_items (service_id);

-- ----------------------------------------------------------------------------
-- 9. PAYMENTS (transactions 1:M RESTRICT; users(STAFF) 1:M RESTRICT)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payments (
    payment_id     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    transaction_id UUID NOT NULL REFERENCES public.transactions(transaction_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    received_by    UUID NOT NULL REFERENCES public.users(user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    amount         NUMERIC(10, 2) NOT NULL CHECK (amount > 0),
    payment_method VARCHAR(20) NOT NULL CHECK (payment_method IN ('CASH', 'GCASH', 'CARD')),
    reference_no   VARCHAR(50),
    paid_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_tx
    ON public.payments (transaction_id);

CREATE INDEX IF NOT EXISTS idx_payments_paid_at
    ON public.payments (paid_at DESC);

-- ----------------------------------------------------------------------------
-- 10. PAYROLL_SETTINGS (users(OWNER) 1:M payroll_settings)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_settings (
    setting_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    created_by       UUID NOT NULL REFERENCES public.users(user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    owner_share_pct  NUMERIC(5, 2) NOT NULL,
    barber_share_pct NUMERIC(5, 2) NOT NULL,
    period_days      INT NOT NULL DEFAULT 15 CHECK (period_days > 0),
    effective_from   DATE NOT NULL,
    effective_to     DATE,
    CONSTRAINT chk_payroll_shares_sum_100 CHECK (
        owner_share_pct >= 0
        AND barber_share_pct >= 0
        AND owner_share_pct + barber_share_pct = 100.00
    ),
    CONSTRAINT chk_payroll_setting_dates CHECK (
        effective_to IS NULL OR effective_to >= effective_from
    )
);

-- Guarantees at most one active payroll setting at a time (`effective_to IS NULL`).
CREATE UNIQUE INDEX IF NOT EXISTS idx_payroll_settings_single_active
    ON public.payroll_settings ((TRUE))
    WHERE effective_to IS NULL;

-- ----------------------------------------------------------------------------
-- 11. PAYROLL_PERIODS (payroll_settings 1:M, users 1:M)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_periods (
    period_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    setting_id   UUID NOT NULL REFERENCES public.payroll_settings(setting_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    generated_by UUID NOT NULL REFERENCES public.users(user_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    start_date   DATE NOT NULL,
    end_date     DATE NOT NULL,
    status       VARCHAR(10) NOT NULL DEFAULT 'DRAFT' CHECK (status IN ('DRAFT', 'APPROVED', 'PAID')),
    generated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT chk_payroll_period_dates CHECK (end_date >= start_date),
    CONSTRAINT excl_payroll_periods_no_overlap EXCLUDE USING gist (
        daterange(start_date, end_date, '[]') WITH &&
    )
);

CREATE INDEX IF NOT EXISTS idx_payroll_periods_dates
    ON public.payroll_periods (start_date DESC, end_date DESC);

-- ----------------------------------------------------------------------------
-- 12. PAYROLL_RECORDS (payroll_periods 1:M CASCADE; barbers 1:M RESTRICT)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.payroll_records (
    payroll_id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    period_id          UUID NOT NULL REFERENCES public.payroll_periods(period_id) ON UPDATE CASCADE ON DELETE CASCADE,
    barber_id          UUID NOT NULL REFERENCES public.barbers(barber_id) ON UPDATE CASCADE ON DELETE RESTRICT,
    total_haircuts     INT NOT NULL DEFAULT 0 CHECK (total_haircuts >= 0),
    gross_sales        NUMERIC(10, 2) NOT NULL DEFAULT 0.00 CHECK (gross_sales >= 0),
    owner_share_pct    NUMERIC(5, 2) NOT NULL,
    barber_share_pct   NUMERIC(5, 2) NOT NULL,
    owner_share_amount NUMERIC(10, 2) NOT NULL CHECK (owner_share_amount >= 0),
    barber_pay_amount  NUMERIC(10, 2) NOT NULL CHECK (barber_pay_amount >= 0),
    status             VARCHAR(10) NOT NULL DEFAULT 'PENDING' CHECK (status IN ('PENDING', 'PAID')),
    paid_at            TIMESTAMPTZ,
    CONSTRAINT uq_payroll_records_period_barber UNIQUE (period_id, barber_id),
    CONSTRAINT chk_payroll_record_amounts CHECK (
        owner_share_amount + barber_pay_amount = gross_sales
    )
);

CREATE INDEX IF NOT EXISTS idx_payroll_records_period
    ON public.payroll_records (period_id);

CREATE INDEX IF NOT EXISTS idx_payroll_records_barber
    ON public.payroll_records (barber_id);
