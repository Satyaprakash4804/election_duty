"""
admin.py — main admin blueprint (production merged version)
────────────────────────────────────────────────────────────
All duty assignment endpoints are guarded by require_active_election().
Every INSERT into duty_assignments / district_duty_assignments stamps election_id.
Auto-finalize runs opportunistically when election_date has passed.
"""

import json
import io
import csv
import math
import re
import time
import hashlib
import threading
import traceback
from concurrent.futures import ThreadPoolExecutor, as_completed

from flask import Blueprint, request, Response, stream_with_context, jsonify
from werkzeug.security import generate_password_hash
from flask_jwt_extended import jwt_required

from db import get_db
from app.routes import ok, err, write_log, admin_required
from app.election_guard import (
    get_active_election,
    require_active_election,
    run_auto_finalize_if_due,
)

admin_bp = Blueprint("admin", __name__, url_prefix="/api/admin")

# ── Constants ─────────────────────────────────────────────────────────────────
DEFAULT_PAGE_SIZE = 50
MAX_PAGE_SIZE     = 200
HASH_WORKERS      = 8
MAX_BATCH_ROWS    = 10_000
INSERT_CHUNK_SIZE = 200
SALT = "election_2026_secure_key"

RANK_HIERARCHY = [
    'SP', 'ASP', 'DSP', 'Inspector', 'SI', 'ASI', 'Head Constable', 'Constable'
]

VALID_SENS = ("A++", "A", "B", "C")

RANK_ASSIGN_ORDER = [
    ("SI",             1, "si_armed_count"),
    ("SI",             0, "si_unarmed_count"),
    ("Head Constable", 1, "hc_armed_count"),
    ("Head Constable", 0, "hc_unarmed_count"),
    ("Constable",      1, "const_armed_count"),
    ("Constable",      0, "const_unarmed_count"),
    ("Constable",      1, "aux_armed_count"),
    ("Constable",      0, "aux_unarmed_count"),
]

DEFAULT_DISTRICT_DUTIES = [
    ("cluster_mobile",        "क्लस्टर मोबाईल",                   10),
    ("thana_mobile",          "थाना मोबाईल",                      20),
    ("thana_reserve",         "थाना रिजर्व",                      30),
    ("thana_extra_mobile",    "थाना अतिरिक्त मोबाईल",             40),
    ("sector_pol_mag_mobile", "सैक्टर पुलिस / मजिस्ट्रेट मोबाईल", 50),
    ("zonal_pol_mag_mobile",  "जोनल पुलिस / मजिस्ट्रेट मोबाईल",   60),
    ("sdm_co_mobile",         "एसडीएम / सीओ मोबाईल",              70),
    ("chowki_mobile",         "चौकी मोबाईल",                      80),
    ("barrier_picket",        "बैरियर / पिकैट",                   90),
    ("evm_security",          "ईवीएम सुरक्षा",                   100),
    ("adm_sp_mobile",         "एडीएम / एसपी मोबाईल",             110),
    ("dm_sp_mobile",          "डीएम / एसपी मोबाईल",              120),
    ("observer_security",     "पर्यवेक्षक सुरक्षा",              130),
    ("hq_reserve",            "मुख्यालय रिजर्व",                  140),
]
_DEFAULT_DUTY_KEYS = {dt for dt, _, _ in DEFAULT_DISTRICT_DUTIES}

FALLBACK = {
    "SI": ["Head Constable", "Constable"],
    "Head Constable": ["Constable"],
    "Constable": [],
}

# Officer endpoints that require an active election guard
OFFICER_GUARD_ENDPOINTS = {
    "admin.add_kshetra_officer",
    "admin.update_kshetra_officer",
    "admin.add_zonal_officer",
    "admin.update_zonal_officer",
    "admin.add_sector_officer",
    "admin.update_sector_officer",
}


# ═════════════════════════════════════════════════════════════════════════════
#  GENERIC HELPERS
# ═════════════════════════════════════════════════════════════════════════════

def _fast_hash(pno: str) -> str:
    return hashlib.sha256((pno + SALT).encode()).hexdigest()

def _sse(data: dict) -> bytes:
    return f"data: {json.dumps(data, ensure_ascii=False)}\n\n".encode("utf-8")

def _admin_id():
    return request.user["id"]

def _o(r):
    return {
        "id":     r["id"],
        "userId": r["user_id"],
        "name":   r["name"]      or "",
        "pno":    r["pno"]       or "",
        "mobile": r["mobile"]    or "",
        "rank":   r["user_rank"] or "",
    }

def _page_params():
    page  = max(1, request.args.get("page", 1, type=int))
    limit = min(MAX_PAGE_SIZE, max(1, request.args.get("limit", DEFAULT_PAGE_SIZE, type=int)))
    return page, limit, (page - 1) * limit

def _paginated(data, total, page, limit):
    return ok({
        "data":       data,
        "total":      total,
        "page":       page,
        "limit":      limit,
        "totalPages": -(-total // limit) if limit else 0,
    })

def _get_lower_rank(rank: str):
    try:
        idx = RANK_HIERARCHY.index(rank)
        if idx < len(RANK_HIERARCHY) - 1:
            return RANK_HIERARCHY[idx + 1]
    except ValueError:
        pass
    return None

def _district_admin_ids() -> list:
    district = (request.user.get("district") or "").strip()
    if not district:
        return [_admin_id()]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id FROM users WHERE role IN ('admin','super_admin') AND district = %s",
                (district,)
            )
            ids = [r["id"] for r in cur.fetchall()]
            if _admin_id() not in ids:
                ids.append(_admin_id())
            return ids if ids else [_admin_id()]
    finally:
        conn.close()

def _district_placeholder(ids: list):
    return ",".join(["%s"] * len(ids)), ids

def _staff_list(cur, district=None):
    if district:
        cur.execute(
            "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users "
            "WHERE role='staff' AND district=%s AND is_active=1 ORDER BY name",
            (district,)
        )
    else:
        cur.execute(
            "SELECT id, name, pno, mobile, thana, user_rank, is_armed FROM users "
            "WHERE role='staff' AND is_active=1 ORDER BY name"
        )
    return [{"id": r["id"], "name": r["name"] or "", "pno": r["pno"] or "",
             "mobile": r["mobile"] or "", "rank": r["user_rank"] or "",
             "isArmed": bool(r["is_armed"])}
            for r in cur.fetchall()]

def normalize_rule(r):
    return {
        "booth_count":         r.get("boothCount"),
        "si_armed_count":      r.get("siArmedCount", 0),
        "si_unarmed_count":    r.get("siUnarmedCount", 0),
        "hc_armed_count":      r.get("hcArmedCount", 0),
        "hc_unarmed_count":    r.get("hcUnarmedCount", 0),
        "const_armed_count":   r.get("constArmedCount", 0),
        "const_unarmed_count": r.get("constUnarmedCount", 0),
        "aux_armed_count":     r.get("auxArmedCount", 0),
        "aux_unarmed_count":   r.get("auxUnarmedCount", 0),
        "pac_count":           r.get("pacCount", 0),
    }

def _serialize_booth_rule(r):
    return {
        "boothCount":        r["booth_count"],
        "siArmedCount":      r["si_armed_count"],
        "siUnarmedCount":    r["si_unarmed_count"],
        "hcArmedCount":      r["hc_armed_count"],
        "hcUnarmedCount":    r["hc_unarmed_count"],
        "constArmedCount":   r["const_armed_count"],
        "constUnarmedCount": r["const_unarmed_count"],
        "auxArmedCount":     r["aux_armed_count"],
        "auxUnarmedCount":   r["aux_unarmed_count"],
        "pacCount":          float(r["pac_count"] or 0),
    }

def _serialize_district_rule(r):
    return {
        "dutyType":          r["duty_type"],
        "dutyLabelHi":       r["duty_label_hi"] or "",
        "sankhya":           r["sankhya"],
        "siArmedCount":      r["si_armed_count"],
        "siUnarmedCount":    r["si_unarmed_count"],
        "hcArmedCount":      r["hc_armed_count"],
        "hcUnarmedCount":    r["hc_unarmed_count"],
        "constArmedCount":   r["const_armed_count"],
        "constUnarmedCount": r["const_unarmed_count"],
        "auxArmedCount":     r["aux_armed_count"],
        "auxUnarmedCount":   r["aux_unarmed_count"],
        "pacCount":          float(r["pac_count"] or 0),
        "sortOrder":         r["sort_order"],
        "isDefault":         r["duty_type"] in _DEFAULT_DUTY_KEYS,
    }


# ═════════════════════════════════════════════════════════════════════════════
#  BEFORE REQUEST — officer election guard
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.before_request
def _enforce_officer_election_guard():
    endpoint = (request.endpoint or "")
    if endpoint in OFFICER_GUARD_ENDPOINTS:
        user = getattr(request, "user", None)
        district = (user.get("district") if user else "") or ""
        cfg, gerr = require_active_election(district)
        if gerr:
            return gerr
        request.active_election_cfg = cfg


# ═════════════════════════════════════════════════════════════════════════════
#  SUPER ZONE ASSIGNMENT JOBS
# ═════════════════════════════════════════════════════════════════════════════

def run_auto_assign_job(job_id, super_zone_id, admin_id, election_id):
    print("🚀 AUTO ASSIGN STARTED", super_zone_id)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE sz_assign_jobs SET status='running' WHERE id=%s", (job_id,))
            conn.commit()

        auto_assign_internal(super_zone_id, admin_id, election_id)

        with conn.cursor() as cur:
            cur.execute("UPDATE sz_assign_jobs SET status='done' WHERE id=%s", (job_id,))
            conn.commit()
        print("✅ Auto assign completed")

    except Exception as e:
        print("❌ AUTO ASSIGN ERROR:", e)
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE sz_assign_jobs SET status='error', error_msg=%s WHERE id=%s",
                    (str(e), job_id)
                )
                conn.commit()
        except Exception:
            pass
    finally:
        conn.close()


@admin_bp.route("/assign/start/<int:super_zone_id>", methods=["POST"])
@admin_required
def start_assignment(super_zone_id):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "INSERT INTO sz_assign_jobs (super_zone_id, created_by) VALUES (%s,%s)",
                (super_zone_id, request.user["id"])
            )
            job_id = cur.lastrowid
        conn.commit()
        threading.Thread(
            target=run_auto_assign_job,
            args=(job_id, super_zone_id, request.user["id"], election_id),
            daemon=True,
        ).start()
    finally:
        conn.close()
    return ok({"jobId": job_id}, "Assignment started")


@admin_bp.route("/assign/status/<int:job_id>", methods=["GET"])
@admin_required
def check_job(job_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sz_assign_jobs WHERE id=%s", (job_id,))
            job = cur.fetchone()
    finally:
        conn.close()
    return ok(job)


@admin_bp.route("/center/<int:id>/custom-rule", methods=["POST"])
@admin_required
def set_custom_rule(id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE matdan_sthal SET custom_rule_id=%s WHERE id=%s",
                        (body.get("ruleId"), id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Custom rule applied")


@admin_bp.route("/lock/<int:super_zone_id>", methods=["POST"])
@admin_required
def lock_sz(super_zone_id):
    body = request.get_json() or {}
    reason = body.get("reason", "")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO sz_duty_locks (super_zone_id, is_locked, status, unlock_reason)
                VALUES (%s,1,'locked',%s)
                ON DUPLICATE KEY UPDATE is_locked=1, status='locked', unlock_reason=%s
            """, (super_zone_id, reason, reason))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Locked")


# ═════════════════════════════════════════════════════════════════════════════
#  SUPER ZONES
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/super-zones", methods=["GET"])
@admin_required
def get_super_zones():
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT sz.id, sz.name, sz.district, sz.block,
                       COUNT(DISTINCT ms.id)         AS center_count,
                       COUNT(DISTINCT da.staff_id)   AS assigned_count,
                       COALESCE(l.is_locked, 0)      AS is_locked
                FROM super_zones sz
                LEFT JOIN zones z            ON z.super_zone_id      = sz.id
                LEFT JOIN sectors s          ON s.zone_id            = z.id
                LEFT JOIN gram_panchayats gp ON gp.sector_id         = s.id
                LEFT JOIN matdan_sthal ms    ON ms.gram_panchayat_id = gp.id
                LEFT JOIN duty_assignments da ON da.sthal_id         = ms.id
                LEFT JOIN sz_duty_locks l    ON l.super_zone_id      = sz.id
                WHERE sz.admin_id IN ({d_ph})
                GROUP BY sz.id ORDER BY sz.id
            """, d_params)
            rows = cur.fetchall()
            if not rows:
                return ok([])
            sz_ids = [r["id"] for r in rows]
            sz_ph  = ",".join(["%s"] * len(sz_ids))

            # Get required staff count per super zone from booth_rules
            cur.execute(f"""
                SELECT
                    sz2.id AS sz_id,
                    COALESCE(SUM(
                        ms2.booth_count *
                        COALESCE(br.si_armed_count,0) +
                        ms2.booth_count *
                        COALESCE(br.si_unarmed_count,0) +
                        ms2.booth_count *
                        COALESCE(br.hc_armed_count,0) +
                        ms2.booth_count *
                        COALESCE(br.hc_unarmed_count,0) +
                        ms2.booth_count *
                        COALESCE(br.const_armed_count,0) +
                        ms2.booth_count *
                        COALESCE(br.const_unarmed_count,0) +
                        ms2.booth_count *
                        COALESCE(br.aux_armed_count,0) +
                        ms2.booth_count *
                        COALESCE(br.aux_unarmed_count,0)
                    ), 0) AS required_count
                FROM super_zones sz2
                LEFT JOIN zones z2            ON z2.super_zone_id      = sz2.id
                LEFT JOIN sectors s2          ON s2.zone_id            = z2.id
                LEFT JOIN gram_panchayats gp2 ON gp2.sector_id         = s2.id
                LEFT JOIN matdan_sthal ms2    ON ms2.gram_panchayat_id = gp2.id
                LEFT JOIN booth_rules br
                    ON br.sensitivity = ms2.center_type
                    AND br.booth_count = LEAST(ms2.booth_count, 15)
                    AND br.admin_id IN ({d_ph})
                WHERE sz2.id IN ({sz_ph})
                GROUP BY sz2.id
            """, d_params + sz_ids)
            required_map = {r["sz_id"]: int(r["required_count"] or 0)
                            for r in cur.fetchall()}

            cur.execute(f"SELECT * FROM kshetra_officers WHERE super_zone_id IN ({sz_ph}) "
                        f"ORDER BY super_zone_id, id", sz_ids)
            officers_by_sz = {}
            for off in cur.fetchall():
                officers_by_sz.setdefault(off["super_zone_id"], []).append(_o(off))

            result = []
            for r in rows:
                sz_id        = r["id"]
                assigned_cnt = int(r["assigned_count"] or 0)
                required_cnt = required_map.get(sz_id, 0)
                center_cnt   = int(r["center_count"] or 0)
                result.append({
                    "id":             sz_id,
                    "name":           r["name"]     or "",
                    "district":       r["district"] or "",
                    "block":          r["block"]    or "",
                    "center_count":   center_cnt,
                    "is_locked":      int(r["is_locked"] or 0),
                    "officers":       officers_by_sz.get(sz_id, []),
                    # ✅ Duty status fields Flutter reads
                    "assignedBooths": assigned_cnt,
                    "totalBooths":    required_cnt,
                    "dutyFullyAssigned": (
                        required_cnt > 0 and assigned_cnt >= required_cnt
                    ),
                })
    finally:
        conn.close()
    return ok(result)

@admin_bp.route("/super-zones", methods=["POST"])
@admin_required
def add_super_zone():
    # Need election_id if officers are embedded; harmless to require always
    body = request.get_json() or {}
    has_officers = bool(body.get("officers"))
    election_id = None
    if has_officers:
        cfg, gerr = require_active_election(request.user.get("district"))
        if gerr:
            return gerr
        election_id = cfg["id"]
 
    name = body.get("name", "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO super_zones (name,district,block,admin_id) VALUES (%s,%s,%s,%s)",
                        (name, body.get("district", request.user.get("district") or ""),
                         body.get("block", ""), _admin_id()))
            sz_id = cur.lastrowid
            for o in body.get("officers", []):
                _insert_officer(cur, "kshetra_officers", "super_zone_id",
                                sz_id, o, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": sz_id, "name": name, "electionId": election_id},
              "Super Zone added", 201)
 
 
@admin_bp.route("/super-zones/<int:sz_id>", methods=["PUT"])
@admin_required
def update_super_zone(sz_id):
    body = request.get_json() or {}
    has_officers = bool(body.get("officers"))
    election_id = None
    if has_officers:
        cfg, gerr = require_active_election(request.user.get("district"))
        if gerr:
            return gerr
        election_id = cfg["id"]
 
    d_ids = _district_admin_ids()
    ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT id FROM super_zones WHERE id=%s AND admin_id IN ({ph})",
                        [sz_id] + d_params)
            if not cur.fetchone():
                return err("Not found or access denied", 403)
            cur.execute("UPDATE super_zones SET name=%s,district=%s,block=%s WHERE id=%s",
                        (body.get("name",""), body.get("district",""),
                         body.get("block",""), sz_id))
            cur.execute("DELETE FROM kshetra_officers WHERE super_zone_id=%s", (sz_id,))
            for o in body.get("officers", []):
                _insert_officer(cur, "kshetra_officers", "super_zone_id",
                                sz_id, o, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"electionId": election_id}, "Updated")
 
 
@admin_bp.route("/super-zones/<int:sz_id>", methods=["DELETE"])
@admin_required
def delete_super_zone(sz_id):
    d_ids = _district_admin_ids()
    ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM super_zones WHERE id=%s AND admin_id IN ({ph})",
                        [sz_id] + d_params)
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


@admin_bp.route("/super-zones/<int:sz_id>/officers", methods=["GET"])
@admin_required
def get_kshetra_officers(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM kshetra_officers WHERE super_zone_id=%s ORDER BY id", (sz_id,))
            rows = cur.fetchall()
            staff = _staff_list(cur, request.user.get("district"))
    finally:
        conn.close()
    return ok({"officers": [_o(r) for r in rows], "availableStaff": staff})


 
@admin_bp.route("/super-zones/<int:sz_id>/officers", methods=["POST"])
@admin_required
def add_kshetra_officer(sz_id):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]
 
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "kshetra_officers", "super_zone_id",
                                     sz_id, body, election_id)
            cur.execute("SELECT user_id FROM kshetra_officers WHERE id=%s", (new_id,))
            row = cur.fetchone()
            user_id = row["user_id"] if row else None
        conn.commit()
    finally:
        conn.close()
    write_log("INFO",
              f"Kshetra officer assigned: super_zone={sz_id} user={user_id} "
              f"(election={election_id}) by admin {_admin_id()}",
              "OfficerDuty")
    return ok({"id": new_id, "userId": user_id, "electionId": election_id},
              "क्षेत्राधिकारी आवंटित", 201)
 
 
