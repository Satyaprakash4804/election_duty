"""
election_guard.py
─────────────────
Shared helpers that enforce:
  "All duty + officer + rule rows must be tied to an active
   election_config. If no active config exists for the admin's district,
   every assignment / officer / rules endpoint must refuse."

ALSO provides the auto-finalize hook called opportunistically when an
admin endpoint runs after an election date has passed.

KEY DESIGN (this revision):
  • Officer archival queries filter by `ko.election_id`/`zo.election_id`/
    `so.election_id` so that only officers belonging to THIS election are
    archived. Legacy NULL rows still get archived via the OR clause —
    one-shot migration so old data doesn't get stranded.
  • election_name is denormalized into every *_history table.
  • finalize_district_auto is idempotent + atomic.
"""

from datetime import date
from flask import request
from db import get_db


# ─────────────────────────────────────────────────────────────────────────────
#  STATUS CODES (Flutter listens for these in `errorCode`)
# ─────────────────────────────────────────────────────────────────────────────
NO_ACTIVE_CONFIG   = "NO_ACTIVE_ELECTION_CONFIG"
ELECTION_FINALIZED = "ELECTION_FINALIZED"


# ─────────────────────────────────────────────────────────────────────────────
#  Internal error builder
# ─────────────────────────────────────────────────────────────────────────────
def _err(msg, code=400, error_code=None):
    from app.routes import err as _err_fn
    if error_code:
        resp = _err_fn(msg, code)
        try:
            body = resp[0].get_json() if isinstance(resp, tuple) else resp.get_json()
            if body:
                body["errorCode"] = error_code
                from flask import jsonify
                return jsonify(body), code
        except Exception:
            pass
        return resp
    return _err_fn(msg, code)


# ═════════════════════════════════════════════════════════════════════════════
#  CORE QUERIES
# ═════════════════════════════════════════════════════════════════════════════

