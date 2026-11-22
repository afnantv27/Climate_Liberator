PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS sources (
    source_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    provider TEXT,
    category TEXT NOT NULL,
    access_mode TEXT NOT NULL,
    license_notes TEXT,
    url TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS datasets (
    dataset_id TEXT PRIMARY KEY,
    source_id TEXT NOT NULL REFERENCES sources(source_id),
    name TEXT NOT NULL,
    geographic_scope TEXT,
    format TEXT,
    status TEXT NOT NULL DEFAULT 'registered',
    requires_manual_request INTEGER NOT NULL DEFAULT 0,
    local_path TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS ingestion_runs (
    ingestion_id TEXT PRIMARY KEY,
    source_id TEXT REFERENCES sources(source_id),
    dataset_id TEXT REFERENCES datasets(dataset_id),
    run_type TEXT NOT NULL,
    status TEXT NOT NULL,
    started_at TEXT NOT NULL,
    completed_at TEXT,
    raw_path TEXT,
    staging_path TEXT,
    processed_path TEXT,
    row_count INTEGER,
    notes TEXT
);

CREATE TABLE IF NOT EXISTS admin_states (
    state_code TEXT PRIMARY KEY,
    state_name TEXT NOT NULL,
    boundary_dataset_id TEXT REFERENCES datasets(dataset_id),
    boundary_path TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS building_stock (
    building_id TEXT PRIMARY KEY,
    source_dataset_id TEXT NOT NULL REFERENCES datasets(dataset_id),
    state_code TEXT REFERENCES admin_states(state_code),
    district_name TEXT,
    latitude REAL,
    longitude REAL,
    area_m2 REAL,
    perimeter_m REAL,
    building_height_m REAL,
    building_floor_count INTEGER,
    total_built_up_m2 REAL,
    landuse TEXT,
    confidence REAL,
    full_plus_code TEXT,
    is_predicted INTEGER,
    prediction_confidence REAL,
    geometry_wkt TEXT,
    source_record_hash TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_building_stock_state ON building_stock(state_code);
CREATE INDEX IF NOT EXISTS idx_building_stock_district ON building_stock(district_name);

CREATE TABLE IF NOT EXISTS site_assets (
    site_asset_id TEXT PRIMARY KEY,
    asset_source TEXT NOT NULL,
    external_asset_id TEXT,
    site_name TEXT,
    address_text TEXT,
    digipin TEXT,
    state_code TEXT REFERENCES admin_states(state_code),
    district_name TEXT,
    latitude REAL,
    longitude REAL,
    plot_area_m2 REAL,
    building_area_m2 REAL,
    parcel_number TEXT,
    building_number TEXT,
    occupancy_type TEXT,
    geometry_wkt TEXT,
    notes TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS site_building_links (
    site_asset_id TEXT NOT NULL REFERENCES site_assets(site_asset_id),
    building_id TEXT NOT NULL REFERENCES building_stock(building_id),
    match_type TEXT NOT NULL,
    distance_m REAL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (site_asset_id, building_id)
);

CREATE TABLE IF NOT EXISTS wildfire_runs (
    run_id TEXT PRIMARY KEY,
    engine_name TEXT NOT NULL,
    engine_version TEXT,
    generated_at TEXT,
    scenario_label TEXT,
    prepared_instance_root TEXT,
    run_artifact_path TEXT NOT NULL,
    run_manifest_path TEXT,
    output_manifest_path TEXT,
    artifact_index_path TEXT,
    landscape_format TEXT,
    weather_mode TEXT,
    weather_input_format TEXT,
    ignition_input_mode TEXT,
    provenance_json TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_wildfire_runs_scenario
    ON wildfire_runs(scenario_label);

CREATE TABLE IF NOT EXISTS wildfire_run_artifacts (
    artifact_id TEXT PRIMARY KEY,
    run_id TEXT NOT NULL REFERENCES wildfire_runs(run_id) ON DELETE CASCADE,
    artifact_type TEXT NOT NULL,
    media_type TEXT,
    artifact_path TEXT NOT NULL,
    relative_path TEXT,
    artifact_sha256 TEXT,
    byte_size INTEGER,
    simulation_index INTEGER,
    surface_kind TEXT,
    planned_only INTEGER NOT NULL DEFAULT 0,
    artifact_summary TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_wildfire_run_artifacts_run_type
    ON wildfire_run_artifacts(run_id, artifact_type);

CREATE TABLE IF NOT EXISTS wildfire_run_surfaces (
    surface_id TEXT PRIMARY KEY,
    run_id TEXT NOT NULL REFERENCES wildfire_runs(run_id) ON DELETE CASCADE,
    source_artifact_id TEXT REFERENCES wildfire_run_artifacts(artifact_id),
    surface_kind TEXT NOT NULL,
    surface_format TEXT NOT NULL,
    surface_path TEXT NOT NULL,
    surface_crs TEXT,
    sampling_basis TEXT,
    ready_for_sampling INTEGER NOT NULL DEFAULT 0,
    source_artifact_sha256 TEXT,
    surface_summary TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_wildfire_run_surfaces_run_kind
    ON wildfire_run_surfaces(run_id, surface_kind);

CREATE TABLE IF NOT EXISTS risk_assessments (
    assessment_id TEXT PRIMARY KEY,
    run_id TEXT REFERENCES wildfire_runs(run_id),
    site_asset_id TEXT REFERENCES site_assets(site_asset_id),
    building_id TEXT REFERENCES building_stock(building_id),
    hazard_type TEXT NOT NULL DEFAULT 'wildfire',
    analysis_scope TEXT NOT NULL DEFAULT 'building',
    scenario_label TEXT,
    surface_id TEXT REFERENCES wildfire_run_surfaces(surface_id),
    source_artifact_id TEXT REFERENCES wildfire_run_artifacts(artifact_id),
    surface_kind TEXT,
    sampled_surface_value REAL,
    sampling_basis TEXT,
    source_surface_format TEXT,
    source_surface_crs TEXT,
    burn_probability REAL,
    expected_exposed_area_m2 REAL,
    distance_to_fire_m REAL,
    distance_to_site_m REAL,
    linked_building_count INTEGER,
    risk_band TEXT,
    tcfd_target_status TEXT,
    assessment_notes TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_risk_assessments_building_hazard_created
    ON risk_assessments(building_id, hazard_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_risk_assessments_site_hazard_created
    ON risk_assessments(site_asset_id, hazard_type, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_risk_assessments_run_id
    ON risk_assessments(run_id);

CREATE INDEX IF NOT EXISTS idx_risk_assessments_surface_id
    ON risk_assessments(surface_id);

CREATE INDEX IF NOT EXISTS idx_risk_assessments_scope
    ON risk_assessments(analysis_scope, hazard_type, created_at DESC);

CREATE TABLE IF NOT EXISTS risk_assessment_metrics (
    metric_id TEXT PRIMARY KEY,
    assessment_id TEXT NOT NULL REFERENCES risk_assessments(assessment_id) ON DELETE CASCADE,
    run_id TEXT NOT NULL REFERENCES wildfire_runs(run_id),
    analysis_scope TEXT NOT NULL,
    surface_id TEXT REFERENCES wildfire_run_surfaces(surface_id),
    source_artifact_id TEXT REFERENCES wildfire_run_artifacts(artifact_id),
    surface_kind TEXT,
    metric_name TEXT NOT NULL,
    metric_role TEXT,
    metric_value REAL,
    metric_unit TEXT,
    provenance_json TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_risk_assessment_metrics_assessment
    ON risk_assessment_metrics(assessment_id, metric_name);

CREATE INDEX IF NOT EXISTS idx_risk_assessment_metrics_run_surface
    ON risk_assessment_metrics(run_id, surface_id);

CREATE VIEW IF NOT EXISTS building_wildfire_risk_analytics AS
SELECT
    ra.assessment_id,
    ra.run_id,
    ra.analysis_scope,
    wr.engine_name,
    wr.engine_version,
    wr.scenario_label AS run_scenario_label,
    ra.scenario_label AS assessment_scenario_label,
    ra.surface_id,
    ra.source_artifact_id,
    ra.surface_kind,
    ra.sampled_surface_value,
    ra.sampling_basis,
    ra.source_surface_format,
    ra.source_surface_crs,
    ra.burn_probability,
    ra.expected_exposed_area_m2,
    ra.distance_to_fire_m,
    ra.distance_to_site_m,
    ra.risk_band,
    ra.tcfd_target_status,
    ra.site_asset_id,
    sa.site_name,
    ra.building_id,
    bs.state_code,
    bs.district_name,
    bs.latitude AS building_latitude,
    bs.longitude AS building_longitude,
    bs.area_m2,
    bs.total_built_up_m2,
    ws.surface_path,
    ws.source_artifact_id AS surface_artifact_id,
    ws.source_artifact_sha256,
    ws.ready_for_sampling,
    ra.created_at
FROM risk_assessments AS ra
LEFT JOIN wildfire_runs AS wr ON wr.run_id = ra.run_id
LEFT JOIN wildfire_run_surfaces AS ws ON ws.surface_id = ra.surface_id
LEFT JOIN building_stock AS bs ON bs.building_id = ra.building_id
LEFT JOIN site_assets AS sa ON sa.site_asset_id = ra.site_asset_id
WHERE ra.hazard_type = 'wildfire'
  AND ra.analysis_scope = 'building';

CREATE VIEW IF NOT EXISTS site_wildfire_risk_analytics AS
SELECT
    ra.assessment_id,
    ra.run_id,
    ra.analysis_scope,
    wr.engine_name,
    wr.engine_version,
    wr.scenario_label AS run_scenario_label,
    ra.scenario_label AS assessment_scenario_label,
    ra.surface_id,
    ra.source_artifact_id,
    ra.surface_kind,
    ra.sampled_surface_value,
    ra.sampling_basis,
    ra.source_surface_format,
    ra.source_surface_crs,
    ra.burn_probability,
    ra.expected_exposed_area_m2,
    ra.distance_to_fire_m,
    ra.distance_to_site_m,
    ra.linked_building_count,
    ra.risk_band,
    ra.tcfd_target_status,
    ra.site_asset_id,
    sa.site_name,
    sa.state_code,
    sa.district_name,
    sa.latitude AS site_latitude,
    sa.longitude AS site_longitude,
    sa.plot_area_m2,
    sa.building_area_m2,
    ws.surface_path,
    ws.source_artifact_id AS surface_artifact_id,
    ws.source_artifact_sha256,
    ws.ready_for_sampling,
    ra.created_at
FROM risk_assessments AS ra
LEFT JOIN wildfire_runs AS wr ON wr.run_id = ra.run_id
LEFT JOIN wildfire_run_surfaces AS ws ON ws.surface_id = ra.surface_id
LEFT JOIN site_assets AS sa ON sa.site_asset_id = ra.site_asset_id
WHERE ra.hazard_type = 'wildfire'
  AND ra.analysis_scope = 'site';

CREATE VIEW IF NOT EXISTS wildfire_risk_metric_analytics AS
SELECT
    ram.metric_id,
    ram.assessment_id,
    ram.run_id,
    ram.analysis_scope,
    ram.surface_id,
    ram.source_artifact_id,
    ram.surface_kind,
    ram.metric_name,
    ram.metric_role,
    ram.metric_value,
    ram.metric_unit,
    ra.scenario_label,
    ra.risk_band,
    ra.site_asset_id,
    sa.site_name,
    ra.building_id,
    bs.state_code,
    bs.district_name,
    wr.engine_name,
    wr.engine_version,
    ws.surface_path,
    ws.source_artifact_sha256,
    ws.surface_format,
    ws.surface_crs,
    ram.created_at
FROM risk_assessment_metrics AS ram
LEFT JOIN risk_assessments AS ra ON ra.assessment_id = ram.assessment_id
LEFT JOIN wildfire_runs AS wr ON wr.run_id = ram.run_id
LEFT JOIN wildfire_run_surfaces AS ws ON ws.surface_id = ram.surface_id
LEFT JOIN site_assets AS sa ON sa.site_asset_id = ra.site_asset_id
LEFT JOIN building_stock AS bs ON bs.building_id = ra.building_id;

CREATE INDEX IF NOT EXISTS idx_building_stock_coordinates ON building_stock(latitude,longitude);
CREATE INDEX IF NOT EXISTS idx_assessment_latest ON risk_assessments(building_id,created_at DESC);