@admin_bp.route("/kshetra-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_kshetra_officer(o_id):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    body = request.get_json() or {}
    return _update_officer_record(o_id, "kshetra_officers", body, cfg["id"])
 

@admin_bp.route("/kshetra-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_kshetra_officer(o_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM kshetra_officers WHERE id=%s", (o_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ═════════════════════════════════════════════════════════════════════════════
#  ZONES
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/super-zones/<int:sz_id>/zones", methods=["GET"])
@admin_required
def get_zones(sz_id):
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()
    conn = get_db()
    try:
        with conn.cursor() as cur:
            d_ids = _district_admin_ids()
            ph, d_params = _district_placeholder(d_ids)
            cur.execute(f"SELECT id FROM super_zones WHERE id=%s AND admin_id IN ({ph})",
                        [sz_id] + d_params)
            if not cur.fetchone():
                return err("Not found or access denied", 403)
            params = [sz_id]
            where_extra = ""
            if search:
                where_extra = "AND z.name LIKE %s"
                params.append(f"%{search}%")
            cur.execute(f"SELECT COUNT(*) AS cnt FROM zones z WHERE z.super_zone_id=%s {where_extra}",
                        params)
            total = cur.fetchone()["cnt"]
            cur.execute(f"""
                SELECT z.id, z.name, z.hq_address, COUNT(DISTINCT s.id) AS sector_count
                FROM zones z LEFT JOIN sectors s ON s.zone_id=z.id
                WHERE z.super_zone_id=%s {where_extra}
                GROUP BY z.id ORDER BY z.id LIMIT %s OFFSET %s
            """, params + [limit, offset])
            zones = cur.fetchall()
            if not zones:
                return _paginated([], total, page, limit)
            z_ids = [z["id"] for z in zones]
            z_ph = ",".join(["%s"] * len(z_ids))
            cur.execute(f"SELECT * FROM zonal_officers WHERE zone_id IN ({z_ph}) "
                        f"ORDER BY zone_id, id", z_ids)
            officers_by_zone = {}
            for row in cur.fetchall():
                officers_by_zone.setdefault(row["zone_id"], []).append(_o(row))
            result = [{
                "id":          z["id"],
                "name":        z["name"]       or "",
                "hqAddress":   z["hq_address"] or "",
                "sectorCount": z["sector_count"],
                "officers":    officers_by_zone.get(z["id"], []),
            } for z in zones]
    finally:
        conn.close()
    return _paginated(result, total, page, limit)



@admin_bp.route("/super-zones/<int:sz_id>/zones", methods=["POST"])
@admin_required
def add_zone(sz_id):
    body = request.get_json() or {}
    has_officers = bool(body.get("officers"))
    election_id = None
    if has_officers:
        cfg, gerr = require_active_election(request.user.get("district"))
        if gerr:
            return gerr
        election_id = cfg["id"]
 
    name = body.get("name", "").strip()
    if not name:
        return err("name required")
    d_ids = _district_admin_ids()
    ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT id FROM super_zones WHERE id=%s AND admin_id IN ({ph})",
                        [sz_id] + d_params)
            if not cur.fetchone():
                return err("Not found or access denied", 403)
            cur.execute("INSERT INTO zones (name,hq_address,super_zone_id) VALUES (%s,%s,%s)",
                        (name, body.get("hqAddress", ""), sz_id))
            z_id = cur.lastrowid
            for o in body.get("officers", []):
                _insert_officer(cur, "zonal_officers", "zone_id", z_id, o, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": z_id, "name": name, "electionId": election_id}, "Zone added", 201)
 
 
@admin_bp.route("/zones/<int:z_id>", methods=["PUT"])
@admin_required
def update_zone(z_id):
    body = request.get_json() or {}
    has_officers = bool(body.get("officers"))
    election_id = None
    if has_officers:
        cfg, gerr = require_active_election(request.user.get("district"))
        if gerr:
            return gerr
        election_id = cfg["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE zones SET name=%s,hq_address=%s WHERE id=%s",
                (body.get("name",""), body.get("hqAddress",""), z_id)
            )
            cur.execute("DELETE FROM zonal_officers WHERE zone_id=%s", (z_id,))
            for o in body.get("officers", []):
                _insert_officer(cur, "zonal_officers", "zone_id", z_id, o, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"electionId": election_id}, "Updated")
 
 


@admin_bp.route("/zones/<int:z_id>", methods=["DELETE"])
@admin_required
def delete_zone(z_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM zones WHERE id=%s", (z_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


@admin_bp.route("/zones/<int:z_id>/officers", methods=["GET"])
@admin_required
def get_zonal_officers(z_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM zonal_officers WHERE zone_id=%s ORDER BY id", (z_id,))
            rows = cur.fetchall()
            staff = _staff_list(cur, request.user.get("district"))
    finally:
        conn.close()
    return ok({"officers": [_o(r) for r in rows], "availableStaff": staff})



@admin_bp.route("/zones/<int:z_id>/officers", methods=["POST"])
@admin_required
def add_zonal_officer(z_id):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]
 
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "zonal_officers", "zone_id",
                                     z_id, body, election_id)
            cur.execute("SELECT user_id FROM zonal_officers WHERE id=%s", (new_id,))
            row = cur.fetchone()
            user_id = row["user_id"] if row else None
        conn.commit()
    finally:
        conn.close()
    write_log("INFO",
              f"Zonal officer assigned: zone={z_id} user={user_id} "
              f"(election={election_id}) by admin {_admin_id()}",
              "OfficerDuty")
    return ok({"id": new_id, "userId": user_id, "electionId": election_id},
              "ज़ोनल अधिकारी आवंटित", 201)
 
 
@admin_bp.route("/zonal-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_zonal_officer(o_id):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    body = request.get_json() or {}
    return _update_officer_record(o_id, "zonal_officers", body, cfg["id"])
 

@admin_bp.route("/zonal-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_zonal_officer(o_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM zonal_officers WHERE id=%s", (o_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ═════════════════════════════════════════════════════════════════════════════
#  SECTORS
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/zones/<int:z_id>/sectors", methods=["GET"])
@admin_required
def get_sectors(z_id):
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()
    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = [z_id]
            where_extra = ""
            if search:
                where_extra = "AND s.name LIKE %s"
                params.append(f"%{search}%")
            cur.execute(f"SELECT COUNT(*) AS cnt FROM sectors s WHERE s.zone_id=%s {where_extra}",
                        params)
            total = cur.fetchone()["cnt"]
            cur.execute(f"""
                SELECT s.id, s.name, s.hq_address, COUNT(DISTINCT gp.id) AS gp_count
                FROM sectors s LEFT JOIN gram_panchayats gp ON gp.sector_id=s.id
                WHERE s.zone_id=%s {where_extra}
                GROUP BY s.id ORDER BY s.id LIMIT %s OFFSET %s
            """, params + [limit, offset])
            sectors = cur.fetchall()
            if not sectors:
                return _paginated([], total, page, limit)
            s_ids = [s["id"] for s in sectors]
            s_ph = ",".join(["%s"] * len(s_ids))
            cur.execute(f"SELECT * FROM sector_officers WHERE sector_id IN ({s_ph}) "
                        f"ORDER BY sector_id, id", s_ids)
            officers_by_sector = {}
            for row in cur.fetchall():
                officers_by_sector.setdefault(row["sector_id"], []).append(_o(row))
            result = [{
                "id":        s["id"],
                "name":      s["name"] or "",
                "hqAddress": s.get("hq_address", "") or "",
                "gpCount":   s["gp_count"],
                "officers":  officers_by_sector.get(s["id"], []),
            } for s in sectors]
    finally:
        conn.close()
    return _paginated(result, total, page, limit)



@admin_bp.route("/zones/<int:z_id>/sectors", methods=["POST"])
@admin_required
def add_sector(z_id):
    body = request.get_json() or {}
    has_officers = bool(body.get("officers"))
    election_id = None
    if has_officers:
        cfg, gerr = require_active_election(request.user.get("district"))
        if gerr:
            return gerr
        election_id = cfg["id"]
 
    name = body.get("name", "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO sectors (name, hq_address, zone_id) VALUES (%s,%s,%s)",
                        (name, body.get("hqAddress", ""), z_id))
            s_id = cur.lastrowid
            for o in body.get("officers", []):
                _insert_officer(cur, "sector_officers", "sector_id", s_id, o, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"id": s_id, "name": name, "electionId": election_id},
              "Sector added", 201)
 
 
@admin_bp.route("/sectors/<int:s_id>", methods=["PUT"])
@admin_required
def update_sector(s_id):
    body = request.get_json() or {}
    has_officers = bool(body.get("officers"))
    election_id = None
    if has_officers:
        cfg, gerr = require_active_election(request.user.get("district"))
        if gerr:
            return gerr
        election_id = cfg["id"]
 
    name = (body.get("name") or "").strip()
    hq   = (body.get("hqAddress") or "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE sectors SET name=%s, hq_address=%s WHERE id=%s",
                        (name, hq, s_id))
            cur.execute("DELETE FROM sector_officers WHERE sector_id=%s", (s_id,))
            for o in body.get("officers", []):
                _insert_officer(cur, "sector_officers", "sector_id", s_id, o, election_id)
        conn.commit()
    finally:
        conn.close()
    return ok({"electionId": election_id}, "Sector + Officers Updated")
 

@admin_bp.route("/sectors/<int:s_id>", methods=["DELETE"])
@admin_required
def delete_sector(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sectors WHERE id=%s", (s_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")



@admin_bp.route("/sectors/<int:s_id>/officers", methods=["POST"])
@admin_required
def add_sector_officer(s_id):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]
 
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            new_id = _insert_officer(cur, "sector_officers", "sector_id",
                                     s_id, body, election_id)
            cur.execute("SELECT user_id FROM sector_officers WHERE id=%s", (new_id,))
            row = cur.fetchone()
            user_id = row["user_id"] if row else None
        conn.commit()
    finally:
        conn.close()
    write_log("INFO",
              f"Sector officer assigned: sector={s_id} user={user_id} "
              f"(election={election_id}) by admin {_admin_id()}",
              "OfficerDuty")
    return ok({"id": new_id, "userId": user_id, "electionId": election_id},
              "सेक्टर अधिकारी आवंटित", 201)
 
 
@admin_bp.route("/sector-officers/<int:o_id>", methods=["PUT"])
@admin_required
def update_sector_officer(o_id):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    body = request.get_json() or {}
    return _update_officer_record(o_id, "sector_officers", body, cfg["id"])
 

@admin_bp.route("/sector-officers/<int:o_id>", methods=["DELETE"])
@admin_required
def delete_sector_officer(o_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sector_officers WHERE id=%s", (o_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


def _update_officer_record(o_id, table, body, election_id=None):
    """Shared helper for officer updates. Stamps election_id on the update too."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT user_id FROM {table} WHERE id=%s", (o_id,))
            existing = cur.fetchone()
            uid    = body.get("userId") or (existing["user_id"] if existing else None)
            name   = body.get("name",   "")
            pno    = body.get("pno",    "")
            mobile = body.get("mobile", "")
            rank   = body.get("rank",   "")
 
            if not uid and pno:
                cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
                u = cur.fetchone()
                if u:
                    uid = u["id"]
                else:
                    cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
                    username = pno if not cur.fetchone() else f"{pno}_off"
                    cur.execute("""
                        INSERT INTO users (name, pno, username, password, mobile,
                                           user_rank, role, is_active, created_by)
                        VALUES (%s,%s,%s,%s,%s,%s,'staff',1,%s)
                    """, (name, pno, username, _fast_hash(pno),
                          mobile, rank, request.user["id"]))
                    uid = cur.lastrowid
 
            if uid:
                cur.execute("""
                    UPDATE users SET name=%s, mobile=%s, user_rank=%s
                    WHERE id=%s AND role='staff'
                """, (name, mobile, rank, uid))
 
            # 🔐 Stamp election_id + assigned_by on update
            cur.execute(f"""
                UPDATE {table}
                SET name=%s, pno=%s, mobile=%s, user_rank=%s, user_id=%s,
                    election_id=%s, assigned_by=%s
                WHERE id=%s
            """, (name, pno, mobile, rank, uid, election_id, request.user["id"], o_id))
        conn.commit()
    finally:
        conn.close()
    return ok({"electionId": election_id}, "Updated")
 

def _insert_officer(cur, table, fk_col, fk_val, o, election_id=None):
    """Insert one officer row. Stamps election_id + assigned_by automatically.
    
    Callers MUST pass election_id (obtained from require_active_election).
    The before_request guard already ensures only guarded routes call this,
    but pass it explicitly for clarity and so we never write NULL.
    """
    uid    = o.get("userId") or o.get("user_id") or None
    name   = (o.get("name")   or "").strip()
    pno    = (o.get("pno")    or "").strip()
    mobile = (o.get("mobile") or "").strip()
    rank   = (o.get("rank")   or "").strip()
 
    if uid:
        cur.execute("SELECT name, pno, mobile, user_rank FROM users WHERE id=%s", (uid,))
        u = cur.fetchone()
        if u:
            if not name:   name   = u["name"] or ""
            if not pno:    pno    = u["pno"] or ""
            if not mobile: mobile = u["mobile"] or ""
            if not rank:   rank   = u["user_rank"] or ""
    elif pno:
        cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
        existing = cur.fetchone()
        if existing:
            uid = existing["id"]
        else:
            cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
            username = pno if not cur.fetchone() else f"{pno}_off"
            cur.execute("""
                INSERT INTO users (name, pno, username, password, mobile, user_rank,
                                   is_armed, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,0,'staff',1,%s)
            """, (name, pno, username, _fast_hash(pno), mobile, rank, request.user["id"]))
            uid = cur.lastrowid
 
    # 🔐 Stamp election_id + assigned_by
    cur.execute(
        f"INSERT INTO {table} "
        f"({fk_col}, user_id, name, pno, mobile, user_rank, election_id, assigned_by) "
        f"VALUES (%s,%s,%s,%s,%s,%s,%s,%s)",
        (fk_val, uid or None, name, pno, mobile, rank, election_id, request.user["id"])
    )
    return cur.lastrowid
 

# ═════════════════════════════════════════════════════════════════════════════
#  GRAM PANCHAYATS
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/sectors/<int:s_id>/gram-panchayats", methods=["GET"])
@admin_required
def get_gram_panchayats(s_id):
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()
    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = [s_id]
            where_extra = ""
            if search:
                where_extra = "AND gp.name LIKE %s"
                params.append(f"%{search}%")
            cur.execute(f"SELECT COUNT(*) AS cnt FROM gram_panchayats gp "
                        f"WHERE gp.sector_id=%s {where_extra}", params)
            total = cur.fetchone()["cnt"]
            cur.execute(f"""
                SELECT gp.*, COUNT(ms.id) AS center_count
                FROM gram_panchayats gp
                LEFT JOIN matdan_sthal ms ON ms.gram_panchayat_id=gp.id
                WHERE gp.sector_id=%s {where_extra}
                GROUP BY gp.id ORDER BY gp.id LIMIT %s OFFSET %s
            """, params + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()
    data = [{
        "id":          r["id"],
        "name":        r["name"]    or "",
        "address":     r["address"] or "",
        "centerCount": r["center_count"],
    } for r in rows]
    return _paginated(data, total, page, limit)


@admin_bp.route("/sectors/<int:s_id>/gram-panchayats", methods=["POST"])
@admin_required
def add_gram_panchayat(s_id):
    body = request.get_json() or {}
    name = body.get("name", "").strip()
    if not name:
        return err("name required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO gram_panchayats (name,address,sector_id) VALUES (%s,%s,%s)",
                        (name, body.get("address", ""), s_id))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "name": name}, "GP added", 201)


@admin_bp.route("/gram-panchayats/<int:gp_id>", methods=["PUT"])
@admin_required
def update_gram_panchayat(gp_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE gram_panchayats SET name=%s,address=%s WHERE id=%s",
                        (body.get("name", ""), body.get("address", ""), gp_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Updated")


@admin_bp.route("/gram-panchayats/<int:gp_id>", methods=["DELETE"])
@admin_required
def delete_gram_panchayat(gp_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM gram_panchayats WHERE id=%s", (gp_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ═════════════════════════════════════════════════════════════════════════════
#  ELECTION CENTERS
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/gram-panchayats/<int:gp_id>/centers", methods=["POST"])
@admin_required
def create_center(gp_id):
    body = request.get_json() or {}
    name        = body.get("name")
    address     = body.get("address")
    thana       = body.get("thana")
    bus_no      = body.get("busNo")
    center_type = body.get("centerType")
    booth_count = body.get("boothCount")
    lat         = body.get("latitude")
    lng         = body.get("longitude")

    if not name or not center_type:
        return err("name and centerType required")
    try:
        booth_count = int(booth_count or 1)
    except Exception:
        booth_count = 1

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO matdan_sthal
                (gram_panchayat_id, name, address, thana, bus_no,
                 center_type, booth_count, latitude, longitude)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)
            """, (gp_id, name, address, thana, bus_no, center_type, booth_count, lat, lng))
            center_id = cur.lastrowid
            cur.execute("DELETE FROM matdan_kendra WHERE matdan_sthal_id=%s", (center_id,))
            for i in range(1, booth_count + 1):
                cur.execute(
                    "INSERT INTO matdan_kendra (matdan_sthal_id, room_number) VALUES (%s, %s)",
                    (center_id, str(i))
                )
        conn.commit()
    except Exception as e:
        conn.rollback()
        return err(f"Create failed: {e}", 500)
    finally:
        conn.close()
    return ok({"centerId": center_id, "boothCount": booth_count}, "Center created with rooms")


@admin_bp.route("/gram-panchayats/<int:gp_id>/centers", methods=["GET"])
@admin_required
def get_centers(gp_id):
    page, limit, offset = _page_params()
    search = request.args.get("q", "").strip()

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    _RANK_COLS = [
        ("SI",             1, "si_armed_count"),
        ("SI",             0, "si_unarmed_count"),
        ("Head Constable", 1, "hc_armed_count"),
        ("Head Constable", 0, "hc_unarmed_count"),
        ("Constable",      1, "const_armed_count"),
        ("Constable",      0, "const_unarmed_count"),
        ("Constable",      1, "aux_armed_count"),
        ("Constable",      0, "aux_unarmed_count"),
    ]

    total           = 0
    centers_raw     = []
    staff_by_center = {}
    rules_map       = {}

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = [gp_id]
            where_extra = ""
            if search:
                where_extra = "AND ms.name LIKE %s"
                params.append(f"%{search}%")

            cur.execute(
                f"SELECT COUNT(*) AS cnt FROM matdan_sthal ms "
                f"WHERE ms.gram_panchayat_id=%s {where_extra}",
                params
            )
            total = int(cur.fetchone()["cnt"] or 0)

            if total == 0:
                return _paginated([], 0, page, limit)

            cur.execute(f"""
                SELECT
                    ms.id,
                    ms.name,
                    ms.address,
                    ms.thana,
                    ms.center_type,
                    ms.booth_count,
                    ms.bus_no,
                    ms.latitude,
                    ms.longitude,
                    (SELECT COUNT(*) FROM duty_assignments da
                     WHERE da.sthal_id = ms.id) AS duty_count,
                    (SELECT COUNT(*) FROM matdan_kendra mk
                     WHERE mk.matdan_sthal_id = ms.id) AS room_count
                FROM matdan_sthal ms
                WHERE ms.gram_panchayat_id=%s {where_extra}
                ORDER BY ms.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            centers_raw = [dict(r) for r in cur.fetchall()]

            if not centers_raw:
                return _paginated([], total, page, limit)

            center_ids = [c["id"] for c in centers_raw]
            c_ph = ",".join(["%s"] * len(center_ids))

            # ── Assigned staff — avoid reserved word 'rank' as alias ──────────
            cur.execute(f"""
                SELECT
                    da.sthal_id,
                    da.id        AS duty_id,
                    u.id         AS staff_id,
                    u.name,
                    u.pno,
                    u.mobile,
                    u.user_rank,
                    u.is_armed
                FROM duty_assignments da
                JOIN users u ON u.id = da.staff_id
                WHERE da.sthal_id IN ({c_ph})
                ORDER BY da.sthal_id, u.user_rank, u.name
            """, center_ids)
            for row in cur.fetchall():
                sid = row["sthal_id"]
                staff_by_center.setdefault(sid, []).append({
                    "dutyId":  row["duty_id"],
                    "id":      row["staff_id"],
                    "name":    row["name"]      or "",
                    "pno":     row["pno"]       or "",
                    "mobile":  row["mobile"]    or "",
                    "rank":    row["user_rank"] or "",
                    "isArmed": bool(row["is_armed"]),
                })

            # ── Booth rules ───────────────────────────────────────────────────
            try:
                cur.execute(f"""
                    SELECT
                        sensitivity,
                        booth_count,
                        si_armed_count,
                        si_unarmed_count,
                        hc_armed_count,
                        hc_unarmed_count,
                        const_armed_count,
                        const_unarmed_count,
                        aux_armed_count,
                        aux_unarmed_count
                    FROM booth_rules
                    WHERE admin_id IN ({d_ph})
                """, d_params)
                for r in cur.fetchall():
                    key = (r["sensitivity"], int(r["booth_count"] or 1))
                    rules_map[key] = {
                        "si_armed_count":      int(r["si_armed_count"]      or 0),
                        "si_unarmed_count":    int(r["si_unarmed_count"]    or 0),
                        "hc_armed_count":      int(r["hc_armed_count"]      or 0),
                        "hc_unarmed_count":    int(r["hc_unarmed_count"]    or 0),
                        "const_armed_count":   int(r["const_armed_count"]   or 0),
                        "const_unarmed_count": int(r["const_unarmed_count"] or 0),
                        "aux_armed_count":     int(r["aux_armed_count"]     or 0),
                        "aux_unarmed_count":   int(r["aux_unarmed_count"]   or 0),
                    }
            except Exception as rule_err:
                write_log("WARN",
                    f"get_centers booth_rules fetch failed gp={gp_id}: {rule_err}",
                    "Centers")

    except Exception as e:
        write_log("ERROR", f"get_centers DB error gp={gp_id}: {e}", "Centers")
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()

    # ── Build response ────────────────────────────────────────────────────────
    data = []
    for c in centers_raw:
        try:
            center_id   = c["id"]
            center_type = c["center_type"] or "C"
            raw_bc      = int(c["booth_count"] or 1)
            lookup_bc   = max(1, min(raw_bc, 15))
            assigned    = staff_by_center.get(center_id, [])

            # Count assigned per (rank, armed_int)
            assigned_rank_count: dict = {}
            for s in assigned:
                armed_int = 1 if s["isArmed"] else 0
                key = (s["rank"], armed_int)
                assigned_rank_count[key] = assigned_rank_count.get(key, 0) + 1

            # Find rule — exact match, then fall back to lower booth_count
            rule = rules_map.get((center_type, lookup_bc))
            if not rule:
                for bc in range(lookup_bc - 1, 0, -1):
                    rule = rules_map.get((center_type, bc))
                    if rule:
                        break

            # Build missing ranks list
            missing = []
            if rule:
                for rank, armed_int, col in _RANK_COLS:
                    required = rule.get(col, 0)
                    if required <= 0:
                        continue
                    have = assigned_rank_count.get((rank, armed_int), 0)
                    if have < required:
                        missing.append({
                            "rank":                rank,
                            "armed":               bool(armed_int),
                            "required":            required,
                            "assigned":            have,
                            "missing":             required - have,
                            "lowerRankSuggestion": _get_lower_rank(rank),
                        })

            data.append({
                "id":            center_id,
                "name":          c["name"]    or "",
                "address":       c["address"] or "",
                "thana":         c["thana"]   or "",
                "centerType":    center_type,
                "boothCount":    raw_bc,
                "busNo":         c["bus_no"]  or "",
                "latitude":      float(c["latitude"])  if c.get("latitude")  else None,
                "longitude":     float(c["longitude"]) if c.get("longitude") else None,
                "dutyCount":     int(c["duty_count"]  or 0),
                "roomCount":     int(c["room_count"]  or 0),
                "assignedStaff": assigned,
                "missingRanks":  missing,
            })
        except Exception as row_err:
            write_log("ERROR",
                f"get_centers row error center_id={c.get('id','?')}: {row_err}",
                "Centers")
            continue

    return _paginated(data, total, page, limit)


@admin_bp.route("/gram-panchayats/<int:gp_id>/centers/debug", methods=["GET"])
@admin_required
def get_centers_debug(gp_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS cnt FROM matdan_sthal WHERE gram_panchayat_id=%s", (gp_id,))
            cnt = cur.fetchone()["cnt"]
            cur.execute("SELECT id, name, center_type, booth_count FROM matdan_sthal WHERE gram_panchayat_id=%s LIMIT 3", (gp_id,))
            samples = [dict(r) for r in cur.fetchall()]
    except Exception as e:
        return err(f"Debug error: {e}", 500)
    finally:
        conn.close()
    return ok({"count": cnt, "samples": samples, "gp_id": gp_id})


@admin_bp.route("/centers/<int:c_id>", methods=["DELETE"])
@admin_required
def delete_center(c_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM matdan_sthal WHERE id=%s", (c_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


@admin_bp.route("/centers/<int:c_id>/clear-assignments", methods=["POST"])
@admin_required
def clear_center_assignments(c_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM duty_assignments WHERE sthal_id=%s", (c_id,))
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Cleared {removed} assignments from center {c_id}", "AutoAssign")
    return ok({"removed": removed}, "Assignments cleared")


# ═════════════════════════════════════════════════════════════════════════════
#  ROOMS
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/centers/<int:c_id>/rooms", methods=["GET"])
@admin_required
def get_rooms(c_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id, room_number FROM matdan_kendra "
                        "WHERE matdan_sthal_id=%s ORDER BY id", (c_id,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{"id": r["id"], "roomNumber": r["room_number"] or ""} for r in rows])


@admin_bp.route("/centers/<int:c_id>/rooms", methods=["POST"])
@admin_required
def add_room(c_id):
    body = request.get_json() or {}
    rn = body.get("roomNumber", "").strip()
    if not rn:
        return err("roomNumber required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO matdan_kendra (room_number,matdan_sthal_id) VALUES (%s,%s)",
                        (rn, c_id))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    return ok({"id": new_id, "roomNumber": rn}, "Room added", 201)


@admin_bp.route("/rooms/<int:r_id>", methods=["DELETE"])
@admin_required
def delete_room(r_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM matdan_kendra WHERE id=%s", (r_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


# ═════════════════════════════════════════════════════════════════════════════
#  ALL CENTERS (map / overview view)
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/centers/all", methods=["GET"])
@admin_required
def all_centers():
    search = request.args.get("q", "").strip()
    page, limit, offset = _page_params()

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            count_params = list(d_params)
            where_extra  = ""
            if search:
                where_extra = "AND (ms.name LIKE %s OR ms.thana LIKE %s OR gp.name LIKE %s)"
                like = f"%{search}%"
                count_params.extend([like, like, like])

            cur.execute(f"""
                SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({d_ph}) {where_extra}
            """, count_params)
            total = cur.fetchone()["cnt"]

            data_params = list(d_params)
            if search:
                data_params.extend([like, like, like])

            cur.execute(f"""
                SELECT ms.id, ms.name, ms.address, ms.thana, ms.center_type,
                       ms.booth_count, ms.bus_no, ms.latitude, ms.longitude,
                       gp.name   AS gp_name,
                       s.name    AS sector_name,
                       z.name    AS zone_name,
                       sz.name   AS super_zone_name,
                       sz.block  AS block_name,
                       COALESCE(l.is_locked, 0) AS is_locked,
                       COUNT(da.id) AS duty_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                LEFT JOIN sz_duty_locks l    ON l.super_zone_id = z.super_zone_id
                LEFT JOIN duty_assignments da ON da.sthal_id   = ms.id
                WHERE sz.admin_id IN ({d_ph}) {where_extra}
                GROUP BY ms.id
                ORDER BY ms.name
                LIMIT %s OFFSET %s
            """, data_params + [limit, offset])
            rows = cur.fetchall()

            if not rows:
                return _paginated([], total, page, limit)

            type_booth_pairs = list({
                (r["center_type"], min(int(r["booth_count"] or 1), 15))
                for r in rows
            })
            rule_map = {}
            if type_booth_pairs:
                pair_conditions = " OR ".join(
                    ["(br.sensitivity=%s AND br.booth_count=%s)"] * len(type_booth_pairs)
                )
                pair_params = []
                for sens, bc in type_booth_pairs:
                    pair_params.extend([sens, bc])
                cur.execute(f"""
                    SELECT br.sensitivity, br.booth_count,
                           br.si_armed_count, br.si_unarmed_count,
                           br.hc_armed_count, br.hc_unarmed_count,
                           br.const_armed_count, br.const_unarmed_count,
                           br.aux_armed_count, br.aux_unarmed_count,
                           br.pac_count
                    FROM booth_rules br
                    WHERE br.admin_id IN ({d_ph}) AND ({pair_conditions})
                    ORDER BY br.booth_count
                """, d_params + pair_params)
                for br in cur.fetchall():
                    key = (br["sensitivity"], br["booth_count"])
                    rule_map[key] = {
                        "siArmedCount":      br["si_armed_count"],
                        "siUnarmedCount":    br["si_unarmed_count"],
                        "hcArmedCount":      br["hc_armed_count"],
                        "hcUnarmedCount":    br["hc_unarmed_count"],
                        "constArmedCount":   br["const_armed_count"],
                        "constUnarmedCount": br["const_unarmed_count"],
                        "auxArmedCount":     br["aux_armed_count"],
                        "auxUnarmedCount":   br["aux_unarmed_count"],
                        "pacCount":          float(br["pac_count"] or 0),
                    }
    finally:
        conn.close()

    data = []
    for r in rows:
        bc         = min(int(r["booth_count"] or 1), 15)
        ctype      = r["center_type"] or "C"
        booth_rule = rule_map.get((ctype, bc))
        data.append({
            "id":            r["id"],
            "name":          r["name"]          or "",
            "address":       r["address"]        or "",
            "thana":         r["thana"]          or "",
            "centerType":    ctype,
            "boothCount":    int(r["booth_count"] or 1),
            "busNo":         r["bus_no"]          or "",
            "latitude":      float(r["latitude"])  if r["latitude"]  else None,
            "longitude":     float(r["longitude"]) if r["longitude"] else None,
            "gpName":        r["gp_name"]        or "",
            "sectorName":    r["sector_name"]    or "",
            "zoneName":      r["zone_name"]       or "",
            "superZoneName": r["super_zone_name"] or "",
            "blockName":     r["block_name"]      or "",
            "dutyCount":     int(r["duty_count"] or 0),
            "isLocked":      bool(r["is_locked"]),
            "boothRule":     booth_rule,
        })
    return _paginated(data, total, page, limit)


# ═════════════════════════════════════════════════════════════════════════════
#  STAFF CRUD
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff", methods=["GET"])
@admin_required
def get_staff():
    search      = request.args.get("q", "").strip()
    assigned    = request.args.get("assigned", "").strip().lower()
    rank_filter = request.args.get("rank", "").strip()
    armed       = request.args.get("armed", "").strip().lower()
    page, limit, offset = _page_params()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = []
            where_parts = ["u.role='staff'"]
            if search:
                where_parts.append(
                    "(u.name LIKE %s OR u.pno LIKE %s OR u.mobile LIKE %s "
                    "OR u.thana LIKE %s OR u.district LIKE %s)"
                )
                like = f"%{search}%"
                params.extend([like, like, like, like, like])
            if rank_filter:
                where_parts.append("u.user_rank = %s")
                params.append(rank_filter)
            OFFICER_EXISTS = """(
                EXISTS (SELECT 1 FROM duty_assignments da WHERE da.staff_id=u.id)
                OR EXISTS (SELECT 1 FROM kshetra_officers ko WHERE ko.user_id=u.id)
                OR EXISTS (SELECT 1 FROM zonal_officers zo WHERE zo.user_id=u.id)
                OR EXISTS (SELECT 1 FROM sector_officers so WHERE so.user_id=u.id)
                OR EXISTS (SELECT 1 FROM district_duty_assignments dda WHERE dda.staff_id=u.id)
            )"""
            if assigned == "yes":
                where_parts.append(OFFICER_EXISTS)
            elif assigned == "no":
                where_parts.append(f"NOT {OFFICER_EXISTS}")
            if armed == "yes":
                where_parts.append("u.is_armed = 1")
            elif armed == "no":
                where_parts.append("u.is_armed = 0")
            where_sql = " AND ".join(where_parts)

            cur.execute(f"SELECT COUNT(*) AS cnt FROM users u WHERE {where_sql}", params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT u.id, u.name, u.pno, u.mobile, u.thana, u.district, u.user_rank, u.is_armed,
                    (SELECT ms.name FROM duty_assignments da
                     JOIN matdan_sthal ms ON ms.id=da.sthal_id
                     WHERE da.staff_id=u.id LIMIT 1) AS center_name,
                    (SELECT sz.name FROM kshetra_officers ko
                     JOIN super_zones sz ON sz.id=ko.super_zone_id
                     WHERE ko.user_id=u.id LIMIT 1) AS sz_name,
                    (SELECT z.name FROM zonal_officers zo
                     JOIN zones z ON z.id=zo.zone_id
                     WHERE zo.user_id=u.id LIMIT 1) AS zone_name,
                    (SELECT s.name FROM sector_officers so
                     JOIN sectors s ON s.id=so.sector_id
                     WHERE so.user_id=u.id LIMIT 1) AS sector_name,
                    (SELECT dda.duty_type FROM district_duty_assignments dda
                     WHERE dda.staff_id=u.id LIMIT 1) AS district_duty
                FROM users u
                WHERE {where_sql}
                ORDER BY u.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()

    data = []
    for r in rows:
        if r["district_duty"]:
            assign_type = "district"; assign_label = r["district_duty"]
        elif r["center_name"]:
            assign_type = "booth";    assign_label = r["center_name"]
        elif r["sz_name"]:
            assign_type = "kshetra";  assign_label = r["sz_name"]
        elif r["zone_name"]:
            assign_type = "zone";     assign_label = r["zone_name"]
        elif r["sector_name"]:
            assign_type = "sector";   assign_label = r["sector_name"]
        else:
            assign_type = "";         assign_label = ""

        data.append({
            "id": r["id"], "name": r["name"] or "", "pno": r["pno"] or "",
            "mobile": r["mobile"] or "", "thana": r["thana"] or "",
            "district": r["district"] or "", "rank": r["user_rank"] or "",
            "isArmed": bool(r["is_armed"]),
            "isAssigned": bool(assign_type),
            "assignType": assign_type, "assignLabel": assign_label,
        })
    return _paginated(data, total, page, limit)


@admin_bp.route("/staff/search", methods=["GET"])
@admin_required
def search_staff():
    q     = request.args.get("q",     "").strip()
    armed = request.args.get("armed", "").strip().lower()
    if not q:
        return ok([])
    like = f"%{q}%"
    armed_clause = ""
    if armed == "yes":  armed_clause = " AND is_armed = 1"
    elif armed == "no": armed_clause = " AND is_armed = 0"
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, pno, mobile, thana, user_rank, district, is_armed "
                f"FROM users WHERE role='staff' {armed_clause} "
                "AND (name LIKE %s OR pno LIKE %s OR mobile LIKE %s OR district LIKE %s) "
                "ORDER BY name LIMIT 20",
                [like, like, like, like]
            )
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id": r["id"], "name": r["name"] or "", "pno": r["pno"] or "",
        "mobile": r["mobile"] or "", "thana": r["thana"] or "",
        "district": r["district"] or "", "rank": r["user_rank"] or "",
        "isArmed": bool(r["is_armed"]),
    } for r in rows])


@admin_bp.route("/staff", methods=["POST"])
@admin_required
def add_staff():
    body = request.get_json() or {}
    name = (body.get("name") or "").strip()
    pno  = (body.get("pno")  or "").strip()
    if not name or not pno:
        return err("name and pno required")
    is_armed = 1 if (
        body.get("isArmed") in [True, 1, "1", "true"] or
        body.get("is_armed") in [True, 1, "1", "true"] or
        str(body.get("weapon", "")).lower() in ["sastra", "armed", "yes"]
    ) else 0
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
            if cur.fetchone():
                return err(f"PNO {pno} already registered", 409)
            cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
            username = pno if not cur.fetchone() else f"{pno}_{_admin_id()}"
            district = request.user.get("district") or ""
            cur.execute("""
                INSERT INTO users
                    (name, pno, username, password, mobile, thana,
                     district, user_rank, is_armed, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
            """, (name, pno, username, _fast_hash(pno),
                  (body.get("mobile") or "").strip(),
                  (body.get("thana")  or "").strip(),
                  district, (body.get("rank") or "").strip(),
                  is_armed, _admin_id()))
            new_id = cur.lastrowid
        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except: pass
        write_log("ERROR", f"add_staff error: {e}", "Staff")
        return err("Failed to add staff", 500)
    finally:
        conn.close()
    write_log("INFO", f"Staff '{name}' PNO:{pno} added (armed={is_armed}) by admin {_admin_id()}", "Staff")
    return ok({"id": new_id, "name": name, "pno": pno, "isArmed": bool(is_armed)}, "Staff added", 201)


@admin_bp.route("/staff/<int:staff_id>", methods=["PUT"])
@admin_required
def update_staff(staff_id):
    body     = request.get_json() or {}
    is_armed = 1 if body.get("isArmed") else 0
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE users
                SET name=%s, pno=%s, mobile=%s, thana=%s, user_rank=%s, is_armed=%s
                WHERE id=%s AND role='staff'
            """, (body.get("name",""), body.get("pno",""), body.get("mobile",""),
                  body.get("thana",""), body.get("rank",""), is_armed, staff_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Staff updated")


@admin_bp.route("/staff/<int:staff_id>", methods=["DELETE"])
@admin_required
def delete_staff(staff_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "DELETE FROM users WHERE id=%s AND role='staff'",
                [staff_id]
            )
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Staff deleted")


@admin_bp.route("/staff/bulk-delete", methods=["POST"])
@admin_required
def bulk_delete_staff():
    body = request.get_json() or {}
    ids  = body.get("staffIds", [])
    if not ids:
        return err("staffIds required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            ph = ",".join(["%s"] * len(ids))
            cur.execute(f"DELETE FROM users WHERE id IN ({ph}) AND role='staff'", ids)
            deleted = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Bulk delete: {deleted} staff by admin {_admin_id()}", "Staff")
    return ok({"deleted": deleted}, f"{deleted} staff deleted")


# ═════════════════════════════════════════════════════════════════════════════
#  STAFF BULK UPLOAD (SSE streaming)
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff/bulk", methods=["POST"])
@admin_required
def add_staff_bulk():
    body  = request.get_json(force=True, silent=True) or {}
    items = body.get("staff", [])
    if not items:
        return err("staff list empty")
    if len(items) > MAX_BATCH_ROWS:
        return err(f"Too many rows. Max {MAX_BATCH_ROWS} per upload.")
    district    = (request.user.get("district") or "").strip()
    admin_id    = request.user["id"]
    total_input = len(items)

    def generate():
        yield _sse({"phase": "parse", "pct": 2, "msg": "Validating rows..."})
        clean, skipped, seen_pnos = [], [], set()
        for i, s in enumerate(items):
            pno  = str(s.get("pno",  "") or "").strip()
            name = str(s.get("name", "") or "").strip()
            if not pno or not name:
                skipped.append(pno or f"row_{i+1}"); continue
            if pno in seen_pnos:
                skipped.append(pno); continue
            seen_pnos.add(pno)
            is_armed_val = str(s.get("sastra", s.get("armed", s.get("is_armed", ""))) or "").strip().lower()
            is_armed = 1 if is_armed_val in ("1","yes","हाँ","han","sastra","सशस्त्र","armed","true") else 0
            clean.append({
                "pno": pno, "name": name,
                "rank":   str(s.get("rank",     "") or "").strip(),
                "mobile": str(s.get("mobile",   "") or "").strip(),
                "thana":  str(s.get("thana",    "") or "").strip(),
                "dist":   (str(s.get("district","") or "").strip()) or district,
                "is_armed": is_armed,
            })
        yield _sse({"phase": "parse", "pct": 10, "msg": f"{len(clean)} valid, {len(skipped)} skipped"})
        if not clean:
            yield _sse({"phase": "done", "added": 0, "skipped": skipped,
                        "total": total_input, "pct": 100, "msg": "0 जोड़े गए"}); return

        yield _sse({"phase": "parse", "pct": 15, "msg": "Duplicates जांच रहे हैं..."})
        read_conn = get_db()
        try:
            with read_conn.cursor() as cur:
                all_pnos = [r["pno"] for r in clean]
                ph = ",".join(["%s"] * len(all_pnos))
                cur.execute(f"SELECT pno FROM users WHERE pno IN ({ph})", all_pnos)
                existing_pnos = {r["pno"] for r in cur.fetchall()}
                cur.execute(f"SELECT username FROM users WHERE username IN ({ph})", all_pnos)
                existing_usernames = {r["username"] for r in cur.fetchall()}
        finally:
            read_conn.close()
        yield _sse({"phase": "parse", "pct": 22, "msg": f"{len(existing_pnos)} duplicates मिले"})

        pre_insert = []
        for r in clean:
            if r["pno"] in existing_pnos:
                skipped.append(r["pno"]); continue
            uname = r["pno"] if r["pno"] not in existing_usernames else f"{r['pno']}_{admin_id}"
            pre_insert.append({**r, "username": uname})
        if not pre_insert:
            yield _sse({"phase": "done", "added": 0, "skipped": skipped,
                        "total": total_input, "pct": 100,
                        "msg": "0 जोड़े गए (सभी duplicate थे)"}); return
        yield _sse({"phase": "parse", "pct": 25, "msg": f"{len(pre_insert)} rows insert होंगे"})

        total_to_hash = len(pre_insert)
        hashed        = [None] * total_to_hash
        hashed_count  = 0
        workers       = min(HASH_WORKERS, max(1, total_to_hash // 5))
        report_every  = max(1, total_to_hash // 50)
        yield _sse({"phase": "hash", "pct": 25, "msg": f"0/{total_to_hash} passwords hash हो रहे हैं..."})
        with ThreadPoolExecutor(max_workers=workers) as pool:
            future_to_idx = {pool.submit(_fast_hash, r["pno"]): i for i, r in enumerate(pre_insert)}
            for future in as_completed(future_to_idx):
                idx = future_to_idx[future]
                hashed[idx] = future.result()
                hashed_count += 1
                if hashed_count % report_every == 0 or hashed_count == total_to_hash:
                    pct = 25 + int((hashed_count / total_to_hash) * 30)
                    yield _sse({"phase": "hash", "pct": pct, "msg": f"Hashing {hashed_count}/{total_to_hash}..."})
        yield _sse({"phase": "hash", "pct": 55, "msg": "Hash पूर्ण। DB में insert हो रहा है..."})

        insert_conn = get_db()
        added = 0
        total_ins = len(pre_insert)
        try:
            with insert_conn.cursor() as cur:
                cur.execute("SET autocommit=1")
            with insert_conn.cursor() as cur:
                for chunk_start in range(0, total_ins, INSERT_CHUNK_SIZE):
                    chunk_rows   = pre_insert[chunk_start: chunk_start + INSERT_CHUNK_SIZE]
                    chunk_hashes = hashed[chunk_start: chunk_start + INSERT_CHUNK_SIZE]
                    params_list = [
                        (r["name"], r["pno"], r["username"], chunk_hashes[i],
                         r["mobile"], r["thana"], r["dist"], r["rank"],
                         r.get("is_armed", 0), admin_id)
                        for i, r in enumerate(chunk_rows)
                    ]
                    cur.executemany("""
                        INSERT IGNORE INTO users
                            (name, pno, username, password, mobile, thana,
                            district, user_rank, is_armed, role, is_active, created_by)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,'staff',1,%s)
                    """, params_list)
                    added += cur.rowcount
                    pct = 55 + int(((chunk_start + len(chunk_rows)) / total_ins) * 43)
                    yield _sse({"phase": "insert", "pct": min(pct, 98),
                                "added": added, "total": total_ins, "msg": f"Insert: {added}/{total_ins}"})
        except Exception as e:
            yield _sse({"phase": "error", "message": f"Insert error (after {added} rows saved): {str(e)}"}); return
        finally:
            try: insert_conn.close()
            except: pass

        write_log("INFO", f"Bulk: {added} added, {len(skipped)} skipped (admin {admin_id})", "Import")
        yield _sse({"phase": "done", "added": added, "skipped": skipped,
                    "total": total_input, "pct": 100,
                    "msg": f"{added} जोड़े गए, {len(skipped)} छोड़े गए"})

    return Response(
        stream_with_context(generate()),
        mimetype="text/event-stream",
        headers={"Cache-Control": "no-cache, no-store", "X-Accel-Buffering": "no",
                 "X-Content-Type-Options": "nosniff", "Connection": "keep-alive"},
        direct_passthrough=True,
    )


@admin_bp.route("/staff/bulk-csv", methods=["POST"])
@admin_required
def add_staff_bulk_csv():
    file = request.files.get("file")
    if not file:
        return err("CSV file required (field: 'file')")
    try:
        content = file.read().decode("utf-8-sig")
    except UnicodeDecodeError:
        try:
            content = file.read().decode("latin-1")
        except Exception as e:
            return err(f"File encoding error: {e}")
    reader = csv.DictReader(io.StringIO(content))
    items = []
    ARMED_VALS = {'1', 'yes', 'हाँ', 'han', 'sastra', 'सशस्त्र', 'armed', 'true'}
    for row in reader:
        norm = {k.strip().lower(): v for k, v in row.items()}
        pno  = norm.get('pno') or norm.get('p.no') or ''
        name = norm.get('name') or norm.get('नाम') or ''
        if not pno and not name:
            continue
        armed_raw = (norm.get('sastra') or norm.get('armed') or
                     norm.get('weapon') or norm.get('शस्त्र') or '').strip().lower()
        items.append({
            "pno":      pno.strip(), "name": name.strip(),
            "mobile":   (norm.get('mobile') or norm.get('mob') or norm.get('phone') or '').strip(),
            "thana":    (norm.get('thana') or norm.get('थाना') or norm.get('ps') or '').strip(),
            "district": (norm.get('district') or norm.get('dist') or norm.get('जिला') or '').strip(),
            "rank":     (norm.get('rank') or norm.get('post') or norm.get('पद') or '').strip(),
            "is_armed": 1 if armed_raw in ARMED_VALS else 0,
        })
    if not items:
        return err("No valid rows found in CSV")
    request._cached_json = ({"staff": items}, True)
    return add_staff_bulk()


# ═════════════════════════════════════════════════════════════════════════════
#  🔐 BOOTH DUTY ASSIGNMENTS
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/staff/bulk-assign", methods=["POST"])
@admin_required
def bulk_assign_duty():
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    body      = request.get_json() or {}
    ids       = body.get("staffIds", [])
    center_id = body.get("centerId")
    bus_no    = body.get("busNo", "")
    if not ids or not center_id:
        return err("staffIds and centerId required")

    conn = get_db()
    assigned = 0
    try:
        with conn.cursor() as cur:
            for sid in ids:
                cur.execute("""
                    INSERT INTO duty_assignments
                        (staff_id, sthal_id, election_id, bus_no, assigned_by)
                    VALUES (%s,%s,%s,%s,%s)
                    ON DUPLICATE KEY UPDATE
                        sthal_id=VALUES(sthal_id), election_id=VALUES(election_id),
                        bus_no=VALUES(bus_no), assigned_by=VALUES(assigned_by)
                """, (sid, center_id, election_id, bus_no, _admin_id()))
                assigned += 1
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Bulk assign: {assigned} staff → center {center_id} "
              f"(election={election_id}) by admin {_admin_id()}", "Duty")
    return ok({"assigned": assigned, "electionId": election_id}, f"{assigned} staff assigned")


@admin_bp.route("/staff/bulk-unassign", methods=["POST"])
@admin_required
def bulk_unassign_duty():
    body = request.get_json() or {}
    ids  = body.get("staffIds", [])
    if not ids:
        return err("staffIds required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            ph = ",".join(["%s"] * len(ids))
            cur.execute(f"DELETE FROM duty_assignments WHERE staff_id IN ({ph})", ids)
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    return ok({"removed": removed}, f"{removed} duties removed")


@admin_bp.route("/duties", methods=["GET"])
@admin_required
def get_duties():
    page, limit, offset = _page_params()
    center_id = request.args.get("center_id", type=int)
    search    = request.args.get("q", "").strip()

    run_auto_finalize_if_due(request.user.get("district") or "")

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    admin_district = (request.user.get("district") or "").strip()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Active election config
            election_cfg = None
            if admin_district:
                cur.execute("""
                    SELECT id, district, state, election_type, election_name, phase,
                           election_year, election_date, pratah_samay, saya_samay, instructions
                    FROM election_configs
                    WHERE district=%s AND is_active=1 AND is_archived=0
                    ORDER BY updated_at DESC, id DESC LIMIT 1
                """, (admin_district,))
                cfg_row = cur.fetchone()
                if cfg_row:
                    election_cfg = {
                        "id":           cfg_row["id"],
                        "district":     cfg_row["district"]      or "",
                        "state":        cfg_row["state"]         or "",
                        "electionType": cfg_row["election_type"] or "",
                        "electionName": cfg_row["election_name"] or "",
                        "phase":        cfg_row["phase"]         or "",
                        "electionYear": cfg_row["election_year"] or "",
                        "electionDate": str(cfg_row["election_date"]) if cfg_row["election_date"] else "",
                        "pratahSamay":  cfg_row["pratah_samay"]  or "",
                        "sayaSamay":    cfg_row["saya_samay"]    or "",
                        "instructions": cfg_row["instructions"]  or "",
                    }

            params  = list(d_params)
            where   = [f"sz.admin_id IN ({d_ph})"]
            # Only show duties belonging to the current active election
            if election_cfg:
                where.append("da.election_id = %s")
                params.append(election_cfg["id"])
            else:
                # No active election → return empty (duties may have been archived)
                return ok({
                    "data": [], "total": 0, "page": page, "limit": limit,
                    "totalPages": 0,
                    "electionConfig": None,
                    "hasActiveConfig": False,
                })
            if center_id:
                where.append("da.sthal_id = %s"); params.append(center_id)
            if search:
                where.append("(u.name LIKE %s OR u.pno LIKE %s OR ms.name LIKE %s)")
                like = f"%{search}%"; params.extend([like, like, like])
            where_sql = " AND ".join(where)

            cur.execute(f"""
                SELECT COUNT(*) AS cnt
                FROM duty_assignments da
                JOIN users u            ON u.id  = da.staff_id
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE {where_sql}
            """, params)
            total = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT da.id, da.bus_no, da.card_downloaded, da.election_id,
                       u.id AS staff_id, u.name, u.pno, u.mobile, u.thana,
                       u.user_rank, u.district, u.is_armed,
                       ms.id AS center_id, ms.name AS center_name,
                       ms.center_type, ms.booth_count,
                       gp.name AS gp_name,
                       s.id AS sector_id, s.name AS sector_name,
                       z.id AS zone_id, z.name AS zone_name,
                       sz.id AS super_zone_id, sz.name AS super_zone_name, sz.block AS block_name
                FROM duty_assignments da
                JOIN users u            ON u.id  = da.staff_id
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE {where_sql}
                ORDER BY ms.name, u.name
                LIMIT %s OFFSET %s
            """, params + [limit, offset])
            rows = cur.fetchall()

            if not rows:
                return ok({"data": [], "total": total, "page": page, "limit": limit,
                           "totalPages": -(-total // limit) if limit > 0 else 0,
                           "electionConfig": election_cfg})

            sz_ids     = list({r["super_zone_id"] for r in rows})
            z_ids      = list({r["zone_id"]       for r in rows})
            s_ids      = list({r["sector_id"]     for r in rows})
            center_ids = list({r["center_id"]     for r in rows})

            def _fetch_map(sql, id_list):
                if not id_list:
                    return {}
                ph = ",".join(["%s"] * len(id_list))
                cur.execute(sql.format(ph=ph), id_list)
                result = {}
                for row in cur.fetchall():
                    key = list(row.values())[0]
                    result.setdefault(key, []).append(dict(row))
                return result

            super_off_map  = _fetch_map(
                "SELECT super_zone_id AS _fk, name, pno, mobile, user_rank "
                "FROM kshetra_officers WHERE super_zone_id IN ({ph})", sz_ids)
            zonal_off_map  = _fetch_map(
                "SELECT zone_id AS _fk, name, pno, mobile, user_rank "
                "FROM zonal_officers WHERE zone_id IN ({ph})", z_ids)
            sector_off_map = _fetch_map(
                "SELECT sector_id AS _fk, name, pno, mobile, user_rank "
                "FROM sector_officers WHERE sector_id IN ({ph})", s_ids)
            sahyogi_map    = _fetch_map(
                "SELECT da2.sthal_id AS _fk, u2.name, u2.pno, u2.mobile, "
                "u2.thana, u2.user_rank, u2.district, u2.is_armed "
                "FROM duty_assignments da2 JOIN users u2 ON u2.id=da2.staff_id "
                "WHERE da2.sthal_id IN ({ph})", center_ids)

            def _strip(lst):
                return [{k: v for k, v in d.items() if k != "_fk"} for d in lst]

            result = [{
                "id":             r["id"],
                "centerId":       r["center_id"],
                "name":           r["name"]            or "",
                "pno":            r["pno"]             or "",
                "mobile":         r["mobile"]          or "",
                "staffThana":     r["thana"]           or "",
                "rank":           r["user_rank"]       or "",
                "district":       r["district"]        or "",
                "isArmed":        bool(r["is_armed"]),
                "centerName":     r["center_name"]     or "",
                "gpName":         r["gp_name"]         or "",
                "sectorName":     r["sector_name"]     or "",
                "zoneName":       r["zone_name"]        or "",
                "superZoneName":  r["super_zone_name"] or "",
                "blockName":      r["block_name"]      or "",
                "busNo":          r["bus_no"]          or "",
                "electionId":     r["election_id"],
                "cardDownloaded": bool(r.get("card_downloaded", False)),
                "superOfficers":  _strip(super_off_map.get(r["super_zone_id"], [])),
                "zonalOfficers":  _strip(zonal_off_map.get(r["zone_id"],       [])),
                "sectorOfficers": _strip(sector_off_map.get(r["sector_id"],    [])),
                "sahyogi":        _strip(sahyogi_map.get(r["center_id"],       [])),
            } for r in rows]

    finally:
        conn.close()

    return ok({
        "data": result, "total": total, "page": page, "limit": limit,
        "totalPages": -(-total // limit) if limit > 0 else 0,
        "electionConfig": election_cfg,
        "hasActiveConfig": bool(election_cfg),
    })


@admin_bp.route("/duties", methods=["POST"])
@admin_required
def assign_duty():
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    body     = request.get_json() or {}
    staff_id = body.get("staffId") or body.get("staff_id")
    sthal_id = body.get("sthalId") or body.get("sthal_id") or body.get("centerId")
    bus_no   = body.get("busNo", "")

    if not staff_id or not sthal_id:
        return err("staffId and sthalId required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM matdan_sthal WHERE id=%s", (sthal_id,))
            if not cur.fetchone():
                return err(f"Invalid centerId: {sthal_id}")

            # Lock check
            cur.execute("""
                SELECT IFNULL(l.is_locked, 0) AS is_locked
                FROM matdan_sthal c
                LEFT JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
                LEFT JOIN sectors s ON gp.sector_id = s.id
                LEFT JOIN zones z ON s.zone_id = z.id
                LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
                WHERE c.id = %s
            """, (sthal_id,))
            row = cur.fetchone()
            if row and row["is_locked"] == 1:
                return err("This Super Zone is LOCKED. Cannot assign duty.")

            cur.execute("""
                INSERT INTO duty_assignments (staff_id, sthal_id, election_id, bus_no, assigned_by)
                VALUES (%s,%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE
                    sthal_id=VALUES(sthal_id), election_id=VALUES(election_id),
                    bus_no=VALUES(bus_no), assigned_by=VALUES(assigned_by)
            """, (staff_id, sthal_id, election_id, bus_no, _admin_id()))
            new_id = cur.lastrowid
        conn.commit()
    except Exception as e:
        conn.rollback()
        return err(f"Server error: {str(e)}")
    finally:
        conn.close()
    write_log("INFO", f"Duty assigned: staff={staff_id} -> sthal={sthal_id} "
              f"(election={election_id}) by admin {_admin_id()}", "Duty")
    return ok({"id": new_id, "electionId": election_id}, "Duty assigned", 201)


@admin_bp.route("/duties/<int:duty_id>", methods=["DELETE"])
@admin_required
def delete_duty(duty_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT sthal_id FROM duty_assignments WHERE id=%s", (duty_id,))
            row = cur.fetchone()
            if not row:
                return err("Duty not found")
            cur.execute("""
                SELECT IFNULL(l.is_locked, 0) AS is_locked
                FROM matdan_sthal c
                JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
                JOIN sectors s ON gp.sector_id = s.id
                JOIN zones z ON s.zone_id = z.id
                LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
                WHERE c.id = %s
            """, (row["sthal_id"],))
            lock = cur.fetchone()
            if lock and lock["is_locked"] == 1:
                return err("Locked — cannot remove")
            cur.execute("DELETE FROM duty_assignments WHERE id=%s", (duty_id,))
        conn.commit()
        return ok(None, "Deleted successfully")
    except Exception as e:
        conn.rollback()
        return err(str(e))
    finally:
        conn.close()


@admin_bp.route("/staff/<int:staff_id>/duty", methods=["DELETE"])
@admin_required
def delete_staff_duty(staff_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT sthal_id FROM duty_assignments WHERE staff_id=%s LIMIT 1",
                        (staff_id,))
            duty = cur.fetchone()
            if not duty:
                return err("No duty assigned")
            cur.execute("""
                SELECT IFNULL(l.is_locked, 0) AS is_locked
                FROM matdan_sthal c
                JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
                JOIN sectors s ON gp.sector_id = s.id
                JOIN zones z ON s.zone_id = z.id
                LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
                WHERE c.id = %s
            """, (duty["sthal_id"],))
            lock = cur.fetchone()
            if lock and lock["is_locked"] == 1:
                return err("Locked Super Zone. Cannot remove duty.")
            cur.execute("DELETE FROM duty_assignments WHERE staff_id=%s", (staff_id,))
            removed = cur.rowcount
        conn.commit()
    except Exception as e:
        conn.rollback()
        return err(str(e))
    finally:
        conn.close()
    return ok({"removed": removed}, "Duty removed")


@admin_bp.route("/duties/<int:duty_id>/attended", methods=["PATCH"])
@admin_required
def mark_attended(duty_id):
    body = request.get_json() or {}
    attended = 1 if body.get("attended") else 0
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE duty_assignments SET attended=%s WHERE id=%s", (attended, duty_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Marked")


# ═════════════════════════════════════════════════════════════════════════════
#  CENTER STAFF VIEW
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/center/<int:c_id>/staff", methods=["GET"])
@admin_required
def get_center_staff(c_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT da.id AS duty_id, u.id, u.name, u.pno, u.mobile,
                       u.user_rank, u.is_armed, da.bus_no, da.election_id
                FROM duty_assignments da
                JOIN users u ON u.id=da.staff_id
                WHERE da.sthal_id=%s
            """, (c_id,))
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "dutyId": r["duty_id"], "id": r["id"], "name": r["name"] or "",
        "pno": r["pno"] or "", "mobile": r["mobile"] or "",
        "rank": r["user_rank"] or "", "isArmed": bool(r["is_armed"]),
        "busNo": r["bus_no"] or "", "electionId": r["election_id"],
    } for r in rows])


# ═════════════════════════════════════════════════════════════════════════════
#  🔐 BOOTH RULES
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/booth-rules", methods=["GET"])
@admin_required
def get_booth_rules():
    sens = (request.args.get("sensitivity") or "").strip()
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if sens:
                if sens not in VALID_SENS:
                    return err("invalid sensitivity")
                cur.execute(f"""
                    SELECT * FROM booth_rules
                    WHERE admin_id IN ({d_ph}) AND sensitivity=%s
                    ORDER BY booth_count
                """, d_params + [sens])
            else:
                cur.execute(f"""
                    SELECT * FROM booth_rules
                    WHERE admin_id IN ({d_ph})
                    ORDER BY FIELD(sensitivity,'A++','A','B','C'), booth_count
                """, d_params)
            rows = cur.fetchall()
    finally:
        conn.close()

    grouped = {"A++": [], "A": [], "B": [], "C": []}
    for r in rows:
        grouped[r["sensitivity"]].append(_serialize_booth_rule(r))
    return ok(grouped)


@admin_bp.route("/booth-rules", methods=["POST"])
@admin_required
def save_booth_rules():
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    body  = request.get_json() or {}
    sens  = (body.get("sensitivity") or "").strip()
    rules = body.get("rules", [])

    if sens not in VALID_SENS:
        return err("sensitivity must be A++, A, B, or C")
    if not isinstance(rules, list):
        return err("rules must be a list")

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT is_locked FROM sz_duty_locks
                WHERE super_zone_id IN (SELECT id FROM super_zones WHERE admin_id=%s) LIMIT 1
            """, (_admin_id(),))
            lock = cur.fetchone()
            if lock and lock["is_locked"]:
                return err("Rules locked. Cannot modify.")

            cur.execute(f"DELETE FROM booth_rules WHERE admin_id IN ({d_ph}) AND sensitivity=%s",
                        d_params + [sens])

            for raw in rules:
                r  = normalize_rule(raw)
                bc = int(r.get("booth_count") or 0)
                if bc < 1 or bc > 15:
                    continue
                total = sum([
                    r["si_armed_count"], r["si_unarmed_count"],
                    r["hc_armed_count"], r["hc_unarmed_count"],
                    r["const_armed_count"], r["const_unarmed_count"],
                    r["aux_armed_count"], r["aux_unarmed_count"],
                ])
                if total == 0:
                    continue
                if total > 50:
                    return err(f"Too many staff in boothCount {bc}")
                cur.execute("""
                    INSERT INTO booth_rules
                    (admin_id, election_id, sensitivity, booth_count,
                     si_armed_count, si_unarmed_count,
                     hc_armed_count, hc_unarmed_count,
                     const_armed_count, const_unarmed_count,
                     aux_armed_count, aux_unarmed_count, pac_count)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """, (_admin_id(), election_id, sens, bc,
                      r["si_armed_count"], r["si_unarmed_count"],
                      r["hc_armed_count"], r["hc_unarmed_count"],
                      r["const_armed_count"], r["const_unarmed_count"],
                      r["aux_armed_count"], r["aux_unarmed_count"],
                      math.ceil(float(r["pac_count"] or 0))))
        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except: pass
        write_log("ERROR", f"save_booth_rules: {e}", "Rules")
        return err(f"Save failed: {e}", 500)
    finally:
        conn.close()
    write_log("INFO", f"Booth rules saved: {sens}, {len(rules)} rows by admin {_admin_id()}", "Rules")
    return ok({"sensitivity": sens, "saved": len(rules), "electionId": election_id}, f"{sens} मानक saved")


@admin_bp.route("/booth-rules/center-counts", methods=["GET"])
@admin_required
def get_center_counts():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ms.id AS center_id, ms.name AS center_name,
                       COUNT(DISTINCT mk.id) AS room_count,
                       COUNT(DISTINCT da.staff_id) AS staff_count
                FROM matdan_sthal ms
                LEFT JOIN matdan_kendra mk ON mk.matdan_sthal_id = ms.id
                LEFT JOIN duty_assignments da ON da.sthal_id = ms.id
                GROUP BY ms.id, ms.name ORDER BY ms.name
            """)
            rows = cur.fetchall()
            return ok([{
                "centerId": r["center_id"], "centerName": r["center_name"],
                "roomCount": r["room_count"] or 0, "staffCount": r["staff_count"] or 0
            } for r in rows])
    except Exception as e:
        return err(str(e), 500)
    finally:
        conn.close()


@admin_bp.route("/booth-rules/center-counts-by-type", methods=["GET"])
@admin_required
def get_center_counts_by_type():
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT ms.center_type,
                       LEAST(ms.booth_count, 15) AS booth_bucket,
                       COUNT(ms.id) AS center_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({d_ph})
                  AND ms.center_type IN ('A++','A','B','C')
                  AND ms.booth_count >= 1
                GROUP BY ms.center_type, booth_bucket
                ORDER BY ms.center_type, booth_bucket
            """, d_params)
            rows = cur.fetchall()
    finally:
        conn.close()

    result = {sens: {str(bc): 0 for bc in range(1, 16)} for sens in ('A++','A','B','C')}
    for row in rows:
        ct     = row['center_type']
        bucket = int(row['booth_bucket'] or 1)
        count  = int(row['center_count'] or 0)
        if ct in result and 1 <= bucket <= 15:
            result[ct][str(bucket)] += count
    return ok(result)


@admin_bp.route("/booth-rules/center-counts-summary", methods=["GET"])
@admin_required
def get_center_counts_summary():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT ms.id AS center_id, ms.name AS center_name,
                       ms.center_type, ms.booth_count,
                       COUNT(DISTINCT mk.id) AS room_count,
                       COUNT(DISTINCT da.staff_id) AS staff_count
                FROM matdan_sthal ms
                LEFT JOIN matdan_kendra mk ON mk.matdan_sthal_id = ms.id
                LEFT JOIN duty_assignments da ON da.sthal_id = ms.id
                GROUP BY ms.id, ms.name, ms.center_type, ms.booth_count
                ORDER BY ms.name
            """)
            rows = cur.fetchall()
            return ok([{
                'centerId':   r['center_id'], 'centerName': r['center_name'],
                'centerType': r['center_type'],
                'boothCount': int(r['booth_count'] or 1),
                'roomCount':  int(r['room_count']  or 0),
                'staffCount': int(r['staff_count'] or 0),
            } for r in rows])
    except Exception as e:
        return err(str(e), 500)
    finally:
        conn.close()


# ═════════════════════════════════════════════════════════════════════════════
#  🔐 DISTRICT RULES
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/district-rules", methods=["GET"])
@admin_required
def get_district_rules():
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT * FROM district_rules
                WHERE admin_id IN ({d_ph})
                ORDER BY sort_order, id
            """, d_params)
            rows = cur.fetchall()
    finally:
        conn.close()

    saved_map = {r["duty_type"]: r for r in rows}
    result = []
    for dt, label, order in DEFAULT_DISTRICT_DUTIES:
        if dt in saved_map:
            result.append(_serialize_district_rule(saved_map[dt]))
        else:
            result.append({
                "dutyType": dt, "dutyLabelHi": label, "sankhya": 0,
                "siArmedCount": 0, "siUnarmedCount": 0,
                "hcArmedCount": 0, "hcUnarmedCount": 0,
                "constArmedCount": 0, "constUnarmedCount": 0,
                "auxArmedCount": 0, "auxUnarmedCount": 0,
                "pacCount": 0.0, "sortOrder": order, "isDefault": True,
            })
    for r in rows:
        if r["duty_type"] not in _DEFAULT_DUTY_KEYS:
            result.append(_serialize_district_rule(r))
    return ok(result)


@admin_bp.route("/district-rules", methods=["POST"])
@admin_required
def save_district_rules():
    # 🔐 election guard
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]
 
    body  = request.get_json() or {}
    rules = body.get("rules", [])
    if not isinstance(rules, list):
        return err("rules must be a list")
 
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM district_rules WHERE admin_id IN ({d_ph})", d_params)
            for r in rules:
                duty_type = (r.get("dutyType") or "").strip()
                if not duty_type:
                    continue
                cur.execute("""
                    INSERT INTO district_rules
                    (admin_id, election_id, duty_type, duty_label_hi, sankhya,
                     si_armed_count, si_unarmed_count,
                     hc_armed_count, hc_unarmed_count,
                     const_armed_count, const_unarmed_count,
                     aux_armed_count, aux_unarmed_count, pac_count, sort_order)
                    VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)
                """, (
                    _admin_id(), election_id, duty_type,
                    (r.get("dutyLabelHi") or "").strip(),
                    int(r.get("sankhya") or 0),
                    int(r.get("siArmedCount")      or 0),
                    int(r.get("siUnarmedCount")    or 0),
                    int(r.get("hcArmedCount")      or 0),
                    int(r.get("hcUnarmedCount")    or 0),
                    int(r.get("constArmedCount")   or 0),
                    int(r.get("constUnarmedCount") or 0),
                    int(r.get("auxArmedCount",     0)),
                    int(r.get("auxUnarmedCount",   0)),
                    float(r.get("pacCount") or 0),
                    int(r.get("sortOrder") or 0),
                ))
        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except: pass
        write_log("ERROR", f"save_district_rules: {e}", "Rules")
        return err(f"Save failed: {e}", 500)
    finally:
        conn.close()
    return ok({"electionId": election_id}, "जनपदीय मानक saved")
 
 


@admin_bp.route("/district-rules/custom", methods=["POST"])
@admin_required
def add_custom_duty_type():
    # 🔐 election guard
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]
 
    body     = request.get_json() or {}
    label_hi = (body.get("labelHi") or "").strip()
    if not label_hi:
        return err("labelHi required")
 
    safe = re.sub(r'[^a-z0-9]', '_', label_hi.lower())[:30]
    duty_type = f"custom_{safe}_{int(time.time()) % 100000}"
 
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
 
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT COALESCE(MAX(sort_order), 140) AS mx "
                        f"FROM district_rules WHERE admin_id IN ({d_ph})", d_params)
            sort_order = (cur.fetchone()["mx"] or 140) + 10
            cur.execute("""
                INSERT INTO district_rules
                (admin_id, election_id, duty_type, duty_label_hi, sankhya,
                 si_armed_count, si_unarmed_count, hc_armed_count, hc_unarmed_count,
                 const_armed_count, const_unarmed_count, aux_armed_count, aux_unarmed_count,
                 pac_count, sort_order)
                VALUES (%s,%s,%s,%s,0,0,0,0,0,0,0,0,0,0,%s)
            """, (_admin_id(), election_id, duty_type, label_hi, sort_order))
        conn.commit()
    finally:
        conn.close()
 
    return ok({
        "dutyType": duty_type, "dutyLabelHi": label_hi, "sortOrder": sort_order,
        "isDefault": False, "sankhya": 0, "electionId": election_id,
        "siArmedCount": 0, "siUnarmedCount": 0, "hcArmedCount": 0, "hcUnarmedCount": 0,
        "constArmedCount": 0, "constUnarmedCount": 0,
        "auxArmedCount": 0, "auxUnarmedCount": 0, "pacCount": 0.0,
    }, "Custom duty type added", 201)
 
 

@admin_bp.route("/district-rules/custom/<duty_type>", methods=["PUT"])
@admin_required
def rename_custom_duty_type(duty_type):
    if duty_type in _DEFAULT_DUTY_KEYS:
        return err("Cannot rename a default duty type", 400)
    body     = request.get_json() or {}
    label_hi = (body.get("labelHi") or "").strip()
    if not label_hi:
        return err("labelHi required")
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"UPDATE district_rules SET duty_label_hi=%s "
                        f"WHERE duty_type=%s AND admin_id IN ({d_ph})",
                        [label_hi, duty_type] + d_params)
            if cur.rowcount == 0:
                return err("Duty type not found", 404)
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Renamed")


@admin_bp.route("/district-rules/custom/<duty_type>", methods=["DELETE"])
@admin_required
def delete_custom_duty_type(duty_type):
    if duty_type in _DEFAULT_DUTY_KEYS:
        return err("Cannot delete a default duty type", 400)
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM district_rules WHERE duty_type=%s AND admin_id IN ({d_ph})",
                        [duty_type] + d_params)
            if cur.rowcount == 0:
                return err("Duty type not found", 404)
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Deleted")


@admin_bp.route("/district-rules/<duty_type>/adjust", methods=["PUT", "PATCH"])
@admin_required
def adjust_district_rule(duty_type):
    body = request.get_json() or {}
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    fields, values = [], []
    for camel, snake in [
        ("siArmedCount",      "si_armed_count"),
        ("siUnarmedCount",    "si_unarmed_count"),
        ("hcArmedCount",      "hc_armed_count"),
        ("hcUnarmedCount",    "hc_unarmed_count"),
        ("constArmedCount",   "const_armed_count"),
        ("constUnarmedCount", "const_unarmed_count"),
        ("auxArmedCount",     "aux_armed_count"),
        ("auxUnarmedCount",   "aux_unarmed_count"),
    ]:
        if camel in body:
            fields.append(f"{snake}=%s")
            values.append(int(body.get(camel) or 0))
    if "sankhya" in body and body["sankhya"] is not None:
        fields.append("sankhya=%s")
        values.append(int(body["sankhya"]))
    if not fields:
        return err("No fields to update")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"UPDATE district_rules SET {', '.join(fields)} "
                        f"WHERE admin_id IN ({d_ph}) AND duty_type=%s",
                        values + d_params + [duty_type])
            if cur.rowcount == 0:
                return err("Duty type not found", 404)
        conn.commit()
    except Exception as e:
        write_log("ERROR", f"adjust rule {duty_type}: {e}", "Rules")
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()
    write_log("INFO", f"Manak adjusted for {duty_type} by admin {_admin_id()}", "Rules")
    return ok(None, "मानक updated")


# ═════════════════════════════════════════════════════════════════════════════
#  🔐 DISTRICT DUTY ASSIGNMENTS
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/district-duty/summary", methods=["GET"])
@admin_required
def get_district_duty_summary():
    district = (request.user.get("district") or "").strip()

    # Run auto-finalize if election date has passed
    run_auto_finalize_if_due(district)

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    # Get active election to filter counts
    cfg_active = get_active_election(district)
    eid_filter = ""
    eid_params = []
    if cfg_active:
        eid_filter = "AND dda.election_id = %s"
        eid_params = [cfg_active["id"]]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT duty_type, duty_label_hi, sankhya, sort_order
                FROM district_rules
                WHERE admin_id IN ({d_ph})
                ORDER BY sort_order
            """, d_params)
            rules = {r["duty_type"]: r for r in cur.fetchall()}

            cur.execute(f"""
                SELECT dda.duty_type,
                       COUNT(DISTINCT dda.staff_id) AS total_assigned,
                       COUNT(DISTINCT dda.batch_no) AS batch_count,
                       MAX(dda.batch_no)            AS max_batch
                FROM district_duty_assignments dda
                WHERE dda.admin_id IN ({d_ph}) {eid_filter}
                GROUP BY dda.duty_type
            """, d_params + eid_params)
            counts = {r["duty_type"]: r for r in cur.fetchall()}

    finally:
        conn.close()

    result = {}
    for dt, rule in rules.items():
        cnt = counts.get(dt, {})
        result[dt] = {
            "dutyType":        dt,
            "dutyLabelHi":     rule["duty_label_hi"] or "",
            "sankhya":         rule["sankhya"]        or 0,
            "totalAssigned":   int(cnt.get("total_assigned") or 0),
            "batchCount":      int(cnt.get("batch_count")    or 0),
            "maxBatch":        int(cnt.get("max_batch")       or 0),
            "hasActiveConfig": bool(cfg_active),
            "electionId":      cfg_active["id"] if cfg_active else None,
        }

    return ok(result)

@admin_bp.route("/district-duty/<duty_type>/batches", methods=["GET"])
@admin_required
def get_duty_batches(duty_type):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT dda.batch_no, COUNT(DISTINCT dda.staff_id) AS staff_count
                FROM district_duty_assignments dda
                WHERE dda.admin_id IN ({d_ph}) AND dda.duty_type=%s
                GROUP BY dda.batch_no ORDER BY dda.batch_no
            """, d_params + [duty_type])
            batches_raw = cur.fetchall()
            if not batches_raw:
                return ok([])
            batch_numbers = [b["batch_no"] for b in batches_raw]
            b_ph = ",".join(["%s"] * len(batch_numbers))
            cur.execute(f"""
                SELECT dda.id AS assignment_id, dda.batch_no, dda.bus_no, dda.note,
                       u.id, u.name, u.pno, u.mobile, u.user_rank,
                       u.thana, u.district, u.is_armed
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                WHERE dda.admin_id IN ({d_ph}) AND dda.duty_type=%s AND dda.batch_no IN ({b_ph})
                ORDER BY dda.batch_no, u.name
            """, d_params + [duty_type] + batch_numbers)
            rows = cur.fetchall()
            staff_by_batch = {}
            for row in rows:
                bn = row["batch_no"]
                staff_by_batch.setdefault(bn, []).append({
                    "assignmentId": row["assignment_id"], "id": row["id"],
                    "name": row["name"] or "", "pno": row["pno"] or "",
                    "mobile": row["mobile"] or "", "rank": row["user_rank"] or "",
                    "thana": row["thana"] or "", "district": row["district"] or "",
                    "isArmed": bool(row["is_armed"]),
                    "busNo": row["bus_no"] or "", "note": row["note"] or "",
                })
    finally:
        conn.close()

    return ok([{
        "batchNo":    b["batch_no"],
        "staffCount": b["staff_count"],
        "staff":      staff_by_batch.get(b["batch_no"], []),
    } for b in batches_raw])


@admin_bp.route("/district-duty/<duty_type>/batch/<int:batch_no>", methods=["GET"])
@admin_required
def get_duty_batch_detail(duty_type, batch_no):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT dda.id AS assignment_id, dda.bus_no, dda.note,
                       u.id, u.name, u.pno, u.mobile,
                       u.user_rank, u.thana, u.district, u.is_armed
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                WHERE dda.admin_id IN ({d_ph}) AND dda.duty_type=%s AND dda.batch_no=%s
                ORDER BY u.name
            """, d_params + [duty_type, batch_no])
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "assignmentId": r["assignment_id"], "id": r["id"],
        "name": r["name"] or "", "pno": r["pno"] or "",
        "mobile": r["mobile"] or "", "rank": r["user_rank"] or "",
        "thana": r["thana"] or "", "district": r["district"] or "",
        "isArmed": bool(r["is_armed"]),
        "busNo": r["bus_no"] or "", "note": r["note"] or "",
    } for r in rows])