def get_active_election(district: str):
    """Returns the active (is_active=1, is_archived=0, is_finalized=0)
    election_config row for the given district, or None."""
    if not district:
        return None
    district = district.strip()
    if not district:
        return None

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, district, state, election_type, election_name,
                       phase, election_year, election_date,
                       pratah_samay, saya_samay, instructions,
                       is_active, is_archived, is_finalized, auto_finalized,
                       finalized_at, finalized_by,
                       created_by, created_at, updated_at
                FROM election_configs
                WHERE district     = %s
                  AND is_active    = 1
                  AND is_archived  = 0
                  AND is_finalized = 0
                ORDER BY updated_at DESC, id DESC
                LIMIT 1
            """, (district,))
            return cur.fetchone()
    finally:
        conn.close()


def require_active_election(district: str):
    """Returns (cfg, err_response). If cfg is None, caller must return err_response.

    Auto-finalize: if a config exists but its election_date is in the past,
    it is finalized in-line and caller is told 'no active config'."""
    cfg = get_active_election(district)

    if not cfg:
        return None, _err(
            "इस जनपद के लिए कोई सक्रिय चुनाव कॉन्फ़िगरेशन नहीं है। "
            "ड्यूटी आवंटन के लिए master से चुनाव कॉन्फ़िगर करवाएं। "
            "(No active election config — ask master to create one.)",
            409,
            error_code=NO_ACTIVE_CONFIG
        )

    election_date = cfg.get("election_date")
    if election_date and election_date < date.today():
        try:
            finalize_district_auto(district, cfg["id"])
        except Exception as e:
            try:
                from app.routes import write_log
                write_log("ERROR",
                          f"auto-finalize failed for district={district}: {e}",
                          "ElectionGuard")
            except Exception:
                print(f"⚠ auto-finalize failed: {e}")
        cfg2 = get_active_election(district)
        if not cfg2:
            return None, _err(
                f"पिछला चुनाव ({cfg.get('election_name','')}) तिथि {election_date} पर समाप्त "
                "हो चुका है और स्वचालित रूप से इतिहास में स्थानांतरित कर दिया गया है। "
                "नई ड्यूटी के लिए master से नया चुनाव कॉन्फ़िगर करवाएं।",
                409,
                error_code=ELECTION_FINALIZED
            )
        cfg = cfg2

    return cfg, None


def run_auto_finalize_if_due(district: str) -> bool:
    """Called from read-only endpoints. Returns True if a config was auto-finalized."""
    cfg = get_active_election(district)
    if not cfg:
        return False
    election_date = cfg.get("election_date")
    if not election_date or election_date >= date.today():
        return False
    try:
        finalize_district_auto(district, cfg["id"])
        return True
    except Exception as e:
        try:
            from app.routes import write_log
            write_log("ERROR", f"auto-finalize ({district}) error: {e}", "ElectionGuard")
        except Exception:
            print(f"⚠ auto-finalize error: {e}")
        return False


# ═════════════════════════════════════════════════════════════════════════════
#  AUTO-FINALIZE — moves all live data to history atomically
# ═════════════════════════════════════════════════════════════════════════════

def _district_admin_ids(conn, district: str) -> list:
    if not district:
        return []
    with conn.cursor() as cur:
        cur.execute(
            "SELECT id FROM users "
            "WHERE role IN ('admin','super_admin') AND district = %s",
            (district,)
        )
        return [r["id"] for r in cur.fetchall()]


def finalize_district_auto(district: str, election_id: int):
    """
    Auto-finalize handler. Idempotent. Atomic per-connection.

    Filters every archive query by `election_id` (with OR election_id IS NULL
    fallback for legacy rows). After archival, only rows for THIS election
    are removed from live tables — rows belonging to a different (still
    active) election are untouched.
    """
    conn = get_db()
    try:
        with conn.cursor() as cur:

            # Recheck under DB read — protects against racing callers
            cur.execute("""
                SELECT id, election_name, election_date, is_finalized
                FROM election_configs
                WHERE id = %s
                FOR UPDATE
            """, (election_id,))
            cfg = cur.fetchone()
            if not cfg or cfg["is_finalized"]:
                conn.commit()
                return

            election_name = cfg.get("election_name") or ""

            admin_ids = _district_admin_ids(conn, district)
            if not admin_ids:
                cur.execute("""
                    UPDATE election_configs
                    SET is_finalized   = 1,
                        auto_finalized = 1,
                        finalized_at   = NOW(),
                        is_active      = 0,
                        is_archived    = 1,
                        archived_at    = NOW()
                    WHERE id = %s
                """, (election_id,))
                conn.commit()
                return

            ph = ",".join(["%s"] * len(admin_ids))

            # ── 1) Booth duty assignments ────────────────────────────────────
            cur.execute(f"""
                INSERT INTO duty_assignments_history
                    (election_id, original_id, admin_id, district, election_name,
                     staff_id, sthal_id,
                     staff_name, staff_pno, staff_mobile, staff_rank,
                     staff_district, staff_thana, is_armed,
                     center_name, center_type,
                     bus_no, election_date, attended, card_downloaded,
                     assigned_by, original_created_at)
                SELECT
                    %s, da.id, sz.admin_id, %s, %s,
                    da.staff_id, da.sthal_id,
                    u.name, u.pno, u.mobile, u.user_rank,
                    u.district, u.thana, u.is_armed,
                    ms.name, ms.center_type,
                    da.bus_no, da.election_date, da.attended, da.card_downloaded,
                    da.assigned_by, da.created_at
                FROM duty_assignments da
                JOIN users u            ON u.id  = da.staff_id
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
                  AND (da.election_id = %s OR da.election_id IS NULL)
            """, [election_id, district, election_name] + admin_ids + [election_id])

            # ── 2) District duty assignments ─────────────────────────────────
            cur.execute(f"""
                INSERT INTO district_duty_history
                    (election_id, original_id, admin_id, district, election_name,
                     duty_type, duty_label_hi, batch_no,
                     staff_id, staff_name, staff_pno, staff_mobile,
                     staff_rank, staff_district, staff_thana, is_armed,
                     assigned_by, bus_no, note, original_created_at)
                SELECT
                    %s, dda.id, dda.admin_id, %s, %s,
                    dda.duty_type, COALESCE(dr.duty_label_hi, ''), dda.batch_no,
                    dda.staff_id, u.name, u.pno, u.mobile,
                    u.user_rank, u.district, u.thana, u.is_armed,
                    dda.assigned_by, dda.bus_no, dda.note, dda.created_at
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                LEFT JOIN district_rules dr
                       ON dr.admin_id  = dda.admin_id
                      AND dr.duty_type = dda.duty_type
                WHERE dda.admin_id IN ({ph})
                  AND (dda.election_id = %s OR dda.election_id IS NULL)
            """, [election_id, district, election_name] + admin_ids + [election_id])

            # ── 3) District rules snapshot ───────────────────────────────────
            cur.execute(f"""
                INSERT INTO district_rules_history
                    (election_id, original_id, admin_id, district, election_name,
                     duty_type, duty_label_hi, sankhya,
                     si_armed_count, si_unarmed_count,
                     hc_armed_count, hc_unarmed_count,
                     const_armed_count, const_unarmed_count,
                     aux_armed_count, aux_unarmed_count,
                     pac_count, sort_order, original_created_at)
                SELECT
                    %s, id, admin_id, %s, %s,
                    duty_type, duty_label_hi, sankhya,
                    si_armed_count, si_unarmed_count,
                    hc_armed_count, hc_unarmed_count,
                    const_armed_count, const_unarmed_count,
                    aux_armed_count, aux_unarmed_count,
                    pac_count, sort_order, created_at
                FROM district_rules
                WHERE admin_id IN ({ph})
                  AND (election_id = %s OR election_id IS NULL)
            """, [election_id, district, election_name] + admin_ids + [election_id])

            # ── 4) Booth rules snapshot ──────────────────────────────────────
            cur.execute(f"""
                INSERT INTO booth_rules_history
                    (election_id, original_id, admin_id, district, election_name,
                     sensitivity, booth_count,
                     si_armed_count, si_unarmed_count,
                     hc_armed_count, hc_unarmed_count,
                     const_armed_count, const_unarmed_count,
                     aux_armed_count, aux_unarmed_count,
                     pac_count, original_created_at)
                SELECT
                    %s, id, admin_id, %s, %s,
                    sensitivity, booth_count,
                    si_armed_count, si_unarmed_count,
                    hc_armed_count, hc_unarmed_count,
                    const_armed_count, const_unarmed_count,
                    aux_armed_count, aux_unarmed_count,
                    pac_count, created_at
                FROM booth_rules
                WHERE admin_id IN ({ph})
                  AND (election_id = %s OR election_id IS NULL)
            """, [election_id, district, election_name] + admin_ids + [election_id])

            # ── 5) 🔐 KSHETRA officers (super-zone level) ───────────────────
            cur.execute(f"""
                INSERT INTO kshetra_officers_history
                    (election_id, original_id, admin_id, district, election_name,
                     super_zone_id, super_zone_name, super_zone_block,
                     user_id, name, pno, mobile, user_rank,
                     assigned_by, original_created_at)
                SELECT
                    %s, ko.id, sz.admin_id, %s, %s,
                    ko.super_zone_id, sz.name, sz.block,
                    ko.user_id, ko.name, ko.pno, ko.mobile, ko.user_rank,
                    ko.assigned_by, ko.created_at
                FROM kshetra_officers ko
                JOIN super_zones sz ON sz.id = ko.super_zone_id
                WHERE sz.admin_id IN ({ph})
                  AND (ko.election_id = %s OR ko.election_id IS NULL)
            """, [election_id, district, election_name] + admin_ids + [election_id])

            # ── 6) 🔐 ZONAL officers (zone level) ────────────────────────────
            cur.execute(f"""
                INSERT INTO zonal_officers_history
                    (election_id, original_id, admin_id, district, election_name,
                     zone_id, zone_name,
                     super_zone_id, super_zone_name,
                     user_id, name, pno, mobile, user_rank,
                     assigned_by, original_created_at)
                SELECT
                    %s, zo.id, sz.admin_id, %s, %s,
                    zo.zone_id, z.name,
                    sz.id, sz.name,
                    zo.user_id, zo.name, zo.pno, zo.mobile, zo.user_rank,
                    zo.assigned_by, zo.created_at
                FROM zonal_officers zo
                JOIN zones z       ON z.id  = zo.zone_id
                JOIN super_zones sz ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
                  AND (zo.election_id = %s OR zo.election_id IS NULL)
            """, [election_id, district, election_name] + admin_ids + [election_id])

            # ── 7) 🔐 SECTOR officers (sector level) ─────────────────────────
            cur.execute(f"""
                INSERT INTO sector_officers_history
                    (election_id, original_id, admin_id, district, election_name,
                     sector_id, sector_name,
                     zone_id, zone_name,
                     super_zone_id, super_zone_name,
                     user_id, name, pno, mobile, user_rank,
                     assigned_by, original_created_at)
                SELECT
                    %s, so.id, sz.admin_id, %s, %s,
                    so.sector_id, s.name,
                    z.id, z.name,
                    sz.id, sz.name,
                    so.user_id, so.name, so.pno, so.mobile, so.user_rank,
                    so.assigned_by, so.created_at
                FROM sector_officers so
                JOIN sectors s     ON s.id  = so.sector_id
                JOIN zones z       ON z.id  = s.zone_id
                JOIN super_zones sz ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
                  AND (so.election_id = %s OR so.election_id IS NULL)
            """, [election_id, district, election_name] + admin_ids + [election_id])

            # ── 8) Delete live booth duty_assignments — only this election ───
            cur.execute(f"""
                DELETE da FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
                  AND (da.election_id = %s OR da.election_id IS NULL)
            """, admin_ids + [election_id])

            # ── 9) Delete live district_duty_assignments — only this election ─
            cur.execute(f"""
                DELETE FROM district_duty_assignments
                WHERE admin_id IN ({ph})
                  AND (election_id = %s OR election_id IS NULL)
            """, admin_ids + [election_id])

            # ── 10) 🔐 Delete live OFFICERS — only this election ─────────────
            cur.execute(f"""
                DELETE ko FROM kshetra_officers ko
                JOIN super_zones sz ON sz.id = ko.super_zone_id
                WHERE sz.admin_id IN ({ph})
                  AND (ko.election_id = %s OR ko.election_id IS NULL)
            """, admin_ids + [election_id])

            cur.execute(f"""
                DELETE zo FROM zonal_officers zo
                JOIN zones z        ON z.id  = zo.zone_id
                JOIN super_zones sz ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
                  AND (zo.election_id = %s OR zo.election_id IS NULL)
            """, admin_ids + [election_id])

            cur.execute(f"""
                DELETE so FROM sector_officers so
                JOIN sectors s      ON s.id  = so.sector_id
                JOIN zones z        ON z.id  = s.zone_id
                JOIN super_zones sz ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({ph})
                  AND (so.election_id = %s OR so.election_id IS NULL)
            """, admin_ids + [election_id])

            # ── 11) Unlock all super zones for this district ─────────────────
            cur.execute(f"""
                UPDATE sz_duty_locks
                SET is_locked     = 0,
                    status        = 'unlocked',
                    unlock_reason = 'Auto-unlocked: election finalized'
                WHERE super_zone_id IN (
                    SELECT id FROM super_zones WHERE admin_id IN ({ph})
                )
            """, admin_ids)

            # ── 12) Mark election finalized + archived ───────────────────────
            cur.execute("""
                UPDATE election_configs
                SET is_finalized   = 1,
                    auto_finalized = 1,
                    finalized_at   = NOW(),
                    is_active      = 0,
                    is_archived    = 1,
                    archived_at    = NOW()
                WHERE id = %s
            """, (election_id,))

        conn.commit()

        try:
            from app.routes import write_log
            write_log("INFO",
                f"Auto-finalized election_id={election_id} district={district}",
                "ElectionGuard")
        except Exception:
            pass

    except Exception:
        try:
            conn.rollback()
        except Exception:
            pass
        raise
    finally:
        conn.close()


# ═════════════════════════════════════════════════════════════════════════════
#  SWEEP — for cron / scheduled job
# ═════════════════════════════════════════════════════════════════════════════

def sweep_auto_finalize_all_districts() -> dict:
    """Finds every active election_config with election_date in the past
    and runs finalize. Returns: { finalized: [...], errors: [...] }"""
    conn = get_db()
    candidates = []
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, district, election_name, election_date
                FROM election_configs
                WHERE is_active    = 1
                  AND is_archived  = 0
                  AND is_finalized = 0
                  AND election_date IS NOT NULL
                  AND election_date < CURDATE()
                ORDER BY election_date
            """)
            candidates = cur.fetchall()
    finally:
        conn.close()

    finalized, errors = [], []
    for c in candidates:
        try:
            finalize_district_auto(c["district"], c["id"])
            finalized.append({
                "id":       c["id"],
                "district": c["district"],
                "name":     c["election_name"],
            })
        except Exception as e:
            errors.append({
                "id":       c["id"],
                "district": c["district"],
                "error":    str(e),
            })
    return {"finalized": finalized, "errors": errors}