import numpy as np
from flask import Flask, request, jsonify

app = Flask(__name__)

@app.route('/roots', methods=['POST'])
def find_roots():
    """
    Expects a JSON payload with a 'coefficients' key.
    Example payload: {"coefficients": [1, 0, -4]}  # x^2 - 4 = 0
    """
    try:
        data = request.get_json()
        
        if not data or 'coefficients' not in data:
            return jsonify({"error": "Please provide a 'coefficients' list"}), 400
        
        coeffs = data['coefficients']
        
        roots = np.roots(coeffs)
        
        # Convert complex numpy types to native Python strings for JSON serialization
        readable_roots = [str(r) for r in roots]
        
        return jsonify({
            "polynomial_coefficients": coeffs,
            "roots": readable_roots
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8080)