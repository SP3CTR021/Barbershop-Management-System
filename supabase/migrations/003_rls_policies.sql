-- ============================================================================
-- 003_rls_policies.sql
-- Row Level Security (RLS) Policies & Function Grants for Supabase
-- ============================================================================
-- Authorization summary:
-- - Only active OWNER and STAFF authenticate with Supabase Auth (`auth.uid()`).
-- - BARBER users are created and checked in by STAFF; they do not sign in.
-- - OWNER manages roles/users, barbers, services/prices, payroll settings/periods,
--   and can void PAID transactions.
-- - STAFF records attendance, customers, transactions (PENDING/PAID), and payments,
--   and can void PENDING transactions.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.current_user_role()
RETURNS VARCHAR
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT r.role_name
    FROM public.users u
    JOIN public.roles r ON r.role_id = u.role_id
    WHERE u.user_id = auth.uid()
      AND u.is_active = TRUE;
$$;

-- Function execution grants
GRANT EXECUTE ON FUNCTION public.resolve_login_email_by_username(TEXT) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.current_user_role() TO authenticated;
GRANT EXECUTE ON FUNCTION public.assert_active_user_role(UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_barber_with_profile(VARCHAR, VARCHAR, VARCHAR, VARCHAR, VARCHAR, DATE, VARCHAR, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_set_user_active_status(UUID, BOOLEAN, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_set_barber_status(UUID, VARCHAR, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_transaction(UUID, UUID, UUID, TIMESTAMPTZ, JSONB, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_record_payment(UUID, UUID, NUMERIC, VARCHAR, VARCHAR, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_void_transaction(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_create_payroll_setting(UUID, NUMERIC, NUMERIC, INT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_generate_payroll_period(DATE, DATE, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rpc_mark_payroll_record_paid(UUID, UUID, TIMESTAMPTZ) TO authenticated;

-- Enable RLS on all 12 tables
ALTER TABLE public.roles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.barbers           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.services          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transactions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.transaction_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_settings  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_periods   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payroll_records   ENABLE ROW LEVEL SECURITY;

-- ----------------------------------------------------------------------------
-- ROLES policies
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS roles_select_authenticated ON public.roles;
CREATE POLICY roles_select_authenticated ON public.roles
    FOR SELECT TO authenticated
    USING (TRUE);

DROP POLICY IF EXISTS roles_insert_owner_or_seed ON public.roles;
CREATE POLICY roles_insert_owner_or_seed ON public.roles
    FOR INSERT TO authenticated
    WITH CHECK (
        public.current_user_role() = 'OWNER'
        OR NOT EXISTS (SELECT 1 FROM public.roles)
    );

-- ----------------------------------------------------------------------------
-- USERS policies
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS users_select_staff_or_owner ON public.users;
CREATE POLICY users_select_staff_or_owner ON public.users
    FOR SELECT TO authenticated
    USING (
        public.current_user_role() IN ('OWNER', 'STAFF')
        OR user_id = auth.uid()
    );

DROP POLICY IF EXISTS users_insert_owner_or_bootstrap ON public.users;
CREATE POLICY users_insert_owner_or_bootstrap ON public.users
    FOR INSERT TO authenticated
    WITH CHECK (
        public.current_user_role() = 'OWNER'
        OR (
            user_id = auth.uid()
            AND NOT EXISTS (
                SELECT 1
                FROM public.users u
                JOIN public.roles r ON r.role_id = u.role_id
                WHERE r.role_name = 'OWNER'
            )
        )
    );

DROP POLICY IF EXISTS users_update_owner ON public.users;
CREATE POLICY users_update_owner ON public.users
    FOR UPDATE TO authenticated
    USING (public.current_user_role() = 'OWNER')
    WITH CHECK (public.current_user_role() = 'OWNER');

-- ----------------------------------------------------------------------------
-- BARBERS policies
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS barbers_select_staff_or_owner ON public.barbers;
CREATE POLICY barbers_select_staff_or_owner ON public.barbers
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS barbers_write_owner ON public.barbers;
CREATE POLICY barbers_write_owner ON public.barbers
    FOR ALL TO authenticated
    USING (public.current_user_role() = 'OWNER')
    WITH CHECK (public.current_user_role() = 'OWNER');

-- ----------------------------------------------------------------------------
-- CUSTOMERS policies
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS customers_rw_staff_or_owner ON public.customers;
CREATE POLICY customers_rw_staff_or_owner ON public.customers
    FOR ALL TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'))
    WITH CHECK (public.current_user_role() IN ('OWNER', 'STAFF'));

-- ----------------------------------------------------------------------------
-- SERVICES policies
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS services_select_staff_or_owner ON public.services;
CREATE POLICY services_select_staff_or_owner ON public.services
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS services_write_owner ON public.services;
CREATE POLICY services_write_owner ON public.services
    FOR ALL TO authenticated
    USING (public.current_user_role() = 'OWNER')
    WITH CHECK (public.current_user_role() = 'OWNER');

-- ----------------------------------------------------------------------------
-- ATTENDANCE policies
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS attendance_rw_staff_or_owner ON public.attendance;
CREATE POLICY attendance_rw_staff_or_owner ON public.attendance
    FOR ALL TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'))
    WITH CHECK (public.current_user_role() IN ('OWNER', 'STAFF'));

-- ----------------------------------------------------------------------------
-- TRANSACTIONS, TRANSACTION_ITEMS, PAYMENTS policies
-- (Complex business transitions run via SECURITY DEFINER RPCs as well.)
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS transactions_select_staff_or_owner ON public.transactions;
CREATE POLICY transactions_select_staff_or_owner ON public.transactions
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS transactions_insert_staff_or_owner ON public.transactions;
CREATE POLICY transactions_insert_staff_or_owner ON public.transactions
    FOR INSERT TO authenticated
    WITH CHECK (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS transactions_update_staff_or_owner ON public.transactions;
CREATE POLICY transactions_update_staff_or_owner ON public.transactions
    FOR UPDATE TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'))
    WITH CHECK (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS transaction_items_select_staff_or_owner ON public.transaction_items;
CREATE POLICY transaction_items_select_staff_or_owner ON public.transaction_items
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS transaction_items_insert_staff_or_owner ON public.transaction_items;
CREATE POLICY transaction_items_insert_staff_or_owner ON public.transaction_items
    FOR INSERT TO authenticated
    WITH CHECK (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS payments_select_staff_or_owner ON public.payments;
CREATE POLICY payments_select_staff_or_owner ON public.payments
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS payments_insert_staff_or_owner ON public.payments;
CREATE POLICY payments_insert_staff_or_owner ON public.payments
    FOR INSERT TO authenticated
    WITH CHECK (public.current_user_role() IN ('OWNER', 'STAFF'));

-- ----------------------------------------------------------------------------
-- PAYROLL_SETTINGS, PAYROLL_PERIODS, PAYROLL_RECORDS policies
-- ----------------------------------------------------------------------------
DROP POLICY IF EXISTS payroll_settings_select_staff_or_owner ON public.payroll_settings;
CREATE POLICY payroll_settings_select_staff_or_owner ON public.payroll_settings
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS payroll_settings_write_owner ON public.payroll_settings;
CREATE POLICY payroll_settings_write_owner ON public.payroll_settings
    FOR ALL TO authenticated
    USING (public.current_user_role() = 'OWNER')
    WITH CHECK (public.current_user_role() = 'OWNER');

DROP POLICY IF EXISTS payroll_periods_select_staff_or_owner ON public.payroll_periods;
CREATE POLICY payroll_periods_select_staff_or_owner ON public.payroll_periods
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS payroll_periods_write_owner ON public.payroll_periods;
CREATE POLICY payroll_periods_write_owner ON public.payroll_periods
    FOR ALL TO authenticated
    USING (public.current_user_role() = 'OWNER')
    WITH CHECK (public.current_user_role() = 'OWNER');

DROP POLICY IF EXISTS payroll_records_select_staff_or_owner ON public.payroll_records;
CREATE POLICY payroll_records_select_staff_or_owner ON public.payroll_records
    FOR SELECT TO authenticated
    USING (public.current_user_role() IN ('OWNER', 'STAFF'));

DROP POLICY IF EXISTS payroll_records_write_owner ON public.payroll_records;
CREATE POLICY payroll_records_write_owner ON public.payroll_records
    FOR ALL TO authenticated
    USING (public.current_user_role() = 'OWNER')
    WITH CHECK (public.current_user_role() = 'OWNER');
