from flask import Flask
import subprocess
import hashlib

app = Flask(__name__)

@app.route("/")
def home():
    password = "admin123"

    # Weak hash (Bandit should detect this)
    hashed = hashlib.md5(password.encode()).hexdigest()

    # Dangerous command execution
    subprocess.call("ls", shell=True)

    return f"Hash: {hashed}"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000)
