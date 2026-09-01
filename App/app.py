from flask import Flask

app = Flask(__name__)

@app.route("/")
def home():
    return "Hello from Om's containerized app!"

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000) # nosemgrep: python.flask.security.audit.app-run-param-config.avoid_app_run_with_bad_host -- required for container networking; actual exposure is controlled by Docker port mapping / K8s Service, not app bind address