@admin_bp.route("/district-duty/<duty_type>/assign", methods=["POST"])
@admin_required
def assign_district_duty(duty_type):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    body      = request.get_json() or {}
    staff_ids = body.get("staffIds", [])
    bus_no    = (body.get("busNo") or "").strip()
    note      = (body.get("note") or "").strip()
    if not staff_ids:
        return err("staffIds required")

    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"""
                SELECT COALESCE(MAX(batch_no), 0) AS mx
                FROM district_duty_assignments
                WHERE admin_id IN ({d_ph}) AND duty_type=%s
            """, d_params + [duty_type])
            batch_no = (cur.fetchone()["mx"] or 0) + 1

            assigned = 0
            skipped  = 0
            already  = []
            for sid in staff_ids:
                try:
                    cur.execute("""
                        INSERT INTO district_duty_assignments
                            (admin_id, duty_type, batch_no, staff_id, election_id, assigned_by, bus_no, note)
                        VALUES (%s,%s,%s,%s,%s,%s,%s,%s)
                    """, (_admin_id(), duty_type, batch_no, sid, election_id,
                          _admin_id(), bus_no, note))
                    assigned += 1
                except Exception:
                    cur.execute("SELECT name FROM users WHERE id=%s", (sid,))
                    u = cur.fetchone()
                    already.append(u["name"] if u else f"id:{sid}")
                    skipped += 1
        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except: pass
        return err(f"Assign failed: {e}", 500)
    finally:
        conn.close()

    write_log("INFO", f"District duty '{duty_type}' batch {batch_no}: {assigned} assigned "
              f"by admin {_admin_id()}", "DistrictDuty")
    return ok({
        "batchNo": batch_no, "assigned": assigned,
        "skipped": skipped, "alreadyAssigned": already,
        "electionId": election_id,
    }, f"Batch {batch_no} created with {assigned} staff", 201)


