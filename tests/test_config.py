import os
import json
import subprocess

def test_auditor_config_syntax():
    """Validates that auditor_config.json is valid JSON and contains required keys."""
    config_path = os.path.join(os.path.dirname(__file__), '..', 'auditor_config.json')
    assert os.path.exists(config_path), "auditor_config.json does not exist"
    
    with open(config_path, 'r') as f:
        # Note: If this file has broken JSON syntax, json.load will throw a 
        # JSONDecodeError and correctly fail the Pytest suite!
        config = json.load(f)
        
    assert 'DB_NAME' in config
    assert isinstance(config.get('EXCLUSIONS'), list)
    assert isinstance(config.get('EXT_FILTER'), list)


def test_bash_config_syntax():
    """Validates that config.env can be safely sourced by bash without syntax errors."""
    config_path = os.path.join(os.path.dirname(__file__), '..', 'config.env')
    assert os.path.exists(config_path), "config.env does not exist"
    
    # Run bash -n (syntax check) on the config file
    result = subprocess.run(['bash', '-n', config_path], capture_output=True, text=True)
    assert result.returncode == 0, f"config.env bash syntax error: {result.stderr}"
    
    # Evaluate if we can source it safely
    result_source = subprocess.run(['bash', '-c', f'set -e; source {config_path}'], capture_output=True, text=True)
    assert result_source.returncode == 0, f"Error sourcing config.env at runtime: {result_source.stderr}"
