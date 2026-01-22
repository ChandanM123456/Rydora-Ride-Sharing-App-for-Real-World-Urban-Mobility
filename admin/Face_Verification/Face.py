# app.py
import os
import pickle
import base64
from flask import Flask, request, jsonify
from flask_cors import CORS
import face_recognition
import psycopg2
from psycopg2.extras import RealDictCursor
import numpy as np
from io import BytesIO

app = Flask(__name__)
CORS(app)

# Your Render PostgreSQL database URL
DATABASE_URL = "postgresql://rider_face_db_user:PKMFc6ih36eIl0LfOf4Y1b9jVPzdSWca@dpg-d3o7kuili9vc73bt9bgg-a.singapore-postgres.render.com/rider_face_db"

def get_db_connection():
    return psycopg2.connect(DATABASE_URL, sslmode='require')

def numpy_to_bytes(array):
    """Convert numpy array to bytes for database storage"""
    return pickle.dumps(array)

def bytes_to_numpy(data):
    """Convert bytes back to numpy array"""
    return pickle.loads(data)

def init_database():
    """Initialize database tables"""
    conn = get_db_connection()
    cur = conn.cursor()
    
    # Create tables if they don't exist
    cur.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) UNIQUE NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    cur.execute("""
        CREATE TABLE IF NOT EXISTS face_encodings (
            id SERIAL PRIMARY KEY,
            user_id VARCHAR(255) REFERENCES users(user_id) ON DELETE CASCADE,
            face_encoding BYTEA NOT NULL,
            image_data BYTEA,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    """)
    
    cur.execute("""
        CREATE INDEX IF NOT EXISTS idx_user_id ON face_encodings(user_id)
    """)
    
    conn.commit()
    cur.close()
    conn.close()
    print("Database initialized successfully")

@app.route('/')
def home():
    return jsonify({'status': 'running', 'message': 'Face Verification API'})

@app.route('/register_face', methods=['POST'])
def register_face():
    """Register a new user face"""
    try:
        user_id = request.form['user_id']
        image_file = request.files['image']
        
        if not user_id or not image_file:
            return jsonify({'status': 'error', 'message': 'Missing user_id or image'}), 400
        
        # Read and process image
        image_data = image_file.read()
        image = face_recognition.load_image_file(BytesIO(image_data))
        
        # Detect face encodings
        face_encodings = face_recognition.face_encodings(image)
        
        if not face_encodings:
            return jsonify({'status': 'error', 'message': 'No face detected in the image'}), 400
        
        # Use the first face found
        face_encoding = face_encodings[0]
        
        # Convert to bytes for storage
        encoding_bytes = numpy_to_bytes(face_encoding)
        
        # Store in database
        conn = get_db_connection()
        cur = conn.cursor()
        
        try:
            # First, ensure user exists
            cur.execute(
                "INSERT INTO users (user_id) VALUES (%s) ON CONFLICT (user_id) DO NOTHING",
                (user_id,)
            )
            
            # Check if user already has a face encoding
            cur.execute(
                "SELECT id FROM face_encodings WHERE user_id = %s",
                (user_id,)
            )
            
            existing_face = cur.fetchone()
            
            if existing_face:
                # Update existing face encoding
                cur.execute(
                    "UPDATE face_encodings SET face_encoding = %s, image_data = %s, created_at = CURRENT_TIMESTAMP WHERE user_id = %s",
                    (encoding_bytes, image_data, user_id)
                )
                message = 'Face updated successfully'
            else:
                # Insert new face encoding
                cur.execute(
                    "INSERT INTO face_encodings (user_id, face_encoding, image_data) VALUES (%s, %s, %s)",
                    (user_id, encoding_bytes, image_data)
                )
                message = 'Face registered successfully'
            
            conn.commit()
            
            return jsonify({
                'status': 'success', 
                'message': message
            })
            
        except Exception as e:
            conn.rollback()
            return jsonify({'status': 'error', 'message': f'Database error: {str(e)}'}), 500
        finally:
            cur.close()
            conn.close()
            
    except Exception as e:
        return jsonify({'status': 'error', 'message': f'Server error: {str(e)}'}), 500

@app.route('/verify_face', methods=['POST'])
def verify_face():
    """Verify a face against stored encodings"""
    try:
        image_file = request.files['image']
        
        if not image_file:
            return jsonify({'match': False, 'error': 'No image provided'}), 400
        
        # Read and process image
        image_data = image_file.read()
        image = face_recognition.load_image_file(BytesIO(image_data))
        
        # Detect face in the uploaded image
        live_face_encodings = face_recognition.face_encodings(image)
        
        if not live_face_encodings:
            return jsonify({'match': False, 'error': 'No face detected in the image'}), 400
        
        live_encoding = live_face_encodings[0]
        
        # Get all stored face encodings from database
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        cur.execute("""
            SELECT u.user_id, fe.face_encoding 
            FROM face_encodings fe
            JOIN users u ON fe.user_id = u.user_id
        """)
        
        stored_faces = cur.fetchall()
        cur.close()
        conn.close()
        
        if not stored_faces:
            return jsonify({'match': False, 'error': 'No registered faces found'}), 400
        
        # Compare with all stored encodings
        for face in stored_faces:
            try:
                stored_encoding = bytes_to_numpy(face['face_encoding'])
                
                # Compare faces with tolerance
                matches = face_recognition.compare_faces([stored_encoding], live_encoding, tolerance=0.6)
                
                if matches[0]:
                    return jsonify({
                        'match': True, 
                        'user_id': face['user_id']
                    })
            except Exception as e:
                print(f"Error processing encoding for user {face['user_id']}: {e}")
                continue
        
        return jsonify({'match': False, 'user_id': None})
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': f'Verification error: {str(e)}'}), 500

@app.route('/get_users', methods=['GET'])
def get_users():
    """Get list of all registered users"""
    try:
        conn = get_db_connection()
        cur = conn.cursor(cursor_factory=RealDictCursor)
        
        cur.execute("""
            SELECT u.user_id, COUNT(fe.id) as face_count,
                   MAX(fe.created_at) as last_updated
            FROM users u
            LEFT JOIN face_encodings fe ON u.user_id = fe.user_id
            GROUP BY u.user_id
            ORDER BY last_updated DESC
        """)
        
        users = cur.fetchall()
        cur.close()
        conn.close()
        
        return jsonify({'status': 'success', 'users': users})
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/delete_user/<user_id>', methods=['DELETE'])
def delete_user(user_id):
    """Delete a user and their face data"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("DELETE FROM users WHERE user_id = %s", (user_id,))
        conn.commit()
        
        if cur.rowcount > 0:
            message = f'User {user_id} deleted successfully'
        else:
            message = f'User {user_id} not found'
        
        cur.close()
        conn.close()
        
        return jsonify({'status': 'success', 'message': message})
        
    except Exception as e:
        return jsonify({'status': 'error', 'message': str(e)}), 500

@app.route('/health', methods=['GET'])
def health_check():
    """Health check endpoint"""
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("SELECT 1")
        cur.close()
        conn.close()
        return jsonify({'status': 'healthy', 'database': 'connected'})
    except Exception as e:
        return jsonify({'status': 'unhealthy', 'database': 'disconnected', 'error': str(e)}), 500

# Initialize database when app starts
init_database()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)