@admin_bp.route("/district-duty/assignment/<int:assignment_id>", methods=["DELETE"])
@admin_required
def delete_district_assignment(assignment_id):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM district_duty_assignments WHERE id=%s AND admin_id IN ({d_ph})",
                        [assignment_id] + d_params)
            if cur.rowcount == 0:
                return err("Assignment not found or access denied", 404)
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Removed")


@admin_bp.route("/district-duty/<duty_type>/batch/<int:batch_no>", methods=["DELETE"])
@admin_required
def delete_duty_batch(duty_type, batch_no):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM district_duty_assignments "
                        f"WHERE admin_id IN ({d_ph}) AND duty_type=%s AND batch_no=%s",
                        d_params + [duty_type, batch_no])
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    return ok({"removed": removed}, f"Batch {batch_no} deleted")


@admin_bp.route("/district-duty/<duty_type>/batch/<int:batch_no>", methods=["PATCH"])
@admin_required
def update_batch_info(duty_type, batch_no):
    body   = request.get_json() or {}
    bus_no = (body.get("busNo") or "").strip()
    note   = (body.get("note")  or "").strip()
    d_ids  = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"UPDATE district_duty_assignments SET bus_no=%s, note=%s "
                        f"WHERE admin_id IN ({d_ph}) AND duty_type=%s AND batch_no=%s",
                        [bus_no, note] + d_params + [duty_type, batch_no])
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Batch updated")


