# Morrow iOS Visual Render Worker

Public, disposable iOS Simulator worker for the private Morrow Wallpaper project.

- Wallpaper inputs are AES-256 encrypted before they enter this repository.
- The decryption key is stored only as a GitHub Actions secret.
- Render outputs are encrypted before artifact upload.
- No plaintext wallpaper or screenshot is committed to this repository.

