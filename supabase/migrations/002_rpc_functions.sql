-- ============================================================================
-- 002_rpc_functions.sql
-- Atomic Business-Rule RPC Functions for Barbershop Management System
-- ============================================================================
-- Structured error message prefixes allow `SupabaseErrorMapper` to map errors
-- identically to domain `AppFailure` subtypes:
--   NOT_FOUND:          -> NotFoundFailure
--   PERMISSION_DENIED:  -> PermissionDeniedFailure
--   DUPLICATE_ENTRY:    -> DuplicateEntryFailure
--   VALIDATION_ERROR:   -> ValidationFailure
--   CONFLICT:           -> ConflictFailure
-- ============================================================================

-- ----------------------------------------------------------------------------
-- Helper: assert_active_user_role
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.assert_active_user_role(
    p_user_id       UUID,
    p_allowed_roles TEXT[]
)
RETURNS VARCHAR
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_role_name VARCHAR;
    v_is_active BOOLEAN;
BEGIN
    SELECT r.role_name, u.is_active
    INTO v_role_name, v_is_active
    FROM public.users u
    JOIN public.roles r ON r.role_id = u.role_id
    WHERE u.user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Acting user % does not exist.', p_user_id;
    END IF;

    IF NOT v_is_active THEN
        RAISE EXCEPTION 'PERMISSION_DENIED: User % is inactive.', p_user_id;
    END IF;

    IF NOT (v_role_name = ANY(p_allowed_roles)) THEN
        RAISE EXCEPTION 'PERMISSION_DENIED: Role % cannot perform this action.', v_role_name;
    END IF;

    RETURN v_role_name;
END;
$$;

-- ----------------------------------------------------------------------------
-- Helper: resolve_login_email_by_username (supports username sign-in under RLS)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.resolve_login_email_by_username(
    p_username TEXT
)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT u.email
    FROM public.users u
    JOIN public.roles r ON r.role_id = u.role_id
    WHERE LOWER(u.username) = LOWER(TRIM(p_username))
      AND u.is_active = TRUE
      AND r.role_name IN ('OWNER', 'STAFF')
    LIMIT 1;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_create_barber_with_profile