@admin_bp.route("/district-duty/<duty_type>/clear", methods=["DELETE"])
@admin_required
def clear_duty_type(duty_type):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM district_duty_assignments "
                        f"WHERE admin_id IN ({d_ph}) AND duty_type=%s",
                        d_params + [duty_type])
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    return ok({"removed": removed}, "All assignments cleared")


@admin_bp.route("/district-duty/<duty_type>/available-staff", methods=["GET"])
@admin_required
def get_available_for_duty(duty_type):
    search      = request.args.get("q", "").strip()
    rank_filter = request.args.get("rank", "").strip()
    page, limit, offset = _page_params()
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            params = []
            where_parts = [
                "u.role = 'staff'", "u.is_active = 1",
                f"u.id NOT IN (SELECT staff_id FROM district_duty_assignments "
                f"WHERE admin_id IN ({d_ph}) AND duty_type=%s)",
            ]
            params += d_params + [duty_type]
            if search:
                where_parts.append("(u.name LIKE %s OR u.pno LIKE %s OR u.mobile LIKE %s)")
                like = f"%{search}%"
                params += [like, like, like]
            if rank_filter:
                where_parts.append("u.user_rank = %s")
                params.append(rank_filter)
            where_sql = " AND ".join(where_parts)
            cur.execute(f"SELECT COUNT(*) AS cnt FROM users u WHERE {where_sql}", params)
            total = cur.fetchone()["cnt"]
            cur.execute(f"""
                SELECT u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana, u.district, u.is_armed
                FROM users u WHERE {where_sql} ORDER BY u.name LIMIT %s OFFSET %s
            """, params + [limit, offset])
            rows = cur.fetchall()
    finally:
        conn.close()

    return _paginated([{
        "id": r["id"], "name": r["name"] or "", "pno": r["pno"] or "",
        "mobile": r["mobile"] or "", "rank": r["user_rank"] or "",
        "thana": r["thana"] or "", "district": r["district"] or "",
        "isArmed": bool(r["is_armed"]),
    } for r in rows], total, page, limit)


@admin_bp.route("/district-duty/<duty_type>/availability", methods=["GET"])
@admin_required
def get_duty_availability(duty_type):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT * FROM district_rules "
                        f"WHERE admin_id IN ({d_ph}) AND duty_type=%s", d_params + [duty_type])
            rule = cur.fetchone()
            if not rule:
                return err(f"Duty type '{duty_type}' not found", 404)
            sankhya = int(rule["sankhya"] or 0)

            cur.execute(f"""
                SELECT u.user_rank AS rank_name, u.is_armed AS is_armed_flag, COUNT(*) AS cnt
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                WHERE dda.admin_id IN ({d_ph}) AND dda.duty_type=%s
                GROUP BY u.user_rank, u.is_armed
            """, d_params + [duty_type])
            assigned_map = {(r["rank_name"] or "", int(r["is_armed_flag"] or 0)): int(r["cnt"] or 0)
                            for r in cur.fetchall()}

            cur.execute("""
                SELECT user_rank AS rank_name, is_armed AS is_armed_flag, COUNT(*) AS cnt
                FROM users WHERE role='staff' AND is_active=1
                GROUP BY user_rank, is_armed
            """)
            total_map = {((r["rank_name"] or "").strip(), int(r["is_armed_flag"] or 0)): int(r["cnt"] or 0)
                         for r in cur.fetchall() if (r["rank_name"] or "").strip()}

            cur.execute(f"""
                SELECT u.user_rank AS rank_name, u.is_armed AS is_armed_flag,
                       COUNT(DISTINCT u.id) AS cnt
                FROM district_duty_assignments dda
                JOIN users u ON u.id = dda.staff_id
                WHERE dda.admin_id IN ({d_ph})
                GROUP BY u.user_rank, u.is_armed
            """, d_params)
            locked_map = {((r["rank_name"] or "").strip(), int(r["is_armed_flag"] or 0)): int(r["cnt"] or 0)
                          for r in cur.fetchall()}
    except Exception as e:
        write_log("ERROR", f"availability {duty_type}: {e}\n{traceback.format_exc()}", "DistrictDuty")
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()

    SLOTS = [
        ("SI",             1, "siArmedCount",      "si_armed_count",      "SI",    "सशस्त्र"),
        ("SI",             0, "siUnarmedCount",    "si_unarmed_count",    "SI",    "निःशस्त्र"),
        ("Head Constable", 1, "hcArmedCount",      "hc_armed_count",      "HC",    "सशस्त्र"),
        ("Head Constable", 0, "hcUnarmedCount",    "hc_unarmed_count",    "HC",    "निःशस्त्र"),
        ("Constable",      1, "constArmedCount",   "const_armed_count",   "Const", "सशस्त्र"),
        ("Constable",      0, "constUnarmedCount", "const_unarmed_count", "Const", "निःशस्त्र"),
        ("Constable",      1, "auxArmedCount",     "aux_armed_count",     "Aux",   "सशस्त्र"),
        ("Constable",      0, "auxUnarmedCount",   "aux_unarmed_count",   "Aux",   "निःशस्त्र"),
    ]
    breakdown = []
    for rank, armed, _camel, snake, label_short, label_armed in SLOTS:
        per_batch       = int(rule.get(snake) or 0)
        required        = per_batch * sankhya
        assigned        = assigned_map.get((rank, armed), 0)
        total_in_system = total_map.get((rank, armed), 0)
        locked          = locked_map.get((rank, armed), 0)
        free_in_system  = max(0, total_in_system - locked)
        breakdown.append({
            "rank": rank, "armed": bool(armed), "ruleField": snake,
            "labelShort": label_short, "labelArmed": label_armed,
            "perBatch": per_batch, "required": required, "assigned": assigned,
            "gap": max(0, required - assigned),
            "totalInSystem": total_in_system, "freeInSystem": free_in_system,
        })

    rank_pool = {}
    for (rank, armed), tot in total_map.items():
        locked = locked_map.get((rank, armed), 0)
        rank_pool[f"{rank}|{armed}"] = {
            "rank": rank, "armed": bool(armed), "total": tot, "free": max(0, tot - locked),
        }
    return ok({
        "dutyType":      duty_type,
        "dutyLabelHi":   rule.get("duty_label_hi") or duty_type,
        "sankhya":       sankhya,
        "breakdown":     breakdown,
        "availablePool": list(rank_pool.values()),
    })
SLOTS = [
        ("SI",             1, "siArmedCount",      "si_armed_count",      "SI",    "सशस्त्र"),
        ("SI",             0, "siUnarmedCount",    "si_unarmed_count",    "SI",    "निःशस्त्र"),
        ("Head Constable", 1, "hcArmedCount",      "hc_armed_count",      "HC",    "सशस्त्र"),
        ("Head Constable", 0, "hcUnarmedCount",    "hc_unarmed_count",    "HC",    "निःशस्त्र"),
        ("Constable",      1, "constArmedCount",   "const_armed_count",   "Const", "सशस्त्र"),
        ("Constable",      0, "constUnarmedCount", "const_unarmed_count", "Const", "निःशस्त्र"),
        ("Constable",      1, "auxArmedCount",     "aux_armed_count",     "Aux",   "सशस्त्र"),
        ("Constable",      0, "auxUnarmedCount",   "aux_unarmed_count",   "Aux",   "निःशस्त्र"),
    ]

