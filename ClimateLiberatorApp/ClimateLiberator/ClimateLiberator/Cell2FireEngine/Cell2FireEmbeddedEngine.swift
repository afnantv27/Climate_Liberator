import Foundation

// MARK: - Result types

struct Cell2FireSimulationSummary: Sendable {
    let totalCells: Int
    let burntCells: Int
    let availableCells: Int
    let nonBurnableCells: Int
    let firebreakCells: Int
    let burntPercent: Float
}

struct Cell2FireGridDimensions: Sendable {
    let rows: Int
    let cols: Int
    var cellCount: Int { rows * cols }
}

// MARK: - Error type

enum Cell2FireEngineError: LocalizedError, Sendable {
    case nullPointer(String)
    case badPath(String)
    case badParameter(String)
    case initFailed(String)
    case notReady(String)
    case unknown(Int32)

    var errorDescription: String? {
        switch self {
        case .nullPointer(let ctx):  return "Cell2Fire: null argument — \(ctx)"
        case .badPath(let ctx):      return "Cell2Fire: bad path — \(ctx)"
        case .badParameter(let ctx): return "Cell2Fire: bad parameter — \(ctx)"
        case .initFailed(let ctx):   return "Cell2Fire: initialization failed — \(ctx)"
        case .notReady(let ctx):     return "Cell2Fire: not ready — \(ctx)"
        case .unknown(let code):     return "Cell2Fire: unknown error (code \(code))"
        }
    }

    static func from(status: c2f_status_t, context: String = "") -> Cell2FireEngineError? {
        switch status {
        case C2F_OK:           return nil
        case C2F_ERR_NULL_ARG: return .nullPointer(context)
        case C2F_ERR_BAD_PATH: return .badPath(context)
        case C2F_ERR_BAD_PARAM: return .badParameter(context)
        case C2F_ERR_INIT_FAIL: return .initFailed(context)
        case C2F_ERR_NOT_READY: return .notReady(context)
        default:               return .unknown(status.rawValue)
        }
    }

    @discardableResult
    static func check(_ status: c2f_status_t, context: String = "") throws -> c2f_status_t {
        if let error = from(status: status, context: context) {
            throw error
        }
        return status
    }
}

// MARK: - Configuration builder

final class Cell2FireConfiguration: @unchecked Sendable {
    private let handle: OpaquePointer

    init() throws {
        guard let h = c2f_config_create() else {
            throw Cell2FireEngineError.initFailed("Failed to allocate config")
        }
        handle = h
    }

    deinit { c2f_config_destroy(handle) }

    // Required
    func setInputFolder(_ path: String) throws {
        try Cell2FireEngineError.check(c2f_config_set_input_folder(handle, path), context: "inputFolder")
    }

    func setOutputFolder(_ path: String) throws {
        try Cell2FireEngineError.check(c2f_config_set_output_folder(handle, path), context: "outputFolder")
    }

    func setSimulator(_ code: String) throws {
        try Cell2FireEngineError.check(c2f_config_set_simulator(handle, code), context: "simulator")
    }

    // Scalars
    func setNsims(_ n: Int) throws {
        try Cell2FireEngineError.check(c2f_config_set_nsims(handle, Int32(n)), context: "nsims")
    }

    func setSeed(_ s: Int) throws {
        try Cell2FireEngineError.check(c2f_config_set_seed(handle, Int32(s)), context: "seed")
    }

    func setNthreads(_ n: Int) throws {
        try Cell2FireEngineError.check(c2f_config_set_nthreads(handle, Int32(n)), context: "nthreads")
    }

    func setFirePeriodLength(_ minutes: Float) throws {
        try Cell2FireEngineError.check(c2f_config_set_fire_period_len(handle, minutes), context: "firePeriodLen")
    }

    func setMaxFirePeriods(_ p: Int) throws {
        try Cell2FireEngineError.check(c2f_config_set_max_fire_periods(handle, Int32(p)), context: "maxFirePeriods")
    }

    func setTotalYears(_ y: Int) throws {
        try Cell2FireEngineError.check(c2f_config_set_total_years(handle, Int32(y)), context: "totalYears")
    }

    // Tuning
    func setROSCV(_ v: Float) throws {
        try Cell2FireEngineError.check(c2f_config_set_roscv(handle, v), context: "roscv")
    }

    func setROSThreshold(_ v: Float) throws {
        try Cell2FireEngineError.check(c2f_config_set_ros_threshold(handle, v), context: "rosThreshold")
    }

    func setHFIThreshold(_ v: Float) throws {
        try Cell2FireEngineError.check(c2f_config_set_hfi_threshold(handle, v), context: "hfiThreshold")
    }

    // Output toggles
    func setFinalGrid(_ enabled: Bool) throws {
        try Cell2FireEngineError.check(c2f_config_set_final_grid(handle, enabled ? 1 : 0), context: "finalGrid")
    }

    func setOutputGrids(_ enabled: Bool) throws {
        try Cell2FireEngineError.check(c2f_config_set_output_grids(handle, enabled ? 1 : 0), context: "outputGrids")
    }

    func setVerbose(_ enabled: Bool) throws {
        try Cell2FireEngineError.check(c2f_config_set_verbose(handle, enabled ? 1 : 0), context: "verbose")
    }

    func setOutROS(_ enabled: Bool) throws {
        try Cell2FireEngineError.check(c2f_config_set_out_ros(handle, enabled ? 1 : 0), context: "outRos")
    }

    func setOutIntensity(_ enabled: Bool) throws {
        try Cell2FireEngineError.check(c2f_config_set_out_intensity(handle, enabled ? 1 : 0), context: "outIntensity")
    }

