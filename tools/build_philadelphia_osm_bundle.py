#!/usr/bin/env python3
"""Create the iOS Philadelphia road bundle from an OSM-derived public roads layer.

Run before XcodeGen in TestFlight workflows. The downloaded source is
OSM Roads Philadelphia, FeatureServer layer 16 (May 2026 snapshot).
This is OSM-derived, NOT the separate City of Philadelphia speed-limit GIS.
No inferred/default speed limits are added.

Download requires network access to ArcGIS. If it fails, exits nonzero so the
release workflow cannot silently distribute an empty "offline" map.
"""
import argparse
import collections
import datetime
import json
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

SOURCE = ('https://services1.arcgis.com/0MSEUqKaxRlEPj5g/ArcGIS/rest/services/'
          'Philadelphia_School_Facilities_Proposal_Study___Spatial_Analysis_WFL1/'
          'FeatureServer/16/query')
SOURCE_ID = 'OSM Roads Philadelphia (ArcGIS FeatureServer layer 16; OSM-derived)'  # ODbL
DEFAULT_OUTPUT = 'ios/HUDController/OfflineOSM/PhiladelphiaOSMRoads.json'
BBOX = (-75.35, 39.86, -75.075, 40.15)
CLASSES = {"motorway", "motorway_link", "trunk", "trunk_link", "primary", "primary_link",
           "secondary", "secondary_link", "tertiary", "tertiary_link", "unclassified",
           "residential", "living_street", "service", "road"}


def request_json(params, *, attempts=3):
    body = urllib.parse.urlencode(params).encode('ascii')
    last = None
    for attempt in range(attempts):
        try:
            req = urllib.request.Request(SOURCE, data=body, headers={
                'User-Agent': 'HUDController-OSM-Offline-Bundle/1.0 (build-time fetch)',
                'Content-Type': 'application/x-www-form-urlencoded',
                'Accept': 'application/json',
            })
            with urllib.request.urlopen(req, timeout=75) as resp:
                result = json.load(resp)
            if 'error' in result:
                raise RuntimeError('ArcGIS server error: ' + repr(result['error'])[:300])
            return result
        except (urllib.error.URLError, TimeoutError, ValueError, RuntimeError) as ex:
            last = ex
            if attempt + 1 != attempts:
                time.sleep(min(2 ** attempt * 3, 12))
    raise RuntimeError(f'Offline OSM acquisition failed: {last}')


def decode_feature(feature):
    p = feature.get('properties') or {}
    name = (p.get('name') or '').strip()
    highway = str(p.get('fclass') or '').lower().strip()
    if highway not in CLASSES or not name:
        return []
    raw_id = p.get('osm_id')
    try:
        ident = abs(int(raw_id))
    except (ValueError, TypeError):
        # ArcGIS OBJECTID is stable for this published snapshot.
        ident = 900000000000 + abs(int(p.get('OBJECTID') or feature.get('id') or 0))
    if ident <= 0:
        return []
    posted = p.get('maxspeed')
    try:
        posted = int(posted)
    except (ValueError, TypeError):
        posted = None
    # Source maxspeed is a transformed numeric OSM attribute; no missing tag
    # gets a legal speed inferred from the local 25 mph neighborhood rule.
    if posted is not None and not 8 <= posted <= 160:
        posted = None
    geom = feature.get('geometry') or {}
    kind = geom.get('type')
    pieces = [geom.get('coordinates')] if kind == 'LineString' else (
        geom.get('coordinates') if kind == 'MultiLineString' else [])
    roads = []
    for part, coords in enumerate(pieces):
        if not isinstance(coords, list) or not 2 <= len(coords) <= 10000:
            continue
        converted = []
        for point in coords:
            if not isinstance(point, list) or len(point) < 2:
                converted = []
                break
            lon, lat = float(point[0]), float(point[1])
            if not (39.7 <= lat <= 40.3 and -75.6 <= lon <= -74.8):
                converted = []
                break
            converted.append([round(lat, 7), round(lon, 7)])
        if len(converted) < 2:
            continue
        # First segment retains true OSM ID, so fresh online data can replace
        # it. Multipart additional pieces have stable disjoint negative IDs.
        road_id = ident if part == 0 else -((ident * 100) + part)
        roads.append(dict(id=road_id, highway=highway, name=name,
                          reference=p.get('ref') or None,
                          maxspeedKmh=posted, coordinates=converted))
    return roads


def build(output, fixture=None):
    features = []
    if fixture:
        features = json.loads(pathlib.Path(fixture).read_text())['features']
    else:
        # Geometry rectangle covers Philadelphia proper and the western
        # neighborhoods/roads used in the user's recorded drives.
        common = dict(where='name IS NOT NULL', outFields='OBJECTID,osm_id,fclass,name,ref,maxspeed',
                      geometry=','.join(map(str, BBOX)), geometryType='esriGeometryEnvelope',
                      inSR='4326', spatialRel='esriSpatialRelIntersects', outSR='4326',
                      returnGeometry='true', orderByFields='OBJECTID ASC', f='geojson')
        page_size = 1500
        for page in range(100):
            batch = request_json({**common, 'resultOffset': page*page_size,
                                  'resultRecordCount': page_size})
            batch_features = batch.get('features', [])
            if not isinstance(batch_features, list):
                raise RuntimeError('Unexpected GeoJSON response; no valid features')
            features.extend(batch_features)
            print(f'OSM offline page {page+1}: {len(batch_features)} features; total {len(features)}', flush=True)
            if len(batch_features) < page_size:
                break
        else:
            raise RuntimeError('OSM dataset exceeded 150k features; refusing incomplete snapshot')
    roads = {}
    for feature in features:
        for road in decode_feature(feature):
            # Published GIS layers can split one OSM way into multiple features
            # with the same osm_id. Keep *all* pieces instead of overwriting
            # an earlier geometry and introducing gaps in offline coverage.
            identifier = road['id']
            collision = 1
            while identifier in roads:
                identifier = -(abs(road['id']) * 1000 + collision)
                collision += 1
            road['id'] = identifier
            roads[identifier] = road
    roads = [roads[k] for k in sorted(roads)]
    tag_count = sum(r['maxspeedKmh'] is not None for r in roads)
    if not fixture:
        # Don't ship a misleading "offline" placeholder after a failed query.
        if len(roads) < 2000 or tag_count < 100:
            raise RuntimeError(f'Unexpectedly incomplete OSM layer: {len(roads)} roads, {tag_count} tagged; refusing TestFlight build')
        names = {r['name'].lower() for r in roads}
        if not any('ridge' in name for name in names) or not any('kelly' in name for name in names):
            raise RuntimeError('OSM snapshot missing expected Philadelphia road names')
    payload = dict(version=1, source=SOURCE_ID,
                   generatedAt=datetime.datetime.now(datetime.timezone.utc).isoformat(),
                   roads=roads)
    dest = pathlib.Path(output)
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix('.json.tmp')
    tmp.write_text(json.dumps(payload, separators=(',', ':')), encoding='utf-8')
    tmp.replace(dest)
    print(f'Offline OSM bundle: {len(roads)} roads, {tag_count} explicit numeric speed limits, '
          f'{dest.stat().st_size:,} bytes -> {dest}', flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--output', default=DEFAULT_OUTPUT)
    parser.add_argument('--fixture', help='Local test only; never used for release')
    args = parser.parse_args()
    build(args.output, args.fixture)

if __name__ == '__main__':
    main()
