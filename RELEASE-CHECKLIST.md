# Candidate release gates

Local builds, package/source integrity and automated checks are recorded in
RELEASE-VALIDATION.json. Published Beta 8/build 11 remain unchanged.

1. Review exact APK, runtime, Pilot archive, source companions and source diffs.
2. Obtain separate authorization for any public repository, push or release upload.
3. Upload immutable package/source assets before adding their actual IDs to catalog-v2.
4. Verify anonymous asset bytes and hashes; run verify-catalog-candidate.py with
   --require-assets from the MMT checkout. Keep legacy catalog.json unchanged.
5. Complete attended phone/Polaris acceptance for the new candidate, including
   clean Toolkit installation and version-specific settings rollback. The
   existing-filesystem clean-directory test is recorded in docs/ATTENDED-ACCEPTANCE.md;
   a newly formatted card was not tested. Preserve this distinction and the
   recovered connection incident in release notes. No firmware or movement
   tests are implied. Preserve working cards and pairing/settings.
6. Publish the reviewed catalog/app release only with the applicable authorization.
   Do not label local VM checks as physical acceptance.
