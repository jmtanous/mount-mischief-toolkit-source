# Project-specific integrations

Adding a new Benro application requires an MMT release. Updating a supported
application requires a package/catalog release unless its integration contract
changes. MMT does not load executable integration code from the catalog.

The compiled registry in lib/integrations/registry.dart owns supported project
identities and integration revisions. Catalog entries use the existing `adapter`
identifier plus optional positive integer `min_integration_revision` and
`min_mmt_build`. Omission retains legacy revision/build 1 behavior. The existing
`min_manager_schema` requirement is also enforced.

An unknown integration or higher requirement can be displayed in the catalog,
but download/install/version-change controls are disabled with “Update MMT
required.” Installation independently checks compatibility before device work.
Malformed metadata is rejected rather than interpreted as an update request.

Pilot's startup, readiness, controller handover and cleanup code lives in
lib/integrations/pilot_lifecycle.dart. Pilot-specific settings/status UI and the
on-device Python adapter remain dedicated Pilot behavior. Future projects get
explicit integrations; they do not have to implement a generic service protocol.

Repository ownership:
- Existing mount-mischief-toolkit-source: APK, integrations, Toolkit runtime,
  and catalog metadata. Keep legacy catalog.json available for build 11.
- Existing alpaca-pilot-polaris-port: all Python port versions and packages.
- New Benro development environment repository: shared tools and VM recipes.
- One additional repository per new application, not per application version.

Publish immutable package assets before enabling their catalog entries. The
staged catalog-v2 is not ready to publish until the standalone runtime has a
verified downloadable asset ID. v2.2.0 must not be listed before its dependency
rebuild and acceptance tests pass. This document does not authorize publication.
