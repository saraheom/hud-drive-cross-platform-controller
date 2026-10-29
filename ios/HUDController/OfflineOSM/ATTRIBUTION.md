# Philadelphia OSM roadway bundle attribution

The TestFlight build pipeline retrieves a geographically bounded excerpt of the
**OSM Roads Philadelphia** ArcGIS FeatureServer layer (May 2026 published data),
which is derived from **OpenStreetMap**.

© OpenStreetMap contributors — https://www.openstreetmap.org/copyright
OpenStreetMap data is distributed under the Open Database License (ODbL).

Source endpoint:
https://services1.arcgis.com/0MSEUqKaxRlEPj5g/ArcGIS/rest/services/Philadelphia_School_Facilities_Proposal_Study___Spatial_Analysis_WFL1/FeatureServer/16

Only numeric `maxspeed` values present in the dataset are used. The source uses
kilometers per hour. No inferred road speed (including any "default 25 mph") is
inserted. A displayed limit is still subject to live CarPlay street identity and
GPS geometry checks. It must not replace the vehicle's posted signs.

The repository's placeholder `PhiladelphiaOSMRoads.json` intentionally contains
zero roads; the *release build* downloads the actual dataset before XcodeGen.
The release workflow fails rather than silently building without the snapshot.
If a build isn't made through that workflow, the app can still use online OSM but
will log `OFFLINE_BUNDLE_UNAVAILABLE`.