    func setOutFlameLength(_ enabled: Bool) throws {
        try Cell2FireEngineError.check(c2f_config_set_out_flame_length(handle, enabled ? 1 : 0), context: "outFlameLength")
    }

    func setOutCrown(_ enabled: Bool) throws {
        try Cell2FireEngineError.check(c2f_config_set_out_crown(handle, enabled ? 1 : 0), context: "outCrown")
    }

    // Optional paths
    func setWeatherOpt(_ opt: String) throws {
        try Cell2FireEngineError.check(c2f_config_set_weather_opt(handle, opt), context: "weatherOpt")
    }

    func setFuelTable(_ path: String) throws {
        try Cell2FireEngineError.check(c2f_config_set_fuel_table(handle, path), context: "fuelTable")
    }

    func setHarvestPlan(_ path: String) throws {
        try Cell2FireEngineError.check(c2f_config_set_harvest_plan(handle, path), context: "harvestPlan")
    }

    /// Internal: pass the opaque pointer to create a simulation.
    var opaqueHandle: OpaquePointer { handle }
}

// MARK: - Simulation engine

final class Cell2FireSimulation: @unchecked Sendable {
    private let handle: OpaquePointer

    init(config: Cell2FireConfiguration) throws {
        guard let h = c2f_sim_create(config.opaqueHandle) else {
            throw Cell2FireEngineError.initFailed("c2f_sim_create returned nil — check stderr for details")
        }
        handle = h
    }

    deinit { c2f_sim_destroy(handle) }

    // MARK: - Run all (fire-and-forget with OpenMP parallelism)

    func runAll() throws {
        try Cell2FireEngineError.check(c2f_sim_run_all(handle), context: "runAll")
    }

    // MARK: - Step-by-step control

    func reset(episode: Int) throws {
        try Cell2FireEngineError.check(c2f_sim_reset(handle, Int32(episode)), context: "reset")
    }

    func step() throws {
        try Cell2FireEngineError.check(c2f_sim_step(handle), context: "step")
    }

    var isDone: Bool {
        c2f_sim_is_done(handle) != 0
    }

    func finalize() throws {
        try Cell2FireEngineError.check(c2f_sim_finalize(handle), context: "finalize")
    }

    // MARK: - Progress callback

    func setProgressCallback(_ callback: @escaping (Int, Int, Float) -> Void) {
        // Store the closure in a box so we can pass a pointer to C
        let box = ProgressBox(callback: callback)
        let retained = Unmanaged.passRetained(box).toOpaque()

        c2f_sim_set_progress_callback(handle, { episode, period, pct, userdata in
            guard let userdata else { return }
            let box = Unmanaged<ProgressBox>.fromOpaque(userdata).takeUnretainedValue()
            box.callback(Int(episode), Int(period), pct)
        }, retained)
    }

    // MARK: - Result accessors

    func getSummary() throws -> Cell2FireSimulationSummary {
        var raw = c2f_summary_t()
        try Cell2FireEngineError.check(c2f_sim_get_summary(handle, &raw), context: "getSummary")
        return Cell2FireSimulationSummary(
            totalCells: Int(raw.total_cells),
            burntCells: Int(raw.burnt_cells),
            availableCells: Int(raw.available_cells),
            nonBurnableCells: Int(raw.non_burnable_cells),
            firebreakCells: Int(raw.firebreak_cells),
            burntPercent: raw.burnt_percent
        )
    }

    func getDimensions() throws -> Cell2FireGridDimensions {
        var rows: Int32 = 0
        var cols: Int32 = 0
        try Cell2FireEngineError.check(c2f_sim_get_dimensions(handle, &rows, &cols), context: "getDimensions")
        return Cell2FireGridDimensions(rows: Int(rows), cols: Int(cols))
    }

    func getGrid() throws -> [Int32] {
        let dims = try getDimensions()
        var buffer = [Int32](repeating: 0, count: dims.cellCount)
        var written: Int32 = 0
        try Cell2FireEngineError.check(
            c2f_sim_get_grid(handle, &buffer, Int32(dims.cellCount), &written),
            context: "getGrid"
        )
        return Array(buffer.prefix(Int(written)))
    }

    func getROS() throws -> [Float] {
        let dims = try getDimensions()
        var buffer = [Float](repeating: 0, count: dims.cellCount)
        try Cell2FireEngineError.check(
            c2f_sim_get_ros(handle, &buffer, Int32(dims.cellCount)),
            context: "getROS"
        )
        return buffer
    }

    func getIntensity() throws -> [Float] {
        let dims = try getDimensions()
        var buffer = [Float](repeating: 0, count: dims.cellCount)
        try Cell2FireEngineError.check(
            c2f_sim_get_intensity(handle, &buffer, Int32(dims.cellCount)),
            context: "getIntensity"
        )
        return buffer
    }

    func getFlameLength() throws -> [Float] {
        let dims = try getDimensions()
        var buffer = [Float](repeating: 0, count: dims.cellCount)
        try Cell2FireEngineError.check(
            c2f_sim_get_flame_length(handle, &buffer, Int32(dims.cellCount)),
            context: "getFlameLength"
        )
        return buffer
    }

    static var engineVersion: String {
        String(cString: c2f_version())
    }
}

// MARK: - Internal helper for progress callback

private final class ProgressBox {
    let callback: (Int, Int, Float) -> Void
    init(callback: @escaping (Int, Int, Float) -> Void) {
        self.callback = callback
    }
}
