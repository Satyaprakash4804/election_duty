from flask import Blueprint, jsonify
from db import get_db

hierarchy = Blueprint('hierarchy', __name__, url_prefix='/api/admin/hierarchy')


@hierarchy.route('/full', methods=['GET', 'OPTIONS'])
def get_full_hierarchy():
    conn = get_db()
    try:
        with conn.cursor() as cur:

            # 🔹 SUPER ZONES
            cur.execute("SELECT * FROM super_zones")
            super_zones = cur.fetchall()

            result = []

            for sz in super_zones:
                sz_id = sz['id']

                # 🔹 ZONES
                cur.execute("SELECT * FROM zones WHERE super_zone_id=%s", (sz_id,))
                zones = cur.fetchall()

                zone_list = []

                for z in zones:
                    z_id = z['id']

                    # 🔹 SECTORS
                    cur.execute("SELECT * FROM sectors WHERE zone_id=%s", (z_id,))
                    sectors = cur.fetchall()

                    sector_list = []

                    for s in sectors:
                        s_id = s['id']

                        # 🔹 PANCHAYATS
                        cur.execute("SELECT * FROM gram_panchayats WHERE sector_id=%s", (s_id,))
                        gps = cur.fetchall()

                        gp_list = []

                        for gp in gps:
                            gp_id = gp['id']

                            # 🔹 MATDAN STHAL (centers)
                            cur.execute("""
                                SELECT * FROM matdan_sthal 
                                WHERE gram_panchayat_id=%s
                            """, (gp_id,))
                            sthals = cur.fetchall()

                            gp['centers'] = sthals
                            gp_list.append(gp)

                        s['panchayats'] = gp_list
                        sector_list.append(s)

                    z['sectors'] = sector_list
                    zone_list.append(z)

                sz['zones'] = zone_list
                result.append(sz)

        return jsonify(result)

    except Exception as e:
        return jsonify({"error": str(e)}), 500

    finally:
        conn.close()