-- Creates a BARBER user row (without Auth credentials) + 1:1 barbers row.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_barber_with_profile(
    p_first_name      VARCHAR,
    p_last_name       VARCHAR,
    p_username        VARCHAR,
    p_phone           VARCHAR,
    p_email           VARCHAR,
    p_hire_date       DATE,
    p_specialty       VARCHAR,
    p_acting_owner_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_barber_role_id UUID;
    v_user_id        UUID;
    v_barber_id      UUID;
    v_clean_email    VARCHAR;
BEGIN
    PERFORM public.assert_active_user_role(p_acting_owner_id, ARRAY['OWNER']);

    SELECT role_id INTO v_barber_role_id
    FROM public.roles
    WHERE role_name = 'BARBER';

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: BARBER role is not seeded.';
    END IF;

    v_clean_email := NULLIF(TRIM(COALESCE(p_email, '')), '');

    INSERT INTO public.users (
        role_id, first_name, last_name, username, phone, email, is_active
    )
    VALUES (
        v_barber_role_id,
        TRIM(p_first_name),
        TRIM(p_last_name),
        TRIM(p_username),
        NULLIF(TRIM(COALESCE(p_phone, '')), ''),
        v_clean_email,
        TRUE
    )
    RETURNING user_id INTO v_user_id;

    INSERT INTO public.barbers (
        user_id, hire_date, specialty, status
    )
    VALUES (
        v_user_id,
        p_hire_date,
        NULLIF(TRIM(COALESCE(p_specialty, '')), ''),
        'ACTIVE'
    )
    RETURNING barber_id INTO v_barber_id;

    RETURN v_barber_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_set_user_active_status (syncs paired barbers.status if present)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_set_user_active_status(
    p_user_id        UUID,
    p_is_active      BOOLEAN,
    p_acting_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.assert_active_user_role(p_acting_user_id, ARRAY['OWNER']);

    UPDATE public.users
    SET is_active = p_is_active
    WHERE user_id = p_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: User % not found.', p_user_id;
    END IF;

    UPDATE public.barbers
    SET status = CASE WHEN p_is_active THEN 'ACTIVE' ELSE 'INACTIVE' END
    WHERE user_id = p_user_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_set_barber_status (syncs paired users.is_active)
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_set_barber_status(
    p_barber_id       UUID,
    p_status          VARCHAR,
    p_acting_owner_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    PERFORM public.assert_active_user_role(p_acting_owner_id, ARRAY['OWNER']);

    IF p_status NOT IN ('ACTIVE', 'INACTIVE') THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Invalid barber status "%".', p_status;
    END IF;

    UPDATE public.barbers
    SET status = p_status
    WHERE barber_id = p_barber_id
    RETURNING user_id INTO v_user_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Barber % not found.', p_barber_id;
    END IF;

    UPDATE public.users
    SET is_active = (p_status = 'ACTIVE')
    WHERE user_id = v_user_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_create_transaction
-- Enforces Business Rules #1, #3 (PRESENT today), #5 (unit_price snapshot).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_transaction(
    p_customer_id         UUID,
    p_barber_id           UUID,
    p_logged_by_staff_id  UUID,
    p_transaction_date    TIMESTAMPTZ,
    p_items               JSONB,
    p_initial_payment     JSONB DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shop_date       DATE;
    v_barber_status   VARCHAR;
    v_barber_active   BOOLEAN;
    v_att_status      VARCHAR;
    v_total_amount    NUMERIC(10, 2) := 0.00;
    v_tx_id           UUID;
    v_tx_status       VARCHAR := 'PENDING';
    v_item            JSONB;
    v_service         RECORD;
    v_qty             INT;
    v_subtotal        NUMERIC(10, 2);
    v_init_amount     NUMERIC(10, 2);
    v_init_method     VARCHAR;
    v_init_ref        VARCHAR;
BEGIN
    PERFORM public.assert_active_user_role(p_logged_by_staff_id, ARRAY['STAFF', 'OWNER']);

    IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: A transaction must include at least one service item.';
    END IF;

    IF p_customer_id IS NOT NULL THEN
        PERFORM 1 FROM public.customers WHERE customer_id = p_customer_id;
        IF NOT FOUND THEN
            RAISE EXCEPTION 'NOT_FOUND: Customer % not found.', p_customer_id;
        END IF;
    END IF;

    SELECT b.status, u.is_active
    INTO v_barber_status, v_barber_active
    FROM public.barbers b
    JOIN public.users u ON u.user_id = b.user_id
    WHERE b.barber_id = p_barber_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Barber % not found.', p_barber_id;
    END IF;

    IF v_barber_status <> 'ACTIVE' OR NOT v_barber_active THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Barber % is inactive and cannot serve transactions.', p_barber_id;
    END IF;

    -- Shop-local (+08:00) calendar date for attendance verification (Business Rule #3).
    v_shop_date := ((p_transaction_date AT TIME ZONE 'UTC') + INTERVAL '8 hours')::date;

    SELECT a.status
    INTO v_att_status
    FROM public.attendance a
    WHERE a.barber_id = p_barber_id
      AND a.work_date = v_shop_date;

    IF NOT FOUND OR v_att_status <> 'PRESENT' THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Barber % must be marked PRESENT on % before logging a transaction.', p_barber_id, v_shop_date;
    END IF;

    -- Validate all services and compute total_amount before inserting.
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_qty := COALESCE((v_item->>'quantity')::INT, 1);
        IF v_qty <= 0 THEN
            RAISE EXCEPTION 'VALIDATION_ERROR: Service quantity must be greater than zero.';
        END IF;

        SELECT service_id, service_name, is_haircut, price, is_active
        INTO v_service
        FROM public.services
        WHERE service_id = (v_item->>'service_id')::UUID;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'NOT_FOUND: Service % not found.', (v_item->>'service_id');
        END IF;

        IF NOT v_service.is_active THEN
            RAISE EXCEPTION 'VALIDATION_ERROR: Service "%" is inactive.', v_service.service_name;
        END IF;

        v_subtotal := ROUND(v_service.price * v_qty, 2);
        v_total_amount := v_total_amount + v_subtotal;
    END LOOP;

    IF p_initial_payment IS NOT NULL THEN
        v_init_amount := ROUND((p_initial_payment->>'amount')::NUMERIC, 2);
        v_init_method := UPPER(TRIM(COALESCE(p_initial_payment->>'payment_method', '')));
        v_init_ref := NULLIF(TRIM(COALESCE(p_initial_payment->>'reference_no', '')), '');

        IF v_init_amount IS NULL OR v_init_amount <= 0 THEN
            RAISE EXCEPTION 'VALIDATION_ERROR: Initial payment amount must be positive.';
        END IF;
        IF v_init_amount > v_total_amount THEN
            RAISE EXCEPTION 'VALIDATION_ERROR: Initial payment (%) exceeds transaction total (%).', v_init_amount, v_total_amount;
        END IF;
        IF v_init_method NOT IN ('CASH', 'GCASH', 'CARD') THEN
            RAISE EXCEPTION 'VALIDATION_ERROR: Invalid payment method "%".', v_init_method;
        END IF;

        IF v_init_amount = v_total_amount THEN
            v_tx_status := 'PAID';
        END IF;
    END IF;

    INSERT INTO public.transactions (
        customer_id, barber_id, logged_by, transaction_date, total_amount, status
    )
    VALUES (
        p_customer_id, p_barber_id, p_logged_by_staff_id, p_transaction_date, v_total_amount, v_tx_status
    )
    RETURNING transaction_id INTO v_tx_id;

    -- Insert item snapshots (`unit_price`, `service_name`, `is_haircut`).
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_qty := COALESCE((v_item->>'quantity')::INT, 1);

        SELECT service_id, service_name, is_haircut, price
        INTO v_service
        FROM public.services
        WHERE service_id = (v_item->>'service_id')::UUID;

        v_subtotal := ROUND(v_service.price * v_qty, 2);

        INSERT INTO public.transaction_items (
            transaction_id, service_id, service_name, is_haircut, quantity, unit_price, subtotal
        )
        VALUES (
            v_tx_id, v_service.service_id, v_service.service_name, v_service.is_haircut, v_qty, v_service.price, v_subtotal
        );
    END LOOP;

    IF p_initial_payment IS NOT NULL THEN
        INSERT INTO public.payments (
            transaction_id, received_by, amount, payment_method, reference_no, paid_at
        )
        VALUES (
            v_tx_id, p_logged_by_staff_id, v_init_amount, v_init_method, v_init_ref, p_transaction_date
        );
    END IF;

    RETURN v_tx_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_record_payment
-- Supports partial/split payments; transitions transaction to PAID when settled.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_record_payment(
    p_transaction_id      UUID,
    p_received_by_staff_id UUID,
    p_amount              NUMERIC,
    p_payment_method      VARCHAR,
    p_reference_no        VARCHAR,
    p_paid_at             TIMESTAMPTZ
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tx          RECORD;
    v_paid_so_far NUMERIC(10, 2);
    v_amount      NUMERIC(10, 2);
    v_method      VARCHAR;
    v_payment_id  UUID;
BEGIN
    PERFORM public.assert_active_user_role(p_received_by_staff_id, ARRAY['STAFF', 'OWNER']);

    v_amount := ROUND(p_amount, 2);
    v_method := UPPER(TRIM(COALESCE(p_payment_method, '')));

    IF v_amount IS NULL OR v_amount <= 0 THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Payment amount must be greater than zero.';
    END IF;
    IF v_method NOT IN ('CASH', 'GCASH', 'CARD') THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Invalid payment method "%".', v_method;
    END IF;

    SELECT transaction_id, total_amount, status
    INTO v_tx
    FROM public.transactions
    WHERE transaction_id = p_transaction_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Transaction % not found.', p_transaction_id;
    END IF;

    IF v_tx.status = 'VOID' THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Cannot record payment on a VOID transaction.';
    END IF;
    IF v_tx.status = 'PAID' THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Transaction % is already fully PAID.', p_transaction_id;
    END IF;

    SELECT COALESCE(SUM(amount), 0.00)
    INTO v_paid_so_far
    FROM public.payments
    WHERE transaction_id = p_transaction_id;

    IF v_paid_so_far + v_amount > v_tx.total_amount THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Payment (%) exceeds remaining balance (%).', v_amount, (v_tx.total_amount - v_paid_so_far);
    END IF;

    INSERT INTO public.payments (
        transaction_id, received_by, amount, payment_method, reference_no, paid_at
    )
    VALUES (
        p_transaction_id,
        p_received_by_staff_id,
        v_amount,
        v_method,
        NULLIF(TRIM(COALESCE(p_reference_no, '')), ''),
        COALESCE(p_paid_at, NOW())
    )
    RETURNING payment_id INTO v_payment_id;

    IF v_paid_so_far + v_amount = v_tx.total_amount THEN
        UPDATE public.transactions
        SET status = 'PAID'
        WHERE transaction_id = p_transaction_id;
    END IF;

    RETURN v_payment_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_void_transaction
-- STAFF/OWNER can void PENDING; only OWNER can void PAID (if not payroll-locked).
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_void_transaction(
    p_transaction_id UUID,
    p_acting_user_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_tx           RECORD;
    v_tx_shop_date DATE;
    v_is_locked    BOOLEAN;
BEGIN
    SELECT transaction_id, transaction_date, status
    INTO v_tx
    FROM public.transactions
    WHERE transaction_id = p_transaction_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Transaction % not found.', p_transaction_id;
    END IF;

    IF v_tx.status = 'VOID' THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Transaction % is already VOID.', p_transaction_id;
    END IF;

    IF v_tx.status = 'PENDING' THEN
        PERFORM public.assert_active_user_role(p_acting_user_id, ARRAY['STAFF', 'OWNER']);
    ELSIF v_tx.status = 'PAID' THEN
        PERFORM public.assert_active_user_role(p_acting_user_id, ARRAY['OWNER']);

        v_tx_shop_date := ((v_tx.transaction_date AT TIME ZONE 'UTC') + INTERVAL '8 hours')::date;
        SELECT EXISTS (
            SELECT 1
            FROM public.payroll_periods pp
            WHERE pp.status IN ('APPROVED', 'PAID')
              AND v_tx_shop_date BETWEEN pp.start_date AND pp.end_date
        )
        INTO v_is_locked;

        IF v_is_locked THEN
            RAISE EXCEPTION 'VALIDATION_ERROR: Cannot void a PAID transaction covered by an APPROVED or PAID payroll period.';
        END IF;
    END IF;

    UPDATE public.transactions
    SET status = 'VOID'
    WHERE transaction_id = p_transaction_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_create_payroll_setting
-- Closes any active setting and inserts the new split configuration.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_create_payroll_setting(
    p_created_by_owner_id UUID,
    p_owner_share_pct     NUMERIC,
    p_barber_share_pct    NUMERIC,
    p_period_days         INT,
    p_effective_from      DATE
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_setting_id UUID;
    v_owner_pct  NUMERIC(5, 2);
    v_barber_pct NUMERIC(5, 2);
BEGIN
    PERFORM public.assert_active_user_role(p_created_by_owner_id, ARRAY['OWNER']);

    v_owner_pct := ROUND(p_owner_share_pct, 2);
    v_barber_pct := ROUND(p_barber_share_pct, 2);

    IF v_owner_pct < 0 OR v_barber_pct < 0 OR (v_owner_pct + v_barber_pct) <> 100.00 THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Owner (%) and barber (%) shares must sum to 100.00.', v_owner_pct, v_barber_pct;
    END IF;

    IF p_period_days IS NULL OR p_period_days <= 0 THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: period_days must be greater than zero.';
    END IF;

    -- Close current active setting if one exists.
    UPDATE public.payroll_settings
    SET effective_to = GREATEST(effective_from, (p_effective_from - INTERVAL '1 day')::date)
    WHERE effective_to IS NULL;

    INSERT INTO public.payroll_settings (
        created_by, owner_share_pct, barber_share_pct, period_days, effective_from, effective_to
    )
    VALUES (
        p_created_by_owner_id, v_owner_pct, v_barber_pct, p_period_days, p_effective_from, NULL
    )
    RETURNING setting_id INTO v_setting_id;

    RETURN v_setting_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_generate_payroll_period
-- Aggregates PAID haircut (`is_haircut = TRUE`) sales over `[p_start_date, p_end_date]`
-- in shop-local (+08:00) time and produces one payroll_record per barber.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_generate_payroll_period(
    p_start_date           DATE,
    p_end_date             DATE,
    p_generated_by_user_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_setting       RECORD;
    v_has_overlap   BOOLEAN;
    v_period_id     UUID;
    v_start_utc     TIMESTAMPTZ;
    v_end_utc_excl  TIMESTAMPTZ;
BEGIN
    PERFORM public.assert_active_user_role(p_generated_by_user_id, ARRAY['OWNER']);

    IF p_end_date < p_start_date THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: end_date (%) cannot precede start_date (%).', p_end_date, p_start_date;
    END IF;

    SELECT *
    INTO v_setting
    FROM public.payroll_settings
    WHERE effective_to IS NULL
    ORDER BY effective_from DESC
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: No active payroll_settings configuration found.';
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.payroll_periods pp
        WHERE daterange(pp.start_date, pp.end_date, '[]') && daterange(p_start_date, p_end_date, '[]')
    )
    INTO v_has_overlap;

    IF v_has_overlap THEN
        RAISE EXCEPTION 'CONFLICT: Payroll period (%..%) overlaps an existing payroll period.', p_start_date, p_end_date;
    END IF;

    INSERT INTO public.payroll_periods (
        setting_id, generated_by, start_date, end_date, status, generated_at
    )
    VALUES (
        v_setting.setting_id, p_generated_by_user_id, p_start_date, p_end_date, 'DRAFT', NOW()
    )
    RETURNING period_id INTO v_period_id;

    -- Shop-local (+08:00) half-open UTC boundaries for [p_start_date, p_end_date].
    v_start_utc := (p_start_date::timestamp AT TIME ZONE 'UTC') - INTERVAL '8 hours';
    v_end_utc_excl := ((p_end_date + 1)::timestamp AT TIME ZONE 'UTC') - INTERVAL '8 hours';

    WITH haircut_sales AS (
        SELECT
            t.barber_id,
            COALESCE(SUM(ti.quantity), 0)::INT AS total_haircuts,
            COALESCE(SUM(ti.subtotal), 0.00)::NUMERIC(10, 2) AS gross_sales
        FROM public.transactions t
        JOIN public.transaction_items ti ON ti.transaction_id = t.transaction_id
        WHERE t.status = 'PAID'
          AND ti.is_haircut = TRUE
          AND t.transaction_date >= v_start_utc
          AND t.transaction_date < v_end_utc_excl
        GROUP BY t.barber_id
    ),
    target_barbers AS (
        SELECT b.barber_id
        FROM public.barbers b
        WHERE b.status = 'ACTIVE'
        UNION
        SELECT hs.barber_id
        FROM haircut_sales hs
    ),
    computed AS (
        SELECT
            tb.barber_id,
            COALESCE(hs.total_haircuts, 0) AS total_haircuts,
            COALESCE(hs.gross_sales, 0.00) AS gross_sales,
            ROUND(COALESCE(hs.gross_sales, 0.00) * v_setting.barber_share_pct / 100.0, 2) AS barber_pay_amount
        FROM target_barbers tb
        LEFT JOIN haircut_sales hs ON hs.barber_id = tb.barber_id
    )
    INSERT INTO public.payroll_records (
        period_id,
        barber_id,
        total_haircuts,
        gross_sales,
        owner_share_pct,
        barber_share_pct,
        owner_share_amount,
        barber_pay_amount,
        status,
        paid_at
    )
    SELECT
        v_period_id,
        c.barber_id,
        c.total_haircuts,
        c.gross_sales,
        v_setting.owner_share_pct,
        v_setting.barber_share_pct,
        (c.gross_sales - c.barber_pay_amount),
        c.barber_pay_amount,
        'PENDING',
        NULL
    FROM computed c;

    RETURN v_period_id;
END;
$$;

-- ----------------------------------------------------------------------------
-- RPC: rpc_mark_payroll_record_paid
-- Marks a barber's payroll record PAID; auto-transitions parent period to PAID
-- when all records in that period are PAID.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.rpc_mark_payroll_record_paid(
    p_payroll_id    UUID,
    p_owner_user_id UUID,
    p_paid_at       TIMESTAMPTZ
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_record        RECORD;
    v_period_status VARCHAR;
    v_pending_left  INT;
BEGIN
    PERFORM public.assert_active_user_role(p_owner_user_id, ARRAY['OWNER']);

    SELECT payroll_id, period_id, status
    INTO v_record
    FROM public.payroll_records
    WHERE payroll_id = p_payroll_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'NOT_FOUND: Payroll record % not found.', p_payroll_id;
    END IF;

    SELECT status
    INTO v_period_status
    FROM public.payroll_periods
    WHERE period_id = v_record.period_id
    FOR UPDATE;

    IF v_period_status NOT IN ('APPROVED', 'PAID') THEN
        RAISE EXCEPTION 'VALIDATION_ERROR: Payroll period must be APPROVED before paying barbers.';
    END IF;

    IF v_record.status = 'PAID' THEN
        RAISE EXCEPTION 'CONFLICT: Payroll record % is already marked PAID.', p_payroll_id;
    END IF;

    UPDATE public.payroll_records
    SET status = 'PAID',
        paid_at = COALESCE(p_paid_at, NOW())
    WHERE payroll_id = p_payroll_id;

    SELECT COUNT(*)::INT
    INTO v_pending_left
    FROM public.payroll_records
    WHERE period_id = v_record.period_id
      AND status <> 'PAID';

    IF v_pending_left = 0 THEN
        UPDATE public.payroll_periods
        SET status = 'PAID'
        WHERE period_id = v_record.period_id;
    END IF;
END;
$$;
