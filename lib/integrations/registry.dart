/// Compiled integrations: adding an application requires an MMT release.
/// Catalog data can select revisions, but cannot add executable behavior.
const managerSchema = 1;
const mmtBuild = 13;
const integrationRevisions = <String, int>{
  'alpaca-pilot-v1': 1,
  'toolkit-runtime-v1': 1,
};
const integrationProjects = <String, String>{
  'alpaca-pilot-v1': 'alpaca-pilot',
  'toolkit-runtime-v1': 'toolkit-runtime',
};
