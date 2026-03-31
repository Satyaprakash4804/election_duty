from flask import Blueprint, render_template, request, session, redirect
from werkzeug.security import generate_password_hash
from app.db import get_db

super_admin = Blueprint('super_admin', __name__)

# 🔥 Dashboard
@super_admin.route('/super_admin_dashboard')
def super_admin_dashboard():
    if session.get('role') != 'super_admin':
        return redirect('/')

    return render_template('super_admin_dashboard.html')


# 🔥 Create Admin
@super_admin.route('/create_admin', methods=['POST'])
def create_admin():
    if session.get('role') != 'super_admin':
        return "Unauthorized"

    name = request.form['name']
    mobile = request.form['mobile']
    password = generate_password_hash(request.form['password'])

    conn = get_db()
    with conn.cursor() as cursor:
        cursor.execute("""
            INSERT INTO users (name, mobile, password, role, created_by)
            VALUES (%s, %s, %s, 'admin', %s)
        """, (name, mobile, password, session.get('user_id')))
        conn.commit()
    conn.close()

    return "✅ Admin Created"