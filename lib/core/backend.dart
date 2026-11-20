import 'package:cloud_functions/cloud_functions.dart';

/// Cloud Functions are deployed to this region (see backend/functions/src/index.ts).
const functionsRegion = 'europe-west1';

FirebaseFunctions zadFunctions() => FirebaseFunctions.instanceFor(region: functionsRegion);
