from flask import Blueprint, render_template, session, redirect, request
from app.db import get_db

admin = Blueprint('admin', __name__)

@admin.route('/admin_dashboard', methods=['GET', 'POST'])
def admin_dashboard():
    if session.get('role') != 'admin':
        return redirect('/')

    conn = get_db()
    cursor = conn.cursor()

    # 🔥 HANDLE INSERT
    if request.method == 'POST':
        form_type = request.form.get('form_type')

        if form_type == 'super_zone':
            name = request.form['name']
            cursor.execute("INSERT INTO super_zones (name) VALUES (%s)", (name,))

        elif form_type == 'zone':
            name = request.form['name']
            super_zone_id = request.form['super_zone_id']
            cursor.execute("INSERT INTO zones (name, super_zone_id) VALUES (%s, %s)", (name, super_zone_id))
        # =========================
# 🔥 INSERT LOGIC
# =========================

        elif form_type == 'sector':
            sector_number = request.form['sector_number']
            zone_id = request.form['zone_id']
            cursor.execute(
                "INSERT INTO sectors (sector_number, zone_id) VALUES (%s, %s)",
                (sector_number, zone_id)
            )

        elif form_type == 'panchayat':
            name = request.form['name']
            sector_id = request.form['sector_id']
            cursor.execute(
                "INSERT INTO gram_panchayats (name, sector_id) VALUES (%s, %s)",
                (name, sector_id)
            )

        elif form_type == 'sthal':
            name = request.form['name']
            gp_id = request.form['gram_panchayat_id']
            cursor.execute(
                "INSERT INTO matdan_sthal (name, gram_panchayat_id) VALUES (%s, %s)",
                (name, gp_id)
            )
        conn.commit()

    # 🔥 FETCH DATA
    cursor.execute("SELECT * FROM super_zones")
    super_zones = cursor.fetchall()

    cursor.execute("SELECT * FROM zones")
    zones = cursor.fetchall()

    cursor.execute("SELECT * FROM users")
    users = cursor.fetchall()

    # 🔥 CURRENT USER
    cursor.execute("SELECT * FROM users WHERE id=%s", (session['user_id'],))
    profile = cursor.fetchone()

    cursor.execute("SELECT * FROM sectors")
    sectors = cursor.fetchall()

    cursor.execute("SELECT * FROM gram_panchayats")
    panchayats = cursor.fetchall()

    cursor.execute("SELECT * FROM matdan_sthal")
    sthal = cursor.fetchall()
    
    conn.close()

    return render_template("admin_dashboard.html",
                           super_zones=super_zones,
                           zones=zones,
                           users=users,
                           profile=profile,
                           sectors=sectors,
                           sthal=sthal,
                           )