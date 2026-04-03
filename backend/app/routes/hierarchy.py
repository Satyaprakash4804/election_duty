from flask import Blueprint, jsonify, request
from db import get_db
from app.routes import admin_required

hierarchy = Blueprint('hierarchy', __name__, url_prefix='/api/admin/hierarchy')


# ─── helpers ──────────────────────────────────────────────────────────────────

def _officer(r):
    """Serialise any *_officers table row into the shape Flutter expects."""
    return {
        "id":        r["id"],
        "user_id":   r.get("user_id"),
        "name":      r.get("name")      or "",
        "pno":       r.get("pno")       or "",
        "mobile":    r.get("mobile")    or "",
        "user_rank": r.get("user_rank") or "",
    }


def _fetch_officers(cur, table, fk_col, fk_val):
    cur.execute(
        f"SELECT * FROM {table} WHERE {fk_col} = %s ORDER BY id",
        (fk_val,)
    )
    return [_officer(r) for r in cur.fetchall()]


def _fetch_duty_officers(cur, sthal_id):
    """Return staff assigned to a matdan_sthal with their details."""
    cur.execute("""
        SELECT u.id, u.name, u.pno, u.mobile, u.user_rank, u.thana,
               da.bus_no
        FROM duty_assignments da
        JOIN users u ON u.id = da.staff_id
        WHERE da.sthal_id = %s
        ORDER BY u.name
    """, (sthal_id,))
    rows = cur.fetchall()
    return [
        {
            "id":        r["id"],
            "name":      r["name"]      or "",
            "pno":       r["pno"]       or "",
            "mobile":    r["mobile"]    or "",
            "user_rank": r["user_rank"] or "",
            "thana":     r["thana"]     or "",
            "bus_no":    r["bus_no"]    or "",
        }
        for r in rows
    ]


def _fetch_kendras(cur, sthal_id):
    """Return matdan_kendra (rooms) for a matdan_sthal."""
    cur.execute(
        "SELECT id, room_number FROM matdan_kendra WHERE matdan_sthal_id = %s ORDER BY id",
        (sthal_id,)
    )
    return [
        {"id": r["id"], "room_number": r["room_number"] or ""}
        for r in cur.fetchall()
    ]


# ─── main route ───────────────────────────────────────────────────────────────

@hierarchy.route('/full', methods=['GET', 'OPTIONS'])
@admin_required
def get_full_hierarchy():
    """
    Returns the complete admin hierarchy tree:

    super_zone
      └── officers          (kshetra_officers)
      └── zones[]
            └── officers    (zonal_officers)
            └── sectors[]
                  └── officers  (sector_officers)
                  └── panchayats[]
                        └── centers[]          (matdan_sthal)
                              └── kendras[]    (matdan_kendra)
                              └── duty_officers[] (duty_assignments → users)
    """

    # Respect admin scope — only return super_zones owned by this admin.
    # Falls back gracefully if the decorator hasn't set request.user
    # (e.g. during development without auth).
    admin_id = getattr(request, "user", {}).get("id") if hasattr(request, "user") else None

    conn = get_db()
    try:
        with conn.cursor() as cur:

            # ── 1. SUPER ZONES ────────────────────────────────────────────────
            if admin_id:
                cur.execute(
                    "SELECT * FROM super_zones WHERE admin_id = %s ORDER BY id",
                    (admin_id,)
                )
            else:
                cur.execute("SELECT * FROM super_zones ORDER BY id")

            super_zones = cur.fetchall()
            result = []

            for sz in super_zones:
                sz_id = sz["id"]

                # ── 2. ZONES ──────────────────────────────────────────────────
                cur.execute(
                    "SELECT * FROM zones WHERE super_zone_id = %s ORDER BY id",
                    (sz_id,)
                )
                zones = cur.fetchall()
                zone_list = []

                for z in zones:
                    z_id = z["id"]

                    # ── 3. SECTORS ────────────────────────────────────────────
                    cur.execute(
                        "SELECT * FROM sectors WHERE zone_id = %s ORDER BY id",
                        (z_id,)
                    )
                    sectors = cur.fetchall()
                    sector_list = []

                    for s in sectors:
                        s_id = s["id"]

                        # ── 4. GRAM PANCHAYATS ────────────────────────────────
                        cur.execute(
                            "SELECT * FROM gram_panchayats WHERE sector_id = %s ORDER BY id",
                            (s_id,)
                        )
                        gps = cur.fetchall()
                        gp_list = []

                        for gp in gps:
                            gp_id = gp["id"]

                            # ── 5. MATDAN STHAL (centers) ─────────────────────
                            cur.execute(
                                "SELECT * FROM matdan_sthal WHERE gram_panchayat_id = %s ORDER BY id",
                                (gp_id,)
                            )
                            sthals = cur.fetchall()
                            center_list = []

                            for ms in sthals:
                                ms_id = ms["id"]
                                center_list.append({
                                    "id":           ms["id"],
                                    "name":         ms["name"]        or "",
                                    "address":      ms["address"]     or "",
                                    "thana":        ms["thana"]       or "",
                                    "center_type":  ms["center_type"] or "C",
                                    "bus_no":       ms["bus_no"]      or "",
                                    "latitude":     float(ms["latitude"])  if ms["latitude"]  else None,
                                    "longitude":    float(ms["longitude"]) if ms["longitude"] else None,
                                    # rooms / kendras
                                    "kendras":       _fetch_kendras(cur, ms_id),
                                    # police / staff on duty at this sthal
                                    "duty_officers": _fetch_duty_officers(cur, ms_id),
                                })

                            # derive thana for the GP from its first center (convenience field)
                            gp_thana = next(
                                (c["thana"] for c in center_list if c.get("thana")), ""
                            )

                            gp_list.append({
                                "id":      gp["id"],
                                "name":    gp["name"]    or "",
                                "address": gp["address"] or "",
                                "thana":   gp_thana,
                                "centers": center_list,
                            })

                        sector_list.append({
                            "id":         s["id"],
                            "name":       s["name"] or "",
                            "officers":   _fetch_officers(cur, "sector_officers",  "sector_id",  s_id),
                            "panchayats": gp_list,
                        })

                    zone_list.append({
                        "id":          z["id"],
                        "name":        z["name"]       or "",
                        "hq_address":  z["hq_address"] or "",
                        "officers":    _fetch_officers(cur, "zonal_officers", "zone_id", z_id),
                        "sectors":     sector_list,
                    })

                result.append({
                    "id":       sz["id"],
                    "name":     sz["name"]     or "",
                    "district": sz["district"] or "",
                    "block":    sz["block"]    or "",
                    "officers": _fetch_officers(cur, "kshetra_officers", "super_zone_id", sz_id),
                    "zones":    zone_list,
                })

        return jsonify(result)

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        conn.close()


