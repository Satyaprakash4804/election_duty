from flask import Blueprint, request, jsonify
from werkzeug.security import check_password_hash
from app.db import get_db
import jwt
import datetime

auth = Blueprint('auth', __name__)

SECRET_KEY = "secret123"

MASTER_ID = "master"
MASTER_PASSWORD = "1234"


# =========================
# LOGIN API
# =========================
@auth.route('/api/login', methods=['POST'])
def login():
    data = request.get_json()

    mobile = data.get('mobile')
    password = data.get('password')

    # MASTER LOGIN
    if mobile == MASTER_ID and password == MASTER_PASSWORD:
        token = jwt.encode({
            'role': 'master',
            'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=10)
        }, SECRET_KEY, algorithm='HS256')

        return jsonify({"token": token, "role": "master"})

    conn = get_db()
    with conn.cursor() as cursor:
        cursor.execute("SELECT * FROM users WHERE mobile=%s", (mobile,))
        user = cursor.fetchone()
    conn.close()

    if user and check_password_hash(user['password'], password):
        token = jwt.encode({
            'user_id': user['id'],
            'role': user['role'],
            'exp': datetime.datetime.utcnow() + datetime.timedelta(hours=10)
        }, SECRET_KEY, algorithm='HS256')

        return jsonify({
            "token": token,
            "role": user['role'],
            "name": user['name']
        })

    return jsonify({"error": "Invalid credentials"}), 401