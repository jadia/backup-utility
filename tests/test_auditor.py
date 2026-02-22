import sys
import os
import tempfile
import pytest

# Ensure parent directory is in python path to import auditor
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '..')))

def test_hash_calculation():
    from auditor import calculate_sha256
    
    # Create temporary file to hash
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(b"backup-utility-test")
        temp_path = f.name
        
    try:
        # Pre-calculated SHA256 of "backup-utility-test"
        expected = "48f23852dc21c9a38e8ffd9f743f847b4d7945b0f4b9006f1635cab462b7fa2b"
        assert calculate_sha256(temp_path) == expected
    finally:
        os.remove(temp_path)

def test_should_exclude(monkeypatch):
    import auditor
    
    # Mock the configuration payload testing specific scenarios
    mock_config = {
        "EXCLUSIONS": [".git/", "node_modules/"],
        "EXT_FILTER": [".jpg", ".mp4"]
    }
    monkeypatch.setattr(auditor, 'CONFIG', mock_config)
    
    # Check directory exclusion rules
    assert auditor.should_exclude("/my/path/.git/config") == True
    assert auditor.should_exclude("/my/path/node_modules/index.js") == True
    
    # Files missing from explicit Extension Filter SHOULD be excluded
    assert auditor.should_exclude("/my/path/src/main.py") == True
    assert auditor.should_exclude("/my/path/document.pdf") == True
    
    # Acceptable files based on the mock filter 
    assert auditor.should_exclude("/my/path/photo.jpg") == False
    assert auditor.should_exclude("/my/path/video.mp4") == False
