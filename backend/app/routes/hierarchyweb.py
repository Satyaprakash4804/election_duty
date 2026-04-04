from flask import Blueprint, jsonify, request
from db import get_db

hierarchy_bp = Blueprint('hierarchyweb', __name__, url_prefix='/api/admin/hierarchy')


# ✅ FULL DATA (frontend ka main API)
@hierarchy_bp.route('/full/h', methods=['GET', 'OPTIONS'])
def get_full_hierarchy():
    if request.method == "OPTIONS":
        return '', 200
    conn = get_db()
    cur = conn.cursor()

    try:
        # SUPER ZONES
        cur.execute("SELECT * FROM super_zones")
        super_zones = cur.fetchall()

        result = []

        for sz in super_zones:
            # officers
            cur.execute("SELECT * FROM kshetra_officers WHERE super_zone_id=%s", (sz['id'],))
            sz['officers'] = cur.fetchall()

            # ZONES
            cur.execute("SELECT * FROM zones WHERE super_zone_id=%s", (sz['id'],))
            zones = cur.fetchall()

            for z in zones:
                cur.execute("SELECT * FROM zonal_officers WHERE zone_id=%s", (z['id'],))
                z['officers'] = cur.fetchall()

                # SECTORS
                cur.execute("SELECT * FROM sectors WHERE zone_id=%s", (z['id'],))
                sectors = cur.fetchall()

                for s in sectors:
                    cur.execute("SELECT * FROM sector_officers WHERE sector_id=%s", (s['id'],))
                    s['officers'] = cur.fetchall()

                    # PANCHAYAT
                    cur.execute("SELECT * FROM gram_panchayats WHERE sector_id=%s", (s['id'],))
                    gps = cur.fetchall()

                    for gp in gps:
                        # CENTERS
                        cur.execute("SELECT * FROM matdan_sthal WHERE gram_panchayat_id=%s", (gp['id'],))
                        centers = cur.fetchall()

                        for c in centers:
                            # KENDRA
                            cur.execute("SELECT * FROM matdan_kendra WHERE matdan_sthal_id=%s", (c['id'],))
                            c['kendras'] = cur.fetchall()

                            # DUTY
                            cur.execute("""
                                SELECT u.name, u.mobile, u.user_rank, u.pno, d.bus_no
                                FROM duty_assignments d
                                JOIN users u ON d.staff_id = u.id
                                WHERE d.sthal_id=%s
                            """, (c['id'],))
                            c['duty_officers'] = cur.fetchall()

                        gp['centers'] = centers

                    s['panchayats'] = gps

                z['sectors'] = sectors

            sz['zones'] = zones

            result.append(sz)

        return jsonify(result)

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        cur.close()
        conn.close()


# ✅ UPDATE API (frontend ka edit button)
@hierarchy_bp.route('/update', methods=['PATCH'])
def update_record():
    data = request.json

    table = data.get("table")
    record_id = data.get("id")

    if not table or not record_id:
        return jsonify({"error": "Missing table or id"}), 400

    conn = get_db()
    cur = conn.cursor()

    try:
        # 🔥 allowed columns per table
        ALLOWED = {
            "super_zones": ["name", "block", "district"],
            "zones": ["name", "hq_address"],
            "sectors": ["name"],
            "gram_panchayats": ["name", "address", "thana"],
            "matdan_sthal": ["name", "address", "thana", "center_type", "bus_no"],
        }

        allowed_fields = ALLOWED.get(table, [])

        # 🔥 filter only valid columns
        fields = {
            k: v for k, v in data.items()
            if k in allowed_fields
        }

        if not fields:
            return jsonify({"error": "No valid fields"}), 400

        set_clause = ", ".join([f"{k}=%s" for k in fields.keys()])
        values = list(fields.values())

        query = f"UPDATE {table} SET {set_clause} WHERE id=%s"
        values.append(record_id)

        cur.execute(query, values)
        conn.commit()

        return jsonify({"message": "updated"})

    except Exception as e:
        conn.rollback()
        print("🔥 ERROR:", e)   # 👉 terminal me exact error dikhega
        return jsonify({"error": str(e)}), 500

    finally:
        cur.close()
        conn.close()