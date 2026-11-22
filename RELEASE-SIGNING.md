# Android release signing

Debug APKs are local test builds. Release tasks now fail when signing credentials
are missing; they never fall back to the development key.

The project does not include a production key. The owner must create or select a
release keystore, back it up securely, and keep the same signer for future updates.
Do not commit the keystore, passwords or shell-history commands containing secrets.
Provide these environment variables through your local secret manager or interactive
shell session before running `flutter build apk --release`:

- `MMT_KEYSTORE_PATH`: absolute path to the existing keystore.
- `MMT_KEYSTORE_PASSWORD`: keystore password.
- `MMT_KEY_ALIAS`: signing-key alias.
- `MMT_KEY_PASSWORD`: key password.

After building, run the Android SDK's `apksigner verify --verbose --print-certs`
on the exact APK. Record the certificate SHA-256 fingerprint with the release and
compare it with the owner's expected release certificate. A successful signature
check alone does not establish that the correct key was used.

Development installations use the debug signer. Android will reject an
in-place update signed with a different production key. Plan the migration and
preserve needed app settings before uninstalling the debug build; no automatic
uninstall or data clearing is performed by these build scripts.

The owner authorized a new local production key during rc.2 preparation. Its
certificate SHA-256 is
`868c4b51f7da0e23fb0277149fefac96808e37e42852219e5264d00f1b61fa68`.
The encrypted PKCS12 keystore and password are stored outside the repositories
with owner-only filesystem permissions. No private key or password is committed.
An independent owner-requested backup was completed and verified before publication.
The test Pixel has been migrated, with owner approval, to production-signed build 11.
Generating a key alone does not authorize publishing a release or uninstalling an app.