@admin_bp.route("/district-duty/<duty_type>/auto-assign-override", methods=["POST"])
@admin_required
def auto_assign_with_override(duty_type):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    body       = request.get_json() or {}
    per_batch  = body.get("perBatch") or {}
    sync_manak = body.get("syncManak", True)

    if not isinstance(per_batch, dict) or not per_batch:
        return err("perBatch is required")

    admin_id = request.user["id"]
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT * FROM district_rules "
                        f"WHERE admin_id IN ({d_ph}) AND duty_type=%s", d_params + [duty_type])
            rule = cur.fetchone()
            if not rule:
                return err(f"Duty type '{duty_type}' not found", 404)
            sankhya = int(rule["sankhya"] or 0)
            cur.execute(f"SELECT COALESCE(MAX(batch_no),0) AS mx FROM district_duty_assignments "
                        f"WHERE admin_id IN ({d_ph}) AND duty_type=%s", d_params + [duty_type])
            next_batch = (cur.fetchone()["mx"] or 0) + 1
            cur.execute(f"SELECT DISTINCT staff_id FROM district_duty_assignments "
                        f"WHERE admin_id IN ({d_ph})", d_params)
            used_ids = set(r["staff_id"] for r in cur.fetchall())
            batches_to_make = sankhya - (next_batch - 1)
    except Exception as e:
        write_log("ERROR", f"override init {duty_type}: {e}\n{traceback.format_exc()}", "DistrictDuty")
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()

    if batches_to_make <= 0:
        return ok({"assigned": 0, "batchesMade": 0, "shortages": [], "manakUpdated": False},
                  "Already complete — no batches to add")

    OVERRIDE_MAP = [
        ("siArmedCount",      "SI",             1, "si_armed_count"),
        ("siUnarmedCount",    "SI",             0, "si_unarmed_count"),
        ("hcArmedCount",      "Head Constable", 1, "hc_armed_count"),
        ("hcUnarmedCount",    "Head Constable", 0, "hc_unarmed_count"),
        ("constArmedCount",   "Constable",      1, "const_armed_count"),
        ("constUnarmedCount", "Constable",      0, "const_unarmed_count"),
        ("auxArmedCount",     "Constable",      1, "aux_armed_count"),
        ("auxUnarmedCount",   "Constable",      0, "aux_unarmed_count"),
    ]

    total_per_batch = sum(int(per_batch.get(k, 0) or 0) for k, *_ in OVERRIDE_MAP)
    if total_per_batch == 0:
        return err("perBatch must include at least one rank with count > 0")

    conn = get_db()
    total_assigned = 0
    batches_made   = 0
    shortages      = []
    try:
        for _ in range(batches_to_make):
            batch_local: set = set()
            batch_picks: list = []
            batch_short: list = []
            for camel, rank, armed, _col in OVERRIDE_MAP:
                want = int(per_batch.get(camel, 0) or 0)
                if want <= 0:
                    continue
                excludes = used_ids | batch_local
                picked   = _pick_random_staff(conn, rank, armed, want, excludes)
                if len(picked) < want:
                    batch_short.append({"rank": rank, "armed": bool(armed), "missing": want - len(picked)})
                batch_picks.extend(picked)
                for sid in picked:
                    batch_local.add(sid)
            if batch_short:
                shortages = batch_short
                break
            try:
                with conn.cursor() as cur:
                    cur.executemany("""
                        INSERT INTO district_duty_assignments
                            (admin_id, duty_type, batch_no, staff_id, election_id, assigned_by)
                        VALUES (%s,%s,%s,%s,%s,%s)
                    """, [(admin_id, duty_type, next_batch, sid, election_id, admin_id)
                          for sid in batch_picks])
                conn.commit()
                for sid in batch_picks:
                    used_ids.add(sid)
                total_assigned += len(batch_picks)
                next_batch     += 1
                batches_made   += 1
            except Exception as e:
                conn.rollback()
                shortages = [{"rank": "DB_ERROR", "armed": False,
                              "missing": batches_to_make - batches_made, "error": str(e)}]
                break

        manak_updated = False
        if sync_manak and batches_made > 0:
            try:
                with conn.cursor() as cur:
                    cur.execute(f"""
                        UPDATE district_rules
                        SET si_armed_count=%s, si_unarmed_count=%s,
                            hc_armed_count=%s, hc_unarmed_count=%s,
                            const_armed_count=%s, const_unarmed_count=%s,
                            aux_armed_count=%s, aux_unarmed_count=%s
                        WHERE admin_id IN ({d_ph}) AND duty_type=%s
                    """, [
                        int(per_batch.get("siArmedCount", 0) or 0),
                        int(per_batch.get("siUnarmedCount", 0) or 0),
                        int(per_batch.get("hcArmedCount", 0) or 0),
                        int(per_batch.get("hcUnarmedCount", 0) or 0),
                        int(per_batch.get("constArmedCount", 0) or 0),
                        int(per_batch.get("constUnarmedCount", 0) or 0),
                        int(per_batch.get("auxArmedCount", 0) or 0),
                        int(per_batch.get("auxUnarmedCount", 0) or 0),
                    ] + d_params + [duty_type])
                conn.commit()
                manak_updated = True
            except Exception as e:
                write_log("WARN", f"Manak sync failed for {duty_type}: {e}", "DistrictDuty")
    except Exception as e:
        write_log("ERROR", f"override loop {duty_type}: {e}\n{traceback.format_exc()}", "DistrictDuty")
        return err(f"Server error: {e}", 500)
    finally:
        conn.close()

    write_log("INFO", f"Override auto-assign for {duty_type}: {total_assigned} staff in "
              f"{batches_made} batches (admin {admin_id})", "DistrictDuty")
    return ok({
        "assigned": total_assigned, "batchesMade": batches_made,
        "batchesTarget": batches_to_make, "shortages": shortages,
        "manakUpdated": manak_updated, "electionId": election_id,
    }, f"{batches_made} batches assigned")


@admin_bp.route("/district-duty/refresh/<duty_type>", methods=["POST"])
@admin_required
def refresh_duty_type(duty_type):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Delete only this district's assignments for this duty_type
            cur.execute(f"""
                DELETE FROM district_duty_assignments
                WHERE admin_id IN ({d_ph}) AND duty_type=%s
            """, d_params + [duty_type])
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()

    write_log("INFO",
              f"District duty '{duty_type}' refreshed: {removed} assignments cleared "
              f"by admin {_admin_id()}",
              "DistrictDuty")
    return ok({"removed": removed}, "Cleared")

# ═════════════════════════════════════════════════════════════════════════════
#  🔐 DISTRICT DUTY AUTO-ASSIGN
# ═════════════════════════════════════════════════════════════════════════════

def _pick_random_staff(conn, rank: str, is_armed: int, count: int,
                       exclude_ids: set) -> list:
    if count <= 0:
        return []
    with conn.cursor() as cur:
        if exclude_ids:
            ph = ",".join(["%s"] * len(exclude_ids))
            cur.execute(f"""
                SELECT id FROM users
                WHERE role='staff' AND user_rank=%s AND is_armed=%s AND is_active=1
                  AND id NOT IN ({ph})
                ORDER BY RAND() LIMIT %s
            """, [rank, is_armed] + list(exclude_ids) + [count])
        else:
            cur.execute("""
                SELECT id FROM users
                WHERE role='staff' AND user_rank=%s AND is_armed=%s AND is_active=1
                ORDER BY RAND() LIMIT %s
            """, (rank, is_armed, count))
        return [r["id"] for r in cur.fetchall()]


def _update_progress(conn, job_id, done_types, assigned, skipped):
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE district_duty_jobs
                SET done_types=%s, assigned=%s, skipped=%s, updated_at=NOW()
                WHERE id=%s
            """, (done_types, assigned, skipped, job_id))
        conn.commit()
    except Exception:
        pass


def _run_auto_assign_background(job_id: int, admin_id: int, only_duty_type=None):
    conn = get_db()
    used_staff_ids: set = set()
    shortage_report: dict = {}

    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE district_duty_jobs SET status='running', updated_at=NOW() WHERE id=%s",
                        (job_id,))
        conn.commit()

        with conn.cursor() as cur:
            cur.execute("SELECT district FROM users WHERE id=%s", (admin_id,))
            row = cur.fetchone()
            district = (row["district"] or "").strip() if row else ""

        if district:
            with conn.cursor() as cur:
                cur.execute("SELECT id FROM users WHERE role IN ('admin','super_admin') AND district=%s",
                            (district,))
                d_ids = [r["id"] for r in cur.fetchall()]
                if admin_id not in d_ids:
                    d_ids.append(admin_id)
        else:
            d_ids = [admin_id]

        d_ph = ",".join(["%s"] * len(d_ids))

        with conn.cursor() as cur:
            cur.execute(f"SELECT DISTINCT staff_id FROM district_duty_assignments "
                        f"WHERE admin_id IN ({d_ph})", d_ids)
            for r in cur.fetchall():
                used_staff_ids.add(r["staff_id"])

        # Get active election
        cfg = get_active_election(district)
        election_id = cfg["id"] if cfg else None

        with conn.cursor() as cur:
            if only_duty_type:
                cur.execute(f"SELECT * FROM district_rules "
                            f"WHERE admin_id IN ({d_ph}) AND duty_type=%s",
                            d_ids + [only_duty_type])
            else:
                cur.execute(f"SELECT * FROM district_rules "
                            f"WHERE admin_id IN ({d_ph}) ORDER BY sort_order, duty_type", d_ids)
            rules = cur.fetchall()

        with conn.cursor() as cur:
            cur.execute("UPDATE district_duty_jobs SET total_types=%s WHERE id=%s",
                        (len(rules), job_id))
        conn.commit()

        total_assigned = 0
        total_skipped  = 0
        done_types     = 0

        for rule in rules:
            duty_type  = rule["duty_type"]
            duty_label = rule.get("duty_label_hi") or duty_type
            sankhya    = int(rule["sankhya"] or 0)

            shortage_report[duty_type] = {
                "label": duty_label, "shortages": [],
                "batches_made": 0, "batches_target": sankhya,
            }

            if sankhya <= 0:
                done_types += 1
                _update_progress(conn, job_id, done_types, total_assigned, total_skipped)
                continue

            with conn.cursor() as cur:
                cur.execute(f"SELECT COALESCE(MAX(batch_no),0) AS mx FROM district_duty_assignments "
                            f"WHERE admin_id IN ({d_ph}) AND duty_type=%s", d_ids + [duty_type])
                next_batch_no = (cur.fetchone()["mx"] or 0) + 1

            existing_batches = next_batch_no - 1
            batches_to_make  = sankhya - existing_batches
            shortage_report[duty_type]["batches_made"] = existing_batches

            if batches_to_make <= 0:
                done_types += 1
                _update_progress(conn, job_id, done_types, total_assigned, total_skipped)
                continue

            for _ in range(batches_to_make):
                batch_staff: list = []
                batch_short: list = []
                batch_used_local: set = set()

                for rank, is_armed, col in RANK_ASSIGN_ORDER:
                    needed = int(rule.get(col) or 0)
                    if needed <= 0:
                        continue
                    excludes = used_staff_ids | batch_used_local
                    picked   = _pick_random_staff(conn, rank, is_armed, needed, excludes)
                    if len(picked) < needed:
                        batch_short.append({
                            "rank": rank, "armed": bool(is_armed),
                            "missing": needed - len(picked), "rankCol": col,
                        })
                    batch_staff.extend(picked)
                    for sid in picked:
                        batch_used_local.add(sid)

                if batch_short:
                    for sh in batch_short:
                        existing = next(
                            (x for x in shortage_report[duty_type]["shortages"]
                             if x["rank"] == sh["rank"] and x["armed"] == sh["armed"]),
                            None
                        )
                        if existing:
                            existing["missing"] = max(existing["missing"], sh["missing"])
                        else:
                            shortage_report[duty_type]["shortages"].append({
                                "rank": sh["rank"], "armed": sh["armed"], "missing": sh["missing"],
                            })
                    total_skipped += 1
                    break

                try:
                    with conn.cursor() as cur:
                        cur.executemany("""
                            INSERT INTO district_duty_assignments
                                (admin_id, duty_type, batch_no, staff_id, election_id, assigned_by)
                            VALUES (%s,%s,%s,%s,%s,%s)
                        """, [(admin_id, duty_type, next_batch_no, sid, election_id, admin_id)
                              for sid in batch_staff])
                    conn.commit()
                    for sid in batch_staff:
                        used_staff_ids.add(sid)
                    total_assigned += len(batch_staff)
                    next_batch_no  += 1
                    shortage_report[duty_type]["batches_made"] += 1
                    _update_progress(conn, job_id, done_types, total_assigned, total_skipped)
                except Exception as e:
                    conn.rollback()
                    write_log("ERROR", f"Batch insert failed for {duty_type}: {e}", "DistrictAutoAssign")
                    total_skipped += 1
                    break

            done_types += 1
            _update_progress(conn, job_id, done_types, total_assigned, total_skipped)

        report_json = json.dumps(shortage_report, ensure_ascii=False)
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE district_duty_jobs
                SET status='done', done_types=%s, assigned=%s, skipped=%s, error_msg=%s, updated_at=NOW()
                WHERE id=%s
            """, (done_types, total_assigned, total_skipped, report_json, job_id))
        conn.commit()
        write_log("INFO", f"Auto-assign done: {total_assigned} assigned, {total_skipped} batches skipped "
                  f"(admin {admin_id})", "DistrictAutoAssign")

    except Exception as e:
        write_log("ERROR", f"Auto-assign error: {e}", "DistrictAutoAssign")
        try:
            with conn.cursor() as cur:
                cur.execute("UPDATE district_duty_jobs SET status='error', error_msg=%s, updated_at=NOW() "
                            "WHERE id=%s", (f"ERROR: {e}", job_id))
            conn.commit()
        except Exception:
            pass
    finally:
        try: conn.close()
        except: pass


@admin_bp.route("/district-duty/auto-assign/start", methods=["POST"])
@admin_required
def start_district_auto_assign():
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    admin_id = request.user["id"]
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO district_duty_jobs (admin_id, status, created_by) "
                        "VALUES (%s,'pending',%s)", (admin_id, admin_id))
            job_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    threading.Thread(target=_run_auto_assign_background, args=(job_id, admin_id, None),
                     daemon=True).start()
    return ok({"jobId": job_id, "status": "started"})


@admin_bp.route("/district-duty/<duty_type>/auto-assign", methods=["POST"])
@admin_required
def start_single_duty_auto_assign(duty_type):
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    admin_id = request.user["id"]
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT id FROM district_rules "
                        f"WHERE admin_id IN ({d_ph}) AND duty_type=%s", d_params + [duty_type])
            if not cur.fetchone():
                return err(f"Duty type '{duty_type}' not found", 404)
            cur.execute("INSERT INTO district_duty_jobs (admin_id, status, created_by) "
                        "VALUES (%s,'pending',%s)", (admin_id, admin_id))
            job_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    threading.Thread(target=_run_auto_assign_background, args=(job_id, admin_id, duty_type),
                     daemon=True).start()
    return ok({"jobId": job_id, "status": "started", "dutyType": duty_type})


@admin_bp.route("/district-duty/auto-assign/status/<int:job_id>", methods=["GET"])
@admin_required
def get_district_job_status(job_id):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT id, status, total_types, done_types, assigned, skipped, "
                        f"error_msg, created_at, updated_at FROM district_duty_jobs "
                        f"WHERE id=%s AND admin_id IN ({d_ph})", [job_id] + d_params)
            job = cur.fetchone()
    finally:
        conn.close()
    if not job:
        return err("Job not found", 404)

    total = job["total_types"] or 0
    done  = job["done_types"]  or 0
    pct   = int((done / total) * 100) if total > 0 else 0
    if job["status"] == "done":
        pct = 100

    shortage_report = None
    error_msg       = ""
    raw = job["error_msg"] or ""
    if job["status"] == "done" and raw and raw.strip().startswith("{"):
        try:
            shortage_report = json.loads(raw)
        except Exception:
            error_msg = raw
    else:
        error_msg = raw

    return ok({
        "jobId": job["id"], "status": job["status"],
        "totalTypes": total, "doneTypes": done,
        "assigned": job["assigned"] or 0, "skipped": job["skipped"] or 0,
        "pct": pct, "errorMsg": error_msg, "shortageReport": shortage_report,
        "createdAt": str(job["created_at"]), "updatedAt": str(job["updated_at"]),
    })


@admin_bp.route("/district-duty/auto-assign/latest", methods=["GET"])
@admin_required
def district_auto_assign_latest():
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"SELECT id, status, total_types, done_types, assigned, skipped, "
                        f"error_msg, created_at, updated_at FROM district_duty_jobs "
                        f"WHERE admin_id IN ({d_ph}) ORDER BY id DESC LIMIT 1", d_params)
            job = cur.fetchone()
    finally:
        conn.close()
    if not job:
        return ok(None)

    total = job["total_types"] or 0
    done  = job["done_types"]  or 0
    pct   = int((done / total) * 100) if total > 0 else 0
    if job["status"] == "done":
        pct = 100

    shortage_report = None
    error_msg       = ""
    raw = job["error_msg"] or ""
    if job["status"] == "done" and raw and raw.strip().startswith("{"):
        try:
            shortage_report = json.loads(raw)
        except Exception:
            error_msg = raw
    else:
        error_msg = raw

    return ok({
        "jobId": job["id"], "status": job["status"],
        "totalTypes": total, "doneTypes": done,
        "assigned": job["assigned"] or 0, "skipped": job["skipped"] or 0,
        "pct": pct, "errorMsg": error_msg, "shortageReport": shortage_report,
        "createdAt": str(job["created_at"]), "updatedAt": str(job["updated_at"]),
    })


@admin_bp.route("/district-duty/auto-assign/clear-all", methods=["DELETE"])
@admin_required
def clear_all_district_assignments():
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(f"DELETE FROM district_duty_assignments WHERE admin_id IN ({d_ph})", d_params)
            removed = cur.rowcount
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"All district duty assignments cleared ({removed} rows) by admin {_admin_id()}",
              "DistrictAutoAssign")
    return ok({"removed": removed}, "All district assignments cleared")


# ═════════════════════════════════════════════════════════════════════════════
#  BOOTH AUTO-ASSIGN INTERNAL
# ═════════════════════════════════════════════════════════════════════════════
@admin_bp.route("/auto-assign/<int:super_zone_id>", methods=["POST"])
@admin_required
def _assign_one_center(cur, center_id, admin_id, election_id, rules_map):
    cur.execute("SELECT center_type FROM matdan_sthal WHERE id=%s", (center_id,))
    center = cur.fetchone()
    if not center:
        return 0

    sensitivity = center["center_type"] or "C"
    rules       = rules_map.get(sensitivity, {})
    assigned    = 0

    rank_columns = [
        ("SI",              True,  "si_armed_count"),
        ("SI",              False, "si_unarmed_count"),
        ("Head Constable",  True,  "hc_armed_count"),
        ("Head Constable",  False, "hc_unarmed_count"),
        ("Constable",       True,  "const_armed_count"),
        ("Constable",       False, "const_unarmed_count"),
        ("Constable",       True,  "aux_armed_count"),
        ("Constable",       False, "aux_unarmed_count"),
    ]

    for rank, armed, col in rank_columns:
        count = rules.get(col, 0)
        if not count:
            continue
        cur.execute("""
            SELECT id FROM users
            WHERE role='staff' AND is_active=1 AND user_rank=%s AND is_armed=%s
              AND id NOT IN (SELECT staff_id FROM duty_assignments)
              AND id NOT IN (SELECT staff_id FROM district_duty_assignments)
            ORDER BY id LIMIT %s
        """, (rank, 1 if armed else 0, count))
        ids = [r["id"] for r in cur.fetchall()]
        for sid in ids:
            try:
                cur.execute("""
                    INSERT INTO duty_assignments
                        (staff_id, sthal_id, election_id, assigned_by)
                    VALUES (%s,%s,%s,%s)
                    ON DUPLICATE KEY UPDATE
                        sthal_id=VALUES(sthal_id), election_id=VALUES(election_id),
                        assigned_by=VALUES(assigned_by)
                """, (sid, center_id, election_id, admin_id))
                assigned += 1
            except Exception:
                pass
    return assigned



# ═════════════════════════════════════════════════════════════════════════════
#  BOOTH AUTO-ASSIGN — Manak-driven with shortage tracking
# ═════════════════════════════════════════════════════════════════════════════


def _pick_booth_staff(cur, rank: str, is_armed, count: int,
                      exclude_ids: set, district: str) -> list:
    """
    Return up to `count` unassigned staff rows of the given rank/armed status.
    - is_armed: bool or int — always normalised to 0/1 internally
    - exclude_ids: set of staff IDs already picked in this job run
    - district: admin's district string; empty string = no district filter
    """
    if count <= 0:
        return []
 
    armed_int = 1 if is_armed else 0
 
    def _query(with_district: bool) -> list:
        params = [rank, armed_int]
 
        sql = """
            SELECT id, name, pno, user_rank, is_armed
            FROM users
            WHERE role = 'staff'
              AND is_active = 1
              AND user_rank = %s
              AND is_armed  = %s
              AND id NOT IN (SELECT staff_id FROM duty_assignments)
              AND id NOT IN (SELECT staff_id FROM district_duty_assignments)
        """
 
        if with_district and district:
            sql += " AND district = %s"
            params.append(district)
 
        if exclude_ids:
            # Use chunked NOT IN to avoid hitting MySQL's max_allowed_packet
            # for very large exclude sets
            ex_list = list(exclude_ids)
            ph = ",".join(["%s"] * len(ex_list))
            sql += f" AND id NOT IN ({ph})"
            params.extend(ex_list)
 
        sql += " ORDER BY RAND() LIMIT %s"
        params.append(count)
 
        cur.execute(sql, params)
        return cur.fetchall()
 
    rows = _query(with_district=True)
 
    # Fallback: if district-scoped returns nothing AND district was set,
    # try without district. This handles staff uploaded without district field.
    if not rows and district:
        rows = _query(with_district=False)
 
    return rows
 


# ── Slot metadata (module-level, shared by auto-assign and shortage info) ────
_SLOT_META = [
    ("SI",             True,  "siArmedCount",      "si_armed_count",      "SI",    "सशस्त्र"),
    ("SI",             False, "siUnarmedCount",     "si_unarmed_count",    "SI",    "निःशस्त्र"),
    ("Head Constable", True,  "hcArmedCount",       "hc_armed_count",      "HC",    "सशस्त्र"),
    ("Head Constable", False, "hcUnarmedCount",      "hc_unarmed_count",    "HC",    "निःशस्त्र"),
    ("Constable",      True,  "constArmedCount",    "const_armed_count",   "Const", "सशस्त्र"),
    ("Constable",      False, "constUnarmedCount",   "const_unarmed_count", "Const", "निःशस्त्र"),
    ("Constable",      True,  "auxArmedCount",      "aux_armed_count",     "Aux",   "सशस्त्र"),
    ("Constable",      False, "auxUnarmedCount",     "aux_unarmed_count",   "Aux",   "निःशस्त्र"),
]