# ─── individual delete/edit shims (Flutter calls /admin/hierarchy/…) ──────────
# These simply delegate to the same DB tables; auth is enforced by @admin_required.

@hierarchy.route('/super-zone/<int:sz_id>', methods=['DELETE'])
@admin_required
def delete_super_zone(sz_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM super_zones WHERE id = %s", (sz_id,))
        conn.commit()
    finally:
        conn.close()
    return jsonify({"status": "ok", "message": "Super Zone deleted"})


@hierarchy.route('/super-zone/<int:sz_id>', methods=['PUT'])
@admin_required
def update_super_zone(sz_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE super_zones SET name=%s, district=%s, block=%s WHERE id=%s",
                (body.get("name", ""), body.get("district", ""), body.get("block", ""), sz_id)
            )
        conn.commit()
    finally:
        conn.close()
    return jsonify({"status": "ok", "message": "Super Zone updated"})


@hierarchy.route('/sector/<int:s_id>', methods=['DELETE'])
@admin_required
def delete_sector(s_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM sectors WHERE id = %s", (s_id,))
        conn.commit()
    finally:
        conn.close()
    return jsonify({"status": "ok", "message": "Sector deleted"})


@hierarchy.route('/sector/<int:s_id>', methods=['PUT'])
@admin_required
def update_sector(s_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute(
                "UPDATE sectors SET name=%s WHERE id=%s",
                (body.get("name", ""), s_id)
            )
        conn.commit()
    finally:
        conn.close()
    return jsonify({"status": "ok", "message": "Sector updated"})


@hierarchy.route('/sthal/<int:ms_id>', methods=['DELETE'])
@admin_required
def delete_sthal(ms_id):
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("DELETE FROM matdan_sthal WHERE id = %s", (ms_id,))
        conn.commit()
    finally:
        conn.close()
    return jsonify({"status": "ok", "message": "Sthal deleted"})


@hierarchy.route('/sthal/<int:ms_id>', methods=['PUT'])
@admin_required
def update_sthal(ms_id):
    body = request.get_json() or {}
    conn = get_db()
    try:
        with conn.cursor() as cur:
            cur.execute("""
                UPDATE matdan_sthal
                SET name        = %s,
                    address     = %s,
                    thana       = %s,
                    center_type = %s,
                    bus_no      = %s
                WHERE id = %s
            """, (
                body.get("name", ""),
                body.get("address", ""),
                body.get("thana", ""),
                body.get("center_type", "C"),
                body.get("bus_no", ""),
                ms_id,
            ))
        conn.commit()
    finally:
        conn.close()
    return jsonify({"status": "ok", "message": "Sthal updated"})