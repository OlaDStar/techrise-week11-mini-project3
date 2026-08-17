import os
from flask import Flask
from werkzeug.security import generate_password_hash

app = Flask(__name__)

@app.route('/')
def home():
    return 'PayliteNG Secure App'

def hash_password(password):
    return generate_password_hash(password)

if __name__ == "__main__":
    app.run(
        host=os.getenv("HOST"),
        port=5000
    )