# Keep module-level SLOTS for district duty (backward compat)
SLOTS = [
    ("SI",             1, "siArmedCount",      "si_armed_count",      "SI",    "सशस्त्र"),
    ("SI",             0, "siUnarmedCount",    "si_unarmed_count",    "SI",    "निःशस्त्र"),
    ("Head Constable", 1, "hcArmedCount",      "hc_armed_count",      "HC",    "सशस्त्र"),
    ("Head Constable", 0, "hcUnarmedCount",    "hc_unarmed_count",    "HC",    "निःशस्त्र"),
    ("Constable",      1, "constArmedCount",   "const_armed_count",   "Const", "सशस्त्र"),
    ("Constable",      0, "constUnarmedCount", "const_unarmed_count", "Const", "निःशस्त्र"),
    ("Constable",      1, "auxArmedCount",     "aux_armed_count",     "Aux",   "सशस्त्र"),
    ("Constable",      0, "auxUnarmedCount",   "aux_unarmed_count",   "Aux",   "निःशस्त्र"),
]


def _assign_one_center_with_manak(cur, center_id: int, admin_id: int,
                                   election_id: int, rules_map: dict,
                                   district: str, used_ids: set) -> dict:
    """
    Assign staff to ONE center using ONE manak set (no booth_count multiplication).
    Every election center gets exactly one set of staff per sensitivity rule.

    rules_map: {(sensitivity, booth_count_capped): db_row_dict}
    Returns:   {"assigned": int, "shortages": [...]}
    """
    cur.execute(
        "SELECT id, name, center_type, booth_count FROM matdan_sthal WHERE id = %s",
        (center_id,)
    )
    center = cur.fetchone()
    if not center:
        return {"assigned": 0, "shortages": []}

    sensitivity = center["center_type"] or "C"
    raw_bc      = int(center["booth_count"] or 1)
    lookup_bc   = max(1, min(raw_bc, 15))

    # ── Check if this center already has a COMPLETE duty assignment ──────────
    # Count currently assigned staff at this center
    cur.execute(
        "SELECT COUNT(*) AS cnt FROM duty_assignments WHERE sthal_id = %s",
        (center_id,)
    )
    already_assigned = int((cur.fetchone() or {}).get("cnt") or 0)

    # ── Find the matching rule ───────────────────────────────────────────────
    rule = rules_map.get((sensitivity, lookup_bc))
    if not rule:
        # Fallback: find closest lower booth_count that has a rule
        for bc in range(lookup_bc - 1, 0, -1):
            rule = rules_map.get((sensitivity, bc))
            if rule:
                break

    if not rule:
        write_log("WARN",
            f"No manak rule for center {center_id} "
            f"(sensitivity={sensitivity}, booth_count={raw_bc}). Skipping.",
            "AutoAssign")
        return {
            "assigned": 0,
            "shortages": [{
                "rank":       "NO_MANAK",
                "armed":      False,
                "required":   0,
                "assigned":   0,
                "missing":    1,
                "labelShort": "मानक नहीं",
                "labelArmed": f"{sensitivity}/{raw_bc}बूथ — मानक सेट नहीं",
                "ruleField":  "",
            }]
        }

    # ── Calculate total required per manak (ONE set, no multiplication) ──────
    total_required = sum(
        int(rule.get(col) or 0)
        for _, _, _, col, _, _ in _SLOT_META
    )

    # ── Skip if already fully assigned ───────────────────────────────────────
    if already_assigned >= total_required > 0:
        write_log("INFO",
            f"Center {center_id} already fully assigned "
            f"({already_assigned}/{total_required}). Skipping.",
            "AutoAssign")
        return {"assigned": 0, "shortages": []}

    # ── Assign each rank slot (ONE per center, not per booth) ────────────────
    assigned_total = 0
    shortages      = []

    # Track what's already assigned at this center per (rank, armed)
    cur.execute("""
        SELECT u.user_rank, u.is_armed, COUNT(*) AS cnt
        FROM duty_assignments da
        JOIN users u ON u.id = da.staff_id
        WHERE da.sthal_id = %s
        GROUP BY u.user_rank, u.is_armed
    """, (center_id,))
    existing_at_center = {
        ((r["user_rank"] or ""), int(r["is_armed"] or 0)): int(r["cnt"] or 0)
        for r in cur.fetchall()
    }

    for rank, armed, _api_field, col, label_short, label_armed in _SLOT_META:
        needed_per_manak = int(rule.get(col) or 0)
        if needed_per_manak <= 0:
            continue

        # ── ONE set only — subtract what's already assigned at this center ──
        armed_int    = 1 if armed else 0
        already_here = existing_at_center.get((rank, armed_int), 0)
        still_needed = max(0, needed_per_manak - already_here)

        if still_needed <= 0:
            # This rank is already satisfied at this center
            continue

        picked = _pick_booth_staff(cur, rank, armed_int, still_needed, used_ids, district)
        got    = len(picked)

        for s in picked:
            try:
                cur.execute("""
                    INSERT INTO duty_assignments
                        (staff_id, sthal_id, election_id, assigned_by)
                    VALUES (%s, %s, %s, %s)
                    ON DUPLICATE KEY UPDATE
                        sthal_id    = VALUES(sthal_id),
                        election_id = VALUES(election_id),
                        assigned_by = VALUES(assigned_by)
                """, (s["id"], center_id, election_id, admin_id))
                used_ids.add(s["id"])
                assigned_total += 1
            except Exception as e:
                write_log("ERROR",
                    f"duty insert failed: staff={s['id']} center={center_id}: {e}",
                    "AutoAssign")

        if got < still_needed:
            shortages.append({
                "rank":       rank,
                "armed":      armed,
                "required":   needed_per_manak,   # what manak says
                "assigned":   already_here + got, # total at center after this run
                "missing":    still_needed - got,
                "labelShort": label_short,
                "labelArmed": label_armed,
                "ruleField":  col,
            })

    return {"assigned": assigned_total, "shortages": shortages}


def auto_assign_internal(super_zone_id: int, admin_id: int, election_id: int):
    """
    Auto-assign duty to every center under the given super zone using manak.
    Partial assignment is allowed — if a rank is short, assign what's available
    and record the shortage. Never aborts a center because of one missing rank.
    """
    conn = get_db()
    total_assigned       = 0
    per_center_shortages = {}
 
    try:
        with conn.cursor() as cur:
            # ── 1. Get admin's district ───────────────────────────────────────
            cur.execute("SELECT district FROM users WHERE id = %s", (admin_id,))
            row      = cur.fetchone()
            district = (row["district"] or "").strip() if row else ""
 
            # ── 2. Collect all admin IDs in same district (for booth_rules) ──
            if district:
                cur.execute(
                    "SELECT id FROM users "
                    "WHERE role IN ('admin','super_admin') AND district = %s",
                    (district,)
                )
                d_ids = [r["id"] for r in cur.fetchall()]
                if admin_id not in d_ids:
                    d_ids.append(admin_id)
            else:
                d_ids = [admin_id]
 
            d_ph = ",".join(["%s"] * len(d_ids))
 
            # ── 3. Build rules_map ────────────────────────────────────────────
            cur.execute(
                f"SELECT * FROM booth_rules WHERE admin_id IN ({d_ph})",
                d_ids
            )
            raw_rules = cur.fetchall()
            rules_map = {
                (r["sensitivity"], int(r["booth_count"] or 1)): dict(r)
                for r in raw_rules
            }
 
            write_log("INFO",
                f"SZ {super_zone_id}: rules_map has {len(rules_map)} entries "
                f"for admin_ids={d_ids} district='{district}'",
                "AutoAssign")
 
            if not rules_map:
                write_log("WARN",
                    f"SZ {super_zone_id}: NO booth_rules found! "
                    f"Assign Duty will assign 0 staff. "
                    f"Admin must set manak (booth rules) first.",
                    "AutoAssign")
 
            # ── 4. Get all centers under this super zone ──────────────────────
            cur.execute("""
                SELECT ms.id, ms.name, ms.center_type, ms.booth_count
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                WHERE z.super_zone_id = %s
                ORDER BY ms.id
            """, (super_zone_id,))
            centers = cur.fetchall()
 
            write_log("INFO",
                f"SZ {super_zone_id}: found {len(centers)} centers to process",
                "AutoAssign")
 
            # ── 5. Pre-populate used_ids ──────────────────────────────────────
            cur.execute("SELECT staff_id FROM duty_assignments")
            used_ids = {r["staff_id"] for r in cur.fetchall()}
            cur.execute("SELECT staff_id FROM district_duty_assignments")
            used_ids.update(r["staff_id"] for r in cur.fetchall())
 
            write_log("INFO",
                f"SZ {super_zone_id}: {len(used_ids)} staff already assigned (excluded)",
                "AutoAssign")
 
        # ── 6. Process each center ────────────────────────────────────────────
        total_centers = len(centers)
        for done, c in enumerate(centers, start=1):
            # Open a fresh cursor for each center to keep transaction clean
            with conn.cursor() as cur2:
                result = _assign_one_center_with_manak(
                    cur2, c["id"], admin_id, election_id,
                    rules_map, district, used_ids
                )
 
            total_assigned += result["assigned"]
 
            if result["shortages"]:
                per_center_shortages[str(c["id"])] = {
                    "centerId":    c["id"],
                    "centerName":  c["name"] or "",
                    "sensitivity": c["center_type"] or "C",
                    "boothCount":  int(c["booth_count"] or 1),
                    "shortages":   result["shortages"],
                }
 
            # Commit after every center so progress is visible immediately
            conn.commit()
 
            # Update progress counter in job row
            with conn.cursor() as cur3:
                cur3.execute("""
                    UPDATE sz_assign_jobs
                       SET total_centers = %s,
                           done_centers  = %s
                     WHERE super_zone_id = %s
                     ORDER BY id DESC
                     LIMIT 1
                """, (total_centers, done, super_zone_id))
            conn.commit()
 
        # ── 7. Persist shortage report ────────────────────────────────────────
        report = {
            "totalCenters":        total_centers,
            "totalAssigned":       total_assigned,
            "centersWithShortage": len(per_center_shortages),
            "hasShortages":        bool(per_center_shortages),
            "district":            district,
            "perCenter":           per_center_shortages,
        }
        with conn.cursor() as cur4:
            cur4.execute("""
                UPDATE sz_assign_jobs
                   SET shortage_report = %s
                 WHERE super_zone_id   = %s
                 ORDER BY id DESC
                 LIMIT 1
            """, (json.dumps(report, ensure_ascii=False), super_zone_id))
        conn.commit()
 
        write_log("INFO",
            f"SZ {super_zone_id}: DONE — assigned {total_assigned} staff "
            f"to {total_centers} centers "
            f"({len(per_center_shortages)} with shortages, election={election_id})",
            "AutoAssign")
 
    except Exception as e:
        write_log("ERROR",
            f"auto_assign_internal SZ={super_zone_id}: {e}\n{traceback.format_exc()}",
            "AutoAssign")
        try:
            conn.rollback()
        except Exception:
            pass
        raise
    finally:
        conn.close()
 


def run_auto_assign_job(job_id: int, super_zone_id: int,
                        admin_id: int, election_id: int):
    """Background thread wrapper around auto_assign_internal."""
    print(f"🚀 AUTO ASSIGN STARTED SZ={super_zone_id} job={job_id} election={election_id}")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE sz_assign_jobs SET status='running' WHERE id = %s",
                (job_id,)
            )
        conn.commit()
 
        auto_assign_internal(super_zone_id, admin_id, election_id)
 
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE sz_assign_jobs SET status='done' WHERE id = %s",
                (job_id,)
            )
        conn.commit()
        print(f"✅ Auto assign completed SZ={super_zone_id} job={job_id}")
 
    except Exception as e:
        print(f"❌ AUTO ASSIGN ERROR SZ={super_zone_id}: {e}")
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "UPDATE sz_assign_jobs "
                    "SET status='error', error_msg=%s WHERE id=%s",
                    (str(e)[:500], job_id)
                )
            conn.commit()
        except Exception:
            pass
    finally:
        try:
            conn.close()
        except Exception:
            pass
 
 
# ═════════════════════════════════════════════════════════════════════════════
#  SWAP / MANUAL ASSIGN
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/swap", methods=["POST"])
@admin_required
def swap_staff():
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    body         = request.get_json() or {}
    old_staff_id = body.get("oldStaffId") or body.get("removeStaffId")
    new_staff_id = body.get("newStaffId") or body.get("addStaffId")
    center_id    = body.get("centerId")

    if not (old_staff_id and new_staff_id and center_id):
        return err("oldStaffId, newStaffId, centerId required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT z.super_zone_id FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s ON s.id = gp.sector_id
                JOIN zones z ON z.id = s.zone_id
                WHERE ms.id=%s
            """, (center_id,))
            row = cur.fetchone()
            if row:
                cur.execute("SELECT is_locked FROM sz_duty_locks WHERE super_zone_id=%s",
                            (row["super_zone_id"],))
                lock = cur.fetchone()
                if lock and lock["is_locked"]:
                    return err("Zone is locked")

            cur.execute("DELETE FROM duty_assignments WHERE staff_id=%s AND sthal_id=%s",
                        (old_staff_id, center_id))
            cur.execute("SELECT id FROM duty_assignments WHERE staff_id=%s", (new_staff_id,))
            if cur.fetchone():
                return err("New staff already assigned")
            cur.execute("""
                INSERT INTO duty_assignments (staff_id, sthal_id, election_id, assigned_by)
                VALUES (%s,%s,%s,%s)
                ON DUPLICATE KEY UPDATE sthal_id=VALUES(sthal_id),
                    election_id=VALUES(election_id), assigned_by=VALUES(assigned_by)
            """, (new_staff_id, center_id, election_id, _admin_id()))
        conn.commit()
    finally:
        conn.close()
    return ok({"electionId": election_id}, "Swapped successfully")


@admin_bp.route("/assign", methods=["POST"])
@admin_required
def manual_assign():
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    body     = request.get_json() or {}
    staff_id = body.get("staffId")
    sthal_id = body.get("centerId")
    if not staff_id or not sthal_id:
        return err("staffId and centerId required")

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM duty_assignments WHERE staff_id=%s", (staff_id,))
            if cur.fetchone():
                return err("Staff already assigned")
            cur.execute("""
                INSERT INTO duty_assignments (staff_id, sthal_id, election_id, assigned_by)
                VALUES (%s,%s,%s,%s)
            """, (staff_id, sthal_id, election_id, _admin_id()))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Staff assigned")


# ═════════════════════════════════════════════════════════════════════════════
#  LOCK / UNLOCK
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/unlock/request", methods=["POST"])
@admin_required
def request_unlock():
    body  = request.get_json() or {}
    sz_id = body.get("superZoneId")
    reason = body.get("reason")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO sz_unlock_requests (super_zone_id, requested_by, reason) "
                        "VALUES (%s,%s,%s)", (sz_id, request.user["id"], reason))
            cur.execute("UPDATE sz_duty_locks SET status='unlock_requested' WHERE super_zone_id=%s",
                        (sz_id,))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Unlock request sent")


@admin_bp.route("/unlock/approve/<int:req_id>", methods=["POST"])
@admin_required
def approve_unlock(req_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT super_zone_id FROM sz_unlock_requests WHERE id=%s", (req_id,))
            req = cur.fetchone()
            if not req:
                return err("Request not found")
            cur.execute("UPDATE sz_unlock_requests SET status='approved', reviewed_by=%s WHERE id=%s",
                        (request.user["id"], req_id))
            cur.execute("UPDATE sz_duty_locks SET is_locked=0, status='unlocked' "
                        "WHERE super_zone_id=%s", (req["super_zone_id"],))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Unlocked successfully")


@admin_bp.route("/unlock/reject/<int:req_id>", methods=["POST"])
@admin_required
def reject_unlock(req_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("UPDATE sz_unlock_requests SET status='rejected', reviewed_by=%s WHERE id=%s",
                        (request.user["id"], req_id))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Request rejected")


@admin_bp.route("/super-zones/<int:sz_id>/job-status", methods=["GET"])
@admin_required
def get_job_status(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT * FROM sz_assign_jobs WHERE super_zone_id=%s "
                        "ORDER BY id DESC LIMIT 1", (sz_id,))
            job = cur.fetchone()
    finally:
        conn.close()
    return ok(job or {})


@admin_bp.route("/refresh/<int:super_zone_id>", methods=["POST"])
@admin_required
def refresh_super_zone(super_zone_id):
    """
    Unassign ALL booth-level staff under the given super zone,
    then re-run auto-assign for that super zone.
    """
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Lock check
            cur.execute(
                "SELECT is_locked FROM sz_duty_locks WHERE super_zone_id=%s",
                (super_zone_id,)
            )
            lock = cur.fetchone()
            if lock and lock["is_locked"]:
                return err("Duties are locked for this Super Zone")

            # Delete ALL booth duty_assignments under this super zone
            cur.execute("""
                DELETE da FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                WHERE z.super_zone_id = %s
            """, (super_zone_id,))
            removed = cur.rowcount

        conn.commit()
    finally:
        conn.close()

    write_log("INFO",
              f"Super zone {super_zone_id} refreshed: {removed} booth assignments cleared "
              f"by admin {_admin_id()}",
              "AutoAssign")

    # Re-run auto-assign in background
    conn2 = get_db()
    try:
        with conn2.cursor() as cur:
            cur.execute(
                "INSERT INTO sz_assign_jobs (super_zone_id, created_by) VALUES (%s,%s)",
                (super_zone_id, _admin_id())
            )
            job_id = cur.lastrowid
        conn2.commit()
        threading.Thread(
            target=run_auto_assign_job,
            args=(job_id, super_zone_id, _admin_id(), election_id),
            daemon=True,
        ).start()
    finally:
        conn2.close()

    return ok({"jobId": job_id, "removed": removed}, "Refresh started")
    

@admin_bp.route("/super-zones/<int:super_zone_id>/clear-duties", methods=["POST"])
@admin_required
def clear_sz_duties(super_zone_id):
    """
    Unassign ALL booth-level staff under this super zone.
    Does NOT re-run auto-assign. Staff go back to reserve.
    """
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    conn = get_db()
    try:
        with conn.cursor() as cur:
            # Verify this super zone belongs to this district
            cur.execute(
                f"SELECT id FROM super_zones WHERE id=%s AND admin_id IN ({d_ph})",
                [super_zone_id] + d_params
            )
            if not cur.fetchone():
                return err("Not found or access denied", 403)

            # Check lock
            cur.execute(
                "SELECT is_locked FROM sz_duty_locks WHERE super_zone_id=%s",
                (super_zone_id,)
            )
            lock = cur.fetchone()
            if lock and lock["is_locked"]:
                return err("Duties are locked for this Super Zone")

            # Delete ALL duty_assignments under this super zone only
            cur.execute("""
                DELETE da FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                WHERE z.super_zone_id = %s
            """, (super_zone_id,))
            removed = cur.rowcount

        conn.commit()
    finally:
        conn.close()

    write_log("INFO",
              f"Super zone {super_zone_id} cleared: {removed} booth assignments removed "
              f"by admin {_admin_id()}",
              "AutoAssign")
    return ok({"removed": removed}, f"{removed} assignments हटाई गईं")



# @admin_bp.route("/auto-assign/<int:super_zone_id>", methods=["POST"])
# @admin_required
# def auto_assign(super_zone_id):
#     cfg, gerr = require_active_election(request.user.get("district"))
#     if gerr:
#         return gerr
#     election_id = cfg["id"]

#     conn = get_db()
#     try:
#         with conn.cursor() as cur:
#             cur.execute("SELECT is_locked FROM sz_duty_locks WHERE super_zone_id=%s",
#                         (super_zone_id,))
#             lock = cur.fetchone()
#             if lock and lock["is_locked"]:
#                 return err("Duties are locked for this Super Zone")
#             cur.execute("""
#                 DELETE da FROM duty_assignments da
#                 JOIN matdan_sthal ms ON ms.id = da.sthal_id
#                 JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
#                 JOIN sectors s ON s.id = gp.sector_id
#                 JOIN zones z ON z.id = s.zone_id
#                 WHERE z.super_zone_id=%s
#             """, (super_zone_id,))
#         conn.commit()
#     finally:
#         conn.close()

#     auto_assign_internal(super_zone_id, _admin_id(), election_id)
#     return ok(None, "Auto assignment completed")


# ═════════════════════════════════════════════════════════════════════════════
#  RESERVE STAFF
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/reserve-staff", methods=["GET"])
@admin_required
def get_reserve_staff():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                SELECT id, name, user_rank, mobile FROM users
                WHERE role='staff' AND is_active=1
                  AND id NOT IN (SELECT staff_id FROM duty_assignments)
                ORDER BY name ASC
            """)
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok(rows)


# ═════════════════════════════════════════════════════════════════════════════
#  ELECTION CONFIG
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/election-config/active", methods=["GET"])
@admin_required
def get_active_election_config():
    district = (request.user.get("district") or "").strip()
    if not district:
        return err("Admin has no district set", 400)
    run_auto_finalize_if_due(district)
    cfg = get_active_election(district)
    if not cfg:
        return ok({"hasActiveConfig": False, "config": None})
    return ok({
        "hasActiveConfig": True,
        "config": {
            "id":           cfg["id"],
            "district":     cfg["district"]       or "",
            "state":        cfg.get("state")      or "",
            "electionType": cfg.get("election_type") or "",
            "electionName": cfg.get("election_name") or "",
            "phase":        cfg.get("phase")      or "",
            "electionYear": cfg.get("election_year") or "",
            "electionDate": str(cfg["election_date"]) if cfg.get("election_date") else "",
            "pratahSamay":  cfg.get("pratah_samay")  or "",
            "sayaSamay":    cfg.get("saya_samay")     or "",
            "instructions": cfg.get("instructions")  or "",
            "isActive":     bool(cfg.get("is_active")),
            "isFinalized":  bool(cfg.get("is_finalized")),
        }
    })


@admin_bp.route("/election-config", methods=["POST"])
@admin_required
def save_election_config():
    body = request.get_json() or {}
    district      = (body.get("district") or request.user.get("district") or "").strip()
    state         = (body.get("state")        or "").strip()
    election_type = (body.get("electionType") or "").strip()
    election_name = (body.get("electionName") or "").strip()
    phase         = (body.get("phase")        or "").strip()
    election_year = (body.get("electionYear") or "").strip()
    election_date = body.get("electionDate")
    pratah_samay  = (body.get("pratahSamay")  or "07:00").strip()
    saya_samay    = (body.get("sayaSamay")    or "06:00").strip()
    instructions  = (body.get("instructions") or "").strip()

    if not district or not election_name:
        return err("district and electionName required")

    if election_date and "." in str(election_date):
        parts = str(election_date).split(".")
        if len(parts) == 3:
            election_date = f"{parts[2]}-{parts[1]}-{parts[0]}"

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE election_configs
                SET is_active=0, is_archived=1, archived_at=NOW()
                WHERE district=%s AND is_active=1 AND is_archived=0
            """, (district,))
            cur.execute("""
                INSERT INTO election_configs
                    (district, state, election_type, election_name, phase,
                     election_year, election_date, pratah_samay, saya_samay,
                     instructions, is_active, is_archived, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,1,0,%s)
            """, (district, state, election_type, election_name, phase,
                  election_year, election_date or None, pratah_samay, saya_samay,
                  instructions, request.user["id"]))
            new_id = cur.lastrowid
        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except: pass
        return err(f"Save failed: {e}", 500)
    finally:
        conn.close()
    write_log("INFO", f"Election config saved for {district} by admin {_admin_id()}", "ElectionConfig")
    return ok({"id": new_id}, "Election config saved", 201)


@admin_bp.route("/election-config/list", methods=["GET"])
@admin_required
def list_election_configs():
    district = (request.args.get("district") or request.user.get("district") or "").strip()
    conn = get_db()
    try:
        with conn.cursor() as cur:
            if district:
                cur.execute("SELECT id, district, state, election_name, phase, election_year, "
                            "election_date, pratah_samay, saya_samay, is_active, is_archived, "
                            "created_at, updated_at FROM election_configs "
                            "WHERE district=%s ORDER BY id DESC", (district,))
            else:
                cur.execute("SELECT id, district, state, election_name, phase, election_year, "
                            "election_date, pratah_samay, saya_samay, is_active, is_archived, "
                            "created_at, updated_at FROM election_configs ORDER BY id DESC LIMIT 100")
            rows = cur.fetchall()
    finally:
        conn.close()
    return ok([{
        "id":           r["id"],
        "district":     r["district"]      or "",
        "state":        r["state"]         or "",
        "electionName": r["election_name"] or "",
        "phase":        r["phase"]         or "",
        "electionYear": r["election_year"] or "",
        "electionDate": str(r["election_date"]) if r["election_date"] else "",
        "pratahSamay":  r["pratah_samay"]  or "",
        "sayaSamay":    r["saya_samay"]    or "",
        "isActive":     bool(r["is_active"]),
        "isArchived":   bool(r["is_archived"]),
        "createdAt":    str(r["created_at"]),
        "updatedAt":    str(r["updated_at"]),
    } for r in rows])


# ═════════════════════════════════════════════════════════════════════════════
#  MISC — config, overview, goswara
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/config", methods=["GET"])
@admin_required
def get_admin_config():
    district = request.user.get("district") or ""
    run_auto_finalize_if_due(district)
    cfg = get_active_election(district)
    return ok({
        "district":       district,
        "thana":          request.user.get("thana") or "",
        "role":           request.user.get("role"),
        "electionConfig": cfg,
        "hasActiveConfig": bool(cfg),
    })


@admin_bp.route("/overview", methods=["GET"])
@admin_required
def admin_overview():
    district = (request.user.get("district") or "").strip()
    
    # Run auto-finalize if election date has passed
    run_auto_finalize_if_due(district)
    
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)

    # Get active election to filter duties
    cfg_active = get_active_election(district)
    eid_filter = ""
    eid_params = []
    if cfg_active:
        eid_filter = "AND da.election_id = %s"
        eid_params = [cfg_active["id"]]

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                f"SELECT COUNT(*) AS cnt FROM super_zones WHERE admin_id IN ({d_ph})",
                d_params
            )
            sz = cur.fetchone()["cnt"]

            cur.execute(f"""
                SELECT COUNT(DISTINCT ms.id) AS cnt
                FROM matdan_sthal ms
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({d_ph})
            """, d_params)
            booths = cur.fetchone()["cnt"]

            # Staff count: district-scoped
            if district:
                cur.execute(
                    "SELECT COUNT(*) AS cnt FROM users "
                    "WHERE role='staff' AND is_active=1 AND district=%s",
                    (district,)
                )
            else:
                cur.execute(
                    "SELECT COUNT(*) AS cnt FROM users "
                    "WHERE role='staff' AND is_active=1"
                )
            staff = cur.fetchone()["cnt"]

            # Booth duty count — filtered by active election_id
            cur.execute(f"""
                SELECT COUNT(DISTINCT da.staff_id) AS cnt
                FROM duty_assignments da
                JOIN matdan_sthal ms    ON ms.id = da.sthal_id
                JOIN gram_panchayats gp ON gp.id = ms.gram_panchayat_id
                JOIN sectors s          ON s.id  = gp.sector_id
                JOIN zones z            ON z.id  = s.zone_id
                JOIN super_zones sz     ON sz.id = z.super_zone_id
                WHERE sz.admin_id IN ({d_ph}) {eid_filter}
            """, d_params + eid_params)
            booth_assigned = cur.fetchone()["cnt"]

            # District duty count — filtered by active election_id
            if cfg_active:
                cur.execute(f"""
                    SELECT COUNT(DISTINCT staff_id) AS cnt
                    FROM district_duty_assignments
                    WHERE admin_id IN ({d_ph}) AND election_id = %s
                """, d_params + [cfg_active["id"]])
            else:
                cur.execute(f"""
                    SELECT COUNT(DISTINCT staff_id) AS cnt
                    FROM district_duty_assignments
                    WHERE admin_id IN ({d_ph})
                """, d_params)
            district_assigned = cur.fetchone()["cnt"]

    except Exception as e:
        write_log("ERROR", f"overview error: {e}", "Overview")
        return {
            "success": True,
            "data": {
                "superZones":      0,
                "totalBooths":     0,
                "totalStaff":      0,
                "boothAssigned":   0,
                "districtAssigned": 0,
                "assignedDuties":  0,
                "hasActiveConfig": False,
                "electionName":    "",
            }
        }
    finally:
        conn.close()

    return {
        "success": True,
        "data": {
            "superZones":       int(sz               or 0),
            "totalBooths":      int(booths            or 0),
            "totalStaff":       int(staff             or 0),
            "boothAssigned":    int(booth_assigned    or 0),
            "districtAssigned": int(district_assigned or 0),
            "assignedDuties":   int(booth_assigned    or 0) + int(district_assigned or 0),
            "hasActiveConfig":  bool(cfg_active),
            "electionName":     cfg_active.get("election_name", "") if cfg_active else "",
        }
    }


@admin_bp.route("/goswara", methods=["GET"])
@admin_required
def get_goswara():
    current_id = _admin_id()
    district   = (request.user.get("district") or "").strip()
    conn = get_db()
    try:
        with conn.cursor() as cur:
            election_date = ""
            phase         = ""
            if district:
                cur.execute("""
                    SELECT election_date, phase FROM election_configs
                    WHERE district=%s AND is_active=1 AND is_archived=0
                    ORDER BY id DESC LIMIT 1
                """, (district,))
                cfg = cur.fetchone()
                if cfg:
                    election_date = str(cfg["election_date"]) if cfg["election_date"] else ""
                    phase         = str(cfg["phase"] or "")

            if district:
                cur.execute("SELECT id FROM users WHERE role IN ('admin','super_admin') AND district=%s",
                            (district,))
                rows_ids  = cur.fetchall()
                admin_ids = [r["id"] for r in rows_ids] if rows_ids else [current_id]
                if current_id not in admin_ids:
                    admin_ids.append(current_id)
            else:
                admin_ids = [current_id]

            ph = ",".join(["%s"] * len(admin_ids))
            cur.execute(f"""
                SELECT sz.block AS block_name,
                       COUNT(DISTINCT zo.id) AS zonal_count,
                       COUNT(DISTINCT so_off.id) AS sector_count,
                       COUNT(DISTINCT gp.id) AS gram_panchayat_count
                FROM super_zones sz
                LEFT JOIN zones z ON z.super_zone_id = sz.id
                LEFT JOIN zonal_officers zo ON zo.zone_id = z.id
                LEFT JOIN sectors s ON s.zone_id = z.id
                LEFT JOIN sector_officers so_off ON so_off.sector_id = s.id
                LEFT JOIN gram_panchayats gp ON gp.sector_id = s.id
                WHERE sz.admin_id IN ({ph})
                  AND sz.block IS NOT NULL AND TRIM(sz.block) != ''
                GROUP BY sz.block ORDER BY sz.block
            """, admin_ids)
            rows = cur.fetchall()

            cur.execute(f"SELECT block_name, SUM(nyay_count) AS nyay_count "
                        f"FROM goswara_nyay_panchayat WHERE admin_id IN ({ph}) "
                        f"GROUP BY block_name", admin_ids)
            nyay_map = {r["block_name"]: int(r["nyay_count"] or 0) for r in cur.fetchall()}

            data = []
            for r in rows:
                block = r["block_name"] or ""
                data.append({
                    "block_name":           block,
                    "zonal_count":          int(r["zonal_count"]          or 0),
                    "sector_count":         int(r["sector_count"]         or 0),
                    "nyay_panchayat_count": nyay_map.get(block, 0),
                    "gram_panchayat_count": int(r["gram_panchayat_count"] or 0),
                })
    finally:
        conn.close()

    return jsonify({
        "success": True,
        "electionDate": election_date,
        "phase": phase,
        "data": data,
    })


@admin_bp.route("/goswara/nyay-panchayat", methods=["POST"])
@admin_required
def save_nyay_panchayat():
    body       = request.get_json() or {}
    block_name = (body.get("blockName") or "").strip()
    nyay_count = int(body.get("nyayCount") or 0)
    if not block_name:
        return err("blockName required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                INSERT INTO goswara_nyay_panchayat (admin_id, block_name, nyay_count)
                VALUES (%s,%s,%s)
                ON DUPLICATE KEY UPDATE nyay_count=VALUES(nyay_count)
            """, (_admin_id(), block_name, nyay_count))
        conn.commit()
    finally:
        conn.close()
    return ok(None, "Saved")


@admin_bp.route("/officers/save-to-users", methods=["POST"])
@admin_required
def save_officer_to_users():
    body   = request.get_json() or {}
    name   = (body.get("name") or "").strip()
    pno    = (body.get("pno") or "").strip()
    mobile = (body.get("mobile") or "").strip()
    rank   = (body.get("rank") or "").strip()
    if not name or not pno:
        return err("name and pno required")
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM users WHERE pno=%s", (pno,))
            existing = cur.fetchone()
            if existing:
                return ok({"id": existing["id"], "existed": True}, "Already in users")
            cur.execute("SELECT id FROM users WHERE username=%s", (pno,))
            username = pno if not cur.fetchone() else f"{pno}_{_admin_id()}"
            district = request.user.get("district") or ""
            cur.execute("""
                INSERT INTO users (name, pno, username, password, mobile,
                                   district, user_rank, is_armed, role, is_active, created_by)
                VALUES (%s,%s,%s,%s,%s,%s,%s,0,'staff',1,%s)
            """, (name, pno, username, generate_password_hash(pno), mobile, district, rank, _admin_id()))
            new_id = cur.lastrowid
        conn.commit()
    finally:
        conn.close()
    write_log("INFO", f"Officer '{name}' PNO:{pno} saved to users by admin {_admin_id()}", "Officer")
    return ok({"id": new_id, "existed": False}, "Officer saved to users", 201)


@admin_bp.route("/staff/debug", methods=["GET"])
@admin_required
def debug_staff():
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT COUNT(*) AS cnt FROM users WHERE role='staff'")
            total = cur.fetchone()["cnt"]
            cur.execute("""
                SELECT LOWER(TRIM(district)) AS district_norm, COUNT(*) AS cnt
                FROM users WHERE role='staff'
                GROUP BY district_norm ORDER BY cnt DESC LIMIT 20
            """)
            by_district = [{"district": r["district_norm"] or "(empty)", "count": r["cnt"]}
                           for r in cur.fetchall()]
            admin_district = (request.user.get("district") or "").strip().lower()
            if admin_district:
                cur.execute("SELECT COUNT(*) AS cnt FROM users "
                            "WHERE role='staff' AND LOWER(TRIM(district))=%s", (admin_district,))
                matching = cur.fetchone()["cnt"]
            else:
                matching = total
    finally:
        conn.close()
    return ok({
        "adminDistrict":    admin_district or "(not set)",
        "totalStaffInDB":   total,
        "matchingDistrict": matching,
        "byDistrict":       by_district,
    })

# ═════════════════════════════════════════════════════════════════════════════
#  SHORTAGE STATUS & OVERRIDE
# ═════════════════════════════════════════════════════════════════════════════

@admin_bp.route("/assign/shortages/<int:job_id>", methods=["GET"])
@admin_required
def get_assign_shortages(job_id):
    """Return the persisted shortage report for a job."""
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, status, total_centers, done_centers, shortage_report, error_msg "
                "FROM sz_assign_jobs WHERE id=%s",
                (job_id,)
            )
            job = cur.fetchone()
    finally:
        conn.close()
    if not job:
        return err("Job not found", 404)
    report = None
    raw = job.get("shortage_report")
    if raw:
        try:
            report = json.loads(raw)
        except Exception:
            report = None
    return ok({
        "jobId":         job["id"],
        "status":        job["status"],
        "totalCenters":  job["total_centers"] or 0,
        "doneCenters":   job["done_centers"]  or 0,
        "shortageReport": report,
        "errorMsg":      job.get("error_msg") or "",
    })


@admin_bp.route("/center/<int:center_id>/shortage-info", methods=["GET"])
@admin_required
def get_center_shortage_info(center_id):
    d_ids = _district_admin_ids()
    d_ph, d_params = _district_placeholder(d_ids)
    district = (request.user.get("district") or "").strip()

    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT id, name, center_type, booth_count FROM matdan_sthal WHERE id=%s",
                (center_id,))
            center = cur.fetchone()
            if not center:
                return err("Center not found", 404)

            sensitivity = center["center_type"] or "C"
            raw_bc      = int(center["booth_count"] or 1)
            lookup_bc   = max(1, min(raw_bc, 15))

            # Find rule with fallback
            cur.execute(f"""
                SELECT * FROM booth_rules
                WHERE admin_id IN ({d_ph}) AND sensitivity=%s AND booth_count=%s
            """, d_params + [sensitivity, lookup_bc])
            rule = cur.fetchone()

            if not rule:
                # Fallback to closest lower booth_count
                cur.execute(f"""
                    SELECT * FROM booth_rules
                    WHERE admin_id IN ({d_ph}) AND sensitivity=%s AND booth_count <= %s
                    ORDER BY booth_count DESC LIMIT 1
                """, d_params + [sensitivity, lookup_bc])
                rule = cur.fetchone()

            if not rule:
                return err(f"No manak set for {sensitivity}", 404)

            # Currently assigned at this center
            cur.execute("""
                SELECT u.user_rank, u.is_armed, COUNT(*) AS cnt
                FROM duty_assignments da
                JOIN users u ON u.id = da.staff_id
                WHERE da.sthal_id=%s
                GROUP BY u.user_rank, u.is_armed
            """, (center_id,))
            assigned_map = {
                ((r["user_rank"] or ""), int(r["is_armed"] or 0)): int(r["cnt"])
                for r in cur.fetchall()
            }

            # Available pool
            district_clause = "AND district=%s" if district else ""
            district_param  = [district] if district else []
            cur.execute(f"""
                SELECT user_rank, is_armed, COUNT(*) AS cnt
                FROM users
                WHERE role='staff' AND is_active=1 {district_clause}
                  AND id NOT IN (SELECT staff_id FROM duty_assignments)
                  AND id NOT IN (SELECT staff_id FROM district_duty_assignments)
                GROUP BY user_rank, is_armed
            """, district_param)
            pool_map = {
                ((r["user_rank"] or ""), int(r["is_armed"] or 0)): int(r["cnt"])
                for r in cur.fetchall()
            }
    finally:
        conn.close()

    _LOCAL_SLOTS = [
        ("SI",             True,  "si_armed_count",      "SI",    "सशस्त्र"),
        ("SI",             False, "si_unarmed_count",    "SI",    "निःशस्त्र"),
        ("Head Constable", True,  "hc_armed_count",      "HC",    "सशस्त्र"),
        ("Head Constable", False, "hc_unarmed_count",    "HC",    "निःशस्त्र"),
        ("Constable",      True,  "const_armed_count",   "Const", "सशस्त्र"),
        ("Constable",      False, "const_unarmed_count", "Const", "निःशस्त्र"),
        ("Constable",      True,  "aux_armed_count",     "Aux",   "सशस्त्र"),
        ("Constable",      False, "aux_unarmed_count",   "Aux",   "निःशस्त्र"),
    ]

    requirements = []
    for rank, armed, col, ls, la in _LOCAL_SLOTS:
        # ✅ ONE set per center — no booth_count multiplication
        required = int(rule.get(col) or 0)
        if required <= 0:
            continue
        armed_int = 1 if armed else 0
        have = assigned_map.get((rank, armed_int), 0)
        free = pool_map.get((rank, armed_int), 0)
        requirements.append({
            "rank":       rank,
            "armed":      armed,
            "ruleField":  col,
            "labelShort": ls,
            "labelArmed": la,
            "required":   required,
            "assigned":   have,
            "missing":    max(0, required - have),
            "available":  free,
        })

    pool = [
        {"rank": rank, "armed": bool(armed), "available": cnt}
        for (rank, armed), cnt in pool_map.items() if rank
    ]

    return ok({
        "centerId":     center_id,
        "centerName":   center["name"] or "",
        "sensitivity":  sensitivity,
        "boothCount":   raw_bc,
        "requirements": requirements,
        "pool":         pool,
    })

@admin_bp.route("/center/<int:center_id>/assign-override", methods=["POST"])
@admin_required
def assign_center_override(center_id):
    """
    Admin chooses substitutes for unavailable ranks for THIS booth only.
    Body:
      {
        "substitutions": [
          { "rank": "SI", "armed": true,
            "replacements": [
              { "rank": "Head Constable", "armed": true, "count": 2 },
              { "rank": "Constable",      "armed": false, "count": 1 }
            ]
          },
          ...
        ]
      }
    This does NOT modify booth_rules. Only inserts duty_assignments rows.
    """
    cfg, gerr = require_active_election(request.user.get("district"))
    if gerr:
        return gerr
    election_id = cfg["id"]

    body          = request.get_json() or {}
    substitutions = body.get("substitutions", [])
    if not isinstance(substitutions, list) or not substitutions:
        return err("substitutions list required")

    district = (request.user.get("district") or "").strip()
    conn = get_db()
    total_inserted = 0
    failures = []
    try:
        with conn.cursor() as cur:
            cur.execute("SELECT id FROM matdan_sthal WHERE id=%s", (center_id,))
            if not cur.fetchone():
                return err("Center not found", 404)

            # Lock check
            cur.execute("""
                SELECT IFNULL(l.is_locked, 0) AS is_locked
                FROM matdan_sthal c
                JOIN gram_panchayats gp ON c.gram_panchayat_id = gp.id
                JOIN sectors s         ON gp.sector_id = s.id
                JOIN zones z           ON s.zone_id = z.id
                LEFT JOIN sz_duty_locks l ON l.super_zone_id = z.super_zone_id
                WHERE c.id = %s
            """, (center_id,))
            lk = cur.fetchone()
            if lk and lk["is_locked"]:
                return err("Super Zone locked. Cannot assign.", 403)

            # Track used IDs from this transaction
            used_ids = set()

            for sub in substitutions:
                replacements = sub.get("replacements", [])
                for rep in replacements:
                    rank  = (rep.get("rank") or "").strip()
                    armed = bool(rep.get("armed"))
                    count = int(rep.get("count") or 0)
                    if not rank or count <= 0:
                        continue
                    picked = _pick_booth_staff(cur, rank, armed, count, used_ids, district)
                    if len(picked) < count:
                        failures.append({
                            "rank":      rank,
                            "armed":     armed,
                            "requested": count,
                            "got":       len(picked),
                        })
                    for s in picked:
                        try:
                            cur.execute("""
                                INSERT INTO duty_assignments
                                    (staff_id, sthal_id, election_id, assigned_by)
                                VALUES (%s,%s,%s,%s)
                                ON DUPLICATE KEY UPDATE
                                    sthal_id=VALUES(sthal_id),
                                    election_id=VALUES(election_id),
                                    assigned_by=VALUES(assigned_by)
                            """, (s["id"], center_id, election_id, _admin_id()))
                            used_ids.add(s["id"])
                            total_inserted += 1
                        except Exception as e:
                            failures.append({
                                "rank": rank, "armed": armed,
                                "error": str(e), "staffId": s["id"],
                            })
        conn.commit()
    except Exception as e:
        try: conn.rollback()
        except: pass
        return err(f"Override failed: {e}", 500)
    finally:
        conn.close()

    write_log(
        "INFO",
        f"Center {center_id} override-assigned {total_inserted} staff "
        f"({len(failures)} failures) by admin {_admin_id()}",
        "AutoAssign"
    )
    return ok({
        "centerId":   center_id,
        "inserted":   total_inserted,
        "failures":   failures,
        "electionId": election_id,
    }, f"{total_inserted} staff assigned (override)